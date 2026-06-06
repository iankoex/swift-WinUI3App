$ProjectRoot = Split-Path $PSScriptRoot -Parent

function Test-Command
{
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-CommandPath
{
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd)
    { return $cmd.Source
    }
    return $null
}

function Get-Version
{
    param([string]$Command, [string]$Arguments)
    $result = & $Command $Arguments 2>&1 | Out-String
    return $result.Trim()
}

function Install-WithWinget
{
    param([string]$PackageId, [string]$DisplayName, [string]$Source)
    Write-Host "  Installing $DisplayName via winget..." -ForegroundColor DarkGray
    $args = @("install", "--id", $PackageId, "--exact", "--accept-source-agreements", "--accept-package-agreements")
    if ($Source) { $args += @("--source", $Source) }
    winget @args
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189)
    {
        Write-Host "  Failed to install $DisplayName. Install it manually." -ForegroundColor Red
        return $false
    }
    return $true
}

function Refresh-Path
{
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Write-Status
{
    param([string]$Name, [string]$Version, [string]$Message)
    $line = ("  {0,-16}" -f $Name) + " "
    if ($Version)
    {
        $line += $Version
    } else
    {
        $line += "NOT FOUND"
    }
    if ($Message)
    {
        $line += "  $Message"
    }
    $color = if ($Version)
    { 'Green'
    } else
    { 'Yellow'
    }
    Write-Host $line -ForegroundColor $color
}

# --- Main ---

Write-Host "Checking prerequisites..." -ForegroundColor Cyan
Write-Host ""

$allSatisfied = $true

# --- winget ---
$wingetPath = Get-CommandPath "winget"
if (-not $wingetPath)
{
    Write-Status "winget"
    Write-Host "  winget is required to install other dependencies." -ForegroundColor Yellow
    Write-Host "  Please install App Installer from the Microsoft Store:" -ForegroundColor Yellow
    Write-Host "  https://www.microsoft.com/p/app-installer/9nblggh4nns1" -ForegroundColor Yellow
    $allSatisfied = $false
} else
{
    $wingetVersion = (Get-Version "winget" "--version") -replace '^v'
    Write-Status "winget" "v$wingetVersion"
}

# --- Git ---
$gitPath = Get-CommandPath "git"
if (-not $gitPath)
{
    Write-Status "git"
    $install = Read-Host "  Install Git via winget? (Y/N)"
    if ($install -eq "Y" -or $install -eq "y")
    {
        Install-WithWinget -PackageId "Git.Git" -DisplayName "Git"
        Refresh-Path
        $gitPath = Get-CommandPath "git"
        if ($gitPath)
        {
            $gitVersion = (Get-Version "git" "--version") -replace '^git version '
            Write-Status "git" $gitVersion
        } else
        {
            Write-Status "git" -Message "FAILED - Install manually and re-run."
            $allSatisfied = $false
        }
    } else
    {
        Write-Status "git" -Message "SKIPPED - Required for cloning swift-winrt."
        $allSatisfied = $false
    }
} else
{
    $gitVersion = Get-Version "git" "--version"
    Write-Status "git" $gitVersion
}

# --- CMake ---
$cmakePath = Get-CommandPath "cmake"
if (-not $cmakePath)
{
    Write-Status "cmake"
    $install = Read-Host "  Install CMake via winget? (Y/N)"
    if ($install -eq "Y" -or $install -eq "y")
    {
        Install-WithWinget -PackageId "Kitware.CMake" -DisplayName "CMake"
        Refresh-Path
        $cmakePath = Get-CommandPath "cmake"
        if ($cmakePath)
        {
            $cmakeVersion = ((Get-Version "cmake" "--version") -split "`n" | Select-Object -First 1).Trim()
            Write-Status "cmake" $cmakeVersion
        } else
        {
            Write-Status "cmake" -Message "FAILED - Install manually and re-run."
            $allSatisfied = $false
        }
    } else
    {
        Write-Status "cmake" -Message "SKIPPED - Required for building swift-winrt."
        $allSatisfied = $false
    }
} else
{
    $cmakeVersion = ((Get-Version "cmake" "--version") -split "`n" | Select-Object -First 1).Trim()
    Write-Status "cmake" $cmakeVersion
}

# --- Ninja ---
$ninjaPath = Get-CommandPath "ninja"
if (-not $ninjaPath)
{
    Write-Status "ninja"
    $install = Read-Host "  Install Ninja via winget? (Y/N)"
    if ($install -eq "Y" -or $install -eq "y")
    {
        Install-WithWinget -PackageId "Ninja-build.Ninja" -DisplayName "Ninja"
        Refresh-Path
        $ninjaPath = Get-CommandPath "ninja"
        if ($ninjaPath)
        {
            $ninjaVersion = "v$(Get-Version "ninja" "--version")"
            Write-Status "ninja" $ninjaVersion
        } else
        {
            Write-Status "ninja" -Message "FAILED - Install manually."
            $allSatisfied = $false
        }
    } else
    {
        Write-Status "ninja" -Message "SKIPPED - CMake may fall back to a different generator."
        $allSatisfied = $false
    }
} else
{
    $ninjaVersion = "v$(Get-Version "ninja" "--version")"
    Write-Status "ninja" $ninjaVersion
}

# --- winapp CLI ---
$winappPath = Get-CommandPath "winapp"
if (-not $winappPath)
{
    Write-Status "winapp"
    $install = Read-Host "  Install winapp CLI via winget? (Y/N)"
    if ($install -eq "Y" -or $install -eq "y")
    {
        Install-WithWinget -PackageId "Microsoft.WinAppCli" -DisplayName "winapp CLI" -Source "winget"
        Refresh-Path
        $winappPath = Get-CommandPath "winapp"
        if ($winappPath)
        {
            $winappVersion = (Get-Version "winapp" "--version") -replace '^\s*v?(.+?)\s*$', '$1'
            Write-Status "winapp" "v$winappVersion"
        } else
        {
            Write-Status "winapp" -Message "FAILED - Install manually and re-run."
            $allSatisfied = $false
        }
    } else
    {
        Write-Status "winapp" -Message "SKIPPED - Required to restore SDK packages and generate icons."
        $allSatisfied = $false
    }
} else
{
    $winappVersion = (Get-Version "winapp" "--version") -replace '^\s*v?(.+?)\s*$', '$1'
    Write-Status "winapp" "v$winappVersion"
}

# --- nuget ---
$nugetPath = Get-CommandPath "nuget"
if (-not $nugetPath)
{
    Write-Status "nuget"
    Write-Host "  nuget.exe is required to restore packages for the development setup." -ForegroundColor Yellow
    Write-Host "  Install manually from https://www.nuget.org/downloads (add the folder containing nuget.exe to PATH)" -ForegroundColor Yellow
    Write-Host "  or run scripts\prerequisites.ps1's winapp step which will be needed for packaging anyway." -ForegroundColor DarkGray
    $allSatisfied = $false
} else
{
    # nuget 7.x dropped the "NuGet Version:" banner from `nuget help`, so we read
    # the version from the executable's file metadata.
    $nugetFileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($nugetPath).FileVersion
    $nugetVersion = if ($nugetFileVersion) { "v$nugetFileVersion" } else { "INSTALLED" }
    Write-Status "nuget" $nugetVersion
}

# --- Swift ---
$swiftPath = Get-CommandPath "swift"
if (-not $swiftPath)
{
    Write-Status "swift"
    Write-Host "  Swift toolchain is required to build the project." -ForegroundColor Yellow
    Write-Host "  Manual installation recommended: https://swift.org/download/" -ForegroundColor Yellow
    $open = Read-Host "  Open the download page in your browser? (Y/N)"
    if ($open -eq "Y" -or $open -eq "y")
    {
        Start-Process "https://swift.org/download/"
        Write-Host "  Download and run the Swift installer, then re-run this script." -ForegroundColor DarkGray
    }
    $allSatisfied = $false
} else
{
    $swiftVersion = (Get-Version "swift" "--version") -split "`n" | Select-Object -First 1
    Write-Status "swift" $swiftVersion
}

# --- MSVC (cl.exe) ---
# Only required when building swift-winrt from source. The check is informational
# here; install-swiftwinrt.ps1 will load the developer environment and prompt
# to install MSVC if it's missing.
$clPath = Get-CommandPath "cl.exe"
if ($clPath)
{
    $clVersion = (Get-Version "cl.exe") -split "`n" | Select-Object -First 1
    Write-Status "MSVC (cl.exe)" $clVersion
    Write-Host "  (required only for building swift-winrt; loaded automatically when needed)" -ForegroundColor DarkGray
} else
{
    Write-Status "MSVC (cl.exe)" -Message "Will be required if you need to build swift-winrt"
}

Write-Host ""

if ($allSatisfied)
{
    Write-Host "All prerequisites satisfied." -ForegroundColor Green
    exit 0
} else
{
    Write-Host "Some prerequisites are missing. Review the messages above." -ForegroundColor Yellow
    exit 1
}
