# Contributing

## Line endings

`MediaCreationTool.bat` and the `bypass11/` scripts are hybrid `.bat`/`.cmd`/PowerShell
files parsed by `cmd.exe`; a stray LF inside them can corrupt parsing. All `.bat`,
`.cmd` and `.xml` files in this repo **must use CRLF line endings**, including any
new line you add or change. `.gitattributes` marks these files `-text` so git never
normalizes or diff-converts them - it does not add CRLF for you, so edit with a tool
that lets you control line endings exactly (e.g. Python opened in binary mode), not
a plain `sed -i` on the checked-out file.

## Style

Keep edits minimal and match the surrounding file's existing style: AveYo's terse
batch style for `.bat`/`.cmd` code, 2-space indented PowerShell blocks. Don't
reformat untouched lines.

## Running the tests

`tests/static-check.sh` is the repo's static test script. It checks CRLF line
endings, well-formed XML, that batch `goto`/`call` labels resolve, and that
PowerShell blocks have balanced braces. Run it after any change:

```
bash tests/static-check.sh
```

It must print `ALL CHECKS PASSED` before you're done.

If PowerShell 7 (`pwsh`) is installed or you point `PWSH=/path/to/pwsh` at one, the
script also parses every `#:NAME:#` PowerShell snippet exactly as the batch bootstrap
extracts it, and then runs the behavioural suites in `tests/func-mock/`, which execute the
real functions against mocked dependencies:

| suite | function under test | what is mocked |
| --- | --- | --- |
| `download.ps1` | `DOWNLOAD` | BITS, `Invoke-WebRequest`, `bitsadmin`, `WebClient` |
| `wim-info.ps1` | `WIM_INFO` | a synthetic `.esd` built to the layout it scans |
| `fetch-cab.ps1` | `FETCH_25H2_CAB` | registry, metadata service, CDN |
| `products-xml.ps1` | `PRODUCTS_XML` | synthetic catalogs on disk |
| `choices.ps1` | `CHOICES`, `CHOICES2` | the WinForms mock, with queued button presses |

With Wine installed, `tests/batch-func-check.sh` additionally drives the batch-side routines
under a real `cmd.exe`: every `:choice-N` version branch, `:save_ini`, `:reg_query` and
`:rename`. Pieces are lifted verbatim from the script rather than retyped.

`tests/link-check.sh` probes every URL in the script and in the docs. On a network that
blocks outbound traffic it reports those as `BLOCKED` rather than failing; `STRICT=1` makes
them failures.

MCT and Windows setup themselves can still only be exercised on Windows.

## `:choice-N` / `VERSIONS` mapping

`MediaCreationTool.bat` picks the OS version/edition to fetch through a small,
hand-curated table:

- `set VERSIONS=1703,1709,1903,...,11_24H2,11_25H2` (around line 59) lists every
  supported version string, in order, and `set /a dV=14` sets the dialog's
  default selection index into that same list.
- Each version has a matching `:choice-N` label further down the script (around
  lines 149-270), where `N` is the 1-based position of that version in
  `VERSIONS` - e.g. `VERSIONS` item 14 is `11_25H2`, and `:choice-14` sets
  `VER`, `VID`, `CB`, `CT`, `CC`, `CAB` and `EXE` for 11 25H2; item 3 is `1903`
  and `:choice-3` configures that release, and so on down to item 1 (`1703`,
  `:choice-1`). Versions whose Microsoft downloads disappeared (1507-1607,
  1803, 1809) were removed in September 2026 rather than pointed elsewhere.
- Adding a new release means appending its name to `VERSIONS`, bumping `dV` if
  it should be the new default, and adding a new `:choice-N` block (copied from
  the previous newest one) with that release's `VER`/`VID`/`CB`/`CT`/`CC`/
  `CAB`/`EXE` values.

## Changelog

There is a single changelog, kept in two places that should stay in sync: the
header comment block at the top of `MediaCreationTool.bat` (`:: Changelog:`,
around lines 6-13) and the `Changelog` section near the bottom of `README.md`.
Add a dated entry to both when a change is user-visible.
