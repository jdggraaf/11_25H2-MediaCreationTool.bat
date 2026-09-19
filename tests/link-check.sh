#!/usr/bin/env bash
# Probes every URL referenced by MediaCreationTool.bat and by the markdown docs with a 1 KB ranged GET.
# Prints a status table; exits 1 on any failure.
#
# curl reports 000 both for "host is down" and for "something between us refused the connection", so a
# sandbox that blocks outbound traffic would otherwise look like a wall of dead links. Any 000 is
# therefore re-tested for reachability and reported as BLOCKED (not counted as a failure) when the
# connection never got off the ground; pass STRICT=1 to count those as failures instead.
cd "$(dirname "$0")/.."
fail=0; blocked=0
probe()   { curl -sS -o /dev/null -w '%{http_code}' --max-time "$2" -A 'Mozilla/5.0' -r 0-1023 "$1" 2>/dev/null; }
# some hosts reject a ranged GET outright (403/405/416) while serving the same url fine unranged
probe_nr() { curl -sS -o /dev/null -w '%{http_code}' --max-time "$2" -A 'Mozilla/5.0' "$1" 2>/dev/null; }

urls() {
  tr -d '\r' < MediaCreationTool.bat | grep -oE 'https?://[A-Za-z0-9./_%?=&:-]+'
  # markdown link targets and bare urls in the docs
  cat README.md CONTRIBUTING.md REVIEW.md REDESIGN.md docs/*.md bypass11/readme.md 2>/dev/null \
    | grep -oE 'https?://[A-Za-z0-9./_%?=&:#@~+-]+' | sed 's/[).,]*$//'
}

while read -r u; do
  code=$(probe "$u" 40)
  case "$code" in 2*|3*) ;; *) code=$(probe "$u" 90) ;; esac
  case "$code" in 403|405|416) code=$(probe_nr "$u" 90) ;; esac
  case "$code" in
    2*|3*) st=ok ;;
    000)   # tell "cannot leave this network" apart from "this link is dead"
           if curl -sS -o /dev/null --max-time 20 -I "$u" 2>&1 | grep -qiE 'tunnel failed|403|proxy'; then
             st=BLOCKED; blocked=$((blocked+1))
           else st=FAIL; fail=1; fi ;;
    403)   # a sandbox gateway can answer 403 in place of the host; its body says so, a real host's does not
           if curl -sS --max-time 20 -A 'Mozilla/5.0' "$u" 2>/dev/null \
              | grep -qiE 'not enabled for this session|agentproxy|policy denial'; then
             st=BLOCKED; blocked=$((blocked+1))
           else st=FAIL; fail=1; fi ;;
    *)     st=FAIL; fail=1 ;;
  esac
  printf '%-10s %-4s %s\n' "$st" "$code" "$u"
done < <(urls | grep -vE 'schemas.microsoft.com|w3.org|EULA_MCTool_$|b1.download.windowsupdate.com/$|fe3.delivery|tlu.dl.delivery.mp.microsoft.com/$' | sort -u)

echo "note: fe3.delivery.mp.microsoft.com uses a Microsoft-private CA (trusted by Windows, not by curl) and is not probed"
[ "$blocked" -gt 0 ] && echo "note: $blocked url(s) could not be reached from this network (egress blocked), not counted as failures - rerun with STRICT=1 to fail on those"
[ -n "${STRICT:-}" ] && [ "$blocked" -gt 0 ] && fail=1
exit $fail
