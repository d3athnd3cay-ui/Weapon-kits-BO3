# Weapon Kits BO3 — native C++ development

This is the supplied **Scropts QOL v35** project, reconstructed into an editable
native Windows x64 DLL and continued as **v36 development**. It uses C++17,
DirectX 11, Dear ImGui and the original hook integration with MinHook/Detours.
The Visual Studio project retains its original `ImGui DirectX 11 Kiero Hook`
name. There is no replacement application runtime.

The v35 native offline writer is the user-confirmed baseline for normal
attachments, camos, eight attachments and persistence after restart. The supplied
v35 files and their original build route are preserved; see
[provenance](docs/SOURCE_PROVENANCE.md) and [v35 notes](docs/V35_RELEASE_NOTES.md).

## Build on Windows

Install Visual Studio 2022 / Build Tools with **Desktop development with C++**,
**MSVC v143**, and a **Windows 10/11 SDK**. From this repository:

```powershell
./Build-Local.ps1
```

Or use `RUN_BUILD_V36_KITS.bat`. The builder runs the portable C++ tests, builds
pinned dependency sources, and compiles the local C++17 **Release | x64** project.
The exact output is `build/bin/WeaponKitsBO3.v36.dll`, with SHA-256 and PE/import
reports. Normal builds preserve your source edits and do not download upstream
code. Full instructions: [Windows development](docs/WINDOWS_BUILD.md).

## v36 changes and current limits

- **Automatic Save & Apply:** freshly checks the selected weapon, updates its
  unique existing native kit, or automatically creates an eligible missing
  firearm kit in a strictly verified empty slot. There is no separate creation
  checkbox. Offline mode, external backup confirmation, schema/identity checks,
  the complete 50-slot scan and supported-attachment checks remain mandatory.
- **Write recovery:** validates original values before writing, verifies the
  complete result, restores attempted fields in reverse order on failure, and
  suspends further writes when recovery or persistence is uncertain. Eight-slot
  layout, camo handling and saved cosmetic preservation are retained.
- **Attachment investigation:** Advanced contains **Inspect attachment
  compatibility** and **Copy attachment report**. **Copy Details** also captures
  the current selection's catalog membership, known IDs and pair checks.
  **Unsupported Suppressor gameplay is not fixed or verified.** Such native
  writes remain blocked; a saved ID is not proof of functioning weapon assets.
  See the [evidence and gameplay test plan](docs/ATTACHMENT_COMPATIBILITY.md).

The Linux cloud checks cover portable C++ behavior and the original v35 source
contracts. They do not compile this Windows DLL, validate game addresses or prove
new-kit persistence. The Windows CI workflow builds the DLL after publication;
its result and BO3 runtime acceptance must be checked separately. v36 is not a
runtime-verified release.

## Source layout

| Path | Purpose |
| --- | --- |
| `src/ScroptsQOL/` | Full application reconstructed by the supplied v35 builder |
| `src/Scropts QOL.sln` | Solution with the imported project path |
| `SourcePatches/ZombiesKitUI.v36.inc` | Active C++ Weapon Kit UI/writer, included by `main.cpp` |
| `SourcePatches/*.v36.h` | Production C++ transaction and compatibility policies |
| `third_party/` | Pinned MinHook and Detours sources and their licenses |
| `tests/` | Portable C++ behavior tests and unchanged v35 source-contract tests |
| `Build-Local.ps1` | Normal Windows test/build path; does not regenerate source |
| `Build-Audited-Scropts.ps1` | Original v35 reproduction path, using a separate disposable work directory |
| `source-manifest.json`, `STATUS.json` | Original v35 metadata, retained as historical input |

Edit the active include and the application sources directly. The v36 include
is compiled by reference; there is no second generated copy to synchronize.
Use only **Release | x64** for the supported DLL build. Source preparation with
the legacy builder is for reproducing v35, not for updating this editable tree.

## Cloud tests

On Linux with a C++17 compiler and Python 3:

```sh
bash scripts/test-native.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Python only runs the preserved source-contract checks. The application and new
behavior tests are C++. The cloud machine cannot supply the Windows SDK, MSVC
runtime or BO3 gameplay. See [runtime acceptance](docs/WINDOWS_BUILD.md#runtime-acceptance)
for the remaining checks. Before testing native writes, back up the entire BO3
`players` folder externally and use offline Zombies with one DLL version loaded.
