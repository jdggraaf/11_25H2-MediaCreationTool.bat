# Exercises the real DOWNLOAD function from MediaCreationTool.bat against mocked transfer mechanisms.
# Every mechanism DOWNLOAD can use (BITS, Invoke-WebRequest, bitsadmin, WebClient) is replaced by a
# function that records the url it was handed, so the fallback order and the https-before-http rule
# can be asserted without touching the network.
param([string]$Bat = "$PSScriptRoot/../../MediaCreationTool.bat")
$ErrorActionPreference = 'Stop'
$0 = ([io.file]::ReadAllText($Bat) -split '#\:DOWNLOAD\:',3)[1]
iex $0

$script:pass = 0; $script:fail = 0
function Check ($name, $got, $want) {
  if ("$got" -eq "$want") { $script:pass++; "ok   $name -> $got" } else { $script:fail++; "FAIL $name -> got [$got] want [$want]" }
}

$T = Join-Path ([IO.Path]::GetTempPath()) ("dl-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $T

# --- mocks: each records "<mechanism> <url>" and creates the target file only when $script:succeedAt matches
$script:log = @(); $script:succeedAt = ''
function Note ($mech, $u, $f) {
  $script:log += "$mech $u"
  if ($script:succeedAt -eq $mech) { Set-Content -LiteralPath $f -Value 'payload' -NoNewline }
  else { throw "mock $mech refused" }
}
function Import-Module { param($Name) }
function Start-BitsTransfer { param($Source, $Destination) Note 'bits' $Source $Destination }
function Invoke-WebRequest { param($Uri, $OutFile) Note 'iwr' $Uri $OutFile }
function bitsadmin { $u = $args[-2]; $f = $args[-1]; Note 'bitsadmin' $u $f }
function New-Object {
  param([Parameter(Position=0)]$TypeName, [Parameter(Position=1)]$ArgumentList)
  if ($TypeName -eq 'Net.WebClient') {
    $o = [pscustomobject]@{ Headers = @{} }
    $o.Headers = New-Object2Headers
    $o | Add-Member ScriptMethod DownloadFile { param($u,$f) Note 'webclient' $u $f } -PassThru
  } else { Microsoft.PowerShell.Utility\New-Object @PSBoundParameters }
}
function New-Object2Headers { $h = [pscustomobject]@{}; $h | Add-Member ScriptMethod Add { param($a,$b) } -PassThru }
# DOWNLOAD deletes a bad file with `del`, which the provider cannot round-trip on Linux for the
# test's literal paths; route it to the framework API, which takes the name as given on both platforms
function Remove-Item { [CmdletBinding()] param([Parameter(Position=0)]$Path,[switch]$Force) if ([io.file]::Exists("$Path")) { [io.file]::Delete("$Path") } }
$script:goodSha = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes('payload'))) -replace '-').ToLowerInvariant()

function RunDownload ($url, $name, $succeedAt, $sha = '') {
  $script:log = @(); $script:succeedAt = $succeedAt
  $f = Join-Path $T $name
  if ([io.file]::Exists($f)) { [io.file]::Delete($f) }
  DOWNLOAD $url $name $T $sha
  return $f
}

# 1. https is attempted before http, and every mechanism is tried in order on the https url first
$null = RunDownload 'http://example.invalid/a/b.cab' 'b.cab' 'none'
Check 'full fallback chain order' ($script:log -join ' | ') ('bits https://example.invalid/a/b.cab | iwr https://example.invalid/a/b.cab | bitsadmin https://example.invalid/a/b.cab | webclient https://example.invalid/a/b.cab | ' +
  'bits http://example.invalid/a/b.cab | iwr http://example.invalid/a/b.cab | bitsadmin http://example.invalid/a/b.cab | webclient http://example.invalid/a/b.cab')

# 2. an http:// input url is upgraded to https for the first pass (the https-first rule)
$null = RunDownload 'http://example.invalid/x.esd' 'x.esd' 'none'
Check 'http input tried as https first' $script:log[0] 'bits https://example.invalid/x.esd'

# 3. a https:// input url is still retried over plain http as the last resort
Check 'https input falls back to http' $script:log[4] 'bits http://example.invalid/x.esd'

# 4. stops at the first mechanism that produces the file - nothing after it runs
$f = RunDownload 'https://example.invalid/c.cab' 'c.cab' 'iwr'
Check 'stops after first success' ($script:log -join ' | ') 'bits https://example.invalid/c.cab | iwr https://example.invalid/c.cab'
Check 'success leaves the file'    (Test-Path -LiteralPath $f) 'True'

# 5. an already-present file short-circuits everything (no mechanism is invoked at all)
$script:log = @(); $script:succeedAt = 'none'
Set-Content -LiteralPath (Join-Path $T 'have.cab') -Value 'old' -NoNewline
DOWNLOAD 'https://example.invalid/have.cab' 'have.cab' $T
Check 'existing file skips all transfers' ($script:log.Count) '0'
Check 'existing file is not overwritten'  (Get-Content -LiteralPath (Join-Path $T 'have.cab') -Raw) 'old'

# 6. total failure is reported on stdout and does not throw
$out = RunDownload 'https://example.invalid/gone.cab' 'gone.cab' 'none' 6>&1 | Out-String
Check 'failure is announced' ($out -match 'gone\.cab download failed').ToString() 'True'

# 7. the default path argument is the current directory
Push-Location $T
$script:log = @(); $script:succeedAt = 'bits'
DOWNLOAD 'https://example.invalid/here.cab' 'here.cab'
Pop-Location
Check 'defaults to current directory' (Test-Path -LiteralPath (Join-Path $T 'here.cab')) 'True'

# 8. a pinned sha256 that matches is accepted at the first mechanism that delivers it
$f = RunDownload 'https://example.invalid/p.cab' 'p.cab' 'bits' $script:goodSha
Check 'matching pin accepted'        (($script:log -join '|') + ' / ' + [io.file]::Exists($f)) 'bits https://example.invalid/p.cab / True'

# 9. a pinned sha256 that does NOT match: the file is discarded and the next mechanism is tried, never trusted
$f = RunDownload 'https://example.invalid/q.cab' 'q.cab' 'bits' ('0' * 64)
Check 'mismatch discards and keeps trying' ($script:log.Count) '8'
Check 'mismatch leaves no file'      ([io.file]::Exists($f)) 'False'

# 10. an already-present file is re-verified against the pin - a stale or tampered cache entry is replaced
Set-Content -LiteralPath (Join-Path $T 'c.cab') -Value 'tampered' -NoNewline
$script:log = @(); $script:succeedAt = 'iwr'
DOWNLOAD 'https://example.invalid/c.cab' 'c.cab' $T $script:goodSha 6>$null
Check 'cached mismatch is replaced'  ((Get-Content -LiteralPath (Join-Path $T 'c.cab') -Raw) + ' / ' + $script:log.Count) 'payload / 2'

# 11. a 0-byte stub (a transfer that died) is treated as absent even with no pin, instead of poisoning the cache
Set-Content -LiteralPath (Join-Path $T 'z.cab') -Value '' -NoNewline
$script:log = @(); $script:succeedAt = 'bits'
DOWNLOAD 'https://example.invalid/z.cab' 'z.cab' $T 6>$null
Check 'empty stub is re-downloaded'  ((Get-Content -LiteralPath (Join-Path $T 'z.cab') -Raw) + ' / ' + $script:log.Count) 'payload / 1'

# 12. the pin is case- and whitespace-insensitive (values are pasted from tool output)
$f = RunDownload 'https://example.invalid/u.cab' 'u.cab' 'bits' ("  " + $script:goodSha.ToUpperInvariant() + " ")
Check 'pin normalised'               ([io.file]::Exists($f)) 'True'

[io.directory]::Delete($T, $true)
"`n$pass passed, $fail failed"; if ($fail) { exit 1 }
