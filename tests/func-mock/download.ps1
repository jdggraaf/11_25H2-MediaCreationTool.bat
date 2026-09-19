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

function RunDownload ($url, $name, $succeedAt) {
  $script:log = @(); $script:succeedAt = $succeedAt
  $f = Join-Path $T $name
  if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
  DOWNLOAD $url $name $T
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

Remove-Item -LiteralPath $T -Recurse -Force
"`n$pass passed, $fail failed"; if ($fail) { exit 1 }
