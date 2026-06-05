param(
    [string]$InputPng,
    [string]$OutputDir,
    [string]$IconName = "AppIcon",
    [switch]$KeepIntermediates
)

# --- Helper: Convert PNG to multi-size ICO ---
function ConvertTo-MultiSizeIco
{
    param(
        [string]$SourcePng,
        [string]$TargetIco,
        [int[]]$Sizes = @(16, 32, 48, 256)
    )

    Add-Type -AssemblyName System.Drawing

    $src = [System.Drawing.Image]::FromFile($SourcePng)
    $bitmaps = @()
    try
    {
        foreach ($size in $Sizes)
        {
            $bmp = New-Object System.Drawing.Bitmap $size, $size
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try
            {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.Clear([System.Drawing.Color]::Transparent)
                $g.DrawImage($src, 0, 0, $size, $size)
            }
            finally
            {
                $g.Dispose()
            }
            $bitmaps += $bmp
        }

        # Encode each bitmap as PNG bytes (Vista+ supports PNG-in-ICO)
        $pngBytes = @()
        foreach ($bmp in $bitmaps)
        {
            $ms = New-Object System.IO.MemoryStream
            try
            {
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $pngBytes += , $ms.ToArray()
            }
            finally
            {
                $ms.Dispose()
            }
        }

        # Build the ICO file
        $icoMs = New-Object System.IO.MemoryStream
        $bw = New-Object System.IO.BinaryWriter $icoMs
        try
        {
            # ICONDIR header
            $bw.Write([uint16]0)                # reserved
            $bw.Write([uint16]1)                # type: 1 = icon
            $bw.Write([uint16]$bitmaps.Count)   # image count

            $dirSize = 6 + (16 * $bitmaps.Count)
            $currentOffset = $dirSize

            # ICONDIRENTRY for each image
            for ($i = 0; $i -lt $bitmaps.Count; $i++)
            {
                $bmp = $bitmaps[$i]
                $bytes = $pngBytes[$i]
                $w = if ($bmp.Width  -ge 256) { 0 } else { [byte]$bmp.Width }
                $h = if ($bmp.Height -ge 256) { 0 } else { [byte]$bmp.Height }
                $bw.Write([byte]$w)
                $bw.Write([byte]$h)
                $bw.Write([byte]0)              # palette colors
                $bw.Write([byte]0)              # reserved
                $bw.Write([uint16]1)            # color planes
                $bw.Write([uint16]32)           # bits per pixel
                $bw.Write([uint32]$bytes.Length)
                $bw.Write([uint32]$currentOffset)
                $currentOffset += $bytes.Length
            }

            # PNG payloads
            foreach ($bytes in $pngBytes)
            {
                $bw.Write($bytes)
            }
        }
        finally
        {
            $bw.Dispose()
        }

        [System.IO.File]::WriteAllBytes($TargetIco, $icoMs.ToArray())
        $icoMs.Dispose()
    }
    finally
    {
        foreach ($bmp in $bitmaps)
        {
            $bmp.Dispose()
        }
        $src.Dispose()
    }
}

# --- Main ---
$ProjectRoot = Split-Path $PSScriptRoot -Parent

# Resolve defaults
if (-not $InputPng)
{
    $InputPng = Join-Path $ProjectRoot "Assets\Icons\AppIcon.png"
}
if (-not $OutputDir)
{
    $OutputDir = Join-Path $ProjectRoot "Assets\Icons"
}

# Locate source PNG
$resolvedPng = Resolve-Path -LiteralPath $InputPng -ErrorAction SilentlyContinue
if (-not $resolvedPng)
{
    Write-Host "  No source PNG at $InputPng - skipping icon resource generation." -ForegroundColor Yellow
    exit 0
}

# Ensure output directory exists
if (-not (Test-Path $OutputDir))
{
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Tool check: rc.exe
$rcExe = Get-Command "rc.exe" -ErrorAction SilentlyContinue
if (-not $rcExe)
{
    Write-Host "  rc.exe not found. Install Windows SDK 10.0.19041 or later." -ForegroundColor Red
    exit 1
}

# Paths
$icoPath = Join-Path $OutputDir "$IconName.ico"
$rcPath  = Join-Path $OutputDir "$IconName.rc"
$resPath = Join-Path $OutputDir "$IconName.res"

# Convert PNG -> multi-size ICO
ConvertTo-MultiSizeIco -SourcePng $resolvedPng.Path -TargetIco $icoPath -Sizes @(16, 32, 48, 256)

# Write .rc file
$escapedIcoPath = $icoPath -replace '\\', '\\'
$rcContent = "MAINICON ICON `"$escapedIcoPath`""
Set-Content -Path $rcPath -Value $rcContent -Encoding ASCII

# Compile .rc -> .res with rc.exe
Push-Location $OutputDir
try
{
    & rc.exe -nologo $rcPath | Out-Null
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "  rc.exe failed (exit $LASTEXITCODE)" -ForegroundColor Red
        Pop-Location
        exit $LASTEXITCODE
    }
}
finally
{
    Pop-Location
}

# Clean up .rc intermediate (always keep .ico for runtime use)
Remove-Item -LiteralPath $rcPath -Force -ErrorAction SilentlyContinue

Write-Host "Icon resource generated successfully." -ForegroundColor Green
exit 0
