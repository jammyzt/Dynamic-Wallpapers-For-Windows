# Install-TimedWallpaper.ps1
# Prompts for a wallpaper pack and creates a scheduled task that runs
# Set-TimedWallpaper.ps1 every 10 seconds with the chosen pack.

$scriptRoot = $PSScriptRoot

# Discover wallpaper packs (subdirectories containing a *-timed.xml)
$packsDir = Join-Path $scriptRoot "wallpaper-packs"
$packs = Get-ChildItem -Path $packsDir -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name)-timed.xml") } |
    Sort-Object Name

if ($packs.Count -eq 0) {
    Write-Host "No wallpaper packs found." -ForegroundColor Red
    exit 1
}

# Display menu with friendly names
Write-Host "`nAvailable wallpaper packs:`n" -ForegroundColor Cyan
for ($i = 0; $i -lt $packs.Count; $i++) {
    $friendly = $packs[$i].Name -replace '[_-]', ' '
    Write-Host "  [$($i + 1)] $friendly"
}

Write-Host ""
$selection = Read-Host "Select a wallpaper pack (1-$($packs.Count))"

if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $packs.Count) {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit 1
}

$chosen = $packs[[int]$selection - 1]
$xmlPath = Join-Path $chosen.FullName "$($chosen.Name)-timed.xml"
$wallpaperDir = $chosen.FullName
$setScript = Join-Path $scriptRoot "Set-TimedWallpaper.ps1"

$friendlyName = $chosen.Name -replace '[_-]', ' '
Write-Host "`nSelected: $friendlyName" -ForegroundColor Green
Write-Host "XML:      $xmlPath"
Write-Host "Dir:      $wallpaperDir`n"

# Create a VBScript launcher to run PowerShell with no visible window
$vbsPath = Join-Path $scriptRoot "RunTimedWallpaper.vbs"
$vbsContent = @"
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$setScript"" -XmlPath ""$xmlPath"" -WallpaperDir ""$wallpaperDir""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII
Write-Host "Created launcher: $vbsPath"

# Build the scheduled task
$taskName = "TimedWallpaper"

# Remove existing task if present
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing '$taskName' scheduled task..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
    -Execute "wscript.exe" `
    -Argument "`"$vbsPath`""

# Repetition: every 10 seconds, indefinitely
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Seconds 60)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Runs Set-TimedWallpaper.ps1 every 60 seconds with the $friendlyName pack." |
    Out-Null

Write-Host "Scheduled task '$taskName' created successfully." -ForegroundColor Green
Write-Host "The wallpaper will update every 60 seconds." -ForegroundColor Green

# Run the task immediately to verify it works and apply the wallpaper
Write-Host "`nRunning task now to apply wallpaper..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $taskName
Write-Host "Wallpaper applied!" -ForegroundColor Green
