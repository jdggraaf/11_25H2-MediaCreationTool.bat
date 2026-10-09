# Repository review - October 2026

Review of the whole repository after 11 26H2 was added (commit `06e1f4a`): `MediaCreationTool.bat`, the `bypass11/`
scripts, the tests, CI and the docs. Six reviewers each covered one area (batch correctness, `bypass11` scripts,
security, docs, hygiene, possible expansions), and every finding was then checked by a second reviewer trying to
disprove it. 17 findings held up, 4 were refuted. Each one that held up was then re-checked by hand before being fixed.

This replaces the September 2026 review. Every item that review listed as open (HTTP before HTTPS, no Authenticode
check, hard-coded FE3 literals, no CONTRIBUTING.md, no CI, changelog drift) had already been fixed.

## Fixed in this round

| Severity | Where | Problem | Fix |
|---|---|---|---|
| High | `bypass11/auto.cmd` (WinPE block) | `for %s in (...) do ... Bypas%sCheck` used a single `%` in a script, so cmd read `%s in (...Bypas%` as an (empty) variable and the loop never ran. Booting the media and running `c:\auto` from Shift+F10 started setup with **none** of the five LabConfig bypasses set. The generator in `MediaCreationTool.bat` has `%%s`. Only the standalone copy had drifted. | `%%s` / `%%sCheck`. `tests/static-check.sh` now fails when `bypass11/auto.cmd` differs from the generated one (from its first `pushd` on). |
| Medium | `MediaCreationTool.bat` 25H2 catalog | A `products_11_25H2.xml` next to the script was copied in with no hash check: `XMLSHA` only applied to the download. A stale or edited local file, or one reached through a pre-set `ROOT` environment variable, was used unverified. | The local file now only seeds the download: `DOWNLOAD` keeps it if it matches `XMLSHA`, otherwise it fetches the pinned copy. It still works offline when the local file is intact. |
| Medium | `MediaCreationTool.bat` static catalogs | The `CABSHA` mechanism existed but no version set it, so the 13 static `products*.cab` downloads were never verified. | All 13 hashes pinned, from `tests/pin-hashes.ps1`. Two were cross-checked with curl. `tests/static-check.sh` fails on an unpinned catalog. |
| Medium | `bypass11/Quick_11_iso_esd_wim_TPM_toggle.bat` / `bypass11/readme.md` | The Server-label trick greys out *keep files and apps* on 24H2+ upgrades, which is why `auto.cmd` stopped using it on build 26100+. The readme recommended the toggle for any Windows 11 media without saying so. | A caveat in `bypass11/readme.md`: on 24H2+ media use the toggle for clean installs only, and upgrade with `auto.cmd` / `Skip_TPM_Check` instead. The script itself is unchanged. |
| Low | `SETUP_GUI` version list | "(latest)" was put on the version at index `dV`. That is the *preselected* version, so a name, commandline or ini choosing 22H2 labelled 22H2 "(latest)". Found during this round, not by the reviewers. | The label goes on the newest entry. New dialog-mock scenario; it fails on the old code. |
| Low | `bypass11/AutoUnattend.xml` | Had drifted from the generated unattend: BypassStorage/BypassCPU order swapped, and a stale comment about a winsetup.dll patch the script no longer uses. | Replaced with the generated unattend byte for byte. `tests/static-check.sh` keeps them identical. |
| Low | `bypass11/readme.md` | Said AutoUnattend.xml works with "22000.x / 22xxx.x" media only. | Now says 21H2 (22000) through 26H2 (26300). |
| Low | `REDESIGN.md` | Test notes still said 14 versions and 12 dialog scenarios, and roadmap item 1 still called pinning a to-do. | Updated. |
| Low | `README.md` | No help for the script's specific error messages. | Troubleshooting section covering the download hint, sha256 mismatch, wrong FE3 catalog, Authenticode failure, ISO in use and "setup terminated unexpectedly". |
| Low | `REVIEW.md` | The old audit listed already-fixed bugs as open, with stale line numbers. | Replaced by this file. |

## Still open (suggestions, not done)

- **Exit codes of the hybrid PowerShell helpers never reach batch.** `exit /b %errorcode%` uses a variable that is never
  set, so `DOWNLOAD` / `FETCH_CAB` (and the inline-only `MakeISO` / `WIM_INFO` wrappers) always return 0 to a
  `call`. There is no bug today: every caller checks for the output file, not `errorlevel`. Fix this before anything
  starts relying on `errorlevel`.
- **Log file.** Errors only go to the console, which the unattended presets can close. An append-only
  `%WORK%\mct.log` written at the existing error points would help support. This is roadmap item 5 in `REDESIGN.md`.
- **ISO checksum.** Auto ISO could print and save the sha256 of the finished ISO (`file.iso.sha256`), so a copy to
  USB or a share can be verified.
- **26H2 once 27H2 ships.** FE3 only serves the newest release. The new build guard makes the 26H2 entry fail loudly
  instead of building 27H2, but it will then need a pinned catalog the way 25H2 has one.
- **README changelog order.** Entries up to 2026.01.15 run oldest to newest; later ones run newest first. This was
  left as is because re-sorting history adds churn for little value.

## Refuted

- *"Stale products files are never purged"*: `.cab` files are deleted every run, the version-stamp purge covers the
  rest, and the cached `.xml` is now hash-checked.
- *"The MCT exe needs a pinned hash"*: it is Authenticode-checked. Microsoft re-signs it in place and two versions
  share its URL, so a pin would break legitimate updates.
- *"Skip_TPM_Check_on_Dynamic_Update.cmd leaves an unverified SYSTEM hook"*: not supported by the code. The script
  documents its install/remove toggle.
- *"Bypass registry keys are never reverted"*: this is intentional and documented. Reverting them would undo the
  bypass for the next feature update.
