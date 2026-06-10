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
    param([scriptblock]$Command, [string]$DisplayName)
    Write-Host "  Installing $DisplayName via winget..." -ForegroundColor DarkGray
    & $Command
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

function Get-WindowsSdkInfo
{
    $sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10"
    $manifest = Join-Path $sdkRoot "SDKManifest.xml"
    if (Test-Path $manifest)
    {
        try
        {
            [xml]$xml = Get-Content $manifest -ErrorAction Stop
            if ($xml.SDKManifest.ProductVersion)
            {
                return @{ Found = $true; Version = $xml.SDKManifest.ProductVersion }
            }
        } catch {}
    }
    $includeDir = Join-Path $sdkRoot "Include"
    if (Test-Path $includeDir)
    {
        $versions = Get-ChildItem $includeDir -Directory | Sort-Object Name -Descending -ErrorAction SilentlyContinue
        if ($versions)
        {
            return @{ Found = $true; Version = $versions[0].Name }
        }
    }
    return @{ Found = $false; Version = $null }
}

function Get-LatestWindowsSdkPackageId
{
    try
    {
        $output = & winget search "Windows SDK" --accept-source-agreements 2>&1 | Out-String
        $lines = $output -split "`r`n|`n"
        $latestBuild = 0
        $latestId = $null
        foreach ($line in $lines)
        {
            if ($line -match "(Microsoft\.WindowsSDK\.10\.0\.(\d+))")
            {
                $id = $matches[1]
                $build = [int]$matches[2]
                if ($build -gt $latestBuild)
                {
                    $latestBuild = $build
                    $latestId = $id
                }
            }
        }
        return $latestId
    } catch
    {
        return $null
    }
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
        Install-WithWinget -Command { winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements } -DisplayName "Git"
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
        Install-WithWinget -Command { winget install -e --id Kitware.CMake --accept-source-agreements --accept-package-agreements } -DisplayName "CMake"
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
        Install-WithWinget -Command { winget install -e --id Ninja-build.Ninja --accept-source-agreements --accept-package-agreements } -DisplayName "Ninja"
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
        Install-WithWinget -Command { winget install -e --id Microsoft.winappcli --source winget --accept-source-agreements --accept-package-agreements } -DisplayName "winapp CLI"
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
    $install = Read-Host "  Install NuGet CLI via winget? (Y/N)"
    if ($install -eq "Y" -or $install -eq "y")
    {
        Install-WithWinget -Command { winget install -e --id Microsoft.NuGet --accept-source-agreements --accept-package-agreements } -DisplayName "NuGet CLI"
        Refresh-Path
        $nugetPath = Get-CommandPath "nuget"
        if ($nugetPath)
        {
            $nugetFileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($nugetPath).FileVersion
            $nugetVersion = if ($nugetFileVersion) { "v$nugetFileVersion" } else { "INSTALLED" }
            Write-Status "nuget" $nugetVersion
        } else
        {
            Write-Status "nuget" -Message "FAILED - Install manually from https://www.nuget.org/downloads"
            $allSatisfied = $false
        }
    } else
    {
        Write-Status "nuget" -Message "SKIPPED - Required to restore SDK packages."
        $allSatisfied = $false
    }
} else
{
    $nugetFileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($nugetPath).FileVersion
    $nugetVersion = if ($nugetFileVersion) { "v$nugetFileVersion" } else { "INSTALLED" }
    Write-Status "nuget" $nugetVersion
}

# --- Swift ---
$swiftPath = Get-CommandPath "swift"
if (-not $swiftPath)
{
    Write-Status "swift"
    $install = Read-Host "  Install Swift toolchain via winget? (Y/N)"
    if ($install -eq "Y" -or $install -eq "y")
    {
        Install-WithWinget -Command { winget install --id Swift.Toolchain -e --source winget --accept-source-agreements --accept-package-agreements } -DisplayName "Swift"
        Refresh-Path
        $swiftPath = Get-CommandPath "swift"
        if ($swiftPath)
        {
            $swiftVersion = (Get-Version "swift" "--version") -split "`n" | Select-Object -First 1
            Write-Status "swift" $swiftVersion
        } else
        {
            Write-Status "swift" -Message "FAILED - Swift may need a manual install."
            Write-Host "  Download from: https://swift.org/download/" -ForegroundColor Yellow
            $open = Read-Host "  Open the download page in your browser? (Y/N)"
            if ($open -eq "Y" -or $open -eq "y") { Start-Process "https://swift.org/download/" }
            $allSatisfied = $false
        }
    } else
    {
        Write-Host "  Manual installation: https://swift.org/download/" -ForegroundColor Yellow
        $open = Read-Host "  Open the download page in your browser? (Y/N)"
        if ($open -eq "Y" -or $open -eq "y") { Start-Process "https://swift.org/download/" }
        $allSatisfied = $false
    }
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
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vsPath = if (Test-Path $vsWhere) { & $vsWhere -latest -products * -property installationPath -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 2>$null } else { $null }
    if ($vsPath)
    {
        Write-Status "MSVC (cl.exe)" -Message "Installed but not in PATH (the script will load the environment when needed to compile swiftwinrt.exe)"
    } else
    {
        Write-Status "MSVC (cl.exe)"
        Write-Host "  Visual Studio Build Tools (~3 GB download)." -ForegroundColor Yellow
        $install = Read-Host "  Install via winget? (Y/N)"
        if ($install -eq "Y" -or $install -eq "y")
        {
            Install-WithWinget -Command { winget install --id=Microsoft.VisualStudio.BuildTools -e --accept-source-agreements --accept-package-agreements } -DisplayName "Visual Studio Build Tools"
            Write-Host ""
            Write-Host "  IMPORTANT: After the installer downloads, you must manually:" -ForegroundColor Yellow
            Write-Host "  1. Open the Visual Studio Installer" -ForegroundColor Yellow
            Write-Host "  2. Click 'Modify' on the 'Visual Studio Build Tools' entry" -ForegroundColor Yellow
            Write-Host "  3. Go to the 'Individual Components' tab" -ForegroundColor Yellow
            Write-Host "  4. Search for and check:" -ForegroundColor Yellow
            Write-Host "     - MSVC build tools for x64/x86 (latest)" -ForegroundColor Cyan
            Write-Host "       (pick the one matching your architecture; there is also an ARM64 variant)" -ForegroundColor DarkGray
            Write-Host '     - Windows 11 SDK (10.0.26100.0)' -ForegroundColor Cyan
            Write-Host "  5. Tap the 'Install while downloading' button" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  *** Windows 11 SDK 10.0.26100 is REQUIRED by swiftwinrt. ***" -ForegroundColor Red
            Write-Host "  *** Other versions will NOT work. You must select exactly 10.0.26100. ***" -ForegroundColor Red
            Write-Host ""
            Write-Host "  After modifying, open a Developer PowerShell for Visual Studio to use cl.exe." -ForegroundColor DarkGray
            $allSatisfied = $false
        } else
        {
            Write-Status "MSVC (cl.exe)" -Message "SKIPPED - Only needed for building swift-winrt from source."
        }
    }
}

# --- Windows SDK ---
# Required for C++ compilation (building swift-winrt) and WinRT metadata headers.
# The NuGet packages provide .winmd metadata, but the SDK headers/libs are needed
# to compile native C++ components.
$sdkInfo = Get-WindowsSdkInfo
if ($sdkInfo.Found)
{
    Write-Status "Windows SDK" $sdkInfo.Version
} else
{
    Write-Status "Windows SDK"
    Write-Host "  Windows SDK is required for building swift-winrt." -ForegroundColor Yellow
    Write-Host "  Install it via the Visual Studio Build Tools installer:" -ForegroundColor Yellow
    Write-Host "  1. If not already installed, install 'Visual Studio Build Tools' via the step above" -ForegroundColor Yellow
    Write-Host "  2. Open the Visual Studio Installer" -ForegroundColor Yellow
    Write-Host "  3. Click 'Modify' on 'Visual Studio Build Tools'" -ForegroundColor Yellow
    Write-Host "  4. Go to the 'Individual Components' tab" -ForegroundColor Yellow
    Write-Host "  5. Search for and check:" -ForegroundColor Yellow
    Write-Host '     - Windows 11 SDK (10.0.26100.0)' -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  *** Windows 11 SDK 10.0.26100 is REQUIRED by swiftwinrt. ***" -ForegroundColor Red
    Write-Host "  *** Other versions will NOT work. You must select exactly 10.0.26100. ***" -ForegroundColor Red
    $allSatisfied = $false
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
