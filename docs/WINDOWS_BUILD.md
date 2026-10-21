# Windows x64 C++ development

The application remains a native C++17 Windows DLL using DirectX 11, Dear ImGui,
Kiero/MinHook, and Detours. The editable source is in `src/ScroptsQOL/`; it is the
materialized **v35** build with the v36 changes applied. The older upstream
repository supplies pinned reconstruction inputs, not the working baseline.

## Prerequisites

- Windows x64.
- Visual Studio 2022 or Visual Studio 2022 Build Tools with **Desktop development
  with C++**, **MSVC v143 x64/x86 build tools**, and a **Windows 10 or 11 SDK**.
- Windows PowerShell 5.1 or PowerShell 7.
- A complete checkout, including `third_party/minhook` and `third_party/detours`.

The Windows SDK supplies D3D11/DXGI. The obsolete June 2010 DirectX SDK is not
required. `CHECK_BUILD_TOOLS.bat` is the original v35 convenience check; the local
builder also validates the selected tools and propagates failures.

## Normal edit, test, and build

From the repository root:

```powershell
./Build-Local.ps1
```

Or double-click `RUN_BUILD_V36_KITS.bat`. The batch launcher preserves the build
exit code. If the local PowerShell execution policy blocks this reviewed local
script, the launcher passes a policy override only to its PowerShell process;
it does not change the machine's execution policy.

The default build:

1. Finds the installed x64 MSVC environment using `vswhere` and `vcvars64.bat`.
2. Compiles and runs every `tests/*_tests.cpp` executable as C++17. A missing test
   set or failed test stops the build.
3. Builds the pinned MinHook and Detours sources, then places their generated
   static libraries at the existing project-relative link paths.
4. Builds the tracked Visual Studio project as **Release | x64**, using v143 and
   C++17. It writes a generated C++17 MSBuild property sheet under `build/` without
   modifying the tracked project or source files.
5. Checks the exact output's PE signature, x64 machine type, and DLL flag;
   generates a SHA-256 and `dumpbin` headers/import reports.

The output is `build/bin/WeaponKitsBO3.v36.dll`. That directory also contains
`WeaponKitsBO3.v36.dll.sha256`, `headers.txt`, `imports.txt`, and `build-report.txt`.
Native test results are in `build/tests/results.txt`. Build artifacts are ignored
by Git. The normal build does not download sources or regenerate your edits.

Useful variants:

```powershell
./Build-Local.ps1 -TestsOnly
./Build-Local.ps1 -Jobs 4
./Build-Local.ps1 -SkipTests  # Explicitly skips tests; recorded in build-report.txt.
```

For IDE editing, open
`src/ScroptsQOL/ImGui DirectX 11 Kiero Hook.vcxproj` and select **Release | x64**.
Run the local builder once to produce the dependency libraries. The script is
the reference build route and gives deterministic artifact locations. Do not use
the legacy preparation script to build over an edited development tree.

## Reproducing the supplied v35 package

`Build-Audited-Scropts.ps1`, `RUN_BUILD_V35_KITS.bat`, and
`SourcePatches/ZombiesKitUI.v35.inc` retain the supplied v35 route. The original
builder downloads the exact revisions recorded in `source-manifest.json`,
applies all v35 patches, builds dependencies from source, and then builds a DLL.

To prepare a separate reconstruction without compiling a DLL:

```powershell
./Build-Audited-Scropts.ps1 -PrepareOnly -WorkDir "$env:TEMP/scropts-v35-reproduction"
```

Omit `-PrepareOnly` for its original Windows build. It contacts
`codeload.github.com` over verified HTTPS. The supplied builder prints archive
SHA-256 values but does not compare them to an expected archive checksum; consult
the repository's import provenance when verifying reconstruction inputs.

**The legacy builder recreates its extraction directories.** Always give it a
separate disposable work directory; never point it at `src/`, `third_party/`, or
an edited source tree. The legacy output's name and behavior remain v35.

## Cloud checks and Windows CI

Linux can edit the C++ source and run the portable transaction/attachment policy
tests; it cannot build this MSVC/Windows SDK DLL or run BO3. For a single test:

```sh
mkdir -p build/tests
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/native_kit_transaction_tests.cpp -o build/tests/native_kit_transaction_tests
build/tests/native_kit_transaction_tests
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/attachment_compatibility_tests.cpp -o build/tests/attachment_compatibility_tests
build/tests/attachment_compatibility_tests
```

Python is used only for the existing source-contract checks, not as the project
runtime:

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The Windows GitHub Actions workflow runs those contract checks, the native C++
tests, and the Windows DLL build on `windows-2022`, then uploads the exact DLL and
verification reports. Adding the workflow does not mean it has executed. Its
result must be checked after the repository is published and the workflow runs.

## Runtime acceptance

A compiled DLL and passing portable tests do not prove the game ABI, hook
installation, attachment assets, or on-disk persistence. Test with a supported
Windows BO3 executable in **offline Zombies**, using a separate complete backup
of the `players` folder and one loaded DLL version at a time.

Recheck the confirmed v35 behaviors first: native normal attachments, eight
attachment slots, camo/style preservation, and persistence after a game restart.
Then test v36's automatic existing-kit update and missing-kit creation, including
repeated Save & Apply without duplicate entries. Record the menu's Copy Details
output and verify the selected attachments in actual gameplay. See
`ATTACHMENT_COMPATIBILITY.md` for suppressor-specific evidence and acceptance
criteria. An attachment ID in storage or a successful in-memory readback alone
does not establish working suppressor behavior.
