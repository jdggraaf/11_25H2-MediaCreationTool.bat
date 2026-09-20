# Runs the real SETUP_GUI function from MediaCreationTool.bat against a mock WinForms layer (WinFormsMock.cs)
# so its selection maths, validation, greying-out and return string can be tested on any OS with pwsh.
# Usage: pwsh -File tests/dialog-mock/run.ps1 MediaCreationTool.bat
param([string]$Bat)
$ErrorActionPreference = 'Stop'
# on Windows [Windows.Forms.Form] resolves to the real System.Windows.Forms and the dialog would really open, so the mock
# lives in its own MockUI namespace and the function text is pointed at it
$mock = [io.file]::ReadAllText("$PSScriptRoot/WinFormsMock.cs") -replace 'namespace (Drawing|Windows\.Forms) ', 'namespace MockUI.$1 '
Add-Type -TypeDefinition $mock
function Mockify ($t) { $t -replace '(?<![\w.])(Windows\.Forms\.|Drawing\.)', 'MockUI.$1' }
$f0 = [io.file]::ReadAllText($Bat); $0 = Mockify ($f0 -split '#\:SETUP_GUI\:',3)[1]
# make Pick/Val etc visible: define the function in this scope
iex $0
$env:VERSIONS='1703,1709,1903,1909,20H1,20H2,21H1,21H2,22H2,11_21H2,11_22H2,11_23H2,11_24H2,11_25H2'
$env:PRESETS='&Auto Upgrade,Auto &ISO,Auto &USB,&Select,MCT &Defaults'
$env:OS_EDITION='Professional'; $env:OS_LANGCODE='en-US'; $env:OS_ARCH='x64'
function Run ($dV,$dP,$edition,$lang,$arch,$key,$noupd,$def,$result='OK',[scriptblock]$tweak) {
  $env:dV="$dV"; $env:dP="$dP"; $env:EDITION=$edition; $env:LANGCODE=$lang; $env:ARCH=$arch; $env:KEY=$key; $env:NO_UPDATE=$noupd; $env:DEF=$def
  [MockUI.Windows.Forms.Form]::NextResult = $result
  $global:tweak = $tweak
  SETUP_GUI
}
# hook: the function calls $f.Add_Shown({...}); our mock fires Shown inside ShowDialog. We use a second Shown handler via a wrapper:
# simplest: patch the function text so that right before ShowDialog it invokes $global:tweak with the form and controls.
$patched = $0 -replace 'if \(\$f\.ShowDialog\(\)', 'if ($global:tweak) { & $global:tweak $f $lb $rbs $cbE $cbL $cbA $tbK $ckU $ckX $ckS $ok }; if ($f.ShowDialog()'
if ($patched -eq $0) { throw 'hook not injected' }
iex $patched
$pass=0; $fail=0
function Check ($name, $got, $want) { if ("$got" -eq "$want") { $script:pass++; "ok   $name -> $got" } else { $script:fail++; "FAIL $name -> got [$got] want [$want]" } }

Check 'defaults (25H2, Select)'          (Run 14 4 '' '' '' '' '' '')                          '14 4 - - - - - - -'
Check 'cancel'                            (Run 14 4 '' '' '' '' '' '' 'Cancel')                 '0 0 - - - - - - -'
Check 'env preselect Enterprise de-DE x86 no_update def' (Run 14 1 'Enterprise' 'de-DE' 'x86' '' '1' 'def') '14 1 Enterprise de-DE x86 - no_update def -'
Check 'preselect ini version 9 (22H2) + AUTO' (Run 9 1 '' '' '' '' '' '')                          '9 1 - - - - - - -'
Check 'pick oldest via list + USB + key + save' (Run 14 4 '' '' '' '' '' '' 'OK' { param($f,$lb,$rbs,$cbE,$cbL,$cbA,$tbK,$ckU,$ckX,$ckS,$ok)
   $lb.SelectedIndex = $lb.Items.Count - 1; $rbs[3].Checked=$false; $rbs[2].Checked=$true; $rbs[2].FireCheckedChanged(); $tbK.Text='VK7JG-NPHTM-C97JM-9MPGT-3V66T'; $tbK.FireTextChanged(); $ckS.Checked=$true }) '1 3 - - - VK7JG-NPHTM-C97JM-9MPGT-3V66T - - save'
Check 'Select greys out edition (value dropped)' (Run 14 1 'Enterprise' 'de-DE' '' '' '' '' 'OK' { param($f,$lb,$rbs,$cbE,$cbL,$cbA,$tbK,$ckU,$ckX,$ckS,$ok)
   $rbs[0].Checked=$false; $rbs[3].Checked=$true; $rbs[3].FireCheckedChanged(); if ($cbE.Enabled -or $tbK.Enabled) { throw 'options not disabled for Select' }; if (-not $ckU.Enabled) { throw 'checkboxes wrongly disabled for Select' } }) '14 4 - - - - - - -'
Check 'MCT Defaults greys out everything'  (Run 14 1 'Enterprise' '' '' '' '1' 'def' 'OK' { param($f,$lb,$rbs,$cbE,$cbL,$cbA,$tbK,$ckU,$ckX,$ckS,$ok)
   $rbs[0].Checked=$false; $rbs[4].Checked=$true; $rbs[4].FireCheckedChanged(); if ($ckU.Enabled -or $ckX.Enabled) { throw 'extras not disabled for Defaults' } }) '14 5 - - - - - - -'
Check 'bad key disables Start'            (Run 14 1 '' '' '' '' '' '' 'OK' { param($f,$lb,$rbs,$cbE,$cbL,$cbA,$tbK,$ckU,$ckX,$ckS,$ok)
   $tbK.Text='NOT-A-KEY'; $tbK.FireTextChanged(); if ($ok.Enabled) { throw 'Start enabled with bad key' }; $tbK.Text=''; $tbK.FireTextChanged(); if (-not $ok.Enabled) { throw 'Start not re-enabled' } }) '14 1 - - - - - - -'
Check 'preloaded bad key disables Start at open' (Run 14 1 '' '' '' 'BADKEY' '' '' 'OK' { param($f,$lb,$rbs,$cbE,$cbL,$cbA,$tbK,$ckU,$ckX,$ckS,$ok)
   if ($ok.Enabled) { throw 'Start enabled with preloaded bad key' }; $tbK.Text=''; $tbK.FireTextChanged() }) '14 1 - - - - - - -'
Check 'typed language with space disables Start' (Run 14 1 '' '' '' '' '' '' 'OK' { param($f,$lb,$rbs,$cbE,$cbL,$cbA,$tbK,$ckU,$ckX,$ckS,$ok)
   $cbL.Text='de DE'; $cbL.FireTextChanged(); if ($ok.Enabled) { throw 'Start enabled with space in language' }; $cbL.Text='sr-Latn-RS'; $cbL.FireTextChanged(); if (-not $ok.Enabled) { throw 'valid 3-part language rejected' } }) '14 1 - sr-Latn-RS - - - - -'
Check 'layout: every control inside client area' (Run 14 4 '' '' '' '' '' '' 'OK' { param($f,$lb,$rbs,$cbE,$cbL,$cbA,$tbK,$ckU,$ckX,$ckS,$ok)
   foreach ($c in $f.Controls) { if ($c.Location.X -lt 0 -or $c.Location.Y -lt 0 -or ($c.Location.Y + [Math]::Max($c.Size.Height,20)) -gt $f.ClientSize.Height -or ($c.Location.X + $c.Size.Width) -gt $f.ClientSize.Width) { throw "control outside client: '$($c.Text)' at $($c.Location) size $($c.Size)" } } }) '14 4 - - - - - - -'
Check 'list labels'                        ((Run 14 4 '' '' '' '' '' '' 'OK' { param($f,$lb) $script:items = @($lb.Items) }) + ' | ' + $script:items[0] + ' | ' + $script:items[-1]) '14 4 - - - - - - - | Windows 11 25H2   (latest) | Windows 10 1703'
"`n$pass passed, $fail failed"; if ($fail) { exit 1 }
