# Scropts QOL BO3 crash collector - read-only, PowerShell 5.1+
# No sending, injecting, editing, deleting, registry changes or privilege elevation.
param([switch]$LogsOnly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { $desktop = $PSScriptRoot }
$destRoot = Join-Path $desktop 'BO3_Crash_Reports'
New-Item -Path $destRoot -ItemType Directory -Force | Out-Null
$staging = Join-Path $env:TEMP ("BO3_CrashReport_" + $stamp + "_" + $PID)
New-Item $staging -ItemType Directory -Force | Out-Null
$notes = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]
$copied = New-Object System.Collections.Generic.List[string]
$notes.Add('BO3 crash evidence collector (local only)')
$notes.Add("Collection time: $(Get-Date -Format o)")
$notes.Add("Windows: $([Environment]::OSVersion.VersionString)")
$notes.Add("Logs only: $LogsOnly")
$notes.Add('This collector does not upload anything or alter BO3.')
function PutFile([string]$src,[string]$subfolder,[string]$name) {
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {return}
    try {
        $dstFolder = Join-Path $staging $subfolder
        New-Item -ItemType Directory -Path $dstFolder -Force | Out-Null
        $dst = Join-Path $dstFolder $name
        Copy-Item -LiteralPath $src -Destination $dst -ErrorAction Stop
        $copied.Add("$subfolder/$name")
    } catch { $errors.Add("Could not copy $src : $($_.Exception.Message)") }
}
try {
    $candidates = @()
    $crashDirs = @((Join-Path $env:LOCALAPPDATA 'CrashDumps'))
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\SteamLibrary', 'D:\SteamLibrary', 'E:\SteamLibrary')) {
        if ($base) { $crashDirs += (Join-Path $base 'Steam\steamapps\common\Call of Duty Black Ops III') }
    }
    foreach ($d in ($crashDirs | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $d -PathType Container) {
            try {
                $candidates += @(Get-ChildItem -LiteralPath $d -File -ErrorAction Stop | Where-Object {
                    $_.Name -match '(?i)^(blackops3|bo3).*\.(dmp|mdmp)$'
                })
            } catch { $errors.Add("Dump scan: $d : $($_.Exception.Message)") }
        }
    }
    if (-not $LogsOnly) {
        $recent = @($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 2)
        foreach ($f in $recent) {
            PutFile $f.FullName 'Dumps' $f.Name
            $notes.Add("Dump: $($f.Name), $([math]::Round($f.Length / 1MB, 1)) MB, $($f.LastWriteTime.ToString('o'))")
        }
    }
    # Windows Event Log: only errors whose provider/message mentions BO3.
    try {
        $cutoff = (Get-Date).AddDays(-3)
        $events = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$cutoff; Level=2} -ErrorAction Stop |
          Where-Object { ($_.Message -match '(?i)blackops3|bo3\.exe') -or ($_.ProviderName -match 'Application Error' -and $_.Message -match '(?i)blackops3') } |
          Sort-Object TimeCreated -Descending | Select-Object -First 30)
        $eventReport = @()
        foreach ($e in $events) {
            $eventReport += "[$($e.TimeCreated.ToString('o'))] Event $($e.Id); Provider: $($e.ProviderName); Record: $($e.RecordId)"
            $eventReport += $e.Message
            $eventReport += ('-' * 70)
        }
        if (-not $eventReport) { $eventReport = @('No BO3-related Application Error events found in past 72 hours.') }
        $eventReport | Set-Content -Path (Join-Path $staging 'Windows_Application_Errors.txt') -Encoding UTF8
        $copied.Add('Windows_Application_Errors.txt')
    } catch { $errors.Add("Event log: $($_.Exception.Message)") }
    # WER diagnostic text only; avoid copying unrelated reports.
    foreach ($which in @('ReportArchive','ReportQueue')) {
        $root = Join-Path $env:ProgramData ("Microsoft\Windows\WER\" + $which)
        if (-not (Test-Path -LiteralPath $root)) {continue}
        try {
            $matchingFolders = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop |
                Where-Object { $_.Name -match '(?i)blackops3|bo3\.exe' } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 3)
            foreach ($folder in $matchingFolders) {
                foreach ($r in @(Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.wer' -ErrorAction SilentlyContinue | Select-Object -First 2)) {
                    PutFile $r.FullName 'WER' ($folder.Name + '__' + $r.Name)
                }
            }
        } catch { $errors.Add("WER scan: $($_.Exception.Message)") }
    }
    # Only likely relevant, reasonably sized console/log files.
    $gameDirs = @(('' + ${env:ProgramFiles(x86)} + '\Steam\steamapps\common\Call of Duty Black Ops III'),
                  'C:\SteamLibrary\steamapps\common\Call of Duty Black Ops III',
                  'D:\SteamLibrary\steamapps\common\Call of Duty Black Ops III',
                  'E:\SteamLibrary\steamapps\common\Call of Duty Black Ops III')
    try {
        $steamKey = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        if ($steamKey.SteamPath) { $gameDirs += (Join-Path $steamKey.SteamPath 'steamapps\common\Call of Duty Black Ops III') }
    } catch {}
    foreach ($d in ($gameDirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) {continue}
        foreach ($sub in @('', 'players')) {
            $scan = Join-Path $d $sub
            if (-not (Test-Path -LiteralPath $scan)) {continue}
            try {
                $recentLogs = @(Get-ChildItem -LiteralPath $scan -File -ErrorAction Stop |
                    Where-Object { $_.Extension -in @('.log','.txt') -and $_.Length -le 4MB -and $_.LastWriteTime -gt (Get-Date).AddDays(-3) } |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 6)
                foreach ($f in $recentLogs) {PutFile $f.FullName 'Game_Logs' ($sub.Replace('\','_')+'_'+$f.Name)}
            } catch { $errors.Add("Log scan: $scan : $($_.Exception.Message)") }
        }
        break
    }
} finally {
    if ($copied.Count -eq 0) { $notes.Add('No matching dump or BO3 events found; please verify crash occurred recently.') }
    $notes.Add('Collected files: ' + ($copied -join ', '))
    $notes.Add('Collection warnings: ' + ($errors -join '; '))
    $notes.Add('Dumps may contain private process data. Review before sharing.')
    $notes.Add('Tested version (fill in): ______')
    $notes.Add('Action that caused crash (fill in): ______')
    $notes | Set-Content -Path (Join-Path $staging 'README_REPORT.txt') -Encoding UTF8
    $zip = Join-Path $destRoot ("BO3_Crash_"+$stamp+'.zip')
    try {
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
        Write-Host ''
        Write-Host 'SUCCESS - CRASH PACKAGE CREATED:' -ForegroundColor Green
        Write-Host $zip -ForegroundColor Cyan
        Write-Host 'Attach this ZIP directly to the ChatGPT conversation.'
        Write-Host 'Remember: a crash dump can contain sensitive process information.'
        Start-Process explorer.exe -ArgumentList @('/select,', '"'+$zip+'"') -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Could not create ZIP: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Uncompressed evidence remains in: $staging"
        exit 1
    }
    if (Test-Path -LiteralPath $zip) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
}
