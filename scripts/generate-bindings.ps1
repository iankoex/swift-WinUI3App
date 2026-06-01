$ProjectRoot = Split-Path $PSScriptRoot -Parent

$swiftwinrt = Get-Command "swiftwinrt.exe" -ErrorAction SilentlyContinue

if (-not $swiftwinrt)
{
    Write-Host "swiftwinrt.exe not found in PATH." -ForegroundColor Yellow

    $DotSwiftWinRT = Join-Path $ProjectRoot ".swift-winrt"
    Write-Host "Checking $DotSwiftWinRT..." -ForegroundColor DarkGray
    if (Test-Path $DotSwiftWinRT)
    {
        $found = Get-ChildItem -Path $DotSwiftWinRT -Filter "swiftwinrt.exe" -Recurse -File | Select-Object -First 1
        if ($found)
        {
            $SwiftWinRTBin = $found.Directory.FullName
            $env:Path += ";$SwiftWinRTBin"
            Write-Host "Found swiftwinrt.exe in $SwiftWinRTBin" -ForegroundColor Green
            $swiftwinrt = Get-Command "swiftwinrt.exe" -ErrorAction SilentlyContinue
        } else
        {
            Write-Host "swiftwinrt.exe not found in .swift-winrt." -ForegroundColor Yellow
        }
    } else
    {
        Write-Host ".swift-winrt folder not found." -ForegroundColor Yellow
    }
}

if (-not $swiftwinrt)
{
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  1. Provide the path to swiftwinrt.exe and add it to PATH"
    Write-Host "  2. Install SwiftWinRT"
    Write-Host "  3. Exit"
    $choice = Read-Host "Enter 1, 2, or 3"

    if ($choice -eq "1")
    {
        $SwiftWinRTBin = Read-Host "Enter the full path to the swift-winrt bin directory"
        if (-not (Test-Path "$SwiftWinRTBin\swiftwinrt.exe"))
        {
            Write-Host "swiftwinrt.exe not found at that path." -ForegroundColor Red
            exit 1
        }
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$SwiftWinRTBin*")
        {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$SwiftWinRTBin", "User")
        }
        if ($env:Path -notlike "*$SwiftWinRTBin*")
        {
            $env:Path += ";$SwiftWinRTBin"
        }
        Write-Host "Added $SwiftWinRTBin to PATH." -ForegroundColor Green
        $swiftwinrt = Get-Command "swiftwinrt.exe" -ErrorAction SilentlyContinue
    } elseif ($choice -eq "2")
    {
        Write-Host "Running install-swiftwinrt.ps1..." -ForegroundColor Cyan
        & "$PSScriptRoot\install-swiftwinrt.ps1"
        if ($LASTEXITCODE -ne 0)
        { exit $LASTEXITCODE
        }
        $SwiftWinRTBin = Join-Path $ProjectRoot ".swift-winrt\bin"
        if (Test-Path "$SwiftWinRTBin\swiftwinrt.exe")
        {
            $env:Path += ";$SwiftWinRTBin"
            $swiftwinrt = Get-Command "swiftwinrt.exe" -ErrorAction SilentlyContinue
        }
    } else
    {
        Write-Host "Exiting. Install swiftwinrt.exe or add it to PATH manually." -ForegroundColor Red
        exit 1
    }
}

if (-not $swiftwinrt)
{
    Write-Host "swiftwinrt.exe still not found. Exiting." -ForegroundColor Red
    exit 1
}

$RspPath = Join-Path $ProjectRoot "generated\swiftwinrt.rsp"
if (-not (Test-Path $RspPath))
{
    Write-Host "Response file not found: $RspPath" -ForegroundColor Red
    exit 1
}

Write-Host "Running swiftwinrt.exe..." -ForegroundColor Cyan
& $swiftwinrt.Source "@$RspPath"

if ($LASTEXITCODE -ne 0)
{
    Write-Host "swiftwinrt.exe failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "Bindings generated successfully." -ForegroundColor Green
Write-Host ""
