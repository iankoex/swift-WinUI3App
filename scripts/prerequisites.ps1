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
    param([string]$PackageId, [string]$DisplayName)
    Write-Host "  Installing $DisplayName via winget..." -ForegroundColor DarkGray
    winget install --id $PackageId --exact --accept-source-agreements --accept-package-agreements
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

function Add-ToUserPath
{
    param([string]$NewPath)
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$NewPath*")
    {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$NewPath", "User")
        Write-Host "  Added to user PATH: $NewPath" -ForegroundColor Green
    }
    if ($env:Path -notlike "*$NewPath*")
    {
        $env:Path += ";$NewPath"
    }
}

function Invoke-VsDevShell
{
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere))
    {
        return $false
    }
    $vsPath = & $vsWhere -latest -products * -property installationPath
    if (-not $vsPath)
    {
        return $false
    }
    $devShellModule = "$vsPath\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
    if (Test-Path $devShellModule)
    {
        Import-Module $devShellModule
        $nativeArch = switch ($env:PROCESSOR_ARCHITECTURE)
        {
            "ARM64"
            { "arm64"
            }
            "AMD64"
            { "amd64"
            }
            "x86"
            { "x86"
            }
            default
            { "amd64"
            }
        }
        & Microsoft.VisualStudio.DevShell\Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -Arch $nativeArch
        return [bool](Get-Command "cl.exe" -ErrorAction SilentlyContinue)
    }
    return $false
}

function Write-Status
{
    param([string]$Name, [string]$Version, [string]$Message)
    $line = "  $Name".PadRight(32)
    if ($Version)
    {
        $line += $Version.PadRight(28)
    } else
    {
        $line += "NOT FOUND".PadRight(28)
    }
    $line += $Message
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

# --- NuGet ---
$nugetPath = Get-CommandPath "nuget.exe"
if (-not $nugetPath)
{
    $tmpNuget = Join-Path $env:TEMP "nuget.exe"
    if (Test-Path $tmpNuget)
    {
        $nugetPath = $tmpNuget
    }
}
if (-not $nugetPath)
{
    Write-Status "nuget.exe"
    $download = Read-Host "  Download nuget.exe to TEMP? (Y/N)"
    if ($download -eq "Y" -or $download -eq "y")
    {
        Write-Host "  Downloading nuget.exe..." -ForegroundColor DarkGray
        $tmpNuget = Join-Path $env:TEMP "nuget.exe"
        Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $tmpNuget
        if (Test-Path $tmpNuget)
        {
            $nugetPath = $tmpNuget
            $nugetVersion = "v$((Get-Item $tmpNuget).VersionInfo.FileVersion)"
            Write-Status "nuget.exe" $nugetVersion
        } else
        {
            Write-Status "nuget.exe" -Message "FAILED - Download manually."
            $allSatisfied = $false
        }
    } else
    {
        Write-Status "nuget.exe" -Message "SKIPPED - Required for restoring NuGet packages."
        $allSatisfied = $false
    }
} else
{
    $nugetVersion = "v$((Get-Item $nugetPath).VersionInfo.FileVersion)"
    Write-Status "nuget.exe" $nugetVersion
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

# --- MSVC (cl.exe) & Developer Environment ---
$clPath = Get-CommandPath "cl.exe"
$inDevEnv = [bool]($env:VCToolsInstallDir)

if ($clPath -and $inDevEnv)
{
    $clVersion = (Get-Version "cl.exe") -split "`n" | Select-Object -First 1
    Write-Status "MSVC (cl.exe)" $clVersion
} else
{
    if ($clPath)
    {
        Write-Status "MSVC (cl.exe)" "$((Get-Version "cl.exe") -split "`n" | Select-Object -First 1) (no dev environment)"
    } else
    {
        Write-Status "MSVC (cl.exe)"
    }

    Write-Host "  Loading Visual Studio developer environment..." -ForegroundColor DarkGray
    if (Invoke-VsDevShell)
    {
        $clPath = Get-CommandPath "cl.exe"
        if ($clPath)
        {
            $clVersion = (Get-Version "cl.exe") -split "`n" | Select-Object -First 1
            Write-Status "MSVC (cl.exe)" $clVersion
            Write-Host "  (loaded VS developer environment into this session)" -ForegroundColor DarkGray
        } else
        {
            Write-Host "  VS environment loaded but cl.exe still not found." -ForegroundColor Yellow
            $allSatisfied = $false
        }
    } else
    {
        Write-Host "  Could not automatically load Visual Studio developer environment." -ForegroundColor Yellow
        $install = Read-Host "  Install Visual Studio Build Tools with the required components? (Y/N)"
        if ($install -eq "Y" -or $install -eq "y")
        {
            Write-Host "  Installing Visual Studio Build Tools..." -ForegroundColor DarkGray
            winget install Microsoft.VisualStudio.BuildTools --exact --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189)
            {
                Write-Host ""
                Write-Host "  Visual Studio Build Tools installed." -ForegroundColor Green
                Write-Host "  Now add the required individual components:" -ForegroundColor Cyan
                Write-Host "  1. Open the Visual Studio Installer" -ForegroundColor White
                Write-Host "  2. Find 'Visual Studio Build Tools' and click 'Modify'" -ForegroundColor White
                Write-Host "  3. Go to the 'Individual components' tab" -ForegroundColor White
                Write-Host "  4. Search for and select:" -ForegroundColor White
                Write-Host "     - MSVC build tools for (ARM64 or x64) latest" -ForegroundColor DarkGray
                Write-Host "     - Windows 10 SDK 10.0.26100.___" -ForegroundColor DarkGray
                Write-Host "  5. Click 'Modify' in the bottom-right corner to install" -ForegroundColor White
                Write-Host ""
                Write-Host "  Once complete, re-run this script from a Developer PowerShell for VS 2022." -ForegroundColor Yellow
                $allSatisfied = $false
            } else
            {
                Write-Host "  Failed to install Visual Studio Build Tools." -ForegroundColor Red
                Write-Host "  Download from: https://visualstudio.microsoft.com/" -ForegroundColor Yellow
                $allSatisfied = $false
            }
        } else
        {
            Write-Status "MSVC (cl.exe)" -Message "SKIPPED - Required for building swift-winrt and the app."
            $allSatisfied = $false
        }
    }
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
