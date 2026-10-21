param(
    [string]$WorkDir = "",
    [switch]$PrepareOnly,
    [ValidateSet("kits")]
    [string]$TestProfile = "kits"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Resolve the folder containing this script. This also works if PowerShell
# launches the script through a wrapper.
$ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
    $ScriptRoot = (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $ScriptRoot "work"
}

# Pinned, audited/public source revisions.
$ScroptsCommit = "bbd4a19cead88372bb227d489a84d32c86a30e60"
$MinHookCommit = "c3fcafdc10146beb5919319d0683e44e3c30d537"   # MinHook v1.3.4
$DetoursCommit = "e4bfd6b03e50de46b47abfbd1e46b384f0c5f833"   # Microsoft Detours v4.0.1
$T7PatchCommit = "46b268a6cda05ac5ee2f8ff88c6db9f6d549df71"   # Scroptss/T7Patch-src v3.07, Sep 2026 aware

$ScroptsUrl = "https://codeload.github.com/Scroptss/Scropts-QOL/zip/$ScroptsCommit"
$MinHookUrl = "https://codeload.github.com/TsudaKageyu/minhook/zip/$MinHookCommit"
$DetoursUrl = "https://codeload.github.com/microsoft/Detours/zip/$DetoursCommit"
$T7PatchUrl = "https://codeload.github.com/Scroptss/T7Patch-src/zip/$T7PatchCommit"

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Download-Zip([string]$Url, [string]$Destination) {
    if (Test-Path $Destination) {
        Remove-Item $Destination -Force
    }
    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination
    $h = Get-FileHash -Algorithm SHA256 $Destination
    Write-Host "Downloaded SHA256: $($h.Hash)"
}

function Expand-Fresh([string]$Zip, [string]$Destination) {
    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    Expand-Archive -Path $Zip -DestinationPath $Destination -Force
}

function Require-VS {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "Visual Studio/Build Tools not found. Install Visual Studio 2022 Build Tools with Desktop development with C++, MSVC v143, and a Windows 10/11 SDK."
    }

    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath

    if (-not $vsPath) {
        throw "MSVC C++ build tools were not found. Add the 'Desktop development with C++' workload."
    }

    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat not found at $vcvars"
    }

    return $vcvars
}

function Invoke-VsCommand([string]$VcVars, [string]$Command) {
    $cmd = 'call "' + $VcVars + '" && ' + $Command
    Write-Host "CMD> $Command"
    & cmd.exe /d /s /c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "Build command failed with exit code $LASTEXITCODE"
    }
}

function Patch-ScroptsProject([string]$ProjectDir) {
    $proj = Join-Path $ProjectDir "ImGui DirectX 11 Kiero Hook.vcxproj"
    if (-not (Test-Path $proj)) {
        throw "Scropts Visual Studio project not found: $proj"
    }

    $text = Get-Content $proj -Raw

    # Use the stable VS2022 C++ toolset used by official MinHook v1.3.4.
    $text = $text.Replace("<PlatformToolset>v145</PlatformToolset>",
                          "<PlatformToolset>v143</PlatformToolset>")

    # The public project references the obsolete June 2010 DirectX SDK even
    # though the source does not use D3DX. Windows SDK supplies D3D11/DXGI.
    $text = [regex]::Replace(
        $text,
        '(?m)^\s*<LibraryPath>C:\\Program Files %28x86%29\\Microsoft DirectX SDK %28June 2010%29\\Lib\\(?:x86|x64);\$\(LibraryPath\)</LibraryPath>\s*\r?\n?',
        ''
    )
    $text = [regex]::Replace(
        $text,
        '(?m)^\s*<IncludePath>C:\\Program Files %28x86%29\\Microsoft DirectX SDK %28June 2010%29\\Include;\$\(IncludePath\)</IncludePath>\s*\r?\n?',
        ''
    )

    $legacyDeps = '$(CoreLibraryDependencies);C:\Program Files (x86)\Microsoft DirectX SDK (June 2010)\Lib\x64\d3dx11.lib;$(SolutionDir)ImGui DirectX 11 Kiero Hook\minhook\lib\libMinHook.x64.lib;$(SolutionDir)ImGui DirectX 11 Kiero Hook\detours\detours.lib'
    $cleanDeps = '$(CoreLibraryDependencies);d3d11.lib;dxgi.lib;$(ProjectDir)minhook\lib\libMinHook.x64.lib;$(ProjectDir)detours\detours.lib'
    $text = $text.Replace($legacyDeps, $cleanDeps)

    # The public tree contains these source files but the .vcxproj omits them.
    if ($text -notmatch '<ClCompile Include="Players\.cpp"') {
        $text = $text.Replace(
            '    <ClCompile Include="main.cpp" />',
            "    <ClCompile Include=`"main.cpp`" />`r`n    <ClCompile Include=`"Players.cpp`" />`r`n    <ClCompile Include=`"servers.cpp`" />"
        )
    }

    if ($text -notmatch '<ClInclude Include="players\.h"') {
        $text = $text.Replace(
            '    <ClInclude Include="hooks.h" />',
            "    <ClInclude Include=`"hooks.h`" />`r`n    <ClInclude Include=`"players.h`" />`r`n    <ClInclude Include=`"servers.h`" />"
        )
    }

    # json.hpp is listed in the project but absent from this public tree and
    # is not referenced by the application source.
    $text = [regex]::Replace(
        $text,
        '(?m)^\s*<ClInclude Include="nlohmann\\json\.hpp" />\s*\r?\n?',
        ''
    )

    Set-Content -Path $proj -Value $text -Encoding UTF8

    # Validate that dependency paths are project-relative. Building a .vcxproj
    # directly gives SolutionDir semantics that can duplicate the project folder.
    $verifyText = Get-Content $proj -Raw
    if ($verifyText -match '\$\(SolutionDir\)ImGui DirectX 11 Kiero Hook\\(?:minhook|detours)') {
        throw "Project patch validation failed: stale SolutionDir dependency path remains."
    }
    if ($verifyText -notmatch '\$\(ProjectDir\)minhook\\lib\\libMinHook\.x64\.lib') {
        throw "Project patch validation failed: project-relative MinHook path missing."
    }
    if ($verifyText -notmatch '\$\(ProjectDir\)detours\\detours\.lib') {
        throw "Project patch validation failed: project-relative Detours path missing."
    }

    # Keep Solution Explorer filters in sync where possible.
    $filters = "$proj.filters"
    if (Test-Path $filters) {
        $ft = Get-Content $filters -Raw
        if ($ft -notmatch '<ClCompile Include="Players\.cpp"') {
            $ft = $ft.Replace(
                '    <ClCompile Include="hooks.cpp">',
                "    <ClCompile Include=`"Players.cpp`">`r`n      <Filter>Source Files</Filter>`r`n    </ClCompile>`r`n    <ClCompile Include=`"servers.cpp`">`r`n      <Filter>Source Files</Filter>`r`n    </ClCompile>`r`n    <ClCompile Include=`"hooks.cpp`">"
            )
        }
        if ($ft -notmatch '<ClInclude Include="players\.h"') {
            $ft = $ft.Replace(
                '    <ClInclude Include="hooks.h">',
                "    <ClInclude Include=`"players.h`">`r`n      <Filter>Header Files</Filter>`r`n    </ClInclude>`r`n    <ClInclude Include=`"servers.h`">`r`n      <Filter>Header Files</Filter>`r`n    </ClInclude>`r`n    <ClInclude Include=`"hooks.h`">"
            )
        }
        $ft = [regex]::Replace(
            $ft,
            '(?ms)\s*<ClInclude Include="nlohmann\\json\.hpp">\s*<Filter>nohlmann</Filter>\s*</ClInclude>',
            ''
        )
        Set-Content -Path $filters -Value $ft -Encoding UTF8
    }
}


function Patch-SeptemberCompatibility([string]$ProjectDir, [string]$T7PatchRoot) {
    Write-Step "Applying September 2026 BO3 address compatibility"

    $gameBuildSource = Join-Path $T7PatchRoot "GameBuild.h"
    if (-not (Test-Path $gameBuildSource)) {
        throw "Pinned T7Patch GameBuild.h was not found: $gameBuildSource"
    }

    $gameBuildDest = Join-Path $ProjectDir "GameBuild.h"
    Copy-Item $gameBuildSource $gameBuildDest -Force

    # Scroptss' September 2026 T7Patch source uses bo3::address() to translate
    # February RVAs for the September executable. Reuse that exact public
    # build-detection/translation logic rather than guessing new addresses.
    $commonHeader = Join-Path $ProjectDir "common.h"
    $commonText = Get-Content $commonHeader -Raw

    if ($commonText -notmatch '#include\s+"GameBuild\.h"') {
        $commonText = $commonText.Replace(
            '#include "includes.h"',
            "#include `"includes.h`"`r`n#include `"GameBuild.h`""
        )
    }

    $commonText = [regex]::Replace(
        $commonText,
        '#define\s+OFFSET\(x\)\s+\(\(INT64\)GetModuleHandleA\(NULL\)\s*\+\s*\(INT64\)x\)',
        '#define OFFSET(x) ((INT64)bo3::address(static_cast<std::uintptr_t>(x)))'
    )
    Set-Content -Path $commonHeader -Value $commonText -Encoding UTF8

    # The current T7Patch source documents that September removed 0x6C0 bytes
    # from the primary code section beginning at RVA 0x1D29C20. Any Scropts
    # direct ProcessBase+RVA reference into that code range therefore needs
    # the same build-aware translation.
    $shiftStart = [UInt64]0x1D29C20
    $codeEnd = [UInt64]0x2EFF000
    $pattern = 'ProcessBase\s*\+\s*0x([0-9A-Fa-f]+)'
    $filesToPatch = @("common.cpp", "common.h", "hooks.cpp", "main.cpp")
    # These counters are script-scoped because the .NET regex callback runs
    # through a PowerShell scriptblock scope under StrictMode.
    $script:totalTranslated = 0

    foreach ($name in $filesToPatch) {
        $path = Join-Path $ProjectDir $name
        if (-not (Test-Path $path)) {
            throw "Expected Scropts source file missing: $path"
        }

        $sourceText = Get-Content $path -Raw
        $script:localCount = 0

        $patchedText = [regex]::Replace(
            $sourceText,
            $pattern,
            {
                param($m)
                $rva = [Convert]::ToUInt64($m.Groups[1].Value, 16)
                if ($rva -ge $shiftStart -and $rva -lt $codeEnd) {
                    $script:totalTranslated++
                    $script:localCount++
                    return "bo3::address(0x$($m.Groups[1].Value))"
                }
                return $m.Value
            }
        )

        Set-Content -Path $path -Value $patchedText -Encoding UTF8
        Write-Host "  $name : translated $script:localCount direct code RVA reference(s)"
    }

    # Refuse to build if a direct stale code RVA remains in the translated range.
    foreach ($name in $filesToPatch) {
        $path = Join-Path $ProjectDir $name
        $check = Get-Content $path -Raw
        $remaining = [regex]::Matches($check, $pattern)
        foreach ($m in $remaining) {
            $rva = [Convert]::ToUInt64($m.Groups[1].Value, 16)
            if ($rva -ge $shiftStart -and $rva -lt $codeEnd) {
                throw "September compatibility validation failed: stale direct code RVA 0x$($m.Groups[1].Value) remains in $name"
            }
        }
    }

    # Stop cleanly on an executable build we do not explicitly recognize.
    # Use a whitespace/line-ending tolerant match. The downloaded GitHub source
    # may use CRLF while this generated PowerShell script itself may use LF.
    $mainPath = Join-Path $ProjectDir "main.cpp"
    $mainText = Get-Content $mainPath -Raw

    if ($mainText -notmatch 'bo3::supported_build\(\)') {
        $attachPattern = '(?ms)case\s+DLL_PROCESS_ATTACH:\s*\r?\n\s*DWORD\s+old;\s*\r?\n\s*dllbase\s*=\s*hMod;\s*\r?\n'
        $attachMatch = [regex]::Match($mainText, $attachPattern)

        if (-not $attachMatch.Success) {
            throw "Could not locate DllMain DLL_PROCESS_ATTACH block for BO3 build guard."
        }

        $guard = @"

`t`tif (!bo3::supported_build())
`t`t{
`t`t`tOutputDebugStringA("Scropts source build: unsupported Black Ops III executable build.\n");
`t`t`treturn FALSE;
`t`t}
"@

        $insertAt = $attachMatch.Index + $attachMatch.Length
        $mainText = $mainText.Insert($insertAt, $guard)

        if ($mainText -notmatch 'bo3::supported_build\(\)') {
            throw "BO3 build guard insertion validation failed."
        }
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    # Add GameBuild.h to the VS project for traceability.
    $proj = Join-Path $ProjectDir "ImGui DirectX 11 Kiero Hook.vcxproj"
    $projText = Get-Content $proj -Raw
    if ($projText -notmatch '<ClInclude Include="GameBuild\.h"') {
        $projText = $projText.Replace(
            '    <ClInclude Include="hooks.h" />',
            "    <ClInclude Include=`"hooks.h`" />`r`n    <ClInclude Include=`"GameBuild.h`" />"
        )
        Set-Content -Path $proj -Value $projText -Encoding UTF8
    }

    $compatReport = @()
    $compatReport += "September 2026 compatibility source: Scroptss/T7Patch-src"
    $compatReport += "T7Patch source commit: $T7PatchCommit"
    $compatReport += "Translation rule source file: GameBuild.h"
    $compatReport += "Shift start RVA: 0x1D29C20"
    $compatReport += "Primary code end RVA: 0x2EFF000"
    $compatReport += "September code delta: -0x6C0"
    $compatReport += "Direct ProcessBase code references translated: $script:totalTranslated"
    $compatReport += "Unknown BO3 executable builds are rejected before hook installation."
    $compatReport | Set-Content (Join-Path $ProjectDir "SOURCE_COMPATIBILITY.txt") -Encoding UTF8

    Write-Host "Translated $script:totalTranslated direct Scropts code RVA reference(s)." -ForegroundColor Green
}


function Patch-DiagnosticOverlayOnly([string]$ProjectDir) {
    Write-Step "Applying DIAGNOSTIC overlay-only patch"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp not found: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw
    $pattern = '(?m)^(?<indent>\s*)hooks::onFrame\(\);\s*$'
    $matches = [regex]::Matches($mainText, $pattern)

    if ($matches.Count -ne 1) {
        throw "Diagnostic patch expected exactly one hooks::onFrame() call, found $($matches.Count)."
    }

    $mainText = [regex]::Replace(
        $mainText,
        $pattern,
        '${indent}// DIAGNOSTIC: hooks::onFrame() disabled to isolate post-render BO3 patching.',
        1
    )

    if ($mainText -match '(?m)^\s*hooks::onFrame\(\);\s*$') {
        throw "Diagnostic patch validation failed: hooks::onFrame() is still active."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    $note = @()
    $note += "DIAGNOSTIC BUILD - NOT FOR UNLOCKING/STATS"
    $note += "hooks::onFrame() is disabled."
    $note += "This prevents PatchPrecomputed(), applyPatches(), server hooks, and other per-frame game patching from starting through hooks::onFrame()."
    $note += "Purpose: verify whether the overlay can remain loaded without the post-render patch path."
    $note | Set-Content (Join-Path $ProjectDir "DIAGNOSTIC_BUILD.txt") -Encoding UTF8

    Write-Host "Diagnostic overlay-only patch applied." -ForegroundColor Yellow
}


function Patch-BlackMarketAndEntitlements([string]$ProjectDir) {
    Write-Step "Applying minimal Black Market + Entitlements hooks"

    $hooksPath = Join-Path $ProjectDir "hooks.cpp"
    $hooksHeaderPath = Join-Path $ProjectDir "hooks.h"
    $mainPath = Join-Path $ProjectDir "main.cpp"

    foreach ($p in @($hooksPath, $hooksHeaderPath, $mainPath)) {
        if (-not (Test-Path $p)) {
            throw "Expected source file missing: $p"
        }
    }

    $hooksText = Get-Content $hooksPath -Raw

    $insertNeedle = "`tvoid applyPatches() {"
    if (-not $hooksText.Contains($insertNeedle)) {
        throw "Could not locate hooks::applyPatches() insertion point."
    }

    $minimalFunction = @'
    void applyBlackMarketAndEntitlementHooks()
    {
        // Minimal cosmetic / entitlement test only.
        // These are the three hooks used by the public-source Spoof options:
        //   Blackmarket Items -> item option lock + inventory quantity
        //   Entitlements      -> entitlement ownership check
        //
        // The old checksum patch path, server hooks, and gameplay hook bundle
        // remain disabled.

        LPVOID optionLockTarget = (LPVOID)OFFSET(0x2631C10);
        LPVOID inventoryQtyTarget = (LPVOID)OFFSET(0x1DFCC60);
        LPVOID entitlementTarget = (LPVOID)OFFSET(0x1E06110);

        MH_STATUS s1 = MH_CreateHook(
            optionLockTarget,
            functions::hkBG_UnlockablesItemOptionLocked,
            (LPVOID*)&BG_UnlockablesItemOptionLocked
        );

        MH_STATUS s2 = MH_CreateHook(
            inventoryQtyTarget,
            functions::hkLiveInventory_GetItemQuantity,
            (LPVOID*)&LiveInventory_GetItemQuantity
        );

        MH_STATUS s3 = MH_CreateHook(
            entitlementTarget,
            functions::hkLiveEntitlements_IsEntitlementActiveForController,
            (LPVOID*)&LiveEntitlements_IsEntitlementActiveForController
        );

        if (s1 == MH_OK || s1 == MH_ERROR_ALREADY_CREATED)
            MH_EnableHook(optionLockTarget);

        if (s2 == MH_OK || s2 == MH_ERROR_ALREADY_CREATED)
            MH_EnableHook(inventoryQtyTarget);

        if (s3 == MH_OK || s3 == MH_ERROR_ALREADY_CREATED)
            MH_EnableHook(entitlementTarget);
    }

'@

    $hooksText = $hooksText.Replace(
        $insertNeedle,
        $minimalFunction + $insertNeedle
    )

    Set-Content -Path $hooksPath -Value $hooksText -Encoding UTF8

    $headerText = Get-Content $hooksHeaderPath -Raw

    if ($headerText -notmatch 'applyBlackMarketAndEntitlementHooks') {
        $headerText = $headerText.Replace(
            '    void applyPatches();',
            "    void applyPatches();`r`n    void applyBlackMarketAndEntitlementHooks();"
        )
    }

    if ($headerText -notmatch 'applyBlackMarketAndEntitlementHooks') {
        throw "Could not declare applyBlackMarketAndEntitlementHooks()."
    }

    Set-Content -Path $hooksHeaderPath -Value $headerText -Encoding UTF8

    $mainText = Get-Content $mainPath -Raw

    if ($mainText -notmatch 'hooks::applyBlackMarketAndEntitlementHooks\(\);') {
        $needle = 'hooks::initPointerSwaps();'

        if (-not $mainText.Contains($needle)) {
            throw "Could not locate initPointerSwaps() in DllMain."
        }

        $mainText = $mainText.Replace(
            $needle,
            "hooks::initPointerSwaps();`r`n`t`thooks::applyBlackMarketAndEntitlementHooks();"
        )
    }

    # Disable the full legacy hook bundle in the UI so it cannot be turned on
    # accidentally while using this compatibility test build.
    $applyPattern = '(?ms)\s*if\s*\(ImGui::Button\("Apply Hooks"\)\)\s*\{\s*hooks::applyPatches\(\);\s*\}'

    if ([regex]::IsMatch($mainText, $applyPattern)) {
        $mainText = [regex]::Replace(
            $mainText,
            $applyPattern,
            "`r`n`t`t`tImGui::BeginDisabled();`r`n`t`t`tImGui::Button(`"Apply Hooks (disabled in compatibility build)`");`r`n`t`t`tImGui::EndDisabled();",
            1
        )
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "BLACK MARKET + ENTITLEMENTS COMPATIBILITY TEST BUILD",
        "hooks::onFrame() remains disabled from v7.",
        "Enabled hooks:",
        "  BG_UnlockablesItemOptionLocked",
        "  LiveInventory_GetItemQuantity",
        "  LiveEntitlements_IsEntitlementActiveForController",
        "Disabled:",
        "  PatchPrecomputed/checksum patch path",
        "  server hooks",
        "  gameplay hook bundle",
        "  full Apply Hooks menu action"
    ) | Set-Content (Join-Path $ProjectDir "BLACKMARKET_ENTITLEMENTS_TEST.txt") -Encoding UTF8

    Write-Host "Minimal Black Market + Entitlements hooks applied." -ForegroundColor Yellow
}


function Patch-MPClassEditorFix([string]$ProjectDir) {
    Write-Step "Applying Multiplayer Class Editor compatibility fix"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp missing: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw

    $fnPattern = '(?ms)^void\s+setClassSetItem\s*\(int itemId,\s*int iComboBoxtype,\s*int classSetIndex,\s*int classIndex,\s*const char\* slotName\)\s*\{.*?^\}\s*\r?\n\s*\r?\nvoid\s+setClassSlotByName'
    if (-not [regex]::IsMatch($mainText, $fnPattern)) {
        throw "Could not locate setClassSetItem() for MP Class Editor patch."
    }

    $replacement = @'
void setClassSetItem(int itemId, int iComboBoxtype, int classSetIndex, int classIndex, const char* slotName) {

    int item = itemId;

    // Use the item type stored for this row, not the global combobox value.
    switch (iComboBoxtype) {
    case CBC_ATTACHMENTS:
        break;
    case CBC_CAMOS:
        break;
    case CBC_WEAPONTYPE:
        if (itemId >= 73)
            item += 1;
        if (itemId == 131)
            item = 147;
        break;
    case CBC_RETICLES:
        item += 140;
        break;
    case CBC_PERK:
        item += 148;
        break;
    case CBC_BONUSCARD:
        item += 178;
        break;
    case CBC_KILLSTREAK:
        item += 198;
        if (item > 208)
            item += 1;
        break;
    case CBC_EXTRA:
        item += 228;
        break;
    default:
        break;
    }

    eGameModes sessionMode = Com_SessionMode_GetGameMode();
    eModes mode = Com_SessionMode_GetMode();

    if (mode == MODE_MULTIPLAYER) {
        // Same direct CAC route used by Scropts' Old Class Editor.
        CACRoot buffer{};
        CACType cacType = LiveStats_Loadouts_GetCACTypeForMode(mode, sessionMode);
        LiveStats_Loadouts_GetCACRoot(&buffer, 0, cacType);

        __int64 loadoutSlot = BG_UnlockablesGetLoadoutSlotFromString(slotName);
        BG_UnlockablesSetItemIndex(
            &buffer,
            static_cast<unsigned int>(classIndex),
            loadoutSlot,
            item
        );

        LiveStorage_UploadStatsForController(0);
        return;
    }

    auto classSetType = LiveStats_ClassSets_GetClassSetTypeForMode(mode, sessionMode);
    BG_UnlockablesSetClassSetItem(
        CONTROLLER_INDEX_0,
        classSetType,
        classSetIndex,
        classIndex,
        slotName,
        item
    );
}


void setClassSlotByName
'@

    $mainText = [regex]::Replace($mainText, $fnPattern, $replacement, 1)

    $mainText = $mainText.Replace(
        '{ primaryMenuNames[1], primarySlots[1], true, CBC_ATTACHMENTS, primaryPreviews, primarySelectedItems, primarySelectedSlot },',
        '{ primaryMenuNames[1], primarySlots[1], true, CBC_CAMOS, primaryPreviews, primarySelectedItems, primarySelectedSlot },'
    )
    $mainText = $mainText.Replace(
        '{ primaryMenuNames[6], primarySlots[6], true, CBC_CAMOS, primaryPreviews, primarySelectedItems, primarySelectedSlot },',
        '{ primaryMenuNames[6], primarySlots[6], true, CBC_ATTACHMENTS, primaryPreviews, primarySelectedItems, primarySelectedSlot },'
    )
    $mainText = $mainText.Replace(
        '{ secondaryMenuNames[1], secondarySlots[1], false, CBC_ATTACHMENTS, secondaryPreviews, secondarySelectedItems, secondarySelectedSlot },',
        '{ secondaryMenuNames[1], secondarySlots[1], false, CBC_CAMOS, secondaryPreviews, secondarySelectedItems, secondarySelectedSlot },'
    )
    $mainText = $mainText.Replace(
        '{ secondaryMenuNames[6], secondarySlots[6], false, CBC_CAMOS, secondaryPreviews, secondarySelectedItems, secondarySelectedSlot },',
        '{ secondaryMenuNames[6], secondarySlots[6], false, CBC_ATTACHMENTS, secondaryPreviews, secondarySelectedItems, secondarySelectedSlot },'
    )

    $noteNeedle = 'ImGui::Dummy(ImVec2(5, 5));'
    $noteInsert = @'
ImGui::Dummy(ImVec2(5, 5));

                if (Com_SessionMode_GetMode() == MODE_MULTIPLAYER) {
                    ImGui::TextWrapped("MP compatibility mode: Send writes directly to the active Multiplayer Create-a-Class buffer. Be inside the Multiplayer Create-a-Class menu before sending. Class-Set selection is ignored for item edits in this mode.");
                    ImGui::Separator();
                }
'@
    if ($mainText.Contains($noteNeedle)) {
        $mainText = $mainText.Replace($noteNeedle, $noteInsert)
    }

    if ($mainText -notmatch 'MP compatibility mode') {
        throw "MP Class Editor note was not inserted."
    }
    if ($mainText -notmatch 'switch\s*\(iComboBoxtype\)') {
        throw "setClassSetItem parameter-use fix validation failed."
    }
    if ($mainText -notmatch 'LiveStorage_UploadStatsForController\(0\);\s*return;') {
        throw "MP direct CAC write validation failed."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "MULTIPLAYER CLASS EDITOR FIX",
        "Based on v10 Black Market + Entitlements compatibility build.",
        "New Class Editor MP item writes use the direct CAC DDL path used by the Old Class Editor.",
        "setClassSetItem now uses its iComboBoxtype argument instead of the global iComboBoxType.",
        "Primary/Secondary Camo row metadata corrected.",
        "MP item edits call LiveStorage_UploadStatsForController(0) after writing.",
        "The v10 minimal Black Market + Entitlements hooks remain enabled.",
        "The crash-prone full legacy hook bundle remains disabled."
    ) | Set-Content (Join-Path $ProjectDir "MP_CLASS_EDITOR_FIX.txt") -Encoding UTF8

    Write-Host "Multiplayer Class Editor compatibility fix applied." -ForegroundColor Yellow
}


function Patch-GrandSlamMenuButton([string]$ProjectDir) {
    Write-Step "Adding Grand Slam Supply Drops button to Black Market menu"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp missing: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw

    $triplePattern = '(?ms)(\s*if\s*\(ImGui::Button\("Triple Play Supply Drops"\)\)\s*\{.*?Successfully activated Triple Plays\."\s*\}\);\s*\})'

    if (-not [regex]::IsMatch($mainText, $triplePattern)) {
        throw "Could not locate Triple Play Supply Drops button block."
    }

    $grandSlamBlock = @'

            if (ImGui::Button("Grand Slam Supply Drops")) {
                runDvars(SUPPLY_DROP_GRAND_SLAM);
                ImGui::InsertNotification({ ImGuiToastType::Success, 5000, "Successfully activated Grand Slam Supply Drops." });
            }
'@

    $mainText = [regex]::Replace(
        $mainText,
        $triplePattern,
        '$1' + $grandSlamBlock,
        1
    )

    if ($mainText -notmatch 'ImGui::Button\("Grand Slam Supply Drops"\)') {
        throw "Grand Slam menu button insertion failed."
    }

    if ($mainText -notmatch 'runDvars\(SUPPLY_DROP_GRAND_SLAM\)') {
        throw "Grand Slam menu button is not wired to SUPPLY_DROP_GRAND_SLAM."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "GRAND SLAM MENU BUTTON PATCH",
        "Adds Black Market -> Misc -> Grand Slam Supply Drops.",
        "Uses the public source's existing SUPPLY_DROP_GRAND_SLAM runDvars implementation.",
        "That existing implementation sets:",
        "  loot_limitedTimeItemPromo_active = 1",
        "  loot_limitedTimeItemPromo_promoString = Scropts",
        "  loot_limitedTimeItemPromo_promoIcon = t7_icon_blackmarket_promo_grandslam_green",
        "  loot_grandSlam_active = 1",
        "All v11 compatibility changes remain intact."
    ) | Set-Content (Join-Path $ProjectDir "GRAND_SLAM_MENU_PATCH.txt") -Encoding UTF8

    Write-Host "Grand Slam Supply Drops button added." -ForegroundColor Yellow
}


function Patch-GrandSlamContractFix([string]$ProjectDir) {
    Write-Step "Applying Grand Slam contract + visibility fix"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    $hooksPath = Join-Path $ProjectDir "hooks.cpp"

    foreach ($p in @($mainPath, $hooksPath)) {
        if (-not (Test-Path $p)) { throw "Expected source file missing: $p" }
    }

    $mainText = Get-Content $mainPath -Raw
    $hooksText = Get-Content $hooksPath -Raw

    # 1) Add a helper that activates Grand Slam as the active MP special contract.
    $insertNeedle = "void resetCrypto() {"
    if (-not $mainText.Contains($insertNeedle)) {
        throw "Could not locate insertion point before resetCrypto()."
    }

    $helper = @'
bool activateGrandSlamContract()
{
    constexpr int kSpecialContractSlot = 3;
    constexpr int kGrandSlamContractIndex = 3010;
    constexpr int kGrandSlamExtraBool = 11;

    auto root = LiveStats_Core_GetRootDDLState(Com_SessionMode_GetMode());
    auto ctx = GetStatsBuffer(0);

    if (!root || !ctx)
        return false;

    DDLState contractsState{};
    DDLState contractState{};
    DDLState fieldState{};

    if (!DDL_MoveToName(root, (char*)&contractsState, "contracts") ||
        !DDL_MoveToIndex(&contractsState, &contractState, kSpecialContractSlot))
        return false;

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "active"))
        DDL_SetUInt((__int64)&fieldState, ctx, 1);

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "index"))
        DDL_SetUInt((__int64)&fieldState, ctx, kGrandSlamContractIndex);

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "progress"))
        DDL_SetUInt((__int64)&fieldState, ctx, 0);

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "award_given"))
        DDL_SetUInt((__int64)&fieldState, ctx, 0);

    DDLState extraArray{};
    DDLState extraElement{};
    if (DDL_MoveToName(root, (char*)&extraArray, "extraBools") &&
        DDL_MoveToIndex(&extraArray, &extraElement, kGrandSlamExtraBool))
    {
        DDL_SetUInt((__int64)&extraElement, ctx, 1);
    }

    LiveStorage_UploadStatsForController(0);
    return true;
}


'@

    $mainText = $mainText.Replace($insertNeedle, $helper + $insertNeedle)

    # 2) Replace the v12 Grand Slam button with one that turns off Triple Play
    #    promo state and activates the actual Grand Slam special-contract slot.
    $buttonPattern = '(?ms)\s*if\s*\(ImGui::Button\("Grand Slam Supply Drops"\)\)\s*\{.*?Successfully activated Grand Slam Supply Drops\."\s*\}\);\s*\}'

    if (-not [regex]::IsMatch($mainText, $buttonPattern)) {
        throw "Could not locate v12 Grand Slam button."
    }

    $buttonReplacement = @'

            static bool grandSlamReplaceConfirmed = false;
            ImGui::Checkbox("Replace current special contract with Grand Slam", &grandSlamReplaceConfirmed);

            if (!grandSlamReplaceConfirmed)
                ImGui::BeginDisabled();

            if (ImGui::Button("Activate Grand Slam")) {
                Dvar_SetFromString("loot_trifectaActive", "0", true);
                Dvar_SetFromString("loot_trifectaActive_dummy", "0", true);

                Dvar_SetFromString("loot_limitedTimeItemPromo_active", "1", true);
                Dvar_SetFromString("loot_limitedTimeItemPromo_promoString", "Grand Slam", true);
                Dvar_SetFromString("loot_limitedTimeItemPromo_promoIcon", "t7_icon_blackmarket_promo_grandslam_green", true);
                Dvar_SetFromString("loot_grandSlam_active", "1", true);
                Dvar_SetFromString("loot_grandslam_cpcost", "4000", true);

                if (activateGrandSlamContract()) {
                    ImGui::InsertNotification({ ImGuiToastType::Success, 5000, "Grand Slam activated. Reopen Contracts / Black Market." });
                } else {
                    ImGui::InsertNotification({ ImGuiToastType::Error, 5000, "Grand Slam DVARs set, but contract profile write failed." });
                }
            }

            if (!grandSlamReplaceConfirmed)
                ImGui::EndDisabled();

            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Replaces your current special contract with Grand Slam (contract 3010) and resets its progress to 0.");
            }
'@

    $mainText = [regex]::Replace($mainText, $buttonPattern, $buttonReplacement, 1)

    # 3) Fix the interaction with Blackmarket Items spoof.
    #    BO3's Grand Slam UI only shows the offer if item 99083 quantity is 0.
    $qtyPattern = '(?ms)(__int64\s+hkLiveInventory_GetItemQuantity\s*\([^)]*\)\s*\{.*?)(if\s*\(bSpoofBlackMarket\)\s*return\s+iBlackmarketAmt;)'
    if (-not [regex]::IsMatch($hooksText, $qtyPattern)) {
        throw "Could not locate Black Market quantity spoof hook."
    }

    $qtyReplacement = '$1' + @'
if (bSpoofBlackMarket && itemId == 99083)
                return LiveInventory_GetItemQuantity(controllerIndex, itemId);

            if (bSpoofBlackMarket) return iBlackmarketAmt;
'@

    $hooksText = [regex]::Replace($hooksText, $qtyPattern, $qtyReplacement, 1)

    if ($mainText -notmatch 'kGrandSlamContractIndex = 3010') {
        throw "Grand Slam contract helper validation failed."
    }
    if ($hooksText -notmatch 'itemId == 99083') {
        throw "Grand Slam inventory-visibility exception validation failed."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8
    Set-Content -Path $hooksPath -Value $hooksText -Encoding UTF8

    @(
        "V13 GRAND SLAM CONTRACT FIX",
        "Replaces the active MP special contract with Grand Slam contract 3010.",
        "Sets contracts[3]: active=1, index=3010, progress=0, award_given=0.",
        "Sets extraBools[11]=1 per mp_contracttable.csv.",
        "Disables Triple Play promo DVARs before enabling Grand Slam.",
        "Sets loot_grandslam_cpcost=4000 per BO3 event data.",
        "Excludes Grand Slam drop item 99083 from the Blackmarket Items quantity spoof so the UI can see quantity 0.",
        "All prior v12 compatibility changes remain intact."
    ) | Set-Content (Join-Path $ProjectDir "V13_GRAND_SLAM_CONTRACT_FIX.txt") -Encoding UTF8

    Write-Host "Grand Slam contract + visibility fix applied." -ForegroundColor Yellow
}


function Patch-GrandSlamNoMatchRewardSync([string]$ProjectDir) {
    Write-Step "Adding Grand Slam no-match completion + reward sync experiment (v14.1)"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp missing: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw

    # Add small state variables beside the existing crypto-loop globals.
    $globalNeedle = "bool bCryptoSpend;"
    if (-not $mainText.Contains($globalNeedle)) {
        throw "Could not locate crypto globals."
    }

    if ($mainText -notmatch 'bGrandSlamRewardSync') {
        $globals = @'
bool bCryptoSpend;
bool bGrandSlamRewardSync = false;
int iGrandSlamRewardSyncPulses = 0;
clock_t GrandSlamRewardSyncTMR = 0;
'@
        $mainText = $mainText.Replace($globalNeedle, $globals)
    }

    # Add Grand Slam completion + diagnostics to the v13 Black Market section.
    $menuNeedle = 'if (ImGui::Button("Activate Grand Slam")) {'
    $menuPos = $mainText.IndexOf($menuNeedle)
    if ($menuPos -lt 0) {
        throw "Could not locate v13 Activate Grand Slam button."
    }

    # Insert after the v13 tooltip block, before the next unrelated Black Market control.
    $tooltipNeedle = 'ImGui::SetTooltip("Replaces your current special contract with Grand Slam (contract 3010) and resets its progress to 0.");'
    $tooltipPos = $mainText.IndexOf($tooltipNeedle, $menuPos)
    if ($tooltipPos -lt 0) {
        throw "Could not locate v13 Grand Slam tooltip."
    }

    $tooltipBlockEnd = $mainText.IndexOf("}", $tooltipPos)
    if ($tooltipBlockEnd -lt 0) {
        throw "Could not determine Grand Slam tooltip block end."
    }
    $insertAt = $tooltipBlockEnd + 1

    if ($mainText -notmatch 'Hard Complete Grand Slam') {
        $menuBlock = @'

            ImGui::SeparatorText("Grand Slam Reward Test");

            static bool grandSlamCompleteConfirmed = false;
            ImGui::Checkbox("I understand this marks Grand Slam 125/125", &grandSlamCompleteConfirmed);

            if (!grandSlamCompleteConfirmed)
                ImGui::BeginDisabled();

            if (ImGui::Button("Hard Complete Grand Slam (125/125)")) {
                // Reuse Scropts' own hard-contract implementation, but only for
                // Grand Slam contract 3010 in special-contract slot 3.
                unlockContracts(3010, 3011, 3);
                LiveStorage_UploadStatsForController(0);
                ImGui::InsertNotification({ ImGuiToastType::Success, 5000, "Grand Slam marked 125/125. award_given=1, extraBools[11]=1." });
            }

            if (!grandSlamCompleteConfirmed)
                ImGui::EndDisabled();

            ImGui::Dummy(ImVec2(0, 4));

            // These calls use the original LiveInventory function pointer
            // supplied by MinHook, so the values shown here are not the
            // Blackmarket Items spoofed quantities.
            const __int64 realWeapon3X = LiveInventory_GetItemQuantity(CONTROLLER_INDEX_0, 99087);
            const __int64 realLimitedCamo = LiveInventory_GetItemQuantity(CONTROLLER_INDEX_0, 99086);
            const __int64 realRare20 = LiveInventory_GetItemQuantity(CONTROLLER_INDEX_0, 99128);

            ImGui::Text("Real reward inventory:");
            ImGui::BulletText("3x Weapon bundle (99087): %lld", realWeapon3X);
            ImGui::BulletText("Limited camo bundle (99086): %lld", realLimitedCamo);
            ImGui::BulletText("Rare 20 bundle (99128): %lld", realRare20);

            if (!bGrandSlamRewardSync) {
                if (ImGui::Button("Start No-Match Reward Sync")) {
                    // User observed Scropts' cryptokey loop causing previously
                    // hard-completed Triple Play rewards to appear. This
                    // controlled experiment reuses that same GiveLootToSelf
                    // inventory mutation, one key at a time, and stops after
                    // 30 pulses or once the two Grand Slam-specific reward
                    // bundle tokens become real inventory.
                    bCrypto = false;
                    bGrandSlamRewardSync = true;
                    iGrandSlamRewardSyncPulses = 0;
                    GrandSlamRewardSyncTMR = clock();
                    ImGui::InsertNotification({ ImGuiToastType::Info, 5000, "Grand Slam reward sync started (max 30 pulses)." });
                }
            }
            else {
                if (ImGui::Button("Stop No-Match Reward Sync")) {
                    bGrandSlamRewardSync = false;
                }
                ImGui::SameLine();
                ImGui::Text("Pulses: %d / 30", iGrandSlamRewardSyncPulses);
            }

            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("This does not purchase the 4000 COD Point Grand Slam. It tests whether BO3's normal inventory sync will reconcile a hard-completed contract without entering a match.");
            }

'@
        $mainText = $mainText.Insert($insertAt, $menuBlock)
    }

    # Add a controlled GiveLootToSelf sync loop beside the existing crypto loop.
    # v14.1: use a whitespace/line-ending tolerant regex instead of an exact
    # string comparison. GitHub ZIP/source line endings can differ after the
    # earlier source-patching stages, which made the original v14 builder stop
    # even though the cryptokey loop was still present.
    $cryptoPattern = '(?ms)if\s*\(bCrypto\)\s*\{\s*if\s*\(clock\(\)\s*-\s*UnlockTMR\s*>\s*iLootSpeed\)\s*\{\s*GiveLootToSelf\s*\(\s*0\s*,\s*1\s*,\s*iCryptoAmt\s*\*\s*100\s*\)\s*;\s*UnlockTMR\s*=\s*clock\(\)\s*;\s*\}\s*\}'

    $cryptoMatch = [regex]::Match($mainText, $cryptoPattern)
    if (-not $cryptoMatch.Success) {
        throw "Could not locate existing cryptokey loop block (regex search)."
    }

    if ($mainText -notmatch 'GiveLootToSelf\s*\(\s*0\s*,\s*1\s*,\s*100\s*\)\s*;') {
        $syncBlock = @'

	if (bGrandSlamRewardSync)
	{
		if (clock() - GrandSlamRewardSyncTMR > 1000)
		{
			// Minimal real inventory mutation: +1 cryptokey equivalent.
			// This is the same BO3 helper used by Scropts' Loop Cryptokeys.
			GiveLootToSelf(0, 1, 100);
			++iGrandSlamRewardSyncPulses;
			GrandSlamRewardSyncTMR = clock();

			const __int64 weapon3X = LiveInventory_GetItemQuantity(CONTROLLER_INDEX_0, 99087);
			const __int64 limitedCamo = LiveInventory_GetItemQuantity(CONTROLLER_INDEX_0, 99086);

			if ((weapon3X > 0 && limitedCamo > 0) ||
				iGrandSlamRewardSyncPulses >= 30)
			{
				bGrandSlamRewardSync = false;
			}
		}
	}
'@
        $insertPos = $cryptoMatch.Index + $cryptoMatch.Length
        $mainText = $mainText.Insert($insertPos, $syncBlock)
    }

    if ($mainText -notmatch 'unlockContracts\(3010,\s*3011,\s*3\)') {
        throw "Grand Slam hard-complete button validation failed."
    }

    if ($mainText -notmatch 'GiveLootToSelf\(0,\s*1,\s*100\)') {
        throw "Reward sync pulse validation failed."
    }

    if ($mainText -notmatch '99087' -or $mainText -notmatch '99086') {
        throw "Grand Slam reward inventory diagnostics validation failed."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "V14 GRAND SLAM NO-MATCH REWARD SYNC",
        "Adds an isolated Hard Complete Grand Slam button using Scropts' own unlockContracts(3010,3011,3) path.",
        "Shows real (unspoofed) inventory quantities for:",
        "  99087 = Weapon 3X bundle",
        "  99086 = Limited Edition Camo bundle",
        "  99128 = Rare 20 bundle",
        "Adds an optional no-match reward sync experiment:",
        "  calls GiveLootToSelf(0,1,100) once per second",
        "  max 30 pulses",
        "  stops early when both 99087 and 99086 are real inventory",
        "Does NOT purchase the 4000 COD Point Grand Slam offer.",
        "Does NOT re-enable the legacy crash-prone hook bundle."
    ) | Set-Content (Join-Path $ProjectDir "V14_GRAND_SLAM_NO_MATCH_REWARD_SYNC.txt") -Encoding UTF8

    Write-Host "Grand Slam no-match reward sync experiment applied." -ForegroundColor Yellow
}


function Patch-GrandSlamRewardRetryAndNoDupeSpender([string]$ProjectDir) {
    Write-Step "Adding Grand Slam reward retry path + No-Dupe cryptokey spender"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp missing: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw

    # ------------------------------------------------------------------
    # 1) Spend Cryptokeys mode selector
    # ------------------------------------------------------------------

    if ($mainText -notmatch 'iCryptoSpendMode') {
        $globalPattern = '(static\s+int\s+iCryptoAmt\s*=\s*48\s*;)'
        if (-not [regex]::IsMatch($mainText, $globalPattern)) {
            throw "Could not locate iCryptoAmt global."
        }

        $mainText = [regex]::Replace(
            $mainText,
            $globalPattern,
            '$1' + "`r`nstatic int iCryptoSpendMode = 0; // 0=Regular Rare, 1=No-Dupe Rare",
            1
        )
    }

    $spendCheckbox = 'ImGui::Checkbox("Spend Cryptokeys", &bCryptoSpend);'
    if (-not $mainText.Contains($spendCheckbox)) {
        throw "Could not locate Spend Cryptokeys checkbox."
    }

    if ($mainText -notmatch 'Spend Drop Type ##CRYPTOSPENDTYPE') {
        $spendUi = @'
ImGui::Checkbox("Spend Cryptokeys", &bCryptoSpend);

            ImGui::SetNextItemWidth(230.0f);
            ImGui::Combo(
                "Spend Drop Type ##CRYPTOSPENDTYPE",
                &iCryptoSpendMode,
                "Regular Rare (30 CK)`0No-Dupe Rare (60 CK)`0"
            );

            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("No-Dupe uses BO3's no-dupe rare crate DWID 35 with Cryptokeys.");
            }
'@
        $mainText = $mainText.Replace($spendCheckbox, $spendUi)
    }

    # Replace the runtime spender block.
    $spendPattern = '(?ms)if\s*\(bCryptoSpend\)\s*\{\s*bCrypto\s*=\s*false\s*;\s*bSpoofBlackMarket\s*=\s*false\s*;\s*Loot_BuyCrate\s*\(\s*0\s*,\s*1\s*,\s*2\s*\)\s*;\s*\}'

    if (-not [regex]::IsMatch($mainText, $spendPattern)) {
        throw "Could not locate existing bCryptoSpend runtime block."
    }

    $spendReplacement = @'
if (bCryptoSpend)
    {
        bCrypto = false;
        bSpoofBlackMarket = false;

        if (iCryptoSpendMode == 1)
        {
            // BO3's scheduled rare-no-dupe event uses:
            //   loot_noDupeRare_active = 1
            //   loot_noDupeRare_dwid = 35
            //   loot_noDupeRare_cryptoCost = 60
            //
            // BlackMarketUtility then passes that DWID to BuyLootCrate
            // using MP Cryptokeys (currency 2).
            Dvar_SetFromString("loot_noDupeRare_active", "1", true);
            Dvar_SetFromString("loot_noDupeRare_dwid", "35", true);
            Dvar_SetFromString("loot_noDupeRare_cryptoCost", "60", true);
            Dvar_SetFromString("loot_noDupeRare_cpCost", "300", true);

            Loot_BuyCrate(0, 35, 2);
        }
        else
        {
            Loot_BuyCrate(0, 1, 2);
        }
    }
'@

    $mainText = [regex]::Replace($mainText, $spendPattern, $spendReplacement, 1)

    # ------------------------------------------------------------------
    # 2) Grand Slam reward retry using BO3's own lobby retry mechanism
    # ------------------------------------------------------------------
    #
    # LuaUtils.BuySpecialContractRewardsIfNeeded() scans special contracts.
    # For Grand Slam row 3010:
    #   column 9  = extraBools 11
    #   column 10 = 99085 (reward inventory item)
    #   column 11 = 99084 (reward SKU)
    #
    # Lobby.Events.Pump calls that function when reward_retry_perform_action=1.
    # This is the normal BO3 reward retry path and avoids faking a match win.

    $grandSlamMarker = 'ImGui::SeparatorText("Grand Slam Reward Test");'
    if (-not $mainText.Contains($grandSlamMarker)) {
        throw "Could not locate v14 Grand Slam Reward Test section."
    }

    if ($mainText -notmatch 'Retry Special Contract Rewards') {
        $retryBlock = @'
ImGui::SeparatorText("Grand Slam Reward Test");

            ImGui::TextWrapped("BO3 has a built-in lobby reward-retry path for completed special contracts. Grand Slam uses extraBools[11], reward item 99085, and reward SKU 99084.");

            if (ImGui::Button("Retry Special Contract Rewards")) {
                // Lua Lobby.Events.Pump watches these dvars while in the LIVE
                // frontend and calls LuaUtils.BuySpecialContractRewardsIfNeeded.
                // That routine reads the contract table and, for Grand Slam,
                // requests SKU 99084 if extraBools[11] is set and inventory
                // item 99085 is still missing.
                Dvar_SetFromString("enable_weapon_contract", "1", true);
                Dvar_SetFromString("live_autoEventEnabled", "1", true);
                Dvar_SetFromString("reward_retry_controller", "0", true);
                Dvar_SetFromString("reward_retry_perform_action", "1", true);
                Dvar_SetFromString("live_autoEventPumpTime", "0", true);

                ImGui::InsertNotification({
                    ImGuiToastType::Info,
                    7000,
                    "Reward retry queued. Stay in the Multiplayer lobby / Black Market for a few seconds."
                });
            }

            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Uses BO3's own Lobby.Events reward-retry mechanism. It may redeem any other pending special-contract rewards too.");
            }

            const __int64 realGrandSlamRedeemItem =
                LiveInventory_GetItemQuantity(CONTROLLER_INDEX_0, 99085);

            ImGui::Text("Grand Slam contract reward item (99085): %lld", realGrandSlamRedeemItem);

'@
        $mainText = $mainText.Replace($grandSlamMarker, $retryBlock)
    }

    # Clarify the old no-match sync button now that the exact BO3 reward path
    # has been identified. Keep it available for comparison, but don't present
    # it as the preferred path.
    $mainText = $mainText.Replace(
        'if (ImGui::Button("Start No-Match Reward Sync")) {',
        'if (ImGui::Button("Start Legacy Crypto-Pulse Sync")) {'
    )

    # Sanity checks.
    if ($mainText -notmatch 'Loot_BuyCrate\(0,\s*35,\s*2\)') {
        throw "No-Dupe spender validation failed."
    }
    if ($mainText -notmatch 'reward_retry_perform_action') {
        throw "Reward retry dvar validation failed."
    }
    if ($mainText -notmatch '99085' -or $mainText -notmatch '99084') {
        throw "Grand Slam reward ID validation failed."
    }
    if ($mainText -notmatch 'Spend Drop Type ##CRYPTOSPENDTYPE') {
        throw "Spend mode UI validation failed."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "V15 GRAND SLAM REWARD RETRY + NO-DUPE CRYPTOKEY SPENDER",
        "",
        "Grand Slam reward retry:",
        "  Uses BO3's normal Lobby.Events reward_retry_perform_action mechanism.",
        "  Grand Slam contract row 3010 maps:",
        "    extraBools[11] -> completion/reward-needed flag",
        "    99085 -> reward inventory item",
        "    99084 -> reward redeem SKU",
        "  BO3's LuaUtils.BuySpecialContractRewardsIfNeeded() calls PurchaseDWSKU(99084)",
        "  when extraBools[11] is set and inventory item 99085 is absent.",
        "",
        "Cryptokey spender:",
        "  Regular Rare -> Loot_BuyCrate(0, 1, 2)",
        "  No-Dupe Rare -> activates no-dupe event dvars and calls Loot_BuyCrate(0, 35, 2)",
        "  No-Dupe event cost is 60 Cryptokeys.",
        "",
        "All v14.1 compatibility patches remain intact.",
        "The legacy full hook bundle remains disabled."
    ) | Set-Content (Join-Path $ProjectDir "V15_REWARD_RETRY_NODUPE_SPENDER.txt") -Encoding UTF8

    Write-Host "Grand Slam reward retry + No-Dupe spender applied." -ForegroundColor Yellow
}


function Patch-V16PersistentGrandSlamRetryAndNoDupeFix([string]$ProjectDir) {
    Write-Step "Applying v16.1 persistent Grand Slam retry + corrected No-Dupe crate type"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp missing: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw

    # ------------------------------------------------------------------
    # FIX 1: No-Dupe spender
    # ------------------------------------------------------------------
    #
    # v15 incorrectly passed DWID 35 as Loot_BuyCrate's CrateType argument.
    # Scropts defines Loot_BuyCrate(controller, CrateType, CurrencyType).
    # BO3's loot_crate.csv maps:
    #   1  -> loot_rareCrate
    #   18 -> loot_noDupeRare
    #
    # The no-dupe event then maps crate type 18 to DWID 35 internally.
    # Passing 35 as CrateType falls outside the normal crate-type table and
    # can fall back to regular Rare behavior.
    $mainText = $mainText.Replace(
        'Loot_BuyCrate(0, 35, 2);',
        'Loot_BuyCrate(0, 18, 2);'
    )

    # Use the event's exact dvar spellings/values as shipped by BO3.
    $mainText = $mainText.Replace(
        'Dvar_SetFromString("loot_noDupeRare_active", "1", true);',
        'Dvar_SetFromString("loot_noduperare_active", "1", true);'
    )
    $mainText = $mainText.Replace(
        'Dvar_SetFromString("loot_noDupeRare_dwid", "35", true);',
        'Dvar_SetFromString("loot_noduperare_dwid", "35", true);'
    )
    $mainText = $mainText.Replace(
        'Dvar_SetFromString("loot_noDupeRare_cryptoCost", "60", true);',
        'Dvar_SetFromString("loot_noduperare_cryptocost", "60", true);'
    )
    $mainText = $mainText.Replace(
        'Dvar_SetFromString("loot_noDupeRare_cpCost", "300", true);',
        'Dvar_SetFromString("loot_noduperare_cpcost", "300", true);'
    )

    # Also make the existing "No Dupe Supply Drops" button initialize the
    # complete event values rather than only toggling the active flag.
    $noDupeButtonPattern = '(?ms)(if\s*\(ImGui::Button\("No Dupe Supply Drops"\)\)\s*\{.*?Dvar_SetFromString\("loot_noduperare_active",\s*"1",\s*true\);)'
    if ([regex]::IsMatch($mainText, $noDupeButtonPattern) -and
        $mainText -notmatch 'No-Dupe event values initialized') {

        $mainText = [regex]::Replace(
            $mainText,
            $noDupeButtonPattern,
            '$1' + @'

                Dvar_SetFromString("loot_noduperare_dwid", "35", true);
                Dvar_SetFromString("loot_noduperare_cpcost", "300", true);
                Dvar_SetFromString("loot_noduperare_cryptocost", "60", true);
                // No-Dupe event values initialized
'@,
            1
        )
    }

    # ------------------------------------------------------------------
    # FIX 2: Persistent Grand Slam reward retry
    # ------------------------------------------------------------------
    #
    # BO3's Lobby.Events.Pump clears reward_retry_perform_action after each
    # attempt, even if Demonware was not yet ready. A one-shot button can
    # therefore miss the ready window. v16 keeps re-queuing the native retry
    # every 2.5 seconds for up to ~60 seconds, stopping early if item 99085
    # appears in REAL inventory.
    #
    # The native Lua path remains:
    # Lobby.Events.Pump ->
    # LuaUtils.BuySpecialContractRewardsIfNeeded ->
    # Grand Slam row 3010:
    #   extraBools[11] completion marker
    #   reward item 99085
    #   reward SKU 99084
    # -> Engine.PurchaseDWSKU(controller, 99084)

    if ($mainText -notmatch 'bGrandSlamPersistentRetry') {
        $globalNeedle = 'bool bGrandSlamRewardSync = false;'
        if (-not $mainText.Contains($globalNeedle)) {
            throw "Could not locate Grand Slam v14 globals."
        }

        $globals = @'
bool bGrandSlamRewardSync = false;
bool bGrandSlamPersistentRetry = false;
int iGrandSlamPersistentRetryPulses = 0;
clock_t GrandSlamPersistentRetryTMR = 0;
'@
        $mainText = $mainText.Replace($globalNeedle, $globals)
    }

    $inventoryLine = 'ImGui::Text("Grand Slam contract reward item (99085): %lld", realGrandSlamRedeemItem);'
    if (-not $mainText.Contains($inventoryLine)) {
        throw "Could not locate v15 Grand Slam inventory status line."
    }

    if ($mainText -notmatch 'Start Persistent Grand Slam Reward Retry') {
        $ui = @'
ImGui::Text("Grand Slam contract reward item (99085): %lld", realGrandSlamRedeemItem);

            if (!bGrandSlamPersistentRetry) {
                if (ImGui::Button("Start Persistent Grand Slam Reward Retry")) {
                    // Re-assert the Grand Slam completion state, then upload
                    // it before the delayed retry pulses begin.
                    unlockContracts(3010, 3011, 3);
                    LiveStorage_UploadStatsForController(0);

                    Dvar_SetFromString("enable_weapon_contract", "1", true);
                    Dvar_SetFromString("contracts_enabled_mp", "1", true);
                    Dvar_SetFromString("skip_contract_rewards", "0", true);
                    Dvar_SetFromString("live_autoEventEnabled", "1", true);
                    Dvar_SetFromString("reward_retry_controller", "0", true);
                    Dvar_SetFromString("live_autoEventPumpTime", "0", true);

                    bGrandSlamPersistentRetry = true;
                    iGrandSlamPersistentRetryPulses = 0;
                    GrandSlamPersistentRetryTMR = clock();

                    ImGui::InsertNotification({
                        ImGuiToastType::Info,
                        7000,
                        "Persistent reward retry armed. Stay in the LIVE Multiplayer frontend for up to 60 seconds."
                    });
                }
            }
            else {
                if (ImGui::Button("Stop Persistent Grand Slam Reward Retry")) {
                    bGrandSlamPersistentRetry = false;
                }

                ImGui::SameLine();
                ImGui::Text("Retry pulses: %d / 24", iGrandSlamPersistentRetryPulses);
            }

            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Re-queues BO3's native special-contract reward retry every 2.5 seconds until reward item 99085 appears or 24 attempts are reached.");
            }

'@
        $mainText = $mainText.Replace($inventoryLine, $ui)
    }

    # Insert the retry pump into the per-Present runtime block immediately
    # before the existing cryptokey loop.
    #
    # v16.1: do not use an exact tab/CRLF string match here. Earlier builder
    # stages can normalize indentation/line endings while preserving the same
    # C++ code. Locate the bCrypto runtime block with a tolerant regex instead.
    $runtimePattern = '(?m)^[ \t]*if\s*\(bCrypto\)\s*\r?$'
    $runtimeMatch = [regex]::Match($mainText, $runtimePattern)

    if (-not $runtimeMatch.Success) {
        throw "Could not locate per-Present cryptokey runtime block (regex search)."
    }

    if ($mainText -notmatch 'iGrandSlamPersistentRetryPulses >= 24') {
        $runtime = @'
	if (bGrandSlamPersistentRetry)
	{
		const __int64 grandSlamRewardItem =
			LiveInventory_GetItemQuantity(CONTROLLER_INDEX_0, 99085);

		if (grandSlamRewardItem > 0)
		{
			bGrandSlamPersistentRetry = false;
			ImGui::InsertNotification({
				ImGuiToastType::Success,
				7000,
				"Grand Slam reward item 99085 appeared in real inventory."
			});
		}
		else if (clock() - GrandSlamPersistentRetryTMR > 2500)
		{
			// Lobby.Events.Pump consumes/clears this flag after each attempt,
			// so keep re-queuing it until Demonware/loot is ready.
			Dvar_SetFromString("enable_weapon_contract", "1", true);
			Dvar_SetFromString("contracts_enabled_mp", "1", true);
			Dvar_SetFromString("skip_contract_rewards", "0", true);
			Dvar_SetFromString("live_autoEventEnabled", "1", true);
			Dvar_SetFromString("reward_retry_controller", "0", true);
			Dvar_SetFromString("reward_retry_perform_action", "1", true);
			Dvar_SetFromString("live_autoEventPumpTime", "0", true);

			++iGrandSlamPersistentRetryPulses;
			GrandSlamPersistentRetryTMR = clock();

			if (iGrandSlamPersistentRetryPulses >= 24)
			{
				bGrandSlamPersistentRetry = false;
				ImGui::InsertNotification({
					ImGuiToastType::Warning,
					7000,
					"Grand Slam retry timed out without real reward item 99085."
				});
			}
		}
	}

'@
        $mainText = $mainText.Insert($runtimeMatch.Index, $runtime)
    }

    # Update v15 UI text so it no longer claims DWID 35 is passed as CrateType.
    $mainText = $mainText.Replace(
        'ImGui::SetTooltip("No-Dupe uses BO3''s no-dupe rare crate DWID 35 with Cryptokeys.");',
        'ImGui::SetTooltip("No-Dupe uses BO3 crate type 18 (loot_noDupeRare), which maps to DWID 35, for 60 Cryptokeys.");'
    )

    # Validation
    if ($mainText -match 'Loot_BuyCrate\(0,\s*35,\s*2\)') {
        throw "v16 validation failed: stale DWID-as-crate call remains."
    }
    if ($mainText -notmatch 'Loot_BuyCrate\(0,\s*18,\s*2\)') {
        throw "v16 validation failed: corrected No-Dupe crate-type call missing."
    }
    if ($mainText -notmatch 'Start Persistent Grand Slam Reward Retry') {
        throw "v16 validation failed: persistent retry UI missing."
    }
    if ($mainText -notmatch 'reward_retry_perform_action') {
        throw "v16 validation failed: reward retry trigger missing."
    }
    if ($mainText -notmatch 'iGrandSlamPersistentRetryPulses >= 24') {
        throw "v16 validation failed: persistent retry runtime loop missing."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "V16 PERSISTENT GRAND SLAM RETRY + NO-DUPE FIX",
        "",
        "NO-DUPE FIX:",
        "  v15 bug: passed DWID 35 as Loot_BuyCrate CrateType.",
        "  Correct call: Loot_BuyCrate(0, 18, 2).",
        "  BO3 loot_crate.csv maps CrateType 18 -> loot_noDupeRare.",
        "  The event maps loot_noDupeRare to DWID 35 and cost 60 Cryptokeys.",
        "",
        "GRAND SLAM RETRY:",
        "  Re-asserts contract 3010 completion and uploads stats once.",
        "  Re-queues BO3's reward_retry_perform_action every 2.5s.",
        "  Maximum 24 retry pulses (~60 seconds).",
        "  Stops early when REAL inventory item 99085 appears.",
        "  Native BO3 path should then redeem reward SKU 99084.",
        "",
        "No checksum/integrity bypass is added or re-enabled.",
        "The legacy full hook bundle remains disabled."
    ) | Set-Content (Join-Path $ProjectDir "V16_PERSISTENT_RETRY_NODUPE_FIX.txt") -Encoding UTF8

    Write-Host "v16 persistent reward retry + No-Dupe fix applied." -ForegroundColor Yellow
}


function Patch-V17CleanBlackMarket([string]$ProjectDir) {
    Write-Step "Applying v17 clean Black Market UI + No-Dupe purchase mapping"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp missing: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw

    # ================================================================
    # 1) Correct Grand Slam activation semantics.
    #
    # extraBools[11] is the Grand Slam COMPLETION/reward marker from
    # mp_contracttable.csv. It should not be set merely by activating
    # contract 3010. Keep activation limited to contracts[3].
    # ================================================================
    $activatePattern = '(?ms)^bool\s+activateGrandSlamContract\(\)\s*\{.*?^\}\s*\r?\n'

    if (-not [regex]::IsMatch($mainText, $activatePattern)) {
        throw "Could not locate activateGrandSlamContract()."
    }

    $activateReplacement = @'
bool activateGrandSlamContract()
{
    constexpr int kSpecialContractSlot = 3;
    constexpr int kGrandSlamContractIndex = 3010;

    auto root = LiveStats_Core_GetRootDDLState(Com_SessionMode_GetMode());
    auto ctx = GetStatsBuffer(0);

    if (!root || !ctx)
        return false;

    DDLState contractsState{};
    DDLState contractState{};
    DDLState fieldState{};

    if (!DDL_MoveToName(root, (char*)&contractsState, "contracts") ||
        !DDL_MoveToIndex(&contractsState, &contractState, kSpecialContractSlot))
        return false;

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "active"))
        DDL_SetUInt((__int64)&fieldState, ctx, 1);

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "index"))
        DDL_SetUInt((__int64)&fieldState, ctx, kGrandSlamContractIndex);

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "progress"))
        DDL_SetUInt((__int64)&fieldState, ctx, 0);

    if (DDL_MoveToName((__int64)&contractState, (char*)&fieldState, "award_given"))
        DDL_SetUInt((__int64)&fieldState, ctx, 0);

    LiveStorage_UploadStatsForController(0);
    return true;
}

'@

    $mainText = [regex]::Replace($mainText, $activatePattern, $activateReplacement, 1)

    # ================================================================
    # 2) Replace the v13/v16 Grand Slam control with one small, honest
    #    contract control. Remove the 4000-CP promo manipulation.
    # ================================================================
    $grandControlPattern = '(?ms)\s*static\s+bool\s+grandSlamReplaceConfirmed\s*=\s*false;.*?ImGui::SetTooltip\("Replaces your current special contract with Grand Slam \(contract 3010\) and resets its progress to 0\."\);\s*\}'

    if (-not [regex]::IsMatch($mainText, $grandControlPattern)) {
        throw "Could not locate Grand Slam contract UI block."
    }

    $grandControl = @'

            ImGui::SeparatorText("Grand Slam Contract");

            static bool grandSlamReplaceConfirmed = false;
            ImGui::Checkbox("Allow replacing current special contract", &grandSlamReplaceConfirmed);

            if (!grandSlamReplaceConfirmed)
                ImGui::BeginDisabled();

            if (ImGui::Button("Set Grand Slam as Active Contract")) {
                if (activateGrandSlamContract()) {
                    ImGui::InsertNotification({
                        ImGuiToastType::Success,
                        5000,
                        "Grand Slam is now the active special contract (0/125)."
                    });
                } else {
                    ImGui::InsertNotification({
                        ImGuiToastType::Error,
                        5000,
                        "Could not write the Grand Slam contract state."
                    });
                }
            }

            if (!grandSlamReplaceConfirmed)
                ImGui::EndDisabled();

            ImGui::TextDisabled("Reward bundles are online inventory items; changing the local contract does not grant them.");
'@

    $mainText = [regex]::Replace($mainText, $grandControlPattern, $grandControl, 1)

    # ================================================================
    # 3) Remove the non-working Grand Slam reward-test/retry UI added in
    #    v14-v16. Keep the code path disabled/unreachable, but remove all
    #    buttons/counters from the menu.
    # ================================================================
    $rewardSectionPattern = '(?ms)\s*ImGui::SeparatorText\("Grand Slam Reward Test"\);.*?(?=\s*/\*ImGui::SetNextItemWidth\(200\.0f\);)'

    if (-not [regex]::IsMatch($mainText, $rewardSectionPattern)) {
        throw "Could not locate Grand Slam Reward Test UI for cleanup."
    }

    $mainText = [regex]::Replace($mainText, $rewardSectionPattern, "`r`n", 1)

    # ================================================================
    # 4) Remove the old separate No-Dupe button. The selected spend mode
    #    now enables/disables the event automatically.
    # ================================================================
    $noDupeButtonPattern = '(?ms)\s*if\s*\(ImGui::Button\("No Dupe Supply Drops"\)\)\s*\{.*?Successfully activated No Dupe Drops\."\s*\}\);\s*\}'

    if ([regex]::IsMatch($mainText, $noDupeButtonPattern)) {
        $mainText = [regex]::Replace($mainText, $noDupeButtonPattern, "`r`n", 1)
    }

    # ================================================================
    # 5) Replace the broken one-entry combo with two explicit radio
    #    buttons. The v15 combo contained literal characters "`0" rather
    #    than C++ NUL separators, so ImGui saw a single item.
    # ================================================================
    $spendUiPattern = '(?ms)ImGui::Checkbox\("Spend Cryptokeys",\s*&bCryptoSpend\);\s*ImGui::SetNextItemWidth\(230\.0f\);\s*ImGui::Combo\(\s*"Spend Drop Type ##CRYPTOSPENDTYPE",\s*&iCryptoSpendMode,\s*"Regular Rare \(30 CK\).*?"\s*\);\s*if\s*\(ImGui::IsItemHovered\(\)\)\s*\{.*?\}'

    if (-not [regex]::IsMatch($mainText, $spendUiPattern)) {
        throw "Could not locate v15/v16 Spend Cryptokeys selector."
    }

    $spendUi = @'
ImGui::Checkbox("Auto Spend Cryptokeys", &bCryptoSpend);

            ImGui::Text("Spend on:");
            ImGui::SameLine();
            ImGui::RadioButton("Rare (30 CK)", &iCryptoSpendMode, 0);
            ImGui::SameLine();
            ImGui::RadioButton("No-Dupe Rare (60 CK)", &iCryptoSpendMode, 1);

            if (iCryptoSpendMode == 1) {
                ImGui::TextDisabled("No-Dupe mode enables the old 60-CK event automatically.");
            }
'@

    $mainText = [regex]::Replace($mainText, $spendUiPattern, $spendUi, 1)

    # ================================================================
    # 6) Correct No-Dupe spending.
    #
    # BO3 ships TWO event pieces:
    #   rare_crate_no_dupe_preview_ON:
    #       loot_rarecrate_dwid = 35
    #   rare_crate_no_dupe_standalone_ON:
    #       loot_noduperare_active = 1
    #       loot_noduperare_dwid = 35
    #       loot_noduperare_cpcost = 300
    #       loot_noduperare_cryptocost = 60
    #
    # Scropts' native Loot_BuyCrate helper only uses the common/rare/bribe
    # family (0/1/2). Therefore the reliable way to make its RARE path
    # request the No-Dupe DWID is to map loot_rarecrate_dwid to 35, then
    # call the existing RARE helper (1), not to pass 18 or 35 as CrateType.
    # ================================================================
    $spendRuntimePattern = '(?ms)if\s*\(bCryptoSpend\)\s*\{.*?\n\s*\}\s*(?=\n\s*if\s*\(bDiviniumSpend\))'

    if (-not [regex]::IsMatch($mainText, $spendRuntimePattern)) {
        throw "Could not locate bCryptoSpend runtime block."
    }

    $spendRuntime = @'
if (bCryptoSpend)
    {
        bCrypto = false;
        bSpoofBlackMarket = false;

        if (iCryptoSpendMode == 1)
        {
            // Match BO3's shipped No-Dupe event configuration.
            Dvar_SetFromString("loot_noduperare_active", "1", true);
            Dvar_SetFromString("loot_noduperare_dwid", "35", true);
            Dvar_SetFromString("loot_noduperare_cpcost", "300", true);
            Dvar_SetFromString("loot_noduperare_cryptocost", "60", true);

            // Critical piece from rare_crate_no_dupe_preview_ON:
            // route the normal Rare helper to No-Dupe DWID 35.
            Dvar_SetFromString("loot_rarecrate_dwid", "35", true);

            // Scropts helper family 1 = Rare. The dvar above selects DWID 35.
            Loot_BuyCrate(0, 1, 2);
        }
        else
        {
            // BO3's preview OFF event restores normal Rare to DWID 2.
            Dvar_SetFromString("loot_noduperare_active", "0", true);
            Dvar_SetFromString("loot_rarecrate_dwid", "2", true);

            Loot_BuyCrate(0, 1, 2);
        }
    }
'@

    $mainText = [regex]::Replace($mainText, $spendRuntimePattern, $spendRuntime, 1)

    # ================================================================
    # Validation
    # ================================================================
    if ($mainText -match 'Spend Drop Type ##CRYPTOSPENDTYPE') {
        throw "v17 validation failed: old broken combo remains."
    }

    if ($mainText -notmatch 'RadioButton\("No-Dupe Rare \(60 CK\)"') {
        throw "v17 validation failed: No-Dupe radio option missing."
    }

    if ($mainText -notmatch 'loot_rarecrate_dwid",\s*"35"') {
        throw "v17 validation failed: No-Dupe Rare DWID remap missing."
    }

    if ($mainText -match 'Loot_BuyCrate\(0,\s*18,\s*2\)' -or
        $mainText -match 'Loot_BuyCrate\(0,\s*35,\s*2\)') {
        throw "v17 validation failed: stale incorrect No-Dupe Loot_BuyCrate call remains."
    }

    if ($mainText -match 'Start Persistent Grand Slam Reward Retry' -or
        $mainText -match 'Start Legacy Crypto-Pulse Sync' -or
        $mainText -match 'Retry Special Contract Rewards') {
        throw "v17 validation failed: old Grand Slam reward retry UI remains."
    }

    if ($mainText -notmatch 'Set Grand Slam as Active Contract') {
        throw "v17 validation failed: simplified Grand Slam contract control missing."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "V17 CLEAN BLACK MARKET",
        "",
        "Grand Slam:",
        "  One working UI action remains: set contract 3010 active at 0/125.",
        "  Activation no longer incorrectly sets completion flag extraBools[11].",
        "  Removed non-working reward retry/sync buttons and counters.",
        "  Removed 4000-CP Grand Slam promo manipulation from the contract button.",
        "",
        "Cryptokeys:",
        "  Replaced broken one-entry combo with two explicit radio buttons.",
        "  Rare (30 CK) restores loot_rarecrate_dwid = 2.",
        "  No-Dupe Rare (60 CK) enables the shipped no-dupe event values.",
        "  Critical fix: No-Dupe sets loot_rarecrate_dwid = 35, then calls",
        "  Scropts' normal Rare helper Loot_BuyCrate(0, 1, 2).",
        "  This mirrors BO3's rare_crate_no_dupe_preview_ON event.",
        "",
        "The full legacy crash-prone hook bundle remains disabled.",
        "No checksum/integrity bypass is added or enabled."
    ) | Set-Content (Join-Path $ProjectDir "V17_CLEAN_BLACK_MARKET.txt") -Encoding UTF8

    Write-Host "v17 clean Black Market patch applied." -ForegroundColor Yellow
}


function Patch-V18LegacyLimitedCamos([string]$ProjectDir) {
    Write-Step "Adding legacy limited-camo inventory-version selector"

    $mainPath = Join-Path $ProjectDir "main.cpp"
    if (-not (Test-Path $mainPath)) {
        throw "Expected main.cpp missing: $mainPath"
    }

    $mainText = Get-Content $mainPath -Raw

    # Insert a compact Limited Camos section immediately before v17's
    # Auto Spend Cryptokeys control.
    $anchor = 'ImGui::Checkbox("Auto Spend Cryptokeys", &bCryptoSpend);'
    $anchorPos = $mainText.IndexOf($anchor)

    if ($anchorPos -lt 0) {
        throw "Could not locate v17 Auto Spend Cryptokeys control."
    }

    if ($mainText -notmatch 'Enable Selected Legacy Camo Pool') {
        $block = @'
            ImGui::SeparatorText("Legacy Limited Camos");

            static int legacyCamoSelection = 0;

            static const char* legacyCamoNames[] = {
                "Luck of the Irish (v101)",
                "Into the Void (v102)",
                "Cherry Fizz (v103)",
                "Empire (v104)",
                "Permafrost / Winter Blue (v105)",
                "Hive / Amber (v106)",
                "Watermelon (v108)",
                "ALL legacy camo versions"
            };

            static const char* legacyCamoVersions[] = {
                ",101",
                ",102",
                ",103",
                ",104",
                ",105",
                ",106",
                ",108",
                ",101,102,103,104,105,106,108"
            };

            static const int legacyCamoInventoryIds[] = {
                2096500187, // Luck of the Irish
                2078979736, // Into the Void / limited PAP
                2008576949, // Cherry Fizz
                2129903245, // Empire
                2009666624, // Permafrost / Winter Blue
                2143014041, // Hive / Amber
                2119988002, // Watermelon
                0
            };

            ImGui::SetNextItemWidth(310.0f);
            ImGui::Combo(
                "Target Camo ##LEGACYCAMO",
                &legacyCamoSelection,
                legacyCamoNames,
                IM_ARRAYSIZE(legacyCamoNames)
            );

            if (ImGui::Button("Enable Selected Legacy Camo Pool")) {
                // The shipped BO3 frontend appends this dvar directly to every
                // Black Market purchase request's InventoryVersion array.
                Dvar_SetFromString(
                    "loot_limitedtimeitemversions",
                    legacyCamoVersions[legacyCamoSelection],
                    true
                );

                // Keep the limited-event UI path awake. This is cosmetic/client
                // state; the important acquisition field is the inventory
                // version string above.
                Dvar_SetFromString("loot_limitedtimeitempromo_active", "1", true);

                // For Watermelon, the shipped data also lists the item in the
                // unreleased-loot table. Only enable this when testing v108/all.
                if (legacyCamoSelection == 6 || legacyCamoSelection == 7)
                    Dvar_SetFromString("loot_unlockunreleasedloot", "1", true);

                // Disable Scropts' inventory/entitlement spoof while testing so
                // a positive quantity means the account inventory really has it.
                bSpoofBlackMarket = false;
                bSpoofPurchases = false;

                ImGui::InsertNotification({
                    ImGuiToastType::Success,
                    7000,
                    "Legacy camo inventory version enabled. Open real Black Market drops to test backend issuance."
                });
            }

            ImGui::SameLine();

            if (ImGui::Button("Disable Legacy Camo Pool")) {
                Dvar_SetFromString("loot_limitedtimeitemversions", "", true);
                Dvar_SetFromString("loot_limitedtimeitempromo_active", "0", true);
                Dvar_SetFromString("loot_unlockunreleasedloot", "0", true);

                ImGui::InsertNotification({
                    ImGuiToastType::Info,
                    5000,
                    "Legacy limited-camo inventory versions disabled."
                });
            }

            if (legacyCamoSelection >= 0 && legacyCamoSelection < 7) {
                const __int64 selectedCamoQty =
                    LiveInventory_GetItemQuantity(
                        CONTROLLER_INDEX_0,
                        legacyCamoInventoryIds[legacyCamoSelection]
                    );

                ImGui::Text(
                    "Real account inventory for selected camo: %lld",
                    selectedCamoQty
                );

                if (selectedCamoQty > 0)
                    ImGui::Text("Status: OWNED in real inventory");
                else
                    ImGui::TextDisabled("Status: not present in real inventory yet");
            }
            else {
                ImGui::TextDisabled(
                    "ALL mode enables every legacy camo inventory version. Select one camo afterward to verify real ownership."
                );
            }

            ImGui::TextWrapped(
                "Test with Blackmarket Items and Entitlements spoof OFF. "
                "A real inventory quantity above 0 after a clean restart is the permanence check."
            );

            ImGui::TextDisabled(
                "Grand Slam's two special camo-bribe camos are a different reward path and are not part of versions 101-108."
            );

            ImGui::Separator();

'@
        $mainText = $mainText.Insert($anchorPos, $block)
    }

    # Validation
    if ($mainText -notmatch 'loot_limitedtimeitemversions') {
        throw "v18 validation failed: limited-time inventory version dvar missing."
    }

    if ($mainText -notmatch ',101,102,103,104,105,106,108') {
        throw "v18 validation failed: combined legacy camo version list missing."
    }

    if ($mainText -notmatch '2096500187' -or
        $mainText -notmatch '2008576949' -or
        $mainText -notmatch '2143014041') {
        throw "v18 validation failed: camo real-inventory IDs missing."
    }

    if ($mainText -notmatch 'bSpoofBlackMarket = false' -or
        $mainText -notmatch 'bSpoofPurchases = false') {
        throw "v18 validation failed: real-inventory test does not disable spoof flags."
    }

    Set-Content -Path $mainPath -Value $mainText -Encoding UTF8

    @(
        "V18 LEGACY LIMITED CAMOS",
        "",
        "BO3 frontend purchase construction:",
        "  InventoryVersion = loot_mpItemVersions + loot_limitedTimeItemVersions",
        "",
        "Historical limited camo versions enabled by this patch:",
        "  101 = Luck of the Irish",
        "  102 = Into the Void / limited PAP camo",
        "  103 = Cherry Fizz",
        "  104 = Empire",
        "  105 = Permafrost / Winter Blue",
        "  106 = Hive / Amber",
        "  108 = Watermelon",
        "",
        "The menu can enable one version at a time or all at once.",
        "It disables Blackmarket Items and Entitlements spoofing when enabled",
        "so the displayed inventory quantity is a real-account check.",
        "",
        "Grand Slam camo-bribe camos (camo_dlc3_pap_var_02 / _03) use a",
        "separate dedicated bundle path and are not supplied by these versions.",
        "",
        "This patch does not forge a server inventory grant. It makes normal",
        "Black Market purchase requests advertise the historical inventory",
        "versions exactly through the field BO3 itself uses."
    ) | Set-Content (Join-Path $ProjectDir "V18_LEGACY_LIMITED_CAMOS.txt") -Encoding UTF8

    Write-Host "v18 legacy limited-camo pool patch applied." -ForegroundColor Yellow
}

function Patch-V22CrashIsolation([string]$ProjectDir, [string]$TestProfile) {
    Write-Step "Applying v22 crash-isolation profile: $TestProfile"
    $mainPath = Join-Path $ProjectDir "main.cpp"
    $hooksPath = Join-Path $ProjectDir "hooks.cpp"
    if (-not (Test-Path $mainPath) -or -not (Test-Path $hooksPath)) {
        throw "v22: main.cpp or hooks.cpp missing."
    }

    $main = [System.IO.File]::ReadAllText($mainPath)
    $hooks = [System.IO.File]::ReadAllText($hooksPath)

    # CRITICAL: Keep the diagnostic UI limited to ImGui only. The normal draw()
    # function directly writes into a BO3 code/data address when opening/closing
    # the menu, and also triggers unrelated game and stats APIs.
    $anchor = 'void draw() {'
    if ([regex]::Matches($main, [regex]::Escape($anchor)).Count -ne 1) {
        throw 'v22: draw() insertion point missing or ambiguous.'
    }
    $diagnosticDraw = @'
void draw() {
    if (open) {
        ImGui::SetNextWindowSize(ImVec2(660.0f, 240.0f), ImGuiCond_Once);
        ImGui::Begin("Scropts QOL v22 - DIAGNOSTIC ONLY", &open);
        ImGui::TextUnformatted("CRASH ISOLATION - NO WEAPON KIT EDITING");
        ImGui::Separator();
        ImGui::TextUnformatted("Active profile: PROFILE_PLACEHOLDER");
        ImGui::TextWrapped("Only test whether BO3 remains stable when opening this menu, entering Zombies and playing briefly.");
        ImGui::TextWrapped("Original Scropts options are disabled in this diagnostic build.");
        ImGui::End();
    }
    return;
'@
    $diagnosticDraw = $diagnosticDraw.Replace('PROFILE_PLACEHOLDER', $TestProfile)
    $main = $main.Replace($anchor, $diagnosticDraw)

    # Every frame: prevent emblem scanning and game-state editing in profiles.
    foreach ($call in @('EmblemPreview::UpdateReleaseGuards(open);', 'EmblemPreview::Update();')) {
        if (-not $main.Contains($call)) { throw "v22: expected call missing: $call" }
        $main = $main.Replace($call, ('/* v22 diagnostic disabled: ' + $call + ' */'))
    }
    # No game memory writes from draw(), no hooks::onFrame(), and no UI actions.
    if ([regex]::IsMatch($main, '(?m)^\s*hooks::onFrame\(\);\s*$')) {
        throw 'v22: legacy per-frame hook was not disabled by earlier patch.'
    }

    # The overlay profile is the safest baseline: only DirectX overlay hook.
    # The core profile includes the legacy exception handler and pointer swaps.
    # Individual hook profiles add one targeted MinHook on top of core.
    if ($TestProfile -eq 'overlay') {
        foreach ($call in @('hooks::initExceptionHandler();', 'hooks::initPointerSwaps();')) {
            if (-not $main.Contains($call)) { throw "v22: DllMain anchor missing: $call" }
            $main = $main.Replace($call, ('/* v22 overlay disabled: ' + $call + ' */'))
        }
    }

    $installCall = 'hooks::applyBlackMarketAndEntitlementHooks();'
    if (($main.Split(@($installCall), [System.StringSplitOptions]::None).Count - 1) -ne 1) {
        throw 'v22: expected exactly one entitlement hook installation call.'
    }
    if ($TestProfile -eq 'overlay' -or $TestProfile -eq 'core') {
        $main = $main.Replace($installCall, ('/* v22 disabled: ' + $installCall + ' */'))
    }

    # Generate the selected test hook installation function from known v18
    # targets; do not install all three hooks merely to test a single one.
    $startMarker = '    void applyBlackMarketAndEntitlementHooks()'
    $endMarker = "`tvoid applyPatches() {"
    $start = $hooks.IndexOf($startMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw 'v22: entitlement hook function not found.' }
    $end = $hooks.IndexOf($endMarker, $start, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { throw 'v22: next hooks.cpp function anchor not found.' }

    $blocks = @()
    $blocks += '    void applyBlackMarketAndEntitlementHooks() {'
    $options = @(
        @{ ID='option'; RVA='0x2631C10'; Callback='functions::hkBG_UnlockablesItemOptionLocked'; Original='BG_UnlockablesItemOptionLocked' },
        @{ ID='quantity'; RVA='0x1DFCC60'; Callback='functions::hkLiveInventory_GetItemQuantity'; Original='LiveInventory_GetItemQuantity' },
        @{ ID='entitlement'; RVA='0x1E06110'; Callback='functions::hkLiveEntitlements_IsEntitlementActiveForController'; Original='LiveEntitlements_IsEntitlementActiveForController' }
    )
    foreach ($h in $options) {
        if ($TestProfile -eq $h.ID -or $TestProfile -eq 'all') {
            $blocks += '        {'
            $blocks += ('            LPVOID target = (LPVOID)OFFSET(' + $h.RVA + ');')
            $blocks += ('            MH_STATUS status = MH_CreateHook(target, ' + $h.Callback + ', (LPVOID*)&' + $h.Original + ');')
            $blocks += '            if (status == MH_OK || status == MH_ERROR_ALREADY_CREATED)'
            $blocks += '                MH_EnableHook(target);'
            $blocks += '        }'
        }
    }
    if ($TestProfile -eq 'overlay' -or $TestProfile -eq 'core') {
        $blocks += '        // v22: no Black Market or entitlement hooks installed in this profile.'
    }
    $blocks += '    }'
    $blocks += ''
    $newFunction = ($blocks -join "`r`n") + "`r`n"
    $hooks = $hooks.Substring(0, $start) + $newFunction + $hooks.Substring($end)

    [System.IO.File]::WriteAllText($mainPath, $main, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($hooksPath, $hooks, (New-Object System.Text.UTF8Encoding($false)))

    @(
        "v22 Crash Isolation - $TestProfile",
        'DIAGNOSTIC ONLY: normal controls, edits and weapon kits are deliberately disabled.',
        'DO NOT interpret passing this test as a verified fix.',
        'Profile overlay: DirectX overlay only.',
        'Profile core: original exception and pointer swaps, no 3 extra hooks.',
        'Profile option, quantity, entitlement: core + one test hook.',
        'Profile all: core + all 3 test hooks.'
    ) | Set-Content (Join-Path $ProjectDir 'V22_DIAGNOSTIC_PROFILE.txt') -Encoding UTF8
    Write-Host "v22 diagnostic profile $TestProfile applied." -ForegroundColor Yellow
}


function Patch-V35ZombiesKitApply([string]$ProjectDir) {
    Write-Step "Adding v35 offline-only native kit writer with schema/weaponID validation to v22 core diagnostic baseline"
    $mainPath = Join-Path $ProjectDir 'main.cpp'
    $main = [System.IO.File]::ReadAllText($mainPath)
    $uiPath = Join-Path $PSScriptRoot 'SourcePatches\ZombiesKitUI.v35.inc'
    if (-not (Test-Path $uiPath)) { throw "Missing v35 UI source: $uiPath" }
    $ui = [System.IO.File]::ReadAllText($uiPath)
    # Replace ONLY the tiny, early-return v22 diagnostic draw stub, never the
    # rest of the original Scropts code or other game assets.
    $pattern = '(?s)void draw\(\) \{\s*if \(open\) \{.*?\}\s*return;'
    if ([regex]::Matches($main, $pattern).Count -ne 1) {
        throw 'v35: expected exactly one v22 diagnostic draw stub.'
    }
    $replacement = $ui + "`r`nvoid draw() {`r`n    V24DrawWeaponKits();`r`n    return;"
    $main = [regex]::Replace($main,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $replacement},1)
    if ($main -notmatch 'V24DrawWeaponKits' -or $main -match 'CRASH ISOLATION - NO WEAPON KIT EDITING') {
        throw 'v35: weapon-kit UI patch validation failed.'
    }
    [System.IO.File]::WriteAllText($mainPath,$main,(New-Object System.Text.UTF8Encoding($false)))
    'v35: guarded experimental OFFLINE-only kit apply to verified storage 0x14.' |
        Set-Content (Join-Path $ProjectDir 'V33_STATUS.txt') -Encoding UTF8
}

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$cache = Join-Path $WorkDir "cache"
$src = Join-Path $WorkDir "src"
$output = Join-Path $WorkDir "output"
New-Item -ItemType Directory -Path $cache,$src,$output -Force | Out-Null

Write-Step "Downloading exact source revisions from GitHub"
$scZip = Join-Path $cache "scropts-$ScroptsCommit.zip"
$mhZip = Join-Path $cache "minhook-$MinHookCommit.zip"
$dtZip = Join-Path $cache "detours-$DetoursCommit.zip"
$t7Zip = Join-Path $cache "t7patch-$T7PatchCommit.zip"

Download-Zip $ScroptsUrl $scZip
Download-Zip $MinHookUrl $mhZip
Download-Zip $DetoursUrl $dtZip
Download-Zip $T7PatchUrl $t7Zip

Write-Step "Extracting source"
$scExtract = Join-Path $src "scropts"
$mhExtract = Join-Path $src "minhook"
$dtExtract = Join-Path $src "detours"
$t7Extract = Join-Path $src "t7patch"
Expand-Fresh $scZip $scExtract
Expand-Fresh $mhZip $mhExtract
Expand-Fresh $dtZip $dtExtract
Expand-Fresh $t7Zip $t7Extract

$scRoot = (Get-ChildItem $scExtract -Directory | Select-Object -First 1).FullName
$mhRoot = (Get-ChildItem $mhExtract -Directory | Select-Object -First 1).FullName
$dtRoot = (Get-ChildItem $dtExtract -Directory | Select-Object -First 1).FullName
$t7Root = (Get-ChildItem $t7Extract -Directory | Select-Object -First 1).FullName

$projectDir = Join-Path $scRoot "ImGui DirectX 11 Kiero Hook"
$projectFile = Join-Path $projectDir "ImGui DirectX 11 Kiero Hook.vcxproj"

Write-Step "Removing bundled precompiled dependency libraries"
$bundledMhX64 = Join-Path $projectDir "minhook\lib\libMinHook.x64.lib"
$bundledMhX86 = Join-Path $projectDir "minhook\lib\libMinHook.x86.lib"
$bundledDetours = Join-Path $projectDir "detours\detours.lib"
Remove-Item $bundledMhX64,$bundledMhX86,$bundledDetours -Force -ErrorAction SilentlyContinue

Write-Step "Patching the public Scropts Visual Studio project"
Patch-ScroptsProject $projectDir
Patch-SeptemberCompatibility $projectDir $t7Root
Patch-DiagnosticOverlayOnly $projectDir
Patch-BlackMarketAndEntitlements $projectDir
Patch-MPClassEditorFix $projectDir
Patch-GrandSlamMenuButton $projectDir
Patch-GrandSlamContractFix $projectDir
Patch-GrandSlamNoMatchRewardSync $projectDir
Patch-GrandSlamRewardRetryAndNoDupeSpender $projectDir
Patch-V16PersistentGrandSlamRetryAndNoDupeFix $projectDir
Patch-V17CleanBlackMarket $projectDir
Patch-V18LegacyLimitedCamos $projectDir
Patch-V22CrashIsolation $projectDir $TestProfile
Patch-V35ZombiesKitApply $projectDir

if ($PrepareOnly) {
    Write-Host ""
    Write-Host "Prepared source tree only. No binaries were built." -ForegroundColor Green
    Write-Host "Scropts source: $scRoot"
    Write-Host "MinHook source: $mhRoot"
    Write-Host "Detours source: $dtRoot"
    Write-Host "T7Patch compatibility source: $t7Root"
    exit 0
}

$vcvars = Require-VS

Write-Step "Building official MinHook v1.3.4 from source"
$mhSln = Join-Path $mhRoot "build\VC17\MinHookVC17.sln"
Invoke-VsCommand $vcvars ('msbuild "' + $mhSln + '" /nologo /m /p:Configuration=Release /p:Platform=x64')

$mhBuilt = Join-Path $mhRoot "build\VC17\lib\Release\libMinHook.x64.lib"
if (-not (Test-Path $mhBuilt)) {
    throw "MinHook build completed but expected library was not found: $mhBuilt"
}

Write-Step "Building Microsoft Detours v4.0.1 from source"
$dtSrc = Join-Path $dtRoot "src"
Invoke-VsCommand $vcvars ('cd /d "' + $dtSrc + '" && nmake /nologo')

$dtBuilt = Join-Path $dtRoot "lib.X64\detours.lib"
$dtHeader = Join-Path $dtRoot "include\detours.h"
if (-not (Test-Path $dtBuilt)) {
    throw "Detours build completed but expected library was not found: $dtBuilt"
}
if (-not (Test-Path $dtHeader)) {
    throw "Detours build completed but generated detours.h was not found: $dtHeader"
}

Write-Step "Replacing bundled libraries with locally source-built dependencies"
New-Item -ItemType Directory -Path (Split-Path $bundledMhX64) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $bundledDetours) -Force | Out-Null

Copy-Item (Join-Path $mhRoot "include\MinHook.h") (Join-Path $projectDir "minhook\include\MinHook.h") -Force
Copy-Item $mhBuilt $bundledMhX64 -Force
Copy-Item $dtHeader (Join-Path $projectDir "detours\detours.h") -Force
Copy-Item $dtBuilt $bundledDetours -Force

Write-Step "Building Scropts from the audited public source"
Invoke-VsCommand $vcvars ('msbuild "' + $projectFile + '" /nologo /m /p:Configuration=Release /p:Platform=x64')

$dlls = Get-ChildItem $projectDir -Recurse -File -Filter "*.dll" |
    Sort-Object LastWriteTimeUtc -Descending

if (-not $dlls) {
    throw "MSBuild completed but no DLL was found under the project directory."
}

$builtDll = $dlls[0].FullName
$finalDll = Join-Path $output "Scropts.QOL.v35-unified-native-kits-Oct2026.dll"
Copy-Item $builtDll $finalDll -Force

Write-Step "Generating verification report"
$hash = Get-FileHash -Algorithm SHA256 $finalDll
$hash.Hash | Set-Content (Join-Path $output "SHA256.txt") -Encoding ASCII

$report = @()
$report += "Scropts public source commit: $ScroptsCommit"
$report += "MinHook source commit:       $MinHookCommit (v1.3.4)"
$report += "Detours source commit:       $DetoursCommit (v4.0.1)"
$report += "T7Patch compatibility commit:$T7PatchCommit (Sep 2026 GameBuild translation)"
$report += "v24 prototype profile:       $TestProfile"
$report += "Built DLL:                   $finalDll"
$report += "SHA256:                      $($hash.Hash)"
$report += ""
$report += "No Windows Defender exclusions or security-setting changes were made."
$report | Set-Content (Join-Path $output "build-report.txt") -Encoding UTF8

# dumpbin comes from the Visual Studio toolchain. Capture import table for review.
$importsPath = Join-Path $output "imports.txt"
$dumpCmd = 'dumpbin /nologo /imports "' + $finalDll + '" > "' + $importsPath + '"'
Invoke-VsCommand $vcvars $dumpCmd

if (-not (Test-Path $finalDll)) {
    throw "Build did not produce the expected DLL."
}

Write-Host ""
Write-Host "SUCCESS" -ForegroundColor Green
Write-Host "Built DLL: $finalDll"
Write-Host "SHA256: $($hash.Hash)"
Write-Host "Import report: $importsPath"
Write-Host ""
Write-Host "This is a v35 experimental OFFLINE native kit writer. A verified unique slot and backup are required; legacy hooks disabled."
Write-Host "Do not disable Defender globally. Scan this self-built DLL normally before deciding whether to use it."
