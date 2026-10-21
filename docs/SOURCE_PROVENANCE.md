# Source provenance

The supplied **Scropts QOL v35** ZIP is the baseline. It contains the native C++
Weapon Kit implementation in `SourcePatches/ZombiesKitUI.v35.inc` and a PowerShell
builder that reconstructs the rest of the application from pinned sources and
applies the accumulated v35 patches. It is not a standalone full source checkout.

The ZIP's 13 files were imported without content changes in the repository's
first commit. The original builder, v35 include, manifest, status, tests, batch
launcher and crash collector are retained. Its original README is also preserved
as `V35_RELEASE_NOTES.md`; the repository root README describes ongoing work.

Uploaded archive: `Scropts_QOL_v35_Simplified_UI_Expanded_Kit_Creation.zip`

SHA-256: `e02b93ad0fe272bcd280c68cd8b6d27cf24c19a2fa05386b7feee57bdccdaef8`

## Reconstructed application

The original `Build-Audited-Scropts.ps1 -PrepareOnly -TestProfile kits` completed
successfully with PowerShell 7.6.7 on Linux, using a disposable work directory.
This executed every v35 patch stage, including the September build translation,
the `kits` crash-isolation profile and the v35 Weapon Kit overlay. The result,
not the unpatched upstream checkout, was imported into `src/ScroptsQOL/`.

| Input | Pinned revision | Observed archive SHA-256 |
| --- | --- | --- |
| Scroptss/Scropts-QOL | `bbd4a19cead88372bb227d489a84d32c86a30e60` | `d8c8e21ddc32fa25024c72f6a06026196f4254fcc28e2a3091138c262b565232` |
| TsudaKageyu/minhook v1.3.4 | `c3fcafdc10146beb5919319d0683e44e3c30d537` | `cdcb160f734d81bd4d235dfea79e3f5a661c8ef0ab74fa814272aa5449069034` |
| microsoft/Detours v4.0.1 | `e4bfd6b03e50de46b47abfbd1e46b384f0c5f833` | `fef0b17c5c3c9356fb8ba7366a3b196149daadd131fb6a92abeda1cb4d3b9b85` |
| Scroptss/T7Patch-src | `46b268a6cda05ac5ee2f8ff88c6db9f6d549df71` | `670508553982ea74fa989c04cd01e4b1b6748d5ad59d8f1bc1697363b2797dd2` |

Inputs were downloaded through verified HTTPS from GitHub's codeload service.
These are recorded observations, not publisher-signed attestations. PowerShell's
Linux distribution was checked against its official release SHA-256 manifest.
No downloaded prebuilt application or dependency library is used in the local
build; MinHook and Detours are built from the tracked sources.

The import excludes precompiled artifacts, the generated `.aps` resource cache,
and `.vcxproj.user` preferences. MinHook and Detours headers match the pinned
dependency source. The upstream solution's relative project path is adjusted to
`ScroptsQOL/`; the application's internal layout and project filename are kept.

## v36 development changes

The editable Visual Studio project uses C++17 and MSVC v143. Its `main.cpp`
includes `../../SourcePatches/ZombiesKitUI.v36.inc`, so the production Weapon Kit
implementation and the portable test headers have one source of truth. Normal
builds never re-download the older project or regenerate edited application code.

`source-manifest.json`, `STATUS.json` and the generated v35 diagnostic `.txt`
files describe the original package. Some historical manifest entries describe
earlier patch stages; the final `kits` profile disables the legacy per-frame
hook bundle. Treat the actual final source and current build results as evidence,
not an earlier-stage manifest claim. No additional hook bundle is enabled by v36.

MinHook and Detours license files remain beside their vendored sources. Original
embedded source notices are retained. The supplied Scropts tree and T7Patch input
do not contain a top-level license file; this import does not assign them a new
license. `UPSTREAM_README.md` preserves the upstream README for attribution.
