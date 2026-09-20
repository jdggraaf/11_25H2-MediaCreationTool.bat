# Redesign: Universal MediaCreationTool wrapper

Goal: keep AveYo's single-file, Microsoft-sources-only design, but make the tool understandable on first run,
configurable without editing the script, and honest about what still works in 2026.

## What changed (implemented on this branch)

### One setup window instead of two blind button lists

Before: two sequential dialogs of bare buttons ("1507 … 11_25H2", then "Auto Upgrade … MCT Defaults"). Edition,
language, architecture, key, dynamic update and the "def" switch could only be set by renaming the script or
editing `rem set` lines.

After: `#:SETUP_GUI:#` (WinForms, Windows PowerShell 5.1 compatible) shows one window:

```
+-----------------------------------------------------------------------------------------+
| 1. Windows version          | 2. What to do                                             |
| [Windows 11 25H2 (latest)]  | (o) Auto Upgrade   MCT downloads the detected media, then |
| [Windows 11 24H2         ]  |                    the script upgrades without prompts    |
| [Windows 11 23H2         ]  | ( ) Auto ISO       ... builds an ISO here / C:\ESD        |
| [Windows 11 22H2         ]  | ( ) Auto USB       ... writes it to the USB stick you pick|
| [Windows 11 21H2         ]  | ( ) Select         MCT asks Edition/Language/Arch/target  |
| [Windows 10 22H2         ]  | ( ) MCT Defaults   plain MCT run, no extras               |
| [ ...                    ]  | 3. Media options   (Auto = same as this PC)               |
|                             | Edition [Auto (Professional) v] Language [Auto (en-US) v] |
| Newest first. Upgrades      | Architecture [Auto (x64) v]                               |
| always get the latest build | Product key [_______-_____-_____-_____-_____]             |
| of the chosen version.      | [x] Dynamic update: let setup download the latest fixes   |
|                             | [x] Script extras: TPM/CPU bypass, auto.cmd, EI.cfg, ...  |
|                             | [ ] Remember these choices (MediaCreationTool.ini)        |
|                             |                                 [ Start ]  [ Cancel ]     |
+-----------------------------------------------------------------------------------------+
```

- Enter = Start, Esc = Cancel, Start is disabled while a typed key or language code is malformed.
- Select greys out Edition/Language/Arch/Key (MCT asks for them itself); MCT Defaults also greys out the extras, so the
  window never collects a value the script would discard.
- Remember writes the chosen version and options; the action is remembered only for Auto Upgrade and Auto ISO, and
  those then start straight away like the `auto` / `iso` script-name keywords.
- The window is preselected from the script name, commandline or ini, so `11_25H2 MediaCreationTool.bat` opens it
  with 25H2 already chosen instead of showing only the preset list.
- Result is one line `mct pre edition langcode arch key no_update def save` ("-" = auto), read by a `for /f`.
  If PowerShell cannot show it, `MCT`/`PRE` stay empty and the classic `:choices2` dialogs run as before.
- `legacy` (script name or argument) forces the classic dialogs.

### Choices survive self-elevation

The dialog values are turned into the same tokens the commandline parser already understands
(`Enterprise de-DE x64 KEY no_update def`) and appended to the elevated relaunch, so nothing is lost when
UAC restarts the script. The relaunch restore line capped the version index at 14 since the 21H2 release,
which made every Windows 11 choice ask again after elevation; it now accepts any index.

### MediaCreationTool.ini

`KEY=VALUE` lines with the same names as the `rem set` block (`MCT AUTO ISO EDITION LANGCODE ARCH KEY NO_UPDATE DEF`).
Loaded from the script folder before argument parsing (commandline and script name still win), copied to the
`C:\ESD` work folder with the script, written by the "Remember these choices" option to both places.

### help

`MediaCreationTool.bat help` (or `-help`, `--help`) prints every keyword with an example and exits.

### Fixes found while redesigning

- Embedded unattend used `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\MoSetup`; the documented key is
  `HKLM\SYSTEM\Setup\MoSetup` (the same as `auto.cmd` and `bypass11` already use).
- Earlier on this branch: HTTPS-first downloads, Authenticode check of the MCT exe, 25H2 CAB query derived
  from the target build, `ProductVersion` policy, `.Admin` runas cleanup in `bypass11`.

## Latest platform facts checked (September 2026) and what they mean for the tool

| Fact | Effect on the tool |
|---|---|
| Windows 11 26H1 (build 28000) ships preinstalled only, no upgrade path, no MCT media | Not added to the version list. The old hardcoded `MediaVersion 10.0.28000.1340` in the CAB query was a 26H1 build; it is now derived from the chosen release. |
| Windows 11 26H2 is an enablement package on the 24H2/25H2 branch, GA expected around October 2026 | Add as `:choice-20` once Microsoft publishes its MCT catalog; the CAB fetch is already parameterised by `CB`. |
| Media Creation Tool still creates x64 media only, no ARM64 | Architecture list stays x64/x86; ARM64 would need the ISO download page, out of scope. |
| Windows 10 support ended 14 Oct 2025, consumer ESU ends 13 Oct 2026 | Stated in the window and README; Windows 10 versions stay available for repair/ISO use. |
| `AllowUpgradesWithUnsupportedTPMOrCPU` still works but 25H2 needs `HwReqChk` alongside it | Both already set by `auto.cmd`, the WinPE path and the unattend; key path fixed. |
| `bypassnro.cmd` removed in 2025; the `OOBE\BypassNRO` registry value still works, `ms-cxh:localonly` blocked on newer 25H2 | The unattend keeps the registry method. `HideOnlineAccountScreens` is the documented fallback if Microsoft removes it (see roadmap). |
| 24H2+ requires SSE4.2 and POPCNT; bypasses cannot help such CPUs | Documented; a pre-flight CPU check is on the roadmap. |

## Roadmap (not implemented, in order of value)

1. **Integrity pinning** - mechanism done: `DOWNLOAD` takes an optional sha256 and discards a mismatch (cached copies are
   re-verified too); each `:choice-N` block may set `CABSHA`. Still to do: populate the 13 values with `tests/pin-hashes.ps1`
   from a machine that can reach the CDN. The exe is deliberately not pinned - Authenticode already gates it.
2. **Pre-flight page in the window**: TPM/CPU/SSE4.2/POPCNT/disk space summary with a plain-language verdict before Start.
3. **Local-account option** (checkbox) that sets `HideOnlineAccountScreens` in the unattend for people who want it,
   independent of the BypassNRO registry trick.
4. **26H2 catalog entry** when available; generalise `FETCH_25H2_CAB` into `FETCH_CAB` taking `VER`/`CB` from the choice block.
5. **Log file** (`C:\ESD\mct.log`) appended by the download, CAB fetch and assisted-MCT stages for post-mortem support.
6. **Split the file**: keep one distributable `.bat`, but build it from `src/*.ps1` + `src/*.cmd` with a tiny script, so the
   PowerShell parts can be linted and unit-tested with Pester on Windows CI.

## Testing

- `tests/static-check.sh` (Linux/macOS): CRLF, XML, labels, snippet markers, brace balance, https-first, and with `pwsh`
  a real parse of every embedded PowerShell snippet. All pass on this branch.
- `tests/dialog-mock/run.ps1` (any OS with `pwsh`): executes the real `SETUP_GUI` function against a mock WinForms layer.
  12 scenarios pass: defaults, cancel, preselection from env/ini, list + radio + key + remember, greying-out for Select and
  MCT Defaults, key and language validation, every control inside the client area, list labels.
- `tests/func-mock/*.ps1` (any OS with `pwsh`): the remaining PowerShell functions run against mocked dependencies.
  112 assertions pass - `DOWNLOAD` (9: fallback order, https-first, short-circuits), `WIM_INFO` (14: all four output
  modes, arch table), `FETCH_25H2_CAB` (31: request shape, country/version derivation, response shapes, SHA256 check),
  `PRODUCTS_XML` (32: catalog wrapping, EULAs, labels, pruning, unhiding, edition clones), `CHOICES`/`CHOICES2` (26:
  index maths, cancel, loop-back).
- `tests/batch-func-check.sh` (Linux with Wine): every `:choice-N` branch (all 14 agree with the version alias table),
  `:save_ini`, `:reg_query` (against a stub `reg`, since Wine's own has no `/se`) and `:rename`.
- `tests/wine-cmd-check.sh` (Linux with Wine): the ini loader, version resync, elevation token builder, dynamic-update
  substitution and the `help` block run under Wine's `cmd.exe` and pass. Wine's cmd cannot parse `&` inside a for-body or
  after `set /a` (idioms real cmd handles and this script has used for years), so the full script cannot run there.
  It also lacks indirect delayed expansion (`!%%v!`), so the `_undo` copies in `:rename` are skipped there.
  Note a generated test file must not be called `rename.bat`: cmd resolves that to the internal RENAME command.
- Rendering the dialog under Wine was attempted with PowerShell 7.0/7.2/7.4 Windows builds; all crash at startup on
  64-bit-only Wine 9.0 (WineHQ bug 52396, needs wine-staging or wine32).
- The mock suites also run on Windows now: the WinForms mock is compiled into a `MockUI` namespace (on Windows
  `[Windows.Forms.Form]` is the real thing and the dialog would really open), and `static-check.sh` falls back to a
  `pwsh` `[xml]` parse when Git Bash has no `xmllint`.

### Windows validation, 2026-09-20

Host: Windows 11 25H2 (26200), en-US, **standard user that is not in Administrators**, script started from a
PowerShell 7.6 terminal, real `cmd.exe` and Windows PowerShell 5.1. No admin credentials, no Windows 10 host and no
VM were available, so everything behind the UAC prompt is still open - those rows say so instead of guessing.
"Gate" = the run reached the `fltmc` self-elevation line with the right relaunch token; to keep credential prompts off
the desktop the test copy printed that line instead of calling `runas` (the only other edit: print instead of starting
the MCT exe). The dialogs were driven through UI Automation.

| Host | What | User | Outcome |
|---|---|---|---|
| 11 25H2 | setup window opens, 14 versions, 5 actions, Select greys out edition/language/arch/key | standard | pass, after fix 4 below |
| 11 25H2 | Cancel | standard | pass: ` CANCELED ` |
| 11 25H2 | MCT Defaults, 11 25H2, via the window - live FE3 query, download, Authenticode, `PRODUCTS_XML`, `makecab` | standard | pass, after fix 2; console shows `CAB verified against Microsoft catalog digest (SHA256)` |
| 11 25H2 | MCT Defaults, 22H2 and 1709 (live catalogs, exe signature Valid, products.xml parses, 1709 edition clones present) | standard | pass |
| 11 25H2 | Auto Upgrade / Auto ISO / Auto USB (+ dynamic update off) / Select via the window | standard | pass to the gate: `14.1`, `14.2`, `14.3 no_update`, `14.4` |
| 11 25H2 | re-entry with the relaunch arguments `14.3 no_update` | standard | pass: no window, straight to the gate |
| 11 25H2 | `help` | standard | pass, after fix 5 |
| 11 25H2 | `legacy`: MCT Version dialog, then `11_25H2 MCT Preset` dialog | standard | pass to the gate: `14.2` |
| 11 25H2 | ini round-trip: Auto ISO + Remember writes `MCT=11_25H2` / `ISO=1` next to the script and in `C:\ESD`; relaunch shows no window | standard | pass to the gate; deleting the ini only worked after fix 3 |
| 11 25H2 | `DOWNLOAD` with a pinned sha256 on a 22H2 `products.cab` with one byte appended | standard | pass: ` products22H2.cab sha256 mismatch - discarding `, re-downloaded, hash matches; 0-byte stub re-downloaded; a pin that never matches ends in `download failed` with no file left |
| 11 25H2 | UAC relaunch itself, anything after it (MCT run, ISO build, USB, upgrade), admin run | - | **not run**: no admin credentials on this host |
| 11 25H2 | Auto ISO boots in a VM | - | **not run**: needs the admin run and Hyper-V rights |
| 10 22H2 | everything | - | **not run**: no host |

The checklist item "corrupt a cached `products<VID>.cab` with a `CABSHA` set" has no target in the script as it stands:
no `:choice-N` sets `CABSHA` yet (`tests/pin-hashes.ps1` prints the values, nobody pasted them in) and `:process` deletes
`products%VID%.cab` after expanding it, so nothing is cached between runs. `DOWNLOAD` was therefore tested directly,
through its real batch wrapper lines.

The two open Wine questions:

1. `MachinePreferredUILanguages` with more than one language. Neither first nor last: real cmd.exe **quit the script**.
   `reg query /se "|"` gives `OS_LANGCODE=nl-NL|en-US`, the value is expanded before the line is parsed, and
   `for %%s in (nl-NL|en-US) do ...` has a live pipe in it: `| was unexpected at this time.`, exit 255, on line 83 of
   every start (tested against a REG_MULTI_SZ copy in an HKCU scratch key; this host itself has one language). Wine kept
   the last entry only because its parser does not treat that `|` as a pipe. Fix 1 keeps the first entry, which is the
   primary UI language: `nl-NL|en-US` -> `nl-NL`, `en-US` -> `en-US`, missing value -> stays undefined.
2. `!%%v!` in `:rename`: works on real cmd.exe. With the exact `:rename` and undo lines pointed at an HKCU scratch key,
   `CompositionEditionID_undo`, `EditionID_undo` and `ProductName_undo` were written with the old values
   (`Enterprise`, `Professional`, `Windows 10 Pro`), and the undo block of auto.cmd restored all three and deleted
   the `_undo` values. Not checked against the real HKLM key (needs admin).

Fixed on the way:

1. The `OS_LANGCODE` line (now line 84): `for /f "delims=|" %%s in ("%OS_LANGCODE%")` - see question 1.
2. `set "PSModulePath="` at start. Started from a PowerShell 7 terminal the script inherits 7's module path, Windows
   PowerShell 5.1 then fails to load `Microsoft.PowerShell.Security`, `Get-AuthenticodeSignature` errors out and the
   script reported a genuine, validly signed MCT exe as ` failed Authenticode signature check ` and deleted it.
3. Stale ini: the relaunched copy in `C:\ESD` reads the ini next to *itself*, and robocopy only ever added it. After
   "delete this file to get auto detection back" the remembered action kept starting. The copy is now dropped when the
   ini next to the script is gone.
4. Setup window: four of the five action descriptions were cut off at the right edge (`...the in-place upgrad`);
   shortened to fit. The mock cannot see this, it has no text metrics.
5. `help` listed a `usb` action keyword that the script never parsed; the text now says Auto USB, Select and MCT
   Defaults are picked in the window.

Still open: the rows marked not run. Cosmetic, left alone: `FETCH_25H2_CAB` prints its return value, a lone `0`,
under the "CAB verified" line.
