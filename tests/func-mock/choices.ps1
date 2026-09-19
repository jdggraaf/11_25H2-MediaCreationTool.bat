# Exercises the real CHOICES and CHOICES2 dialogs against the WinForms mock. Button presses are queued
# on the mock form, so the index maths, the Cancel convention (0) and CHOICES2's "go back to the first
# dialog when the second is cancelled" loop can be asserted without a display.
param([string]$Bat = "$PSScriptRoot/../../MediaCreationTool.bat")
$ErrorActionPreference = 'Stop'
Add-Type -Path "$PSScriptRoot/../dialog-mock/WinFormsMock.cs"
$f0 = [io.file]::ReadAllText($Bat)
$0 = ($f0 -split '#\:CHOICES\:',3)[1]
iex $0

$script:pass = 0; $script:fail = 0
function Check ($name, $got, $want) {
  if ("$got" -eq "$want") { $script:pass++; "ok   $name -> $got" } else { $script:fail++; "FAIL $name -> got [$got] want [$want]" }
}
function Plan ([int[]]$clicks) { [Windows.Forms.Form]::ClickQueue.Clear(); foreach ($c in $clicks) { [void][Windows.Forms.Form]::ClickQueue.Add($c) } }

$three = 'First,Second,Third'

# --- CHOICES: the returned index is 1-based over the supplied choices
Plan @(0); Check 'first choice'   (CHOICES 'r' $three) '1'
Plan @(1); Check 'second choice'  (CHOICES 'r' $three) '2'
Plan @(2); Check 'third choice'   (CHOICES 'r' $three) '3'

# --- the appended Cancel button is the last one and reports 0, not its own index
Plan @(3); Check 'cancel returns 0' (CHOICES 'r' $three) '0'

# --- no button pressed at all (window dismissed) returns an empty string, not 0. That is deliberate:
#     the batch side reads the result with `for /f`, which leaves the variable unset, and the script
#     carries a dedicated ":choice- " label for that case ("broken environment, continue with defaults").
Plan @(); Check 'dismissed returns empty' ("[" + (CHOICES 'r' $three) + "]") '[]'
Check 'script handles the empty case' ([bool]([regex]::IsMatch($f0, '(?m)^:choice- '))) 'True'

# --- a single choice still gets a Cancel button beside it
Plan @(0); Check 'single choice'        (CHOICES 'r' 'Only') '1'
Plan @(1); Check 'single choice cancel' (CHOICES 'r' 'Only') '0'

# --- structure: one button per choice plus Cancel, labelled and named in order
Plan @(0); $null = CHOICES 'r' $three 1 'Pick one'
$f = $null
# rebuild a form the same way to inspect it: capture via a Shown hook on the next run
$script:seen = $null
$patched = $0 -replace '\$f\.ShowDialog\(\) >\$null', '$script:seen = $f; if ($global:probe) { & $global:probe $f $bt }; $f.ShowDialog() >$null'
if ($patched -eq $0) { throw 'inspection hook not injected' }
iex $patched
Plan @(0); $null = CHOICES 'r' $three 2 'Pick one' 14 'Black' 'White' '420'
$btns = @($script:seen.Controls)
Check 'button count (choices + cancel)' $btns.Count '4'
Check 'button labels'    (($btns | % { $_.Text }) -join ',') 'First,Second,Third,Cancel'
Check 'button names are 1-based' (($btns | % { $_.Name }) -join ',') '1,2,3,4'
Check 'title applied'    $script:seen.Text 'Pick one'
Check 'colours applied'  ($script:seen.BackColor + '/' + $script:seen.ForeColor) 'Black/White'
Check 'accept button is the default index' $script:seen.AcceptButton.Text 'Second'
Check 'cancel button is the last'          $script:seen.CancelButton.Text 'Cancel'
Check 'minimum width honoured'             $btns[0].MinimumSize.Width '420'
Check 'font size honoured'                 $btns[0].Font.Size '14'
# buttons are stacked, each below the previous, none overlapping
$ys = @($btns | % { $_.Location.Y })
Check 'buttons stacked in order' (($ys | Sort-Object) -join ',') ($ys -join ',')
Check 'buttons do not share a row' ((@($ys | Sort-Object -Unique)).Count) '4'

# --- focus handlers swap the colours (hover feedback). They read the dialog's colour variables, so they
#     have to be fired while the dialog is still open - exactly as WinForms would raise them.
$global:probe = { param($f,$bt) $b = $bt[0]
  $b.FireGotFocus();  $script:onFocus = $b.BackColor + '/' + $b.ForeColor
  $b.FireLostFocus(); $script:onBlur  = $b.BackColor + '/' + $b.ForeColor }
Plan @(0); $null = CHOICES 'r' $three 1 'Pick one' 12 'Black' 'White' '300'
$global:probe = $null
Check 'focus inverts colours'  $script:onFocus 'White/Black'
Check 'blur restores colours'  $script:onBlur  'Black/White'

# --- CHOICES2: two dialogs in sequence, returning "<first> <second>"
$0b = ($f0 -split '#\:CHOICES2\:',3)[1]
iex $0b
Plan @(0,1); Check 'two dialogs'       (CHOICES2 'a' $three 1 'One' 'b' 'X,Y' 1 'Two' 12 'Black' 'White' '300') '1 2'
Plan @(2,0); Check 'other combination' (CHOICES2 'a' $three 1 'One' 'b' 'X,Y' 1 'Two' 12 'Black' 'White' '300') '3 1'

# --- cancelling the FIRST dialog aborts both
Plan @(3); Check 'cancel first aborts' (CHOICES2 'a' $three 1 'One' 'b' 'X,Y' 1 'Two' 12 'Black' 'White' '300') '0 0'

# --- cancelling the SECOND dialog goes back to the first rather than aborting
Plan @(0,2,1,0); Check 'cancel second loops back' (CHOICES2 'a' $three 1 'One' 'b' 'X,Y' 1 'Two' 12 'Black' 'White' '300') '2 1'

# --- and after looping back, cancelling the first aborts the whole thing
Plan @(0,2,3); Check 'loop back then cancel' (CHOICES2 'a' $three 1 'One' 'b' 'X,Y' 1 'Two' 12 'Black' 'White' '300') '0 0'

"`n$pass passed, $fail failed"; if ($fail) { exit 1 }
