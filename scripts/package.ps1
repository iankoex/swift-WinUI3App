param(
    [ValidateSet("x64", "arm64", "x86")]
    [string]$Arch,
    [string]$CertificatePath,
    [string]$CertificatePassword,
    [string[]]$Locales = @("en-US")
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent

# --- Swift runtime DLL allow list (trimmed to actually referenced DLLs) ---
$dllBundlingAllowList = @(
    "swiftCore",
    "swiftCRT",
    "swiftDispatch",
    "swiftObservation",
    "swiftRegexBuilder",
    "swiftSynchronization",
    "swiftWinSDK",
    "Foundation",
    "FoundationNetworking",
    "FoundationEssentials",
    "FoundationInternationalization",
    "BlocksRuntime",
    "_FoundationICU",
    "swift_Concurrency",
    "swift_RegexParser",
    "swift_StringProcessing",
    "msvcp140",
    "vcruntime140",
    "vcruntime140_1",
    "dispatch"
) | ForEach-Object { "$_.dll".ToLower() }

# --- Project layout ---
$PlatformDir = Join-Path $ProjectRoot "Platform"
$ManifestDir = $PlatformDir
$IconsDir = Join-Path $PlatformDir "Assets"
$StagingDir = Join-Path $ProjectRoot ".build\out\msix-staging"
$OutputDir = Join-Path $ProjectRoot ".build\out"

# --- Required asset files (matches Platform/Package.appxmanifest) ---
$RequiredAssets = @(
    "StoreLogo.png",
    "MedTile.png",
    "AppList.png",
    "WideTile.png"
)

# --- Required manifest file ---
$RequiredManifest = "Package.appxmanifest"

# --- Architecture resolution ---
function Resolve-Architecture
{
    if ($Arch)
    { return $Arch
    }
    $procArch = $env:PROCESSOR_ARCHITECTURE
    switch ($procArch)
    {
        "AMD64"
        { return "x64"
        }
        "ARM64"
        { return "arm64"
        }
        "x86"
        { return "x86"
        }
        default
        {
            Write-Host "Unknown architecture: $procArch, defaulting to x64" -ForegroundColor Yellow
            return "x64"
        }
    }
}

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

function Write-Status
{
    param([string]$Name, [string]$Version, [string]$Message)
    $line = "  $Name".PadRight(24)
    if ($Version)
    {
        $line += $Version.PadRight(10)
    } else
    {
        $line += "NOT FOUND".PadRight(10)
    }
    $line += $Message
    $color = if ($Version)
    { 'Green'
    } else
    { 'Yellow'
    }
    Write-Host $line -ForegroundColor $color
}

# --- Try to load the VS developer environment (same as prerequisites.ps1) ---
function Get-PackageVersion
{
    # Reads Platform/packages.config and returns the version for a given package id.
    param([string]$PackageId)
    $configPath = Join-Path $PlatformDir "packages.config"
    if (-not (Test-Path $configPath))
    { return $null
    }
    [xml]$xml = Get-Content -LiteralPath $configPath
    $node = $xml.packages.package | Where-Object { $_.id -eq $PackageId }
    if ($node)
    { return $node.version
    }
    return $null
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
        return $true
    }
    return $false
}

# --- Step 1: Tool check ---
function Test-PackagingTools
{
    Write-Host "Checking packaging tools..." -ForegroundColor Cyan
    Write-Host ""

    $allSatisfied = $true

    # swift
    $swiftPath = Get-CommandPath "swift"
    if (-not $swiftPath)
    {
        Write-Status "swift" -Message "Required for release build."
        $allSatisfied = $false
    } else
    {
        $swiftVersion = (& swift --version) -split "`n" | Select-Object -First 1
        Write-Status "swift" $swiftVersion
    }

    # winapp CLI (handles SDK BuildTools, makeappx, signing)
    $winappPath = Get-CommandPath "winapp"
    if (-not $winappPath)
    {
        Write-Status "winapp" -Message "Install with: winget install Microsoft.WinAppCli"
        $allSatisfied = $false
    } else
    {
        $winappVersion = (& winapp --version 2>&1 | Select-Object -Last 1) -replace '^\s*v?(.+?)\s*$', '$1'
        Write-Status "winapp" "v$winappVersion"
    }

    Write-Host ""

    if (-not $allSatisfied)
    {
        Write-Host "Some packaging tools are missing." -ForegroundColor Red
        Write-Host "Install the winapp CLI (it manages SDK BuildTools and signing):" -ForegroundColor Yellow
        Write-Host "  winget install Microsoft.WinAppCli --source winget" -ForegroundColor White
        Write-Host "Or run scripts\prerequisites.ps1 to set up the environment." -ForegroundColor DarkGray
        exit 1
    }
}

# --- Step 2: File check ---
function Test-PackagingFiles
{
    param([string]$TargetArch)

    Write-Host "Checking required files..." -ForegroundColor Cyan
    Write-Host ""

    $allSatisfied = $true

    # manifest
    $manifestPath = Join-Path $ManifestDir $RequiredManifest
    if (Test-Path $manifestPath)
    {
        Write-Status "$RequiredManifest" "FOUND" $manifestPath
    } else
    {
        Write-Status "$RequiredManifest" -Message "Missing at $manifestPath"
        $allSatisfied = $false
    }

    # icons
    foreach ($asset in $RequiredAssets)
    {
        $assetPath = Join-Path $IconsDir $asset
        if (Test-Path $assetPath)
        {
            Write-Status $asset "FOUND" $assetPath
        } else
        {
            Write-Status $asset -Message "Missing at $assetPath"
            $allSatisfied = $false
        }
    }

    Write-Host ""

    if (-not $allSatisfied)
    {
        Write-Host "Required files are missing. Place them in $ManifestDir." -ForegroundColor Red
        Write-Host "  Run .\scripts\generate-icon-resource.ps1 to generate assets from Platform\AppIcon.png." -ForegroundColor Yellow
        exit 1
    }
}

# --- Step 3: Build for release ---
function Build-Release
{
    param(
        [string]$TargetArch,
        [string]$ExeName
    )

    Write-Host "Building release ($TargetArch)..." -ForegroundColor Cyan
    Write-Host ""

    & swift build -c release -Xswiftc -Osize
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "Release build failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit 1
    }
    Write-Host ""

    # Strip debug symbols to reduce binary size
    $exePath = Join-Path $ProjectRoot ".build\release\$ExeName.exe"
    if (Test-Path $exePath)
    {
        Write-Host "Stripping symbols from $ExeName.exe..." -ForegroundColor Cyan
        & llvm-strip -x $exePath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            Write-Host "Symbol stripping failed, but build succeeded." -ForegroundColor Yellow
        } else
        {
            Write-Host "Symbols stripped successfully." -ForegroundColor Green
        }
        Write-Host ""
    }
}

# --- Step 4: Stage the package layout ---
function Stage-PackageLayout
{
    param(
        [string]$TargetArch,
        [string]$ExeName
    )

    Write-Host "Staging package layout..." -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $StagingDir)
    {
        Remove-Item -Path $StagingDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $StagingDir | Out-Null

    # manifest
    Copy-Item -Path (Join-Path $ManifestDir $RequiredManifest) -Destination $StagingDir -Force

    # icons
    $stagedIcons = Join-Path $StagingDir "Assets"
    New-Item -ItemType Directory -Path $stagedIcons | Out-Null
    foreach ($asset in $RequiredAssets)
    {
        $src = Join-Path $IconsDir $asset
        if (Test-Path $src)
        {
            Copy-Item -Path $src -Destination $stagedIcons -Force
        }
    }
    # compiled binary
    $exeSource = Join-Path $ProjectRoot ".build\release\$ExeName.exe"
    if (-not (Test-Path $exeSource))
    {
        Write-Host "  Expected binary not found: $exeSource" -ForegroundColor Red
        exit 1
    }
    Copy-Item -Path $exeSource -Destination $StagingDir -Force
    Write-Host "  Copied $ExeName.exe" -ForegroundColor DarkGray

    # swift runtime DLLs — look in the Runtimes dir (contains swiftCore, Foundation, etc.)
    $swiftExe = Get-CommandPath "swift"
    $swiftDir = Split-Path $swiftExe -Parent
    # swift.exe is at ...\Swift\Toolchains\<ver>\usr\bin\swift.exe
    # runtimes are at ...\Swift\Runtimes\<ver>\usr\bin
    $swiftRoot = $swiftDir
    for ($i = 0; $i -lt 4; $i++)
    { $swiftRoot = Split-Path $swiftRoot -Parent
    }
    $runtimeDirs = @()
    $runtimeBase = Join-Path $swiftRoot "Runtimes"
    if (Test-Path $runtimeBase)
    {
        $runtimeDirs += Get-ChildItem -Path $runtimeBase -Directory | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName "usr\bin" }
    }
    # also fall back to the toolchain bin (catches anything missed in Runtimes)
    $runtimeDirs += $swiftDir

    $stagedDlls = 0
    $seen = @{}
    foreach ($dir in $runtimeDirs)
    {
        if (-not (Test-Path $dir))
        { continue
        }
        Get-ChildItem -Path $dir -Filter "*.dll" -File | ForEach-Object {
            $baseName = $_.BaseName.ToLower()
            if ($dllBundlingAllowList -contains "$baseName.dll" -and -not $seen.ContainsKey($baseName))
            {
                $seen[$baseName] = $true
                Copy-Item -Path $_.FullName -Destination $StagingDir -Force
                $stagedDlls++
            }
        }
    }
    Write-Host "  Copied $stagedDlls Swift runtime DLL(s)" -ForegroundColor DarkGray

    # resource bundles (.resources) for Bundle.module
    $buildDir = Join-Path $ProjectRoot ".build\release"
    $resourceBundles = Get-ChildItem -Path $buildDir -Directory -Filter "*.resources"
    foreach ($bundle in $resourceBundles)
    {
        Copy-Item -Path $bundle.FullName -Destination $StagingDir -Recurse -Force
        Write-Host "  Copied $($bundle.Name)" -ForegroundColor DarkGray
    }

    # --- Windows App SDK framework DLLs (self-contained deployment) ---
    $nugetDir = Join-Path $env:USERPROFILE ".nuget\packages"
    if (Test-Path $nugetDir)
    {
        $foundationVer = Get-PackageVersion -PackageId "Microsoft.WindowsAppSDK.Foundation"
        $winuiVer      = Get-PackageVersion -PackageId "Microsoft.WindowsAppSDK.WinUI"
        $interactVer   = Get-PackageVersion -PackageId "Microsoft.WindowsAppSDK.InteractiveExperiences"

        $frameworkPackages = @()
        if ($foundationVer)
        { $frameworkPackages += "Microsoft.WindowsAppSDK.Foundation.$foundationVer"
        }
        if ($winuiVer)
        { $frameworkPackages += "Microsoft.WindowsAppSDK.WinUI.$winuiVer"
        }
        if ($interactVer)
        { $frameworkPackages += "Microsoft.WindowsAppSDK.InteractiveExperiences.$interactVer"
        }
        $frameworkDllCount = 0
        foreach ($pkg in $frameworkPackages)
        {
            $nativeDir = Join-Path $nugetDir "$pkg\runtimes-framework\win-x64\native"
            if (-not (Test-Path $nativeDir))
            { continue
            }
            # Copy DLLs
            Get-ChildItem -Path $nativeDir -Filter "*.dll" -File | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $StagingDir -Force
                $frameworkDllCount++
            }
            # Copy .pri resource index files
            Get-ChildItem -Path $nativeDir -Filter "*.pri" -File | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $StagingDir -Force
            }
        }
        Write-Host "  Copied $frameworkDllCount Windows App SDK framework DLL(s)" -ForegroundColor DarkGray

        # WinUI XAML locale resources (only the requested locales)
        $winuiNative = Join-Path $nugetDir "Microsoft.WindowsAppSDK.WinUI.$winuiVer\runtimes-framework\win-x64\native"
        if (Test-Path $winuiNative)
        {
            $localeCount = 0
            $localeSet = $Locales | ForEach-Object { $_.ToLower() }
            Get-ChildItem -Path $winuiNative -Directory | ForEach-Object {
                if ($localeSet -contains $_.Name.ToLower())
                {
                    $destDir = Join-Path $StagingDir $_.Name
                    Copy-Item -Path $_.FullName -Destination $destDir -Recurse -Force
                    $localeCount++
                }
            }
            if ($localeCount -gt 0)
            {
                Write-Host "  Copied $localeCount WinUI locale resource director(ies): $($Locales -join ', ')" -ForegroundColor DarkGray
            } else
            {
                Write-Host "  WARNING: No matching WinUI locale resources found for: $($Locales -join ', ')" -ForegroundColor Yellow
            }
        }

        # Merge framework activatable class registrations into manifest
        $stagedManifest = Join-Path $StagingDir $RequiredManifest
        $manifestContent = [System.IO.File]::ReadAllText($stagedManifest)

        $fragmentPackages = $frameworkPackages

        $extensionsBlock = "  <Extensions>"
        foreach ($pkg in $fragmentPackages)
        {
            $fragFile = Join-Path $nugetDir "$pkg\runtimes-framework\package.appxfragment"
            if (-not (Test-Path $fragFile))
            { continue
            }
            $fragContent = [System.IO.File]::ReadAllText($fragFile)
            if ($fragContent -match '(?s)<Extensions.*?>(.*?)</Extensions>')
            {
                $extensionsBlock += $matches[1]
            }
        }
        $extensionsBlock += "`r`n  </Extensions>"

        $closePackageTag = "</Package>"
        $insertPos = $manifestContent.LastIndexOf($closePackageTag)
        if ($insertPos -ge 0)
        {
            $manifestContent = $manifestContent.Insert($insertPos, "`r`n$extensionsBlock`r`n")
            [System.IO.File]::WriteAllText($stagedManifest, $manifestContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Merged framework activatable class registrations into manifest" -ForegroundColor DarkGray
        }
    } else
    {
        Write-Host "  WARNING: .nuget-packages not found - framework DLLs and manifest extensions not bundled." -ForegroundColor Yellow
    }

    Write-Host ""
}

# --- Step 5: Create and sign the MSIX package ---
function New-MsixPackage
{
    param(
        [string]$ExeName,
        [string]$TargetArch,
        [string]$Version
    )

    Write-Host "Creating MSIX package..." -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $OutputDir))
    {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $msixName = "${ExeName}_${Version}_${TargetArch}"
    $msixPath = Join-Path $OutputDir "${msixName}.msix"

    if (Test-Path $msixPath)
    {
        Remove-Item $msixPath -Force
    }

    # Pull the publisher CN from the staged manifest so cert and manifest agree.
    $stagedManifest = Join-Path $StagingDir $RequiredManifest
    [xml]$manifestXml = Get-Content $stagedManifest
    $publisher = $manifestXml.Package.Identity.Publisher
    if (-not $publisher)
    {
        Write-Host "  Manifest is missing the Identity@Publisher attribute." -ForegroundColor Red
        exit 1
    }

    # Determine signing certificate
    if ($CertificatePath)
    {
        $certPath = $CertificatePath
        $certPassword = if ($CertificatePassword)
        { $CertificatePassword
        } else
        { "password"
        }
        Write-Host "  Using provided cert: $certPath" -ForegroundColor DarkGray
    } else
    {
        $certPath = Join-Path $PlatformDir "WindowsPackage.pfx"
        $certPassword = "password"
        if (-not (Test-Path $certPath))
        {
            Write-Host "  Generating self-signed cert for publisher $publisher..." -ForegroundColor DarkGray
            & winapp cert generate --publisher $publisher --output $certPath --password $certPassword 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0)
            {
                Write-Host "  Cert generation failed. Provide your own with -CertificatePath." -ForegroundColor Red
                exit 1
            }
        } else
        {
            Write-Host "  Reusing existing dev cert: $certPath" -ForegroundColor DarkGray
        }
    }

    # Install cert to trust store so the signed MSIX can be installed locally
    $certInstalled = $false
    try
    {
        $psCmd = "winapp cert install `"$certPath`" --password $certPassword"
        Start-Process -FilePath powershell -ArgumentList "-NoProfile -Command $psCmd" -Verb RunAs -Wait -WindowStyle Hidden
        if ($LASTEXITCODE -eq 0)
        { $certInstalled = $true
        }
    } catch
    {
    }
    if (-not $certInstalled)
    {
        try
        {
            Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop | Out-Null
            $certInstalled = $true
        } catch
        {
        }
    }
    if ($certInstalled)
    {
        Write-Host "  Cert trusted for local install." -ForegroundColor Green
    } else
    {
        Write-Host "  Could not install cert automatically." -ForegroundColor Yellow
        Write-Host "  To trust it (required for MSIX install), run as Admin:" -ForegroundColor Yellow
        Write-Host "    Import-Certificate -FilePath '$certPath' -CertStoreLocation Cert:\LocalMachine\Root" -ForegroundColor White
    }

    $env:WINAPP_CLI_TELEMETRY_OPTOUT = "1"
    $packOutput = & winapp pack $StagingDir --cert $certPath --cert-password $certPassword --output $msixPath --executable "$ExeName.exe" 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0)
    {
        Write-Host "  MSIX packaging failed (exit $exitCode)." -ForegroundColor Red
        Write-Host $packOutput -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  Package created and signed: $msixPath" -ForegroundColor Green

    return $msixPath
}

# --- Main ---
$TargetArch = Resolve-Architecture
$ExeName = "App"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Swift WinUI 3 App - MSIX Packaging" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Architecture: $TargetArch" -ForegroundColor White
Write-Host "  Locales:      $($Locales -join ', ')" -ForegroundColor White
Write-Host "  Output dir:   $OutputDir" -ForegroundColor White
Write-Host ""

Test-PackagingTools
Test-PackagingFiles -TargetArch $TargetArch
Build-Release -TargetArch $TargetArch -ExeName $ExeName
Stage-PackageLayout -TargetArch $TargetArch -ExeName $ExeName

# read version from manifest
$manifestPath = Join-Path $StagingDir $RequiredManifest
[xml]$manifestXml = Get-Content $manifestPath
$pkgVersion = $manifestXml.Package.Identity.Version
if (-not $pkgVersion)
{
    $pkgVersion = "0.0.0.0"
}

$msixPath = New-MsixPackage -ExeName $ExeName -TargetArch $TargetArch -Version $pkgVersion

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Packaging complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  App.exe: .build\release\$ExeName.exe" -ForegroundColor White
Write-Host "  MSIX:    $msixPath" -ForegroundColor White
Write-Host ""
Write-Host "  For distribution, sign with your own certificate." -ForegroundColor Cyan
Write-Host "  See: https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview" -ForegroundColor White
Write-Host ""
