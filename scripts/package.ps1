param(
    [ValidateSet("x64", "arm64", "x86")]
    [string]$Arch,
    [string]$CertificatePath,
    [string]$CertificatePassword,
    [switch]$SkipSign
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent

# --- Swift runtime DLL allow list (mirrors the Swift Bundler) ---
$dllBundlingAllowList = @(
    "swiftCore",
    "swiftCRT",
    "swiftDispatch",
    "swiftDistributed",
    "swiftObservation",
    "swiftRegexBuilder",
    "swiftRemoteMirror",
    "swiftSwiftOnoneSupport",
    "swiftSynchronization",
    "swiftWinSDK",
    "Foundation",
    "FoundationXML",
    "FoundationNetworking",
    "FoundationEssentials",
    "FoundationInternationalization",
    "BlocksRuntime",
    "_FoundationICU",
    "_InternalSwiftScan",
    "_InternalSwiftStaticMirror",
    "swift_Concurrency",
    "swift_RegexParser",
    "swift_StringProcessing",
    "swift_Differentiation",
    "concrt140",
    "msvcp140",
    "msvcp140d",
    "msvcp140_1",
    "msvcp140_2",
    "msvcp140_atomic_wait",
    "msvcp140_codecvt_ids",
    "vccorlib140",
    "vcruntime140",
    "vcruntime140d",
    "vcruntime140_1",
    "vcruntime140_1d",
    "ucrtbased",
    "vcruntime140_threads",
    "dispatch"
) | ForEach-Object { "$_.dll".ToLower() }

# --- Project layout ---
$AssetsDir = Join-Path $ProjectRoot "Assets"
$ManifestDir = $AssetsDir
$IconsDir = Join-Path $AssetsDir "Icons"
$StagingDir = Join-Path $ProjectRoot ".build\out\msix-staging"
$OutputDir = Join-Path $ProjectRoot ".build\out"

# --- Required asset files (Windows App SDK / MSIX convention) ---
$RequiredAssets = @(
    "StoreLogo.png",
    "Square150x150Logo.png",
    "Square44x44Logo.png",
    "Wide310x150Logo.png",
    "SplashScreen.png"
)

# --- Required manifest file ---
$RequiredManifest = "AppxManifest.xml"

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
    $line = "  $Name".PadRight(36)
    if ($Version)
    {
        $line += $Version.PadRight(28)
    } else
    {
        $line += "NOT FOUND".PadRight(28)
    }
    $line += $Message
    $color = if ($Version)
    { 'Green' }
    else
    { 'Yellow' }
    Write-Host $line -ForegroundColor $color
}

# --- Try to load the VS developer environment (same as prerequisites.ps1) ---
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
            "ARM64" { "arm64" }
            "AMD64" { "amd64" }
            "x86"   { "x86" }
            default { "amd64" }
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

    # makeappx.exe (Windows SDK)
    $makeAppxPath = Get-CommandPath "makeappx.exe"
    if (-not $makeAppxPath)
    {
        Write-Status "makeappx.exe" -Message "Install Windows SDK 10.0.19041 or later."
        $allSatisfied = $false
    } else
    {
        $makeAppxVersion = (& makeappx.exe 2>&1 | Select-Object -First 1) -replace '^\s*Microsoft\s*\(R\)\s*MakeAppx\s*Tool\s*Version:\s*', ''
        Write-Status "makeappx.exe" "v$makeAppxVersion"
    }

    # signtool.exe (Windows SDK)
    $signToolPath = Get-CommandPath "signtool.exe"
    if (-not $signToolPath)
    {
        Write-Status "signtool.exe" -Message "Install Windows SDK 10.0.19041 or later."
        $allSatisfied = $false
    } else
    {
        $null = & signtool.exe 2>&1
        Write-Status "signtool.exe" "FOUND"
    }

    # Try loading VS developer environment if tools are missing
    if (-not $allSatisfied)
    {
        Write-Host ""
        Write-Host "Attempting to load Visual Studio developer environment..." -ForegroundColor DarkGray
        if (Invoke-VsDevShell)
        {
            Write-Host "  Developer environment loaded. Re-checking tools..." -ForegroundColor DarkGray
            $allSatisfied = $true

            $makeAppxPath = Get-CommandPath "makeappx.exe"
            if ($makeAppxPath)
            {
                $makeAppxVersion = (& makeappx.exe 2>&1 | Select-Object -First 1) -replace '^\s*Microsoft\s*\(R\)\s*MakeAppx\s*Tool\s*Version:\s*', ''
                Write-Status "makeappx.exe" "v$makeAppxVersion"
            } else
            {
                Write-Status "makeappx.exe" -Message "Still not found."
                $allSatisfied = $false
            }

            $signToolPath = Get-CommandPath "signtool.exe"
            if ($signToolPath)
            {
                $null = & signtool.exe 2>&1
                Write-Status "signtool.exe" "FOUND"
            } else
            {
                Write-Status "signtool.exe" -Message "Still not found."
                $allSatisfied = $false
            }
        } else
        {
            Write-Host "  Could not load Visual Studio developer environment automatically." -ForegroundColor Yellow
        }
    }

    Write-Host ""

    if (-not $allSatisfied)
    {
        Write-Host "Some packaging tools are missing." -ForegroundColor Red
        Write-Host "Install the Windows SDK and run this script from a" -ForegroundColor Yellow
        Write-Host "'Developer PowerShell for VS 2022' (or newer)." -ForegroundColor Yellow
        Write-Host "You can also run scripts\prerequisites.ps1 to set up the environment." -ForegroundColor DarkGray
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
        Write-Host "    Create an AppxManifest.xml - see https://learn.microsoft.com/en-us/windows/uwp/design/app-settings/store-and-publish-manifest" -ForegroundColor Yellow
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
        Write-Host "Required files are missing. Place them in $ManifestDir and $IconsDir." -ForegroundColor Red
        Write-Host ""
        Write-Host "Suggested folder structure:" -ForegroundColor Cyan
        Write-Host "  Assets/" -ForegroundColor White
        Write-Host "    AppxManifest.xml" -ForegroundColor DarkGray
        Write-Host "    WindowsPackage.pfx (optional signing cert)" -ForegroundColor DarkGray
        Write-Host "    Icons/" -ForegroundColor White
        Write-Host "      StoreLogo.png           (50x50)" -ForegroundColor DarkGray
        Write-Host "      Square150x150Logo.png   (150x150)" -ForegroundColor DarkGray
        Write-Host "      Square44x44Logo.png     (44x44)" -ForegroundColor DarkGray
        Write-Host "      Wide310x150Logo.png     (310x150)" -ForegroundColor DarkGray
        Write-Host "      SplashScreen.png        (620x300)" -ForegroundColor DarkGray
        exit 1
    }
}

# --- Step 3: Build for release ---
function Build-Release
{
    param([string]$TargetArch)

    Write-Host "Building release ($TargetArch)..." -ForegroundColor Cyan
    Write-Host ""

    & swift build -c release
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "Release build failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit 1
    }
    Write-Host ""
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

    # manifest (makeappx.exe requires AppxManifest.xml)
    Copy-Item -Path (Join-Path $ManifestDir $RequiredManifest) -Destination (Join-Path $StagingDir "AppxManifest.xml") -Force

    # icons
    $stagedIcons = Join-Path $StagingDir "Icons"
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

    # swift runtime DLLs
    $swiftBinDir = Join-Path (Split-Path (Get-CommandPath "swift") -Parent) ""
    $stagedDlls = 0
    if (Test-Path $swiftBinDir)
    {
        Get-ChildItem -Path $swiftBinDir -Filter "*.dll" -File | ForEach-Object {
            $baseName = $_.BaseName.ToLower()
            if ($dllBundlingAllowList -contains "$baseName.dll")
            {
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

    Write-Host ""
}

# --- Step 5: Create the MSIX package ---
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

    & makeappx.exe pack -d $StagingDir -p $msixPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "MSIX packaging failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Package created: $msixPath" -ForegroundColor Green

    return $msixPath
}

# --- Step 6: Sign the package (optional) ---
function Add-PackageSignature
{
    param(
        [string]$PackagePath,
        [string]$CertPath,
        [string]$CertPassword
    )

    Write-Host "Signing package..." -ForegroundColor Cyan
    Write-Host ""

    $pwdArg = if ($CertPassword)
    { "/p $CertPassword" }
    else
    { "" }

    & signtool.exe sign /fd SHA256 /a /f "`"$CertPath`"" $pwdArg "`"$PackagePath`"" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "  Signing failed (exit $LASTEXITCODE)." -ForegroundColor Yellow
        Write-Host "  The MSIX was created unsigned at: $PackagePath" -ForegroundColor Yellow
        Write-Host "  To sign it manually, run in a Developer PowerShell:" -ForegroundColor DarkGray
        Write-Host "    signtool.exe sign /fd SHA256 /a /f `"<path-to.pfx>`" `"$PackagePath`"" -ForegroundColor DarkGray
        Write-Host "  Or pass -CertificatePath and -CertificatePassword to this script." -ForegroundColor DarkGray
        return
    }
    Write-Host "  Package signed." -ForegroundColor Green
}

# --- Self-signed certificate (default) ---
function Ensure-Certificate
{
    $defaultCert = Join-Path $AssetsDir "WindowsPackage.pfx"
    if ($SkipSign)
    {
        return $null
    }
    if ($CertificatePath -and (Test-Path $CertificatePath))
    {
        return @{ Path = $CertificatePath; Password = $CertificatePassword }
    }
    if (Test-Path $defaultCert)
    {
        $pw = if ($CertificatePassword) { $CertificatePassword } else { "password" }
        return @{ Path = $defaultCert; Password = $pw }
    }
    Write-Host "Generating self-signed certificate for testing..." -ForegroundColor Yellow
    Write-Host "  To use your own certificate, pass -CertificatePath and -CertificatePassword." -ForegroundColor DarkGray
    try
    {
        $cert = New-SelfSignedCertificate -Type Custom -Subject "CN=SwiftWinUI3App" -KeyUsage DigitalSignature -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3") -CertStoreLocation "Cert:\CurrentUser\My"
        $pwd = ConvertTo-SecureString -String "password" -Force -AsPlainText
        Export-PfxCertificate -Cert $cert -FilePath $defaultCert -Password $pwd | Out-Null
        Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
        Write-Host "  Generated: $defaultCert" -ForegroundColor Green
        return @{ Path = $defaultCert; Password = "password" }
    }
    catch
    {
        Write-Host "  Certificate generation failed: $_" -ForegroundColor Yellow
        Write-Host "  The MSIX will be created unsigned. Install the Windows SDK and try" -ForegroundColor Yellow
        Write-Host "  passing -CertificatePath and -CertificatePassword with your own cert." -ForegroundColor Yellow
        return $null
    }
}

# --- Main ---
$TargetArch = Resolve-Architecture
$ExeName = "App"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Swift WinUI 3 App - MSIX Packaging" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Architecture: $TargetArch" -ForegroundColor White
Write-Host "  Output dir:   $OutputDir" -ForegroundColor White
Write-Host ""

Test-PackagingTools
Test-PackagingFiles -TargetArch $TargetArch
$cert = Ensure-Certificate
Build-Release -TargetArch $TargetArch
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
if ($cert)
{
    Add-PackageSignature -PackagePath $msixPath -CertPath $cert.Path -CertPassword $cert.Password
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Packaging complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  $msixPath" -ForegroundColor White
Write-Host ""
