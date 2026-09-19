#!/usr/bin/env bash
# Static checks for the batch/PowerShell/XML sources. Runs on Linux; no Windows needed.
set -u
cd "$(dirname "$0")/.."
fail=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; fail=1; }

# 1. CRLF: every line of every .bat/.cmd/.xml must end in CRLF (cmd.exe misparses LF-only labels/parens).
for f in MediaCreationTool.bat bypass11/*.bat bypass11/*.cmd bypass11/*.xml; do
  lines=$(grep -c '' "$f"); crlf=$(grep -c $'\r$' "$f")
  [ "$lines" -eq "$crlf" ] && say "ok   CRLF $f ($lines lines)" || bad "CRLF mismatch in $f: $crlf of $lines lines"
  grep -q $'\r\r' "$f" && bad "double CR in $f"
done

# 2. XML well-formedness of the standalone unattend file.
xmllint --noout bypass11/AutoUnattend.xml && say "ok   xmllint bypass11/AutoUnattend.xml" || bad "AutoUnattend.xml not well-formed"

# 3. Embedded unattend XML inside MediaCreationTool.bat (between <?xml and </unattend>).
tmp=$(mktemp)
awk '/^<unattend /{p=1} p{print} /^<\/unattend>/{p=0}' MediaCreationTool.bat | tr -d '\r' > "$tmp"
if [ -s "$tmp" ]; then
  xmllint --noout "$tmp" && say "ok   xmllint embedded unattend in MediaCreationTool.bat" || bad "embedded unattend XML not well-formed"
fi
rm -f "$tmp"

# 4. Every `call :LABEL` / `goto :LABEL` in each batch file has a matching `:LABEL` (or hybrid `#:LABEL:#`) line.
for f in MediaCreationTool.bat bypass11/*.bat bypass11/*.cmd; do
  for lbl in $(tr -d '\r' < "$f" | grep -oiE '(call|goto) :[A-Za-z0-9_-]+' | awk '{print $2}' | tr -d ':' | sort -u); do
    [ "$lbl" = "eof" ] && continue
    tr -d '\r' < "$f" | grep -qiE "^(#)?:$lbl\b" || bad "$f: no label :$lbl"
  done
  say "ok   labels $f"
done

# 5. PowerShell snippets in MediaCreationTool.bat are delimited as #:NAME:# ... #:NAME:# — each must appear exactly twice.
for n in $(grep -oE '#:[A-Z0-9_]+:#' MediaCreationTool.bat | sort -u); do
  c=$(grep -o "$n" MediaCreationTool.bat | wc -l)
  [ "$c" -eq 2 ] || bad "snippet marker $n appears $c times (expected 2)"
done
say "ok   powershell snippet markers"

# 6. Brace balance inside each PowerShell snippet (cheap syntax sanity).
for n in $(grep -oE '#:[A-Z0-9_]+:#' MediaCreationTool.bat | sort -u); do
  body=$(awk -v m="$n" 'index($0,m){c++; if(c==1){next}} c>=1{print} c==2{exit}' MediaCreationTool.bat)
  o=$(printf '%s' "$body" | tr -cd '{' | wc -c); cl=$(printf '%s' "$body" | tr -cd '}' | wc -c)
  [ "$o" -eq "$cl" ] || bad "brace imbalance in snippet $n ({=$o }=$cl)"
done
say "ok   powershell brace balance"

# 7. The HTTPS-first rule: DOWNLOAD must try $https before $http.
grep -q 'foreach ($url in $https, $http)' MediaCreationTool.bat && say "ok   DOWNLOAD tries https first" || bad "DOWNLOAD does not try https first"

# 8. Parse every #:NAME:# PowerShell snippet exactly as the script's bootstrap extracts it (needs pwsh; skipped otherwise).
PWSH=${PWSH:-$(command -v pwsh || true)}
if [ -n "$PWSH" ]; then
  for n in $(grep -oE '#:[A-Z0-9_]+:#' MediaCreationTool.bat | sort -u); do
    name=${n#\#:}; name=${name%:\#}
    "$PWSH" -NoProfile -c "
      \$f0=[io.file]::ReadAllText('MediaCreationTool.bat'); \$0=(\$f0 -split '#\:${name}\:',3)[1]
      \$e=\$null; \$null=[System.Management.Automation.Language.Parser]::ParseInput(\$0,[ref]\$null,[ref]\$e)
      if (\$e) { \$e | % { \"  \$(\$_.Extent.StartLineNumber): \$(\$_.Message)\" }; exit 1 }" \
      && say "ok   pwsh parse $n" || bad "PowerShell parse error in snippet $n"
  done
  # 9. Run the real SETUP_GUI function against a mock WinForms layer: selection maths, validation, greying-out, output line.
  "$PWSH" -NoProfile -File tests/dialog-mock/run.ps1 MediaCreationTool.bat > /tmp/dialog-mock.out 2>&1 \
    && say "ok   dialog logic ($(grep -c '^ok' /tmp/dialog-mock.out) scenarios)" || { cat /tmp/dialog-mock.out; bad "dialog logic scenarios failed"; }
  # 9b. Behavioural tests for the remaining PowerShell functions, each driven against mocked dependencies
  #     (transfers, registry, metadata service, WinForms) so no network or Windows host is needed.
  for t in download wim-info fetch-cab products-xml choices; do
    out=$(mktemp)
    if "$PWSH" -NoProfile -File "tests/func-mock/$t.ps1" > "$out" 2>&1; then
      say "ok   $t ($(grep -c '^ok' "$out") assertions)"
    else
      cat "$out"; bad "$t function tests failed"
    fi
    rm -f "$out"
  done
else
  say "skip pwsh parse + dialog logic (pwsh not found; set PWSH=/path/to/pwsh)"
fi

# 10. Batch pieces under Wine cmd.exe when available (best effort).
bash tests/wine-cmd-check.sh || bad "wine cmd checks failed"

# 11. Batch-side routines (every :choice-N branch, :save_ini, :reg_query, :rename) under Wine cmd.exe.
bash tests/batch-func-check.sh || bad "batch function checks failed"

[ $fail -eq 0 ] && say "ALL CHECKS PASSED" || say "SOME CHECKS FAILED"
exit $fail
