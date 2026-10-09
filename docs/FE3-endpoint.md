# Microsoft FE3 update-metadata endpoint (FETCH_25H2_CAB)

> **2026-10-09: 25H2 no longer uses FE3.** Since Windows 11 26H2 shipped (29 Sep 2026) FE3 returns the 26H2 catalog
> (`26300.9457.260913-1737.26h2_ge_release_svc_refresh`, update id `ff4a40ae-2555-463f-aa41-79b38dca930c`) for every
> query, so the 25H2 choice was downloading 26H2. Re-probed live: `V=26100`, `V=26200`, `V=26200.6899` and `V=26300` all
> return that same file, adding `TargetReleaseVersion=1;TargetReleaseVersionInfo=25H2` or `ReleaseType=25H2` or retail
> `ge_release` attributes changes nothing, and `V=26400` returns nothing. None of the attributes tried selects an older
> release. The 25H2 MCT exe itself only knows the same FE3 query (`SetupMgr.dll`), and its fwlink fallback
> (`LinkId=2156292`) still points at the 24H2 cab. So 25H2 now uses the pinned catalog `products_11_25H2.xml`
> (26200.6899, ESD links checked live on 2026-10-09). `FETCH_25H2_CAB` stays in the script for a 26H2 entry; FE3 only
> ever serves the newest release. Everything below is the original 2026-09-13 research.

Researched and probed live on 2026-09-13. FE3 = Microsoft's internet-facing Update Metadata
Service (a.k.a. DCAT). The script's `FETCH_25H2_CAB` uses it because Microsoft has not published
a static `download.microsoft.com` products.cab for 25H2 (26200); older releases still use their
static per-release cab URLs in the choice blocks.

## The request

`POST https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/search/v1/bydeviceinfo`
Body (JSON): `{"Products":"PN=Windows.Products.Cab.amd64&V=<floor>","DeviceAttributes":"<k=v;...>"}`

Verified by probing the live endpoint:

- **`V` is a minimum-version floor, not an exact selector.** `V=26100.0.0.0` and `V=26200.0.0.0`
  both return the identical current file; `V=22631` (23H2) and `V=19045` (Win 10) return zero
  items. The script now derives the floor from the target build in `CB` so it tracks future
  releases instead of a hardcoded literal.
- **The catalog is a single global file.** Changing `OSSKUId`, `EditionId`, `CompositionEditionId`,
  `FlightRing`, `BuildFlighting`, `FlightingBranchName`, `PreviewBuilds` or `IsoCountryShortCode`
  did not change the returned file (same GUID every time). So the edition/flighting attributes in
  the request are harmless but not selective - the returned products.cab contains every edition
  (Home..Enterprise), 38 languages, and both x64 and ARM64 ESD entries; the script's PRODUCTS_XML
  step is what filters it.
- **DeviceAttributes must be present and reasonably complete.** An empty attribute string returns
  HTTP 400; a too-minimal one returns zero items. The full set the script sends works.
- `PN=Windows.Products.Cab.arm64` returned zero items at the time of testing; amd64 is the one to use.

## The response and integrity

Top-level JSON array: `[{ "UpdateIds":[...], "FileLocations":[{ "FileName":"products.cab",
"Size":..., "Digest":"<base64 SHA256>", "Url":"http://tlu.dl.delivery.mp.microsoft.com/..." }] }]`.

- The download **URL is HTTP only** - the CDN certificate does not cover `tlu.dl.delivery.mp.microsoft.com`,
  so HTTPS to it fails by hostname. Integrity therefore comes from the hash, not the transport.
- **`Digest` is the base64 SHA256 of the file.** Confirmed: the downloaded cab hashed to exactly the
  `Digest` value. `FETCH_25H2_CAB` now verifies the cab against it and discards on mismatch, which is
  the correct integrity check for an http download (and why disabling TLS validation in the fallback
  was unnecessary and has been removed).
- The signed URL carries `P1` (a unix expiry timestamp), `P2`/`P3` (routing) and `P4` (an HMAC
  signature); the P1 seen was ~19 hours out. Re-query to get a fresh URL rather than caching it.

## The FE3 TLS chain (for reference)

leaf `*.delivery.mp.microsoft.com` -> `Microsoft Update Secure Server CA 2.1` ->
`Microsoft Root Certificate Authority 2010`. That root is trusted by default on Windows (so the
HTTPS POST validates there) but is not in typical Linux/Mozilla CA bundles.

## What was tested live (not part of the committed test suite, needs outbound access)

- POST for `V=26100` and `V=26200`: both HTTP 200, identical file GUID, same 43383-byte cab.
- Extracted cab: `Catalog version="2.1"`, ESDs labelled `26200.9445.260908-0406.25h2_ge_release_svc_refresh`.
- Attribute sweep (retail, Enterprise SKU 4, Core SKU 101, German country, OSVersion 26200): all
  returned the same file. Minimal/empty attributes: zero items / HTTP 400.
- Downloaded cab SHA256 (base64) equalled the response `Digest` exactly.
