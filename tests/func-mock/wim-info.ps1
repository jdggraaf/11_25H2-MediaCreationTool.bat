# Exercises the real WIM_INFO function against a synthetic .esd built to the same layout it scans for:
# a >2-block file whose tail holds a UTF-16LE XML manifest introduced by an FF FE mark, so the backward
# block scan, the 0xFE rewind, the </WIM> forward search and every output mode can be asserted offline.
param([string]$Bat = "$PSScriptRoot/../../MediaCreationTool.bat")
$ErrorActionPreference = 'Stop'
$0 = ([io.file]::ReadAllText($Bat) -split '#[:]WIM_INFO[:]',3)[1]
iex $0

$script:pass = 0; $script:fail = 0
function Check ($name, $got, $want) {
  if ("$got" -eq "$want") { $script:pass++; "ok   $name -> $got" } else { $script:fail++; "FAIL $name -> got [$got] want [$want]" }
}

$T = Join-Path ([IO.Path]::GetTempPath()) ("wim-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $T

function Image ($idx, $arch, $build, $sp, $lang, $ed, $name) {
  "<IMAGE INDEX=`"$idx`"><NAME>$name</NAME><WINDOWS><ARCH>$arch</ARCH><EDITIONID>$ed</EDITIONID>" +
  "<INSTALLATIONTYPE>Client</INSTALLATIONTYPE><LANGUAGES><LANGUAGE>$lang</LANGUAGE></LANGUAGES>" +
  "<VERSION><BUILD>$build</BUILD><SPBUILD>$sp</SPBUILD></VERSION></WINDOWS></IMAGE>"
}
# an ESD the script would meet in the wild: 4 editions, x64, 25H2 build
$xml = '<WIM>' + (Image 1 9 26200 1234 'en-US' 'Core' 'Windows 11 Home') +
                 (Image 2 9 26200 1234 'en-US' 'Professional' 'Windows 11 Pro') +
                 (Image 3 0 26200 1234 'de-DE' 'Education' 'Windows 11 Education') +
                 (Image 4 12 26200 1234 'en-GB' 'Enterprise' 'Windows 11 Enterprise') + '</WIM>'

function BuildEsd ($path, $xmlText, $padBlocks = 3) {
  # padding must contain no 0xFE byte, or the backward rewind would stop short of the FF FE mark
  $fs = [IO.File]::Create($path)
  $pad = New-Object byte[] 2097152; for ($i=0; $i -lt $pad.Length; $i++) { $pad[$i] = 0x41 }
  for ($b=0; $b -lt $padBlocks; $b++) { $fs.Write($pad, 0, $pad.Length) }
  $fs.Write([byte[]]@(0xFF,0xFE), 0, 2)                      # the mark WIM_INFO rewinds to
  $body = [Text.Encoding]::Unicode.GetBytes($xmlText)
  $fs.Write($body, 0, $body.Length)
  $tail = New-Object byte[] 4096; for ($i=0; $i -lt $tail.Length; $i++) { $tail[$i] = 0x41 }
  $fs.Write($tail, 0, $tail.Length)                          # trailing data after </WIM>
  $fs.Dispose()
}

$esd = Join-Path $T 'install.esd'
BuildEsd $esd $xml

# 1. default output (out 0): one CSV line per image, index,build,spbuild,arch,lang,edition,name
$txt = WIM_INFO $esd
$lines = @($txt -split "`r`n" | where { $_ -ne '' })
Check 'line count'              $lines.Count            '4'
Check 'image 1 line'            $lines[0]               '1,26200,1234,x64,en-US,Core,Windows 11 Home'
Check 'image 3 decodes x86'     $lines[2]               '3,26200,1234,x86,de-DE,Education,Windows 11 Education'
Check 'image 4 decodes arm64'   $lines[3]               '4,26200,1234,arm64,en-GB,Enterprise,Windows 11 Enterprise'

# 2. index filter returns only the requested image
$one = @((WIM_INFO $esd 2) -split "`r`n" | where { $_ -ne '' })
Check 'index filter count'      $one.Count              '1'
Check 'index filter content'    $one[0]                 '2,26200,1234,x64,en-US,Professional,Windows 11 Pro'

# 3. out 4 hands back the parsed xml object
$obj = WIM_INFO $esd 0 4
Check 'out 4 returns xml'       $obj.WIM.IMAGE.Count    '4'
Check 'out 4 edition readable'  $obj.WIM.IMAGE[1].WINDOWS.EDITIONID 'Professional'

# 4. out 2 writes a .txt beside the esd; out 3 writes a .xml
$null = WIM_INFO $esd 0 2
$null = WIM_INFO $esd 0 3
Check 'out 2 wrote install.txt' (Test-Path -LiteralPath (Join-Path $T 'install.txt')) 'True'
Check 'out 3 wrote install.xml' (Test-Path -LiteralPath (Join-Path $T 'install.xml')) 'True'
Check 'written txt matches'     ((Get-Content -LiteralPath (Join-Path $T 'install.txt') -Raw) -replace "`r`n$",'' -split "`r`n")[0] '1,26200,1234,x64,en-US,Core,Windows 11 Home'
Check 'written xml well-formed' ([xml](Get-Content -LiteralPath (Join-Path $T 'install.xml') -Raw)).WIM.IMAGE.Count '4'

# 5. a missing optional field collapses to ", " rather than running two commas together
$xml2 = '<WIM>' + (Image 1 9 26200 '' 'en-US' 'Core' 'Windows 11 Home') + '</WIM>'
$esd2 = Join-Path $T 'nosp.esd'; BuildEsd $esd2 $xml2
Check 'empty field padded'      (@((WIM_INFO $esd2) -split "`r`n")[0]) '1,26200, ,x64,en-US,Core,Windows 11 Home'

# 6. a single-image esd still parses (smallest realistic manifest)
$xml3 = '<WIM>' + (Image 1 9 22621 525 'fr-FR' 'Professional' 'Windows 11 Pro') + '</WIM>'
$esd3 = Join-Path $T 'one.esd'; BuildEsd $esd3 $xml3
Check 'single image esd'        (@((WIM_INFO $esd3) -split "`r`n")[0]) '1,22621,525,x64,fr-FR,Professional,Windows 11 Pro'

Remove-Item -LiteralPath $T -Recurse -Force
"`n$pass passed, $fail failed"; if ($fail) { exit 1 }
