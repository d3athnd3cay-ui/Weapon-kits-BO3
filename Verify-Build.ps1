param(
    [Parameter(Mandatory=$true)]
    [string]$DllPath
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $DllPath)) {
    throw "DLL not found: $DllPath"
}

Write-Host "SHA-256:"
(Get-FileHash -Algorithm SHA256 $DllPath).Hash
Write-Host ""

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Warning "Visual Studio tools not found; import-table check skipped."
    exit 0
}

$vsPath = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"

$tmp = Join-Path $env:TEMP ("scropts-imports-" + [Guid]::NewGuid().ToString("N") + ".txt")
$cmd = 'call "' + $vcvars + '" && dumpbin /nologo /imports "' + (Resolve-Path $DllPath) + '" > "' + $tmp + '"'
& cmd.exe /d /s /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin failed."
}

$imports = Get-Content $tmp
$imports | Out-Host

Write-Host ""
Write-Host "Checking for imports that were NOT observed in the audited Scropts binary/source..." -ForegroundColor Cyan
$suspicious = @(
    "WINHTTP.DLL",
    "WININET.DLL",
    "WS2_32.DLL",
    "URLMON.DLL",
    "CRYPT32.DLL"
)

$found = @()
foreach ($name in $suspicious) {
    if ($imports -match [regex]::Escape($name)) {
        $found += $name
    }
}

if ($found.Count -eq 0) {
    Write-Host "None of the watched networking/credential-related DLL imports were found." -ForegroundColor Green
} else {
    Write-Warning ("Unexpected watched imports found: " + ($found -join ", "))
}

Remove-Item $tmp -Force -ErrorAction SilentlyContinue
