$ProjectRoot = Split-Path $PSScriptRoot -Parent
$InstallDir = Join-Path $ProjectRoot ".swift-winrt"
$BinDir = Join-Path $InstallDir "bin"
$SourceDir = Join-Path $InstallDir "source"
$SwiftWinRTExe = Join-Path $BinDir "swiftwinrt.exe"

function Add-ToUserPath
{
    param([string]$NewPath)
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$NewPath*")
    {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$NewPath", "User")
        Write-Host "Added to user PATH: $NewPath" -ForegroundColor Green
    } else
    {
        Write-Host "Already in user PATH: $NewPath" -ForegroundColor DarkGray
    }
    if ($env:Path -notlike "*$NewPath*")
    {
        $env:Path += ";$NewPath"
        Write-Host "Added to session PATH: $NewPath" -ForegroundColor Green
    }
}

function Install-WithWinget
{
    param([string]$PackageId, [string]$DisplayName, [string]$ExpectedPath)
    Write-Host "$DisplayName not found. Installing via winget..." -ForegroundColor DarkGray
    winget install --id $PackageId --exact --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189)
    {
        Write-Host "Failed to install $DisplayName. Install it manually." -ForegroundColor Red
        exit 1
    }
    if (Test-Path $ExpectedPath)
    {
        Add-ToUserPath -NewPath $ExpectedPath
        Write-Host "$DisplayName installed." -ForegroundColor Green
    } else
    {
        Write-Host "$DisplayName installed. Make sure it is in your PATH." -ForegroundColor Yellow
    }
}

function Test-Command
{
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
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

# --- Main ---

# Fast path: swiftwinrt.exe is already built. Nothing to do.
if (Test-Path $SwiftWinRTExe)
{
    Write-Host "swiftwinrt.exe already present at $SwiftWinRTExe" -ForegroundColor Green
    exit 0
}

Write-Host "Installing Swift/WinRT..." -ForegroundColor Cyan
Write-Host ""

# From here on we need the VS developer environment for cl.exe / cmake.
if (Test-Command "cl.exe")
{
    Write-Host "Found C++ compiler (cl.exe)" -ForegroundColor DarkGray
} else
{
    Write-Host "C++ compiler (cl.exe) not found - loading Visual Studio developer environment..." -ForegroundColor Cyan

    if (-not (Invoke-VsDevShell))
    {
        $installVs = Read-Host "Visual Studio 2022 not found. Install it with C++ workload? (Y/N)"
        if ($installVs -eq "Y" -or $installVs -eq "y")
        {
            Write-Host "Installing Visual Studio 2022 Community..." -ForegroundColor DarkGray
            winget install --id Microsoft.VisualStudio.2022.Community --exact --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189)
            {
                Write-Host "Failed to install Visual Studio. Install it manually." -ForegroundColor Red
                Write-Host "Download from: https://visualstudio.microsoft.com/" -ForegroundColor Yellow
                exit 1
            }
            Write-Host "Adding C++ development workload (this may take a while)..." -ForegroundColor DarkGray
            $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
            $vsPath = & $vsWhere -latest -products * -property installationPath
            $setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
            if ($vsPath -and (Test-Path $setup))
            {
                & $setup modify --installPath $vsPath --add Microsoft.VisualStudio.Workload.NativeDesktop --passive --norestart
                if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010)
                {
                    Write-Host "Workload install may have failed. Try installing 'Desktop development with C++' manually." -ForegroundColor Yellow
                }
            }
            if (Invoke-VsDevShell)
            {
                Write-Host "Loaded Visual Studio developer environment." -ForegroundColor Green
            } else
            {
                Write-Host "Could not load the Visual Studio developer environment." -ForegroundColor Red
                Write-Host "Open a Developer PowerShell for VS 2022 and run this script again." -ForegroundColor Yellow
                exit 1
            }
        } else
        {
            Write-Host "Cannot build swift-winrt without a C++ compiler." -ForegroundColor Red
            Write-Host "Install Visual Studio 2022 with the 'Desktop development with C++' workload." -ForegroundColor Yellow
            Write-Host "Then run this script from a Developer PowerShell for VS 2022." -ForegroundColor Yellow
            exit 1
        }
    } else
    {
        Write-Host "Loaded Visual Studio developer environment." -ForegroundColor Green
    }
}

# --- Git ---
if (-not (Test-Command "git"))
{
    Install-WithWinget -PackageId "Git.Git" -DisplayName "Git" -ExpectedPath "C:\Program Files\Git\cmd"
    if (-not (Test-Command "git"))
    {
        Write-Host "Git installation failed. Please install Git manually and re-run." -ForegroundColor Red
        exit 1
    }
} else
{
    Write-Host "Found git" -ForegroundColor DarkGray
}

# --- CMake ---
if (-not (Test-Command "cmake"))
{
    Install-WithWinget -PackageId "Kitware.CMake" -DisplayName "CMake" -ExpectedPath "C:\Program Files\CMake\bin"
    if (-not (Test-Command "cmake"))
    {
        Write-Host "CMake installation failed. Please install CMake manually and re-run." -ForegroundColor Red
        exit 1
    }
} else
{
    Write-Host "Found cmake" -ForegroundColor DarkGray
}

Write-Host ""

# --- Clone / Update source ---
if (-not (Test-Path $SourceDir))
{
    Write-Host "Cloning swift-winrt..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $SourceDir -Force | Out-Null
    git clone https://github.com/thebrowsercompany/swift-winrt.git $SourceDir
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "Failed to clone swift-winrt." -ForegroundColor Red
        exit 1
    }
} else
{
    Write-Host "swift-winrt source already present." -ForegroundColor DarkGray
}

# --- Init submodules ---
Write-Host "Initializing submodules..." -ForegroundColor Cyan
Push-Location $SourceDir
git submodule init
if ($LASTEXITCODE -ne 0)
{ Pop-Location; exit 1
}
git submodule update --recursive
if ($LASTEXITCODE -ne 0)
{ Pop-Location; exit 1
}
Pop-Location

# --- Patch for MSVC 19.51+ (await → await:strict) ---
$CMakeLists = Join-Path $SourceDir "CMakeLists.txt"
$PatchContent = Get-Content $CMakeLists -Raw
$Fixes = @(
    "add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)"
    'string(REPLACE "/await " "/await:strict " CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")'
)
$needsUpdate = $false
foreach ($Flag in $Fixes)
{
    if ($PatchContent -notmatch [regex]::Escape($Flag))
    {
        $PatchContent = $PatchContent -replace "(?<=project\(swiftwinrt[^)]*\))", "`n$Flag"
        $needsUpdate = $true
    }
}
if ($needsUpdate)
{
    Set-Content -Path $CMakeLists -Value $PatchContent -NoNewline
    Write-Host "Patched CMakeLists.txt for MSVC 19.51+ compatibility" -ForegroundColor DarkGray
}

# --- CMake configure ---
Write-Host "Configuring CMake (release)..." -ForegroundColor Cyan
Push-Location $SourceDir
cmake --preset release
if ($LASTEXITCODE -ne 0)
{ Pop-Location; exit 1
}
Pop-Location

# --- CMake build ---
Write-Host "Building swift-winrt.exe..." -ForegroundColor Cyan
Push-Location $SourceDir
cmake --build --preset release --target swiftwinrt
if ($LASTEXITCODE -ne 0)
{ Pop-Location; exit 1
}
Pop-Location

# --- Copy binary ---
$BinarySource = Join-Path $SourceDir "build\release\swiftwinrt\swiftwinrt.exe"
if (-not (Test-Path $BinarySource))
{
    Write-Host "Build succeeded but swiftwinrt.exe not found at expected path." -ForegroundColor Red
    Write-Host "Expected: $BinarySource" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $BinDir))
{
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}
Copy-Item -Path $BinarySource -Destination $BinDir -Force
Write-Host "Copied swiftwinrt.exe to $BinDir" -ForegroundColor Green

# --- Cleanup: always remove the source folder to save space ---
Write-Host ""
Remove-Item -Path $SourceDir -Recurse -Force
Write-Host "Source folder deleted." -ForegroundColor DarkGray

# --- Summary ---
Write-Host ""
Write-Host "Swift/WinRT installed successfully." -ForegroundColor Green
Write-Host "  Binary: $BinDir\swiftwinrt.exe" -ForegroundColor Cyan
