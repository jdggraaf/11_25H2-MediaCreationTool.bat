# Prints the sha256 of every static products*.cab the version ladder downloads, as ready-to-paste
# `set "CABSHA=..."` lines, so DOWNLOAD can discard a catalog that does not match.
#
# Needs a machine that can reach download.microsoft.com. Only the dated catalogs are listed: the
# 25H2 entry is fetched live from the metadata service and verified against the digest it returns.
#
#   pwsh -File tests/pin-hashes.ps1              download each catalog and print its pin
#   pwsh -File tests/pin-hashes.ps1 -ListOnly    just print what would be fetched (no network)
param([string]$Bat = "$PSScriptRoot/../MediaCreationTool.bat", [switch]$ListOnly)
$ErrorActionPreference = 'Stop'
$lines = [io.file]::ReadAllText($Bat) -split "`r`n"

# walk the :choice-N ladder: each block sets VID then CAB
$rows = @(); $vid = $null
foreach ($l in $lines) {
  if ($l -match '^:choice-\d+') { $vid = $null; continue }
  if ($l -match 'set "VID=([^"]+)"') { $vid = $matches[1] }
  if ($vid -and $l -match '^set "CAB=(https://[^"]+)"') { $rows += [pscustomobject]@{ VID = $vid; Url = $matches[1] }; $vid = $null }
}
if ($ListOnly) { $rows | % { '{0,-8} {1}' -f $_.VID, $_.Url }; return }

$T = Join-Path ([IO.Path]::GetTempPath()) ("pin-" + [guid]::NewGuid().ToString('N')); $null = New-Item -ItemType Directory $T
foreach ($r in $rows) {
  $f = Join-Path $T ($r.VID + '.cab')
  try { Invoke-WebRequest -Uri $r.Url -OutFile $f -UserAgent 'Mozilla/5.0' -ErrorAction Stop }
  catch { Write-Warning "$($r.VID): $($_.Exception.Message)"; continue }
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLowerInvariant()
  '{0,-8} set "CABSHA={1}"   {2:N0} bytes' -f $r.VID, $h, (Get-Item -LiteralPath $f).Length
}
Remove-Item -LiteralPath $T -Recurse -Force
