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

1. **Integrity pinning**: per-version SHA256 of `products*.cab/xml` and the MCT exe next to the URL, verified after download.
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
- Still required on Windows before release: open the window on Windows 10 22H2 and 11 25H2 hosts, run each preset once,
  run as standard user (UAC relaunch) and as admin, `help`, `legacy`, and an ini round-trip.
