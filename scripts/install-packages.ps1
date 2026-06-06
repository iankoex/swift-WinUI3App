param(
    [ValidateSet("x64", "arm64", "x86")]
    [string]$Arch,
    [switch]$Latest
)

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$PlatformDir = Join-Path $ProjectRoot "Platform"
$NugetCache = Join-Path $env:USERPROFILE ".nuget\packages"

# Mapping from package ID to the subpath inside the NuGet package that contains
# the .winmd files swiftwinrt needs to project.
$PackageInputPaths = @{
    "Microsoft.WindowsAppSDK.Foundation"              = "metadata"
    "Microsoft.WindowsAppSDK.WinUI"                   = "metadata"
    "Microsoft.Web.WebView2"                          = "lib\Microsoft.Web.WebView2.Core.winmd"
    "Microsoft.Windows.SDK.Contracts"                 = ""
    "Microsoft.WindowsAppSDK.InteractiveExperiences"  = "metadata\10.0.18362.0"
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

function Get-CachedPackageVersion
{
    param(
        [string]$PackageId,
        [string]$PackagesDir
    )
    $pkgRoot = Join-Path $PackagesDir $PackageId.ToLower()
    if (-not (Test-Path $pkgRoot))
    {
        return $null
    }
    $latest = Get-ChildItem -LiteralPath $pkgRoot -Directory |
        Where-Object { $_.Name -notmatch '-' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $latest)
    {
        return $null
    }
    return $latest.Name
}

function Parse-PackagesConfig
{
    # Reads Platform/packages.config (standard NuGet XML) and returns a list of
    # @{Name; Version} objects. If a version attribute is missing we treat it as
    # $null so the caller can fall back to the latest available version.
    param([string]$ConfigDir)

    $ConfigPath = Join-Path $ConfigDir "packages.config"
    if (-not (Test-Path $ConfigPath))
    {
        Write-Host "packages.config not found at $ConfigPath" -ForegroundColor Red
        exit 1
    }

    [xml]$xml = Get-Content -LiteralPath $ConfigPath
    $Packages = New-Object System.Collections.Generic.List[object]
    foreach ($node in $xml.packages.package)
    {
        $id    = $node.id
        $ver   = if ($node.version) { $node.version } else { $null }
        if ($id)
        {
            $Packages.Add([PSCustomObject]@{ Name = $id; Version = $ver })
        }
    }
    return , $Packages
}

function Invoke-NuGetRestore
{
    # Restores the packages listed in packages.config into the global NuGet cache
    # via `nuget install`. This avoids the C++/WinRT header generation that
    # `winapp restore` does, which a Swift project does not need.
    param(
        [string]$ConfigDir,
        [switch]$Latest
    )

    $nugetCmd = Get-Command "nuget" -ErrorAction SilentlyContinue
    if (-not $nugetCmd)
    {
        Write-Host "nuget.exe not found. Run scripts\prerequisites.ps1 to install it." -ForegroundColor Red
        exit 1
    }

    $Packages = Parse-PackagesConfig -ConfigDir $ConfigDir
    if (-not $Packages -or $Packages.Count -eq 0)
    {
        Write-Host "No packages listed in packages.config" -ForegroundColor Yellow
        return
    }

    foreach ($Pkg in $Packages)
    {
        $args = @("install", $Pkg.Name, "-OutputDirectory", $NugetCache, "-DependencyVersion", "Ignore", "-NonInteractive")
        if ($Pkg.Version -and -not $Latest)
        {
            $args += @("-Version", $Pkg.Version)
        }
        $versionLabel = if ($Latest) { " (latest)" } elseif ($Pkg.Version) { " $($Pkg.Version)" } else { "" }
        Write-Host "  nuget install $($Pkg.Name)$versionLabel" -ForegroundColor DarkGray
        & nuget @args | Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            Write-Host "  nuget install failed for $($Pkg.Name) (exit $LASTEXITCODE)" -ForegroundColor Red
            exit 1
        }
    }
}

function Copy-RequiredDLLs
{
    param(
        [string]$TargetArch
    )

    $DestDir = Join-Path $ProjectRoot "generated\Resources"
    if (-not (Test-Path $DestDir))
    {
        New-Item -ItemType Directory -Path $DestDir | Out-Null
    }

    $Dlls = @(
        "Microsoft.WindowsAppRuntime.Bootstrap.dll"
    )

    $nugetArch = Get-NuGetArch -TargetArch $TargetArch

    # The bootstrap DLL ships inside the WindowsAppSDK.Foundation package (in
    # runtimes\win-<arch>\native\). Search Foundation first, then Runtime, then
    # the metapackage, since the home varies across WinAppSDK releases.
    $PackageCandidates = @(
        "Microsoft.WindowsAppSDK.Foundation",
        "Microsoft.WindowsAppSDK.Runtime",
        "Microsoft.WindowsAppSDK"
    )

    foreach ($DllName in $Dlls)
    {
        $src = $null
        $srcDesc = $null

        foreach ($PackageId in $PackageCandidates)
        {
            $Version = Get-CachedPackageVersion -PackageId $PackageId -PackagesDir $NugetCache
            if (-not $Version) { continue }
            $PkgDir = Join-Path $NugetCache "$($PackageId.ToLower())\$Version"

            $NativeDir = Find-PackageNativeDir -PackageDir $PkgDir -NugetArch $nugetArch
            if ($NativeDir)
            {
                $candidate = Join-Path $NativeDir $DllName
                if (Test-Path $candidate)
                {
                    $src = $candidate
                    $srcDesc = "$PackageId (native folder)"
                    break
                }
            }

            $found = Get-ChildItem -LiteralPath $PkgDir -Recurse -Filter $DllName -File -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -like "*\$nugetArch*" } |
                Select-Object -First 1
            if ($found)
            {
                $src = $found.FullName
                $srcDesc = "$PackageId (recursive search)"
                break
            }
        }

        # Last resort: the .winapp layout, in case `winapp restore` was run
        # separately (e.g. by package.ps1).
        if (-not $src)
        {
            foreach ($sub in @("packaged", ""))
            {
                $base = ".winapp\bin\$TargetArch"
                if ($sub) { $base = "$base\$sub" }
                $candidate = Join-Path $ProjectRoot "$base\$DllName"
                if (Test-Path $candidate)
                {
                    $src = $candidate
                    $srcDesc = ".winapp layout"
                    break
                }
            }
        }

        if ($src)
        {
            Copy-Item -Path $src -Destination (Join-Path $DestDir $DllName) -Force
            Write-Host "  $DllName <- $srcDesc" -ForegroundColor DarkGray
        } else
        {
            Write-Host "  $DllName not found in any candidate package or .winapp\bin\$TargetArch" -ForegroundColor Yellow
        }
    }
}

function Find-PackageNativeDir
{
    # Locates the <arch>/native folder inside a NuGet package. Different WinAppSDK
    # releases use different roots ("runtimes" vs "runtimes-framework"), so we
    # probe the known candidates first and fall back to a recursive search.
    param(
        [string]$PackageDir,
        [string]$NugetArch
    )

    if (-not (Test-Path $PackageDir))
    {
        return $null
    }

    $CandidateRoots = @("runtimes", "runtimes-framework", "runtimes-windowsapp", "native")
    foreach ($Root in $CandidateRoots)
    {
        $Candidate = Join-Path $PackageDir "$Root\$NugetArch\native"
        if (Test-Path $Candidate)
        {
            return $Candidate
        }
    }

    $Match = Get-ChildItem -LiteralPath $PackageDir -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "native" -and $_.Parent.Name -eq $NugetArch } |
        Select-Object -First 1
    if ($Match)
    {
        return $Match.FullName
    }

    return $null
}

function Copy-WinUIResources
{
    param(
        [string]$TargetArch,
        [string]$PackagesDir
    )

    $DestDir = Join-Path $ProjectRoot "generated\Resources"
    if (-not (Test-Path $DestDir))
    {
        New-Item -ItemType Directory -Path $DestDir | Out-Null
    }

    $Version = Get-CachedPackageVersion -PackageId "Microsoft.WindowsAppSDK.WinUI" -PackagesDir $PackagesDir
    if (-not $Version)
    {
        Write-Host "Microsoft.WindowsAppSDK.WinUI not found in $PackagesDir" -ForegroundColor Yellow
        return
    }

    $nugetArch = Get-NuGetArch -TargetArch $TargetArch
    $PackageDir = Join-Path $PackagesDir "microsoft.windowsappsdk.winui\$Version"
    $NativeDir = Find-PackageNativeDir -PackageDir $PackageDir -NugetArch $nugetArch
    if (-not $NativeDir)
    {
        Write-Host "WinUI native runtime folder not found under $PackageDir (arch: $nugetArch)" -ForegroundColor Yellow
        return
    }

    foreach ($FileName in @("Microsoft.UI.Xaml.Controls.pri"))
    {
        $SourcePath = Join-Path $NativeDir $FileName
        if (Test-Path $SourcePath)
        {
            Copy-Item -Path $SourcePath -Destination $DestDir -Force
            Write-Host "  Copied $FileName from $NativeDir" -ForegroundColor DarkGray
        } else
        {
            Write-Host "  Missing WinUI resource file: $FileName (searched $NativeDir)" -ForegroundColor Yellow
        }
    }
}

function Update-SwiftWinRTRsp
{
    param([string]$PackagesDir)

    $RspPath = Join-Path $ProjectRoot "generated\swiftwinrt.rsp"
    if (-not (Test-Path $RspPath))
    {
        Write-Host "swiftwinrt.rsp not found, skipping" -ForegroundColor Yellow
        return
    }

    $Lines = Get-Content -Path $RspPath
    $FilteredLines = @($Lines | Where-Object { $_ -notmatch "^-input\s+.*[/\\]" })

    $GeneratedDir = Join-Path $ProjectRoot "generated"
    for ($i = 0; $i -lt $FilteredLines.Count; $i++)
    {
        if ($FilteredLines[$i] -match "^-output\s+")
        {
            $FilteredLines[$i] = "-output $GeneratedDir"
        }
    }

    $NewInputLines = @()
    foreach ($PackageId in $PackageInputPaths.Keys)
    {
        $Version = Get-CachedPackageVersion -PackageId $PackageId -PackagesDir $PackagesDir
        $InputPath = $PackageInputPaths[$PackageId]

        if ($Version)
        {
            $pkgDir = Join-Path $PackagesDir "$($PackageId.ToLower())\$Version"
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

    $InsertIndex = 0
    for ($i = 0; $i -lt $FilteredLines.Count; $i++)
    {
        if ($FilteredLines[$i] -match "^-input\s+sdk\+")
        {
            $InsertIndex = $i
            break
        }
    }

    $FinalLines = @()
    $FinalLines += $NewInputLines
    $FinalLines += ""
    $FinalLines += $FilteredLines[$InsertIndex..($FilteredLines.Count - 1)]

    $FinalLines | Out-File -FilePath $RspPath -Encoding ascii
    Write-Host "Updated swiftwinrt.rsp" -ForegroundColor Green
}

function Generate-VersionConstant
{
    param([string]$DllPath, [string]$OutPath)

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

    $OutDir = Split-Path $OutPath -Parent
    if (-not (Test-Path $OutDir))
    {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    $Content | Out-File -FilePath $OutPath -Encoding utf8 -Force
    Write-Host "  Wrote $MajorMinor to $OutPath" -ForegroundColor DarkGray
}

# --- Main ---

$TargetArch = Resolve-Architecture
Write-Host "Architecture: $TargetArch" -ForegroundColor Cyan
Write-Host ""

Write-Host "Restoring Windows SDK packages (nuget)..." -ForegroundColor Cyan
if ($Latest)
{
    Write-Host "  (fetching latest versions - ignoring pinned versions in packages.config)" -ForegroundColor DarkGray
} else
{
    Write-Host "  Using versions from packages.config. Use -Latest to install the latest versions." -ForegroundColor White
}
Invoke-NuGetRestore -ConfigDir $PlatformDir -Latest:$Latest
Write-Host ""

Write-Host "Copying required DLLs..." -ForegroundColor Cyan
Copy-RequiredDLLs -TargetArch $TargetArch
Write-Host ""

Write-Host "Copying WinUI resources..." -ForegroundColor Cyan
Copy-WinUIResources -TargetArch $TargetArch -PackagesDir $NugetCache
Write-Host ""

Write-Host "Updating swiftwinrt.rsp..." -ForegroundColor Cyan
Update-SwiftWinRTRsp -PackagesDir $NugetCache
Write-Host ""

Write-Host "Writing WindowsAppRuntimeVersion.swift..." -ForegroundColor Cyan
$BootstrapDll = Join-Path $ProjectRoot "generated\Resources\Microsoft.WindowsAppRuntime.Bootstrap.dll"
$VersionOut = Join-Path $ProjectRoot "generated\Sources\SwiftWinUIApplication\WindowsAppRuntimeVersion.swift"
Generate-VersionConstant -DllPath $BootstrapDll -OutPath $VersionOut
Write-Host ""
