param(
    [switch]$TestsOnly,
    [switch]$SkipTests,
    [ValidateRange(1, 32)]
    [int]$Jobs = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') {
    throw 'The DLL requires Windows x64, Visual Studio 2022 C++ Build Tools, and the Windows SDK. See docs/WINDOWS_BUILD.md for portable tests on Linux.'
}
if ($TestsOnly -and $SkipTests) {
    throw '-TestsOnly and -SkipTests cannot be combined.'
}

$repoRoot = $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build'
$projectDir = Join-Path $repoRoot 'src/ScroptsQOL'
$projectFile = Join-Path $projectDir 'ImGui DirectX 11 Kiero Hook.vcxproj'
$minhookRoot = Join-Path $repoRoot 'third_party/minhook'
$detoursRoot = Join-Path $repoRoot 'third_party/detours'
$binDir = Join-Path $buildRoot 'bin'
$objDir = Join-Path $buildRoot 'obj'
$testDir = Join-Path $buildRoot 'tests'
New-Item -ItemType Directory -Force -Path $buildRoot, $binDir, $objDir, $testDir | Out-Null

function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path. Use a complete checkout of the imported v35/v36 source."
    }
}

function Find-VcVars {
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
        throw 'A Windows x64 host with Visual Studio Build Tools is required.'
    }
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio/Installer/vswhere.exe'
    Require-File $vswhere
    $vsPath = & $vswhere -latest -version '[17.0,18.0)' -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($vsPath)) {
        throw 'Install Desktop development with C++, the MSVC v143 x64/x86 tools, and a Windows 10/11 SDK.'
    }
    $vcvars = Join-Path $vsPath 'VC/Auxiliary/Build/vcvars64.bat'
    Require-File $vcvars
    return $vcvars
}

function Invoke-VsCommand([string]$Command) {
    Write-Host "CMD> $Command"
    & cmd.exe /d /s /c ('call "' + $script:vcvars + '" && ' + $Command)
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command"
    }
}

function Assert-X64Dll([string]$Path) {
    Require-File $Path
    $stream = [System.IO.File]::OpenRead($Path)
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw 'Build output is not a PE image (missing MZ header).'
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or ($peOffset + 26) -gt $stream.Length) {
            throw 'Build output has an invalid PE header offset.'
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw 'Build output is not a Windows x64 PE image.'
        }
        $stream.Position = $peOffset + 22
        if (($reader.ReadUInt16() -band 0x2000) -eq 0 -or $reader.ReadUInt16() -ne 0x20B) {
            throw 'Build output is not a PE32+ DLL.'
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$script:vcvars = Find-VcVars
Push-Location $repoRoot
try {
    if (-not $SkipTests) {
        $testSources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*_tests.cpp' -File | Sort-Object Name)
        if ($testSources.Count -eq 0) {
            throw 'No native test sources were found; refusing to report an empty test run as passing.'
        }
        $testResults = @()
        foreach ($testSource in $testSources) {
            $exe = Join-Path $testDir ($testSource.BaseName + '.exe')
            $obj = Join-Path $testDir ($testSource.BaseName + '.obj')
            Invoke-VsCommand ('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /I "' + $repoRoot + '" "' + $testSource.FullName + '" /Fe:"' + $exe + '" /Fo:"' + $obj + '" /link /INCREMENTAL:NO')
            & $exe
            if ($LASTEXITCODE -ne 0) {
                throw "Native test failed: $($testSource.Name) (exit $LASTEXITCODE)."
            }
            $testResults += "PASS $($testSource.Name)"
        }
        $testResults | Set-Content -LiteralPath (Join-Path $testDir 'results.txt') -Encoding UTF8
        Write-Host "Passed $($testSources.Count) native test executable(s)."
    }
    if ($TestsOnly) {
        return
    }

    Require-File $projectFile
    $minhookProject = Join-Path $minhookRoot 'build/VC17/libMinHook.vcxproj'
    $detoursMakefile = Join-Path $detoursRoot 'src/Makefile'
    Require-File $minhookProject
    Require-File $detoursMakefile

    # Build the pinned, tracked dependency sources. No download or source regeneration.
    $minhookOut = Join-Path $buildRoot 'deps/minhook'
    $minhookObj = Join-Path $buildRoot 'obj/minhook'
    New-Item -ItemType Directory -Force -Path $minhookOut, $minhookObj | Out-Null
    $minhookOutProperty = $minhookOut.Replace('\', '/') + '/'
    $minhookIntProperty = $minhookObj.Replace('\', '/') + '/'
    Invoke-VsCommand ('msbuild "' + $minhookProject + '" /nologo /m:' + $Jobs + ' /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143 /p:TargetName=libMinHook.x64 /p:OutDir="' + $minhookOutProperty + '" /p:IntDir="' + $minhookIntProperty + '"')
    Invoke-VsCommand ('cd /d "' + (Join-Path $detoursRoot 'src') + '" && nmake /nologo')
    $minhookLib = Join-Path $minhookOut 'libMinHook.x64.lib'
    $detoursLib = Join-Path $detoursRoot 'lib.X64/detours.lib'
    Require-File $minhookLib
    Require-File $detoursLib
    $projectMinhookLib = Join-Path $projectDir 'minhook/lib/libMinHook.x64.lib'
    $projectDetoursLib = Join-Path $projectDir 'detours/detours.lib'
    New-Item -ItemType Directory -Force -Path (Split-Path $projectMinhookLib), (Split-Path $projectDetoursLib) | Out-Null
    Copy-Item -LiteralPath $minhookLib -Destination $projectMinhookLib -Force
    Copy-Item -LiteralPath $detoursLib -Destination $projectDetoursLib -Force

    # Imported item metadata can override /p:LanguageStandard. Import our C++17
    # metadata after the project's item definitions without rewriting the project.
    $propsFile = Join-Path $buildRoot 'Cpp17.props'
    @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemDefinitionGroup>
    <ClCompile><LanguageStandard>stdcpp17</LanguageStandard></ClCompile>
  </ItemDefinitionGroup>
</Project>
'@ | Set-Content -LiteralPath $propsFile -Encoding UTF8
    $dllName = 'WeaponKitsBO3.v36'
    $dll = Join-Path $binDir ($dllName + '.dll')
    # Forward-slash trailing separators avoid Windows argument quoting of \".
    $outProperty = $binDir.Replace('\', '/') + '/'
    $intProperty = $objDir.Replace('\', '/') + '/'
    Invoke-VsCommand ('msbuild "' + $projectFile + '" /nologo /m:' + $Jobs + ' /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143 /p:TargetName=' + $dllName + ' /p:TargetExt=.dll /p:OutDir="' + $outProperty + '" /p:IntDir="' + $intProperty + '" /p:ForceImportBeforeCppTargets="' + $propsFile + '"')
    Assert-X64Dll $dll
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dll).Hash
    $hash | Set-Content -LiteralPath ($dll + '.sha256') -Encoding ASCII
    Invoke-VsCommand ('dumpbin /nologo /headers "' + $dll + '" > "' + (Join-Path $binDir 'headers.txt') + '"')
    Invoke-VsCommand ('dumpbin /nologo /imports "' + $dll + '" > "' + (Join-Path $binDir 'imports.txt') + '"')
    @(
        'Source: tracked local v36 C++ tree derived from the supplied v35 package.',
        'Target: Windows x64 DLL, Release, MSVC v143, C++17, Windows SDK D3D11/DXGI.',
        "DLL: $dll",
        "SHA256: $hash",
        "Native tests skipped: $SkipTests",
        'A successful build and portable tests do not establish in-game compatibility or persistence.'
    ) | Set-Content -LiteralPath (Join-Path $binDir 'build-report.txt') -Encoding UTF8
    Write-Host "Built and verified x64 PE DLL: $dll"
    Write-Host "SHA256: $hash"
}
finally {
    Pop-Location
}
