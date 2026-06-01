param(
    [ValidateSet("x64", "arm64", "x86")]
    [string]$Arch
)

$RequiredDLLs = @(
    "Microsoft.WindowsAppRuntime.Bootstrap.dll"
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent

$PackageIds = @(
    "Microsoft.WindowsAppSDK.Foundation",
    "Microsoft.WindowsAppSDK.WinUI",
    "Microsoft.Web.WebView2",
    "Microsoft.Windows.SDK.Contracts",
    "Microsoft.WindowsAppSDK.InteractiveExperiences"
)

$PackageInputPaths = @{
    "Microsoft.WindowsAppSDK.Foundation" = "metadata"
    "Microsoft.WindowsAppSDK.WinUI"      = "metadata"
    "Microsoft.Web.WebView2"             = "lib\Microsoft.Web.WebView2.Core.winmd"
    "Microsoft.Windows.SDK.Contracts"    = ""
    "Microsoft.WindowsAppSDK.InteractiveExperiences" = "metadata\10.0.18362.0"
}

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

function Get-NuGetArch
{
    param([string]$TargetArch)
    return "win-$TargetArch"
}

function Get-LatestStableVersion
{
    param([string]$PackageId)
    $url = "https://api.nuget.org/v3-flatcontainer/$($PackageId.ToLower())/index.json"
    $response = Invoke-RestMethod -Uri $url
    $stableVersions = $response.versions | Where-Object { $_ -notmatch '-' }
    if (-not $stableVersions)
    {
        Write-Host "No stable version found for $PackageId" -ForegroundColor Red
        exit 1
    }
    return $stableVersions | Select-Object -Last 1
}

function Restore-Nuget
{
    param(
        [string]$PackagesDir,
        [hashtable]$ResolvedPackages
    )

    $NugetDownloadPath = Join-Path $env:TEMP "nuget.exe"
    if (-not (Test-Path $NugetDownloadPath))
    {
        Write-Host "Downloading nuget.exe..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $NugetDownloadPath
    }

    $PackagesConfigContent = "<?xml version=""1.0"" encoding=""utf-8""?>`n"
    $PackagesConfigContent += "<packages>`n"
    foreach ($entry in $ResolvedPackages.GetEnumerator())
    {
        $PackagesConfigContent += "  <package id=""$($entry.Key)"" version=""$($entry.Value)"" />`n"
    }
    $PackagesConfigContent += "</packages>"

    if (-not (Test-Path $PackagesDir))
    {
        New-Item -ItemType Directory -Path $PackagesDir | Out-Null
    }

    $PackagesConfigPath = Join-Path $PackagesDir "packages.config"
    $PackagesConfigContent | Out-File -FilePath $PackagesConfigPath -Encoding ascii

    & $NugetDownloadPath restore $PackagesConfigPath -PackagesDirectory $PackagesDir
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "NuGet restore failed with error code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
}

function Copy-RequiredDLLs
{
    param(
        [string]$PackagesDir,
        [hashtable]$ResolvedPackages,
        [string]$TargetArch
    )

    $DestDir = Join-Path $ProjectRoot "generated\Resources"
    if (-not (Test-Path $DestDir))
    {
        New-Item -ItemType Directory -Path $DestDir | Out-Null
    }

    $nugetArch = Get-NuGetArch -TargetArch $TargetArch

    foreach ($entry in $ResolvedPackages.GetEnumerator())
    {
        $PackageId = $entry.Key
        $Version = $entry.Value
        $PackageDir = Join-Path $PackagesDir "$PackageId.$Version"

        foreach ($DllName in $RequiredDLLs)
        {
            $Found = Get-ChildItem -Path $PackageDir -Filter $DllName -Recurse -File |
                Where-Object { $_.DirectoryName -match "$nugetArch\\native" } |
                Select-Object -First 1

            if ($Found)
            {
                Copy-Item -Path $Found.FullName -Destination $DestDir -Force
            }
        }
    }

    $Copied = Get-ChildItem -Path $DestDir -Filter *.dll -File
    foreach ($dll in $Copied)
    {
        Write-Host "  $($dll.Name)" -ForegroundColor DarkGray
    }
}

function Copy-WinUIResources
{
    param(
        [string]$PackagesDir,
        [hashtable]$ResolvedPackages,
        [string]$TargetArch
    )

    $DestDir = Join-Path $ProjectRoot "generated\Resources"
    if (-not (Test-Path $DestDir))
    {
        New-Item -ItemType Directory -Path $DestDir | Out-Null
    }

    $WinUIPackageId = "Microsoft.WindowsAppSDK.WinUI"
    $Version = $ResolvedPackages[$WinUIPackageId]
    if (-not $Version)
    {
        Write-Host "WinUI package version not found in resolved packages." -ForegroundColor Yellow
        return
    }

    $nugetArch = Get-NuGetArch -TargetArch $TargetArch
    $NativeDir = Join-Path $PackagesDir "$WinUIPackageId.$Version\runtimes-framework\$nugetArch\native"
    if (-not (Test-Path $NativeDir))
    {
        Write-Host "WinUI native runtime folder not found: $NativeDir" -ForegroundColor Yellow
        return
    }

    $AssetFiles = @(
        "Microsoft.UI.Xaml.Controls.pri"
    )

    foreach ($FileName in $AssetFiles)
    {
        $SourcePath = Join-Path $NativeDir $FileName
        if (Test-Path $SourcePath)
        {
            Copy-Item -Path $SourcePath -Destination $DestDir -Force
            Write-Host "  Copied $FileName" -ForegroundColor DarkGray
        } else
        {
            Write-Host "  Missing WinUI resource file: $FileName" -ForegroundColor Yellow
        }
    }
}

function Generate-VersionConstant
{
    param([string]$ProjectRoot)

    $DllPath = Join-Path $ProjectRoot "generated\Resources\Microsoft.WindowsAppRuntime.Bootstrap.dll"
    if (-not (Test-Path $DllPath))
    {
        Write-Host "  Bootstrap DLL not found at $DllPath, skipping" -ForegroundColor Yellow
        return
    }

    $Version = (Get-Item $DllPath).VersionInfo.FileVersionRaw
    $MajorMinor = "0x{0:X8}" -f (($Version.Major -shl 16) -bor $Version.Minor)

    $Content = @"
// Auto-generated from bootstrap DLL file version ($($Version.Major).$($Version.Minor).$($Version.Build).$($Version.Revision))
internal let WINDOWSAPPSDK_RELEASE_MAJORMINOR: UInt32 = $MajorMinor
"@

    $OutPath = Join-Path $ProjectRoot "generated\Sources\SwiftWinUIApplication\WindowsAppRuntimeVersion.swift"
    $Content | Out-File -FilePath $OutPath -Encoding utf8 -Force
    Write-Host "  Wrote $MajorMinor to $OutPath" -ForegroundColor DarkGray
}

function Update-SwiftWinRTRsp
{
    param(
        [string]$PackagesDir,
        [hashtable]$ResolvedPackages
    )

    $RspPath = Join-Path $ProjectRoot "generated\swiftwinrt.rsp"
    if (-not (Test-Path $RspPath))
    {
        Write-Host "swiftwinrt.rsp not found, skipping" -ForegroundColor Yellow
        return
    }

    $Lines = Get-Content -Path $RspPath

    # Filter out old NuGet package -input lines (those with path separators)
    $FilteredLines = @($Lines | Where-Object { $_ -notmatch "^-input\s+.*[/\\]" })

    # Replace absolute -output path with project-relative path
    $GeneratedDir = Join-Path $ProjectRoot "generated"
    for ($i = 0; $i -lt $FilteredLines.Count; $i++)
    {
        if ($FilteredLines[$i] -match "^-output\s+")
        {
            $FilteredLines[$i] = "-output $GeneratedDir"
        }
    }

    # Build new -input lines for packages using absolute paths
    $NewInputLines = @()

    foreach ($PackageId in $PackageIds)
    {
        $Version = $ResolvedPackages[$PackageId]
        $InputPath = $PackageInputPaths[$PackageId]

        if ($Version)
        {
            $pkgDir = Join-Path $PackagesDir "$PackageId.$Version"
            $FullInputPath = if ($InputPath)
            { Join-Path $pkgDir $InputPath 
            } else
            { $pkgDir 
            }

            if (Test-Path $FullInputPath)
            {
                $NewInputLines += "-input $FullInputPath"
            } else
            {
                Write-Host "Input path not found for $PackageId : $FullInputPath" -ForegroundColor Yellow
            }
        }
    }

    # Find insertion point: before -input sdk+
    $InsertIndex = 0
    for ($i = 0; $i -lt $FilteredLines.Count; $i++)
    {
        if ($FilteredLines[$i] -match "^-input\s+sdk\+")
        {
            $InsertIndex = $i
            break
        }
    }

    # Build final content (strip leading empty lines, add blank line before -input sdk+)
    $FinalLines = @()
    $FinalLines += $NewInputLines
    $FinalLines += ""
    $FinalLines += $FilteredLines[$InsertIndex..($FilteredLines.Count - 1)]

    $FinalLines | Out-File -FilePath $RspPath -Encoding ascii
    Write-Host "Updated swiftwinrt.rsp" -ForegroundColor Green
    Write-Host ""
}

# --- Main ---

$TargetArch = Resolve-Architecture
Write-Host "Architecture: $TargetArch" -ForegroundColor Cyan
Write-Host ""

Write-Host "Installing packages..." -ForegroundColor Cyan
$ResolvedPackages = @{}
foreach ($PackageId in $PackageIds)
{
    $Version = Get-LatestStableVersion -PackageId $PackageId
    $ResolvedPackages[$PackageId] = $Version
}

$PackagesDir = Join-Path $ProjectRoot ".nuget-packages"
Restore-Nuget -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages
Write-Host ""

Write-Host ("Package".PadRight(55) + "Version") -ForegroundColor White
Write-Host ("-" * 55 + "-" * 20) -ForegroundColor DarkGray
foreach ($entry in $ResolvedPackages.GetEnumerator())
{
    Write-Host ($entry.Key.PadRight(55) + $entry.Value) -ForegroundColor Green
}
Write-Host ""

Write-Host "Copying required DLLs..." -ForegroundColor Cyan
Copy-RequiredDLLs -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages -TargetArch $TargetArch
Write-Host ""

Write-Host "Copying WinUI resources..." -ForegroundColor Cyan
Copy-WinUIResources -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages -TargetArch $TargetArch
Write-Host ""

Write-Host "Updating version constant from bootstrap DLL..." -ForegroundColor Cyan
Generate-VersionConstant -ProjectRoot $ProjectRoot
Write-Host ""

Update-SwiftWinRTRsp -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages
