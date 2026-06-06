param(
    [string]$InputPng
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$PlatformDir = Join-Path $ProjectRoot "Platform"
$ManifestPath = Join-Path $PlatformDir "Package.appxmanifest"
$AssetsDir = Join-Path $PlatformDir "Assets"
$ResPath = Join-Path $AssetsDir "AppIcon.res"

# Resolve default source PNG
if (-not $InputPng)
{
    $InputPng = Join-Path $PlatformDir "AppIcon.png"
}

if (-not (Test-Path $InputPng))
{
    Write-Host "  No source PNG at $InputPng - skipping icon generation." -ForegroundColor Yellow
    Write-Host "  Drop a square PNG at Platform\AppIcon.png (or pass -InputPng) and re-run." -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $ManifestPath))
{
    Write-Host "  Manifest not found at $ManifestPath" -ForegroundColor Red
    exit 1
}

function Get-WinAppPath
{
    $cmd = Get-Command "winapp" -ErrorAction SilentlyContinue
    if (-not $cmd)
    {
        Write-Host "  winapp CLI not found. Run scripts\prerequisites.ps1 first." -ForegroundColor Red
        exit 1
    }
    return $cmd.Source
}

# --- 1. Generate MSIX assets and rewrite the manifest ---
Write-Host "Generating MSIX icon assets from $InputPng..." -ForegroundColor Cyan
$env:WINAPP_CLI_TELEMETRY_OPTOUT = "1"
& winapp manifest update-assets $InputPng --manifest $ManifestPath
if ($LASTEXITCODE -ne 0)
{
    Write-Host "  winapp manifest update-assets failed (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# winapp writes assets to <manifest_dir>/Assets/
if (-not (Test-Path $AssetsDir))
{
    Write-Host "  Expected assets at $AssetsDir but the folder was not created." -ForegroundColor Red
    exit 1
}

# --- 2. Compile app.ico -> AppIcon.res via winapp tool rc ---
# winapp manifest update-assets emits "app.ico" (lowercase) as the multi-resolution
# ICO. We compile it to AppIcon.res (the name we reference from Package.swift's
# linkerSettings).
$IcoPath = Join-Path $AssetsDir "app.ico"
if (-not (Test-Path $IcoPath))
{
    Write-Host "  Expected app.ico at $IcoPath but it was not created." -ForegroundColor Red
    exit 1
}

$EscapedIcoPath = $IcoPath -replace '\\', '\\'
$RcContent = "MAINICON ICON `"$EscapedIcoPath`""
$RcPath = Join-Path $AssetsDir "_AppIcon.rc"
Set-Content -LiteralPath $RcPath -Value $RcContent -Encoding ASCII

Write-Host "Compiling AppIcon.res via winapp tool rc..." -ForegroundColor Cyan
Push-Location $AssetsDir
try
{
    & winapp tool rc /nologo /fo "AppIcon.res" "_AppIcon.rc"
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "  winapp tool rc failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}
finally
{
    Pop-Location
    Remove-Item -LiteralPath $RcPath -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $ResPath))
{
    Write-Host "  Expected AppIcon.res at $ResPath but it was not created." -ForegroundColor Red
    exit 1
}

Write-Host "Icon resource generated successfully." -ForegroundColor Green
exit 0
