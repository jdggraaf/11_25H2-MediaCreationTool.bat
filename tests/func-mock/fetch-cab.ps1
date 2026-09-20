# Exercises the real FETCH_25H2_CAB function with the registry, the metadata service and the CDN all mocked,
# so the request it builds, the country/version derivation, the response shapes it accepts and above all the
# SHA256 digest check can be asserted without contacting Microsoft.
param([string]$Bat = "$PSScriptRoot/../../MediaCreationTool.bat")
$ErrorActionPreference = 'Stop'
$0 = ([io.file]::ReadAllText($Bat) -split '#\:FETCH_25H2_CAB\:',3)[1]
iex $0

$script:pass = 0; $script:fail = 0
function Check ($name, $got, $want) {
  if ("$got" -eq "$want") { $script:pass++; "ok   $name -> $got" } else { $script:fail++; "FAIL $name -> got [$got] want [$want]" }
}

$T = Join-Path ([IO.Path]::GetTempPath()) ("cab-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $T

$script:payload = [Text.Encoding]::ASCII.GetBytes('MSCF-fake-cab-payload')
$script:goodDigest = [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash($script:payload))
$script:body = $null; $script:fetched = $null; $script:response = $null; $script:restThrows = $false

function Get-ItemProperty { param($Path) [pscustomobject]@{ CurrentBuild = '26100'; UBR = 4946; EditionID = 'Core' } }
# FETCH_25H2_CAB addresses its output as "$pwd\products$env:VID.cab". On Windows that is an ordinary path;
# on Linux the backslash is a literal name character the PowerShell provider cannot round-trip, so Get-Item
# and Remove-Item are redirected to the framework file APIs, which take the name literally on both platforms.
function Get-Item { [CmdletBinding()] param([Parameter(Position=0)]$Path) [pscustomobject]@{ Length = [io.file]::ReadAllBytes("$Path").Length } }
function Remove-Item { [CmdletBinding()] param([Parameter(Position=0)]$Path,[switch]$Force,[switch]$Recurse) [io.file]::Delete("$Path") }
function Get-Culture { New-Object System.Globalization.CultureInfo 'en-GB' }
function Invoke-RestMethod {
  param($Uri,$Method,$Headers,$ContentType,$Body,$ErrorAction,$TimeoutSec)
  $script:body = $Body | ConvertFrom-Json
  if ($script:restThrows) { throw 'service unavailable' }
  return $script:response
}
function Invoke-WebRequest {
  param($Uri,$Headers,$OutFile,$ErrorAction)
  $script:fetched = $Uri
  [io.file]::WriteAllBytes($OutFile, $script:payload)
}
function Attrs { $h=@{}; foreach ($p in ($script:body.DeviceAttributes -split ';')) { $k,$v = $p -split '=',2; $h[$k]=$v }; $h }

function Run ($digest = $script:goodDigest, $shape = 'object') {
  $loc = [pscustomobject]@{ Url = 'http://cdn.invalid/windows.products.cab'; Digest = $digest }
  switch ($shape) {
    'object'  { $script:response = [pscustomobject]@{ FileLocations = @($loc) } }
    'array'   { $script:response = @([pscustomobject]@{ FileLocations = @($loc) }) }
    'updates' { $script:response = [pscustomobject]@{ Updates = @([pscustomobject]@{ FileLocations = @($loc) }) } }
    'empty'   { $script:response = [pscustomobject]@{ FileLocations = @() } }
    'null'    { $script:response = $null }
  }
  $script:fetched = $null
  if ([io.file]::Exists($script:outPath)) { [io.file]::Delete($script:outPath) }
  $env:VID = '11_25H2'
  Push-Location $T
  try { $rc = FETCH_25H2_CAB 6>$null } finally { Pop-Location }
  return $rc
}
# the exact expression the function builds, so the test looks where the function actually writes
$script:outPath = "$T\products11_25H2.cab"

# the real shape of CB in the script: build.ubr.date-time.branch
$realCB = '26200.6899.251011-1532.25h2_ge_release_svc_refresh'
$env:CB = $realCB; $env:EDITION = 'Pro'; $env:LANGCODE = 'de-DE'; $env:MEDIA_LANGCODE = ''

# 1. happy path: digest matches, cab is kept, rc 0
Check 'valid digest returns 0'      (Run) '0'
Check 'cab written'                 ([io.file]::Exists($script:outPath)) 'True'
Check 'cab kept intact'             ([io.file]::ReadAllBytes($script:outPath).Length) $script:payload.Length

# 2. the integrity check actually bites: a wrong digest discards the file and fails
Check 'bad digest returns 1'        (Run 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=') '1'
Check 'bad digest deletes the cab'  ([io.file]::Exists($script:outPath)) 'False'

# 3. no digest supplied -> file is kept (nothing to verify against)
Check 'absent digest returns 0'     (Run $null) '0'
Check 'absent digest keeps cab'     ([io.file]::Exists($script:outPath)) 'True'

# 4. every response shape the parser claims to handle
Check 'array response'              (Run $script:goodDigest 'array')   '0'
Check 'nested Updates response'     (Run $script:goodDigest 'updates') '0'
Check 'empty FileLocations -> 1'    (Run $script:goodDigest 'empty')   '1'
Check 'null response -> 1'          (Run $script:goodDigest 'null')    '1'

# 5. a throwing metadata service is caught, not propagated
$script:restThrows = $true
Check 'service error returns 1'     (Run) '1'
$script:restThrows = $false

# 6. request shape: version floor derived from CB, LCU version from CB, country from LANGCODE
$null = Run
Check 'product floor from CB'       ($script:body.Products) 'PN=Windows.Products.Cab.amd64&V=26200.0.0.0'
$a = Attrs
Check 'LCUVersion from CB'          $a['LCUVersion']            '10.0.26200.6899'
Check 'MediaVersion matches LCU'    $a['MediaVersion']          '10.0.26200.6899'
Check 'country from LANGCODE'       $a['IsoCountryShortCode']   'DE'
Check 'edition from EDITION'        $a['EditionId']             'Pro'
Check 'composition edition'         $a['CompositionEditionId']  'Pro'
Check 'installation type'           $a['InstallationType']      'Client'
Check 'architecture'                $a['OSArchitecture']        'AMD64'

# 6b. a CB without the ubr field falls back to the running build/UBR from the registry
$env:CB = '26200.1234'; $null = Run
Check 'malformed CB falls back'     (Attrs)['LCUVersion']       '10.0.26100.4946'
Check 'floor still derived from CB' ($script:body.Products)     'PN=Windows.Products.Cab.amd64&V=26200.0.0.0'
$env:CB = $realCB

# 7. country falls back to MEDIA_LANGCODE, then to the host culture
$env:LANGCODE = ''; $env:MEDIA_LANGCODE = 'fr-FR'; $null = Run
Check 'country from MEDIA_LANGCODE' (Attrs)['IsoCountryShortCode'] 'FR'
$env:MEDIA_LANGCODE = ''; $null = Run
Check 'country from host culture'   (Attrs)['IsoCountryShortCode'] 'GB'

# 8. the region is the LAST subtag, so a script subtag must not shift it (sr-Latn-RS is a language
#    the script explicitly supports; taking parts[1] would give LA, Laos)
$env:LANGCODE = 'sr-Latn-RS'; $null = Run
Check 'country from 3-part code'    (Attrs)['IsoCountryShortCode'] 'RS'
$env:LANGCODE = 'zh-Hans-CN'; $null = Run
Check 'country from script subtag'  (Attrs)['IsoCountryShortCode'] 'CN'
# a UN M49 region (es-419) is not a 2-letter code, so it takes the RegionInfo path; .NET resolves
# that one rather than throwing, so it yields 419 (the old parts[1] path would have given "41")
$env:LANGCODE = 'es-419'; $null = Run
Check 'numeric region via RegionInfo' (Attrs)['IsoCountryShortCode'] '419'

# 9. no EDITION set -> documented defaults, and no CB -> the 26100 floor
$env:LANGCODE = 'en-US'; $env:EDITION = ''; $env:CB = ''; $null = Run
Check 'default composition edition' (Attrs)['CompositionEditionId'] 'Enterprise'
Check 'editionId from registry'     (Attrs)['EditionId']            'Core'
Check 'default floor without CB'    ($script:body.Products)         'PN=Windows.Products.Cab.amd64&V=26100.0.0.0'
Check 'LCU from registry build/ubr' (Attrs)['LCUVersion']           '10.0.26100.4946'

if ([io.file]::Exists($script:outPath)) { [io.file]::Delete($script:outPath) }
[io.directory]::Delete($T, $true)
"`n$pass passed, $fail failed"; if ($fail) { exit 1 }
