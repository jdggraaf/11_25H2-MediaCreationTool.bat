# Exercises the real PRODUCTS_XML function against synthetic catalogs. PRODUCTS_XML rewrites products.xml
# in place, so each case builds a fixture, runs the function and asserts on the saved result: catalog
# wrapping, EULA insertion/rewrite, language relabelling, ARM64/China pruning, business unhiding and the
# edition clones that work around MCT refusing to run on some host editions.
param([string]$Bat = "$PSScriptRoot/../../MediaCreationTool.bat")
$ErrorActionPreference = 'Stop'
$0 = ([io.file]::ReadAllText($Bat) -split '#\:PRODUCTS_XML\:',3)[1]
iex $0

$script:pass = 0; $script:fail = 0
function Check ($name, $got, $want) {
  if ("$got" -eq "$want") { $script:pass++; "ok   $name -> $got" } else { $script:fail++; "FAIL $name -> got [$got] want [$want]" }
}

$T = Join-Path ([IO.Path]::GetTempPath()) ("px-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $T
# the function addresses "$pwd\products.xml"; build the same literal string so both platforms agree
$xmlPath = "$T\products.xml"

function File ($lang, $arch, $edition, $loc, $retail = 'True') {
  "<File><FileName>x.esd</FileName><LanguageCode>$lang</LanguageCode><Architecture>$arch</Architecture>" +
  "<Edition>$edition</Edition><Edition_Loc>$loc</Edition_Loc><IsRetailOnly>$retail</IsRetailOnly>" +
  "<FilePath>http://b1.download.windowsupdate.com/old.esd</FilePath><Size>1</Size><Sha1>abc</Sha1></File>"
}
function Lang ($code, $client = 'Windows 10') {
  "<Language><LanguageCode>$code</LanguageCode><CLIENT>$client</CLIENT><CLIENT_N>$client N</CLIENT_N></Language>"
}
function Catalog ($files, $langs, $wrapped = $false, $eulas = '') {
  $inner = "<PublishedMedia><Languages>$langs</Languages>$eulas<Files>$files</Files></PublishedMedia>"
  if ($wrapped) { "<?xml version=`"1.0`" encoding=`"UTF-8`"?><MCT><Catalogs><Catalog version=`"0.0`">$inner</Catalog></Catalogs></MCT>" }
  else { "<?xml version=`"1.0`" encoding=`"UTF-8`"?>$inner" }
}
function Run ($content, $ver, $vid, $cc = '2.1', $unhide = 1, $insert = 0, $x = '', $vis = '') {
  [io.file]::WriteAllText($xmlPath, $content, [Text.Encoding]::UTF8)
  $env:VER = "$ver"; $env:VID = "$vid"; $env:CC = "$cc"; $env:UNHIDE_BUSINESS = "$unhide"
  $env:INSERT_BUSINESS = "$insert"; $env:X = "$x"; $env:VIS = "$vis"; $env:0 = $Bat
  $env:CB = '26200.6899.251011-1532.25h2_ge_release_svc_refresh'; $env:CT = '2025/10/'
  Push-Location $T
  try { PRODUCTS_XML } finally { Pop-Location }
  [xml]([io.file]::ReadAllText($xmlPath))
}
function Editions ($r) { (@($r.SelectNodes('//File/Edition') | % { $_.InnerText }) | Sort-Object -Unique) -join ',' }

$langs = (Lang 'en-us') + (Lang 'de-de') + (Lang 'default')

# --- 1. a bare <PublishedMedia> catalog is wrapped in the MCT/Catalogs/Catalog envelope MCT expects
$r = Run (Catalog ((File 'en-us' 'x64' 'Professional' 'Windows 10 Pro')) $langs) 26200 '11_25H2'
Check 'bare catalog gets MCT root'     $r.DocumentElement.Name                     'MCT'
Check 'catalog version applied'        $r.MCT.Catalogs.Catalog.version             '2.1'
Check 'PublishedMedia preserved'       ($null -ne $r.MCT.Catalogs.Catalog.PublishedMedia) 'True'

# --- 2. an already-wrapped catalog keeps its shape and just has the version refreshed
$r = Run (Catalog ((File 'en-us' 'x64' 'Professional' 'Windows 10 Pro')) $langs $true) 26200 '11_25H2' '2.5'
Check 'wrapped catalog stays wrapped'  $r.DocumentElement.Name                     'MCT'
Check 'existing version overwritten'   $r.MCT.Catalogs.Catalog.version             '2.5'

# --- 3. EULAs are inserted for every non-default language, with the fixed rtf url
$e = $r.SelectNodes('//EULAS/EULA')
Check 'EULA inserted per language'     $e.Count                                    '2'
Check 'EULA language codes'            ((@($e | % { $_.LanguageCode }) | Sort-Object) -join ',') 'de-de,en-us'
Check 'EULA url pattern'               $e[0].URL 'http://download.microsoft.com/download/C/0/3/C036B882-9F99-4BC9-A4B5-69370C4E17E9/EULA_MCTool_EN-US_6.27.16.rtf'

# --- 4. an existing EULAS block is rewritten to the same fixed url rather than duplicated
$withEulas = '<EULAS><EULA><LanguageCode>en-us</LanguageCode><URL>http://stale/x.rtf</URL></EULA></EULAS>'
$r = Run (Catalog ((File 'en-us' 'x64' 'Professional' 'Windows 10 Pro')) $langs $false $withEulas) 26200 '11_25H2'
$e = $r.SelectNodes('//EULAS/EULA')
Check 'existing EULAS not duplicated'  $e.Count                                    '1'
Check 'existing EULA url rewritten'    $e[0].URL 'http://download.microsoft.com/download/C/0/3/C036B882-9F99-4BC9-A4B5-69370C4E17E9/EULA_MCTool_EN-US_6.27.16.rtf'

# --- 5. language labels: "Windows 10" becomes the target version id, consumer editions get a combined label
$r = Run (Catalog ((File 'en-us' 'x64' 'Professional' 'Windows 10 Pro')) $langs) 26200 '11_25H2'
$l = $r.SelectNodes('//Languages/Language') | where { $_.LanguageCode -eq 'en-us' }
Check 'consumer label (modern)'        $l.CLIENT                                   '11_25H2 Pro | Edu | Home'
Check 'consumer N label'               $l.CLIENT_N                                 '11_25H2 Pro | Edu | Home N'
$r = Run (Catalog ((File 'en-us' 'x64' 'Professional' 'Windows 10 Pro')) $langs) 15063 '1703'
$l = $r.SelectNodes('//Languages/Language') | where { $_.LanguageCode -eq 'en-us' }
Check 'consumer label (<=15063)'       $l.CLIENT                                   '1703 Pro | Home'

# --- 6. Windows 11 uses the "11 <visible name>" form
$r = Run (Catalog ((File 'en-us' 'x64' 'Professional' 'Windows 10 Pro')) $langs) 26200 '11_25H2' '2.1' 1 0 '11' '25H2'
$l = $r.SelectNodes('//Languages/Language') | where { $_.LanguageCode -eq 'en-us' }
Check 'windows 11 label form'          $l.CLIENT                                   '11 25H2 Pro | Edu | Home'

# --- 7. ARM64 entries are dropped; %BASE_CHINA% only below 22000
$files = (File 'en-us' 'x64' 'Professional' 'Windows 10 Pro') + (File 'en-us' 'ARM64' 'Professional' 'Windows 10 Pro') +
         (File 'zh-cn' 'x64' 'Professional' '%BASE_CHINA%')
$r = Run (Catalog $files $langs) 19045 '22H2'
Check 'ARM64 removed'                  (@($r.SelectNodes('//File/Architecture') | % { $_.InnerText }) -contains 'ARM64') 'False'
Check 'china removed below 22000'      (@($r.SelectNodes('//File/Edition_Loc') | % { $_.InnerText }) -contains '%BASE_CHINA%') 'False'
$r = Run (Catalog $files $langs) 26200 '11_25H2'
Check 'china kept at/above 22000'      (@($r.SelectNodes('//File/Edition_Loc') | % { $_.InnerText }) -contains '%BASE_CHINA%') 'True'

# --- 8. business unhiding flips IsRetailOnly and relabels Enterprise
$files = (File 'en-us' 'x64' 'Enterprise' 'Windows 10 Enterprise') + (File 'en-us' 'x64' 'EnterpriseN' 'Windows 10 Enterprise N')
$r = Run (Catalog $files $langs) 26200 '11_25H2' '2.1' 1
$ent = $r.SelectNodes('//File') | where { $_.Edition -eq 'Enterprise' } | select -First 1
Check 'enterprise unhidden'            $ent.IsRetailOnly                           'False'
Check 'enterprise relabelled'          $ent.Edition_Loc                            '11_25H2 Pro | Edu | Enterprise'

# --- 9. with UNHIDE_BUSINESS off, nothing is unhidden and no clones are made
$r = Run (Catalog $files $langs) 26200 '11_25H2' '2.1' 0
$ent = $r.SelectNodes('//File') | where { $_.Edition -eq 'Enterprise' } | select -First 1
Check 'unhide off keeps retail flag'   $ent.IsRetailOnly                           'True'
Check 'unhide off makes no clones'     (Editions $r)                               'Enterprise,EnterpriseN'

# --- 10. Education is only unhidden on the oldest builds
$files = (File 'en-us' 'x64' 'Education' 'Windows 10 Education')
$r = Run (Catalog $files $langs) 15063 '1703'
Check 'education unhidden <=15063'     (@($r.SelectNodes('//File') | where { $_.Edition -eq 'Education' })[0].IsRetailOnly) 'False'
$r = Run (Catalog $files $langs) 26200 '11_25H2'
Check 'education untouched >15063'     (@($r.SelectNodes('//File') | where { $_.Edition -eq 'Education' })[0].IsRetailOnly) 'True'

# --- 11. host-edition clones: modern builds clone Enterprise into the three awkward SKUs
$files = (File 'en-us' 'x64' 'Enterprise' 'Windows 10 Enterprise') + (File 'en-us' 'x64' 'EnterpriseN' 'Windows 10 Enterprise N')
$r = Run (Catalog $files $langs) 26200 '11_25H2'
Check 'modern clone set'               (Editions $r) 'Embedded,Enterprise,EnterpriseN,EnterpriseS,EnterpriseSN,IoTEnterpriseS'
Check 'clones are not retail only'     ((@($r.SelectNodes('//File') | where { $_.Edition -eq 'EnterpriseS' } | % { $_.IsRetailOnly }) | Sort-Object -Unique) -join ',') 'False'

# --- 12. <=16299 additionally clones the ProfessionalEducation / Workstation SKUs.
#    The non-N list is correct. The N list is NOT: $cloneN is initialised as a bare string
#    ('EnterpriseSN') instead of an array, so `+=` concatenates rather than appends and the three
#    N clones collapse into one entry with a joined-up Edition name. Pinned as-is so the defect is
#    locked down and any fix shows up here as a deliberate change.
$r = Run (Catalog $files $langs) 16299 '1709'
Check 'legacy clone set (non-N correct)' (@($r.SelectNodes('//File/Edition') | % { $_.InnerText } | Sort-Object -Unique) -notcontains 'ProfessionalEducationN') 'True'
Check 'legacy N clones collapse (known defect)' (Editions $r) 'Embedded,Enterprise,EnterpriseN,EnterpriseS,EnterpriseSNProfessionalEducationN ProfessionalWorkstationN,IoTEnterpriseS,ProfessionalEducation,ProfessionalWorkstation'

# --- 13. <=10586 clones from Professional instead, because those builds have no Enterprise entries
#    (same $cloneN defect applies, with 'EnterpriseN' concatenated in as well)
$files = (File 'en-us' 'x64' 'Professional' 'Windows 10 Pro') + (File 'en-us' 'x64' 'ProfessionalN' 'Windows 10 Pro N')
$r = Run (Catalog $files $langs) 10586 '1511'
Check 'professional is clone source'   (@($r.SelectNodes('//File/Edition') | % { $_.InnerText }) -contains 'Enterprise') 'True'
Check 'legacy N clones collapse (known defect)' (Editions $r) 'Embedded,Enterprise,EnterpriseS,EnterpriseSNEnterpriseNProfessionalEducationN ProfessionalWorkstationN,IoTEnterpriseS,Professional,ProfessionalEducation,ProfessionalN,ProfessionalWorkstation'

# --- 14. the saved file is still well-formed xml and keeps its declaration
Check 'output parses as xml'           ($null -ne ([xml]([io.file]::ReadAllText($xmlPath))))       'True'
Check 'xml declaration kept'           ([io.file]::ReadAllText($xmlPath).StartsWith('<?xml'))      'True'

[io.file]::Delete($xmlPath); [io.directory]::Delete($T, $true)
"`n$pass passed, $fail failed"; if ($fail) { exit 1 }
