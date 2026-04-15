# Set-TimedWallpaper.ps1
# Reads the GNOME timed wallpaper XML and sets the correct wallpaper based on current time.
# For transitions, blends the two images at the appropriate opacity.
#
# Usage:
#   .\Set-TimedWallpaper.ps1 -XmlPath ".\Lakeside-2-timed.xml" -WallpaperDir "C:\Wallpapers\Lakeside-2"
#
# Run periodically (e.g. every 30s via Task Scheduler) to animate transitions.

param(
    [string]$XmlPath = "$PSScriptRoot\wallpaper-packs\Lakeside-2\Lakeside-2-timed.xml",
    [string]$WallpaperDir = "$PSScriptRoot\wallpaper-packs\Lakeside-2",
    [string]$TempDir = "$env:TEMP\TimedWallpaper"
)

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WallpaperAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    public static void Set(string path) {
        SystemParametersInfo(0x0014, 0, path, 0x01 | 0x02);
    }
}
"@

# --- Parse the XML timeline ---
[xml]$xml = Get-Content -Path $XmlPath -Raw
$bg = $xml.background

# Build ordered list of phases from child nodes
$timeline = @()
foreach ($node in $bg.ChildNodes) {
    switch ($node.LocalName) {
        "static" {
            $fileName = [System.IO.Path]::GetFileName($node.file)
            $timeline += @{
                Type     = "static"
                Duration = [double]$node.duration
                File     = $fileName
            }
        }
        "transition" {
            $fromFile = [System.IO.Path]::GetFileName($node.from)
            $toFile   = [System.IO.Path]::GetFileName($node.to)
            $timeline += @{
                Type     = "transition"
                Duration = [double]$node.duration
                From     = $fromFile
                To       = $toFile
            }
        }
    }
}

$totalCycle = ($timeline | ForEach-Object { $_.Duration } | Measure-Object -Sum).Sum
Write-Host "Total cycle: $totalCycle seconds ($([math]::Round($totalCycle / 3600, 2)) hours)"
Write-Host "Phases: $($timeline.Count)"

# --- Determine seconds elapsed since midnight ---
$now = Get-Date
$secondsSinceMidnight = $now.Hour * 3600 + $now.Minute * 60 + $now.Second + ($now.Millisecond / 1000.0)
$elapsed = $secondsSinceMidnight % $totalCycle

# --- Walk the timeline to find the current phase ---
$cumulative = 0.0
$currentPhase = $null
$phaseElapsed = 0.0

foreach ($phase in $timeline) {
    if ($elapsed -lt ($cumulative + $phase.Duration)) {
        $currentPhase = $phase
        $phaseElapsed = $elapsed - $cumulative
        break
    }
    $cumulative += $phase.Duration
}

if (-not $currentPhase) {
    # Shouldn't happen, but fall back to last phase
    $currentPhase = $timeline[-1]
    $phaseElapsed = 0
}

# --- Ensure temp directory exists ---
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# --- Apply wallpaper ---
if ($currentPhase.Type -eq "static") {
    $wallpaperPath = Join-Path $WallpaperDir $currentPhase.File
    $remaining = [math]::Round($currentPhase.Duration - $phaseElapsed)
    Write-Host "Static: $($currentPhase.File)"
    Write-Host "Remaining: ${remaining}s"
    [WallpaperAPI]::Set((Resolve-Path $wallpaperPath).Path)
}
else {
    # Transition: blend from -> to at the current progress
    $progress = $phaseElapsed / $currentPhase.Duration
    $pct = [math]::Round($progress * 100, 1)
    $remaining = [math]::Round($currentPhase.Duration - $phaseElapsed)

    Write-Host "Transition: $($currentPhase.From) -> $($currentPhase.To)"
    Write-Host "Progress: ${pct}% (new image opacity), ${remaining}s remaining"

    $fromPath = Join-Path $WallpaperDir $currentPhase.From
    $toPath   = Join-Path $WallpaperDir $currentPhase.To
    $outPath  = Join-Path $TempDir "blended_wallpaper.bmp"

    $fromImg = $null; $toImg = $null; $blended = $null; $gfx = $null; $imgAttr = $null
    try {
        $fromImg = [System.Drawing.Image]::FromFile((Resolve-Path $fromPath).Path)
        $toImg   = [System.Drawing.Image]::FromFile((Resolve-Path $toPath).Path)

        $w = $fromImg.Width
        $h = $fromImg.Height

        $blended = New-Object System.Drawing.Bitmap($w, $h)
        $gfx = [System.Drawing.Graphics]::FromImage($blended)
        $gfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $gfx.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gfx.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        # Draw base (from) image at full opacity
        $gfx.DrawImage($fromImg, 0, 0, $w, $h)

        # Draw overlay (to) image at transition opacity
        $cm = New-Object System.Drawing.Imaging.ColorMatrix
        $cm.Matrix33 = [float]$progress
        $imgAttr = New-Object System.Drawing.Imaging.ImageAttributes
        $imgAttr.SetColorMatrix($cm, [System.Drawing.Imaging.ColorMatrixFlag]::Default, [System.Drawing.Imaging.ColorAdjustType]::Bitmap)

        $destRect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $gfx.DrawImage($toImg, $destRect, 0, 0, $toImg.Width, $toImg.Height, [System.Drawing.GraphicsUnit]::Pixel, $imgAttr)

        # Save as BMP for wallpaper API compatibility
        $blended.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    }
    finally {
        if ($imgAttr) { $imgAttr.Dispose() }
        if ($gfx)     { $gfx.Dispose() }
        if ($blended)  { $blended.Dispose() }
        if ($toImg)   { $toImg.Dispose() }
        if ($fromImg) { $fromImg.Dispose() }
    }

    [WallpaperAPI]::Set($outPath)
}

Write-Host "Wallpaper set at $(Get-Date -Format 'HH:mm:ss')"
