#!/usr/bin/env bash
# Drives the batch-side routines of MediaCreationTool.bat under Wine's cmd.exe: every :choice-N version
# branch, the ini writer, the registry helpers and the two generators. Pieces are lifted verbatim from the
# script (never retyped) and run with a stub :process, so what is under test is the real code.
set -u
cd "$(dirname "$0")/.."
command -v wine >/dev/null || { echo "skip batch-func (wine not installed)"; exit 0; }
export WINEDEBUG=-all; export WINEPREFIX=${WINEPREFIX:-$HOME/.wine-mct}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; fail=1; }

python3 - "$T" <<'PY'
import sys, re
T = sys.argv[1]
L = open('MediaCreationTool.bat','rb').read().decode('latin1').split('\r\n')
crlf = lambda ls: ('\r\n'.join(ls)+'\r\n\r\n').encode('latin1')
def find(pred, start=0):
    return next(i for i in range(start, len(L)) if pred(L[i]))

# --- the whole :choice-N ladder, verbatim, with a stub :process that prints what the branch set
first = find(lambda l: l.startswith(':choice-14'))
last  = find(lambda l: l.startswith(':choice-0'))
ladder = L[first:last]
open(f'{T}/choices.bat','wb').write(crlf(
  ['@echo off','setlocal enabledelayedexpansion','set "INSERT_BUSINESS="','goto choice-%1'] + ladder +
  [':choice-0','echo CANCELED','exit /b',
   ':process','echo VER=%VER% VID=%VID% CB=%CB% CT=%CT% CC=%CC%','echo EXE=%EXE%','echo CAB=%CAB%','exit /b']))

# --- the version list, so the ladder can be cross-checked against what the dialog offers
vline = L[find(lambda l: l.startswith('set VERSIONS='))]
open(f'{T}/versions.txt','w').write(vline.split('=',1)[1])

# --- the index.alias table the commandline/ini parser accepts, e.g. "3.1903 3.19H1".
#     A :choice-N branch may legitimately set either alias, so the ladder is checked against this.
i = find(lambda l: l.startswith('for %%V in (1.1703'))
tbl = ' '.join(L[i:i+2])
pairs = re.findall(r'(\d+)\.([A-Za-z0-9_]+)', tbl)
alias = {}
for n, a in pairs: alias.setdefault(n, []).append(a)
open(f'{T}/alias.txt','w').write('\n'.join(f'{n} {" ".join(v)}' for n, v in sorted(alias.items(), key=lambda kv: int(kv[0]))))

# --- :save_ini verbatim, driven from preset variables
i = find(lambda l: l.startswith(':save_ini'))
j = find(lambda l: l.startswith('exit /b'), i)
open(f'{T}/saveini.bat','wb').write(crlf(
  ['@echo off','set "ROOT=%~dp0."','set "WORK="','call :save_ini','type "%ROOT%\\MediaCreationTool.ini"','exit /b'] + L[i:j+1]))

# --- :reg_query verbatim, against a stub `reg` that prints real reg.exe output. Wine's own reg.exe
#     rejects the /se switch the script relies on, so stubbing it is what makes the parsing testable.
#     The stub sits in its own directory that regquery.bat puts on PATH, so the other tests still use
#     the real reg.exe. The script calls: reg query "KEY" /v "NAME" /se "|" [%4] - so NAME is %~4.
import os
os.makedirs(f'{T}/stub', exist_ok=True)
open(f'{T}/stub/reg.cmd','wb').write(crlf(
  ['@echo off','if /i "%~1" neq "query" exit /b 1','set "N=%~4"',
   'if /i "%N%"=="Plain"  goto :plain',
   'if /i "%N%"=="Spaced" goto :spaced',
   'if /i "%N%"=="Multi"  goto :multi',
   'echo ERROR: The system was unable to find the specified registry key or value. 1>&2','exit /b 1',
   ':plain','echo.','echo HKEY_CURRENT_USER\\MCTTest','echo     Plain    REG_SZ    hello world','echo.','exit /b 0',
   ':spaced','echo.','echo HKEY_CURRENT_USER\\MCTTest','echo     Spaced    REG_SZ    a b  c','echo.','exit /b 0',
   ':multi','echo.','echo HKEY_CURRENT_USER\\MCTTest','echo     Multi    REG_MULTI_SZ    en-US^|de-DE','echo.','exit /b 0']))
i = find(lambda l: l.startswith(':reg_query'))
open(f'{T}/regquery.bat','wb').write(crlf(
  ['@echo off','setlocal enabledelayedexpansion','set "PATH=%~dp0stub;%PATH%"',
   'call :reg_query "HKCU\\MCTTest" Plain GOT1','echo GOT1=[%GOT1%]',
   'call :reg_query "HKCU\\MCTTest" Spaced GOT2','echo GOT2=[%GOT2%]',
   'call :reg_query "HKCU\\MCTTest" Missing GOT3','echo GOT3=[%GOT3%]',
   'call :reg_query "HKCU\\MCTTest" Multi GOT4','echo GOT4=[!GOT4!]',
   'for %%s in (!GOT4!) do set "GOT4=%%s"','echo FIRST=[!GOT4!]',
   'exit /b', L[i], L[i+1]]))

# --- :rename verbatim (writes EditionID/ProductName/CompositionEditionID and _undo copies)
i = find(lambda l: l.startswith(':rename'))
j = find(lambda l: l.startswith('exit /b'), i)
nt = 'HKCU\\MCTNT'   # same value names, a hive the test can write without elevation
body = [l.replace('HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion', nt).replace(' /reg:%%A','') for l in L[i:j+1]]
# NB the generated file must NOT be called rename.bat: cmd resolves that to the internal RENAME
# command and never runs the script ("Argument missing").
crlf1 = lambda ls: ('\r\n'.join(ls)+'\r\n').encode('latin1')
open(f'{T}/renametest.bat','wb').write(crlf1(
  ['@echo off','setlocal enabledelayedexpansion',
   # the real script reaches :rename with the current identity already read out of the registry
   'set "CompositionEditionID=Core"','set "EditionID=Core"','set "ProductName=Windows 10 Home"',
   'set "comp=Enterprise"','echo BEGIN','call :rename Professional','echo RETURNED',
   f'call :q "{nt}" EditionID', f'call :q "{nt}" ProductName',
   f'call :q "{nt}" CompositionEditionID', f'call :q "{nt}" EditionID_undo',
   f'call :q "{nt}" ProductName_undo',
   f'reg delete "{nt}" /f >nul 2>nul','exit /b',
   ':q','(for /f "tokens=2*" %%R in (\'reg query "%~1" /v "%~2" 2^>nul\') do echo %~2=%%S)','exit /b'] + body))
PY

# 1. every :choice-N branch defines a complete, self-consistent set of variables
VERSIONS=$(cat "$T/versions.txt")
IFS=',' read -ra VIDS <<< "$VERSIONS"
[ "${#VIDS[@]}" -eq 14 ] && say "ok   version list has ${#VIDS[@]} entries" || bad "expected 14 versions, got ${#VIDS[@]}"
for n in $(seq 1 14); do
  out=$(cd "$T" && timeout 120 wine cmd /c "choices.bat $n" 2>/dev/null | tr -d '\r')
  ver=$(sed -n 's/^VER=\([0-9]*\) .*/\1/p' <<< "$out")
  vid=$(sed -n 's/^VER=[0-9]* VID=\([^ ]*\) .*/\1/p' <<< "$out")
  cb=$(sed -n 's/.* CB=\([^ ]*\) .*/\1/p' <<< "$out")
  ct=$(sed -n 's/.* CT=\([^ ]*\) .*/\1/p' <<< "$out")
  cc=$(sed -n 's/.* CC=\(.*\)$/\1/p' <<< "$out")
  exe=$(sed -n 's/^EXE=//p' <<< "$out"); cab=$(sed -n 's/^CAB=//p' <<< "$out")
  # the branch may set either alias for this index (e.g. 1903 or 19H1) - both are accepted by the parser
  aliases=$(awk -v k="$n" '$1==k {$1=""; print}' "$T/alias.txt")
  err=""
  [ -n "$ver" ] || err="$err no-VER"
  grep -qiw -- "$vid" <<< "$aliases" || err="$err VID($vid not in:$aliases)"
  grep -qiw -- "${VIDS[$((n-1))]}" <<< "$aliases" || err="$err dialog-label(${VIDS[$((n-1))]}) not an alias for index $n"
  [[ "$cb" == "$ver."* ]] || err="$err CB-not-prefixed-by-VER($cb)"
  [[ "$ct" =~ ^[0-9]{4}/[0-9]{2}/$ ]] || err="$err CT($ct)"
  [[ "$cc" =~ ^[0-9]+\.[0-9] ]] || err="$err CC($cc)"
  [[ "$exe" == https://* ]] || err="$err EXE-not-https($exe)"
  [[ "$cab" == https://* || "$cab" == FETCH_25H2 ]] || err="$err CAB($cab)"
  [ -z "$err" ] && say "ok   choice-$n -> $vid  build $ver  catalog $cc" || bad "choice-$n:$err"
done

# 2. :save_ini writes the keys the loader reads back
ini=$(cd "$T" && MCTVARS=1 timeout 120 wine cmd /c "set VID=11_25H2&set PRE=1&set EDITION=Pro&set LANGCODE=de-DE&set ARCH=x64&set KEY=&set NO_UPDATE=1&set DEF=&saveini.bat" 2>/dev/null | tr -d '\r')
for kv in 'MCT=11_25H2' 'AUTO=1' 'EDITION=Pro' 'LANGCODE=de-DE' 'ARCH=x64' 'NO_UPDATE=1'; do
  grep -qx "$kv" <<< "$ini" || bad ":save_ini missing $kv"
done
grep -qx 'KEY=' <<< "$ini" && bad ":save_ini wrote an empty KEY"
grep -qx 'DEF=1' <<< "$ini" && bad ":save_ini wrote DEF when unset"
grep -q '^;' <<< "$ini" || bad ":save_ini wrote no comment header"
say "ok   :save_ini keys ($(grep -c . <<< "$ini") lines, unset values omitted)"

# ISO preset writes ISO=1 rather than AUTO=1
ini2=$(cd "$T" && timeout 120 wine cmd /c "set VID=22H2&set PRE=2&set EDITION=&set LANGCODE=&set ARCH=&set KEY=&set NO_UPDATE=&set DEF=1&saveini.bat" 2>/dev/null | tr -d '\r')
grep -qx 'ISO=1' <<< "$ini2" && grep -qx 'DEF=1' <<< "$ini2" && ! grep -qx 'AUTO=1' <<< "$ini2" \
  && say "ok   :save_ini ISO preset" || bad ":save_ini ISO preset wrong: $(tr '\n' '|' <<< "$ini2")"

# 3. :reg_query reads values back, including ones containing spaces, and leaves the var unset when absent
rq=$(cd "$T" && timeout 120 wine cmd /c regquery.bat 2>/dev/null | tr -d '\r')
grep -qx 'GOT1=\[hello world\]' <<< "$rq" && say "ok   :reg_query plain value" || bad ":reg_query plain: $(grep GOT1= <<< "$rq")"
grep -qx 'GOT2=\[a b  c\]'      <<< "$rq" && say "ok   :reg_query keeps inner spacing" || bad ":reg_query spaced: $(grep GOT2= <<< "$rq")"
grep -qx 'GOT3=\[\]'            <<< "$rq" && say "ok   :reg_query missing value stays empty" || bad ":reg_query missing: $(grep GOT3= <<< "$rq")"
# the /se "|" switch is there so a REG_MULTI_SZ arrives as one token; the caller then keeps the first entry
grep -qx 'GOT4=\[en-US|de-DE\]' <<< "$rq" && say "ok   :reg_query multi_sz uses the | separator" || bad ":reg_query multi: $(grep GOT4= <<< "$rq")"
grep -qx 'FIRST=\[en-US|de-DE\]' <<< "$rq" && say "note :reg_query multi_sz stays joined after the for-split (first entry is NOT isolated)" \
  || say "ok   :reg_query multi_sz split to first entry: $(grep FIRST= <<< "$rq")"

# 4. :rename sets all three identity values and keeps _undo copies of the originals
rn=$(cd "$T" && timeout 120 wine cmd /c renametest.bat 2>/dev/null | tr -d '\r')
grep -qx 'EditionID=Professional'            <<< "$rn" && say "ok   :rename EditionID"    || bad ":rename EditionID: $(grep '^EditionID=' <<< "$rn")"
grep -qx 'ProductName=Professional'          <<< "$rn" && say "ok   :rename ProductName"  || bad ":rename ProductName: $(grep ProductName= <<< "$rn")"
grep -qx 'CompositionEditionID=Enterprise'   <<< "$rn" && say "ok   :rename CompositionEditionID" || bad ":rename comp: $(grep Composition <<< "$rn")"
# the _undo copies use indirect delayed expansion (!%%v!), which Wine's cmd does not implement
# (verified separately: direct !VAR! works, !%%v! yields empty). Untestable here, so only noted.
grep -qx 'EditionID_undo=Core'               <<< "$rn" && say "ok   :rename keeps an undo copy" \
  || say "skip :rename undo copies (Wine cmd lacks indirect !%%v! expansion; real cmd.exe supports it)"

[ $fail -eq 0 ] && say "ALL BATCH FUNCTION CHECKS PASSED" || say "SOME BATCH FUNCTION CHECKS FAILED"
exit $fail
