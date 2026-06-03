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

function Invoke-WithRetry
{
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 3,
        [string]$Label = "operation"
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++)
    {
        try
        {
            return & $ScriptBlock
        } catch
        {
            if ($attempt -lt $MaxAttempts)
            {
                $wait = [Math]::Pow(2, $attempt)
                Write-Host "  $Label failed (attempt $attempt/$MaxAttempts), retrying in ${wait}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $wait
            } else
            {
                Write-Host "  $Label failed after $MaxAttempts attempts" -ForegroundColor Red
                throw
            }
        }
    }
}

function Get-LatestStableVersion
{
    param([string]$PackageId)
    $url = "https://api.nuget.org/v3-flatcontainer/$($PackageId.ToLower())/index.json"
    $json = Invoke-WithRetry -Label "Version lookup for $PackageId" -ScriptBlock {
        Invoke-RestMethod -Uri $url -TimeoutSec 30 -ErrorAction Stop
    }
    if (-not $json.versions)
    {
        throw "Unexpected response for $PackageId"
    }
    $stableVersions = $json.versions | Where-Object { $_ -notmatch '-' }
    if (-not $stableVersions)
    {
        throw "$PackageId has no stable release"
    }
    return $stableVersions | Select-Object -Last 1
}

function Resolve-PackageVersions
{
    param([string[]]$PackageIds)

    $jobs = @()
    $jobMap = @{}

    $i = 0
    foreach ($packageId in $PackageIds)
    {
        if ($i -gt 0)
        { Start-Sleep -Milliseconds 200
        }
        $i++
        $job = Start-Job -Name $packageId -ScriptBlock {
            param($id)
            $url = "https://api.nuget.org/v3-flatcontainer/$($id.ToLower())/index.json"
            $json = Invoke-RestMethod -Uri $url -TimeoutSec 100 -ErrorAction Stop
            if (-not $json.versions)
            { throw "Unexpected response for $id"
            }
            $stable = $json.versions | Where-Object { $_ -notmatch '-' }
            if (-not $stable)
            { throw "$id has no stable release"
            }
            return @{ PackageId = $id; Version = $stable | Select-Object -Last 1 }
        } -ArgumentList $packageId
        $jobs += $job
        $jobMap[$job.Id] = $packageId
    }

    Write-Host "  Resolving $(@($PackageIds).Count) package versions in parallel..." -ForegroundColor DarkGray

    $resolved = @{}
    $failed = $false
    $total = $jobs.Count
    $completed = 0

    while ($jobs.Count -gt 0)
    {
        $done = Wait-Job -Job $jobs -Any

        foreach ($job in $done)
        {
            $completed++
            Write-Progress -Activity "Resolving package versions" -Status "$completed of $total" -PercentComplete (($completed / $total) * 100)

            $result = Receive-Job -Job $job
            if ($job.State -eq "Failed")
            {
                $errorMsg = $job.ChildJobs[0].Error[0].Exception.Message
                Write-Host "  Failed to resolve version for $($jobMap[$job.Id]): $errorMsg" -ForegroundColor Red
                $failed = $true
            } else
            {
                $resolved[$result.PackageId] = $result.Version
                Write-Host "  $($result.PackageId) -> $($result.Version)" -ForegroundColor DarkGray
            }
            Remove-Job -Job $job
            $jobs = $jobs | Where-Object { $_.Id -ne $job.Id }
        }
    }

    Write-Progress -Activity "Resolving package versions" -Completed

    if ($failed)
    {
        exit 1
    }

    return $resolved
}

function Restore-Packages
{
    param(
        [string]$PackagesDir,
        [hashtable]$ResolvedPackages
    )

    $NugetPath = Join-Path $env:TEMP "nuget.exe"
    if (-not (Test-Path $NugetPath))
    {
        Write-Host "  nuget.exe not found at $NugetPath" -ForegroundColor Red
        Write-Host "  Run prerequisites.ps1 first or manually download nuget.exe to that path." -ForegroundColor Yellow
        exit 1
    }

    if (-not (Test-Path $PackagesDir))
    {
        New-Item -ItemType Directory -Path $PackagesDir | Out-Null
    }

    # Filter out already-cached packages
    $missingPackages = @{}
    foreach ($entry in $ResolvedPackages.GetEnumerator())
    {
        $pkgDir = Join-Path $PackagesDir "$($entry.Key).$($entry.Value)"
        if (Test-Path $pkgDir)
        {
            Write-Host "  $($entry.Key) $($entry.Value) (cached)" -ForegroundColor DarkGray
        } else
        {
            $missingPackages[$entry.Key] = $entry.Value
        }
    }

    if ($missingPackages.Count -eq 0)
    {
        Write-Host "  All packages are already cached" -ForegroundColor Green
        return
    }

    $PackagesConfigContent = "<?xml version=""1.0"" encoding=""utf-8""?>`n"
    $PackagesConfigContent += "<packages>`n"
    foreach ($entry in $missingPackages.GetEnumerator())
    {
        $PackagesConfigContent += "  <package id=""$($entry.Key)"" version=""$($entry.Value)"" />`n"
    }
    $PackagesConfigContent += "</packages>"

    $PackagesConfigPath = Join-Path $PackagesDir "packages.config"
    $PackagesConfigContent | Out-File -FilePath $PackagesConfigPath -Encoding ascii

    $env:NUGET_DISABLE_VULNERABILITY_CHECK = '1'
    & $NugetPath restore $PackagesConfigPath -PackagesDirectory $PackagesDir -Verbosity quiet
    Remove-Item Env:\NUGET_DISABLE_VULNERABILITY_CHECK -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "  NuGet restore failed with error code $LASTEXITCODE" -ForegroundColor Red
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
    Write-Host ""
}

function Install-WindowsAppRuntime
{
    param(
        [string]$ProjectRoot,
        [string]$TargetArch
    )

    $ArchMap = @{ "x64" = "X64"; "arm64" = "ARM64"; "x86" = "X86" }
    $SysArch = $ArchMap[$TargetArch]
    if (-not $SysArch)
    {
        Write-Host "  Unknown target architecture: $TargetArch" -ForegroundColor Yellow
        return
    }

    $Packages = Get-AppxPackage -Name "Microsoft.WindowsAppRuntime.*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "\.CBS\." -and $_.Architecture -eq $SysArch }

    if (-not $Packages)
    {
        Write-Host "  Windows App Runtime not found for architecture $TargetArch." -ForegroundColor Yellow
        Write-Host "  Download and install the latest runtime (as Administrator):" -ForegroundColor Yellow
        Write-Host "  https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads" -ForegroundColor Cyan
        return
    }

    $Packages = $Packages | ForEach-Object {
        $sdkVer = $_.Name -replace '^Microsoft\.WindowsAppRuntime\.', ''
        if ($sdkVer -notmatch '\.')
        { $sdkVer = "$sdkVer.0"
        }
        $_ | Add-Member -NotePropertyName SdkVersion -NotePropertyValue ([System.Version]$sdkVer) -PassThru
    }

    Write-Host "Updating Windows App Runtime..." -ForegroundColor Cyan
    $Packages | Sort-Object SdkVersion -Descending | ForEach-Object {
        Write-Host ("  " + $_.Name.PadRight(40) + "SDK " + $_.SdkVersion.ToString().PadRight(12) + "v" + $_.Version.ToString().PadRight(20) + $_.Architecture) -ForegroundColor DarkGray
    }

    $Latest = $Packages | Sort-Object -Property SdkVersion -Descending | Select-Object -First 1
    Write-Host ("  " + "Selected: " + $Latest.Name + " (SDK " + $Latest.SdkVersion + ")") -ForegroundColor Green

    $SysDll = Get-ChildItem -Path $Latest.InstallLocation -Filter "Microsoft.WindowsAppRuntime.dll" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "Microsoft.WindowsAppRuntime.dll" -and $_.DirectoryName -eq $Latest.InstallLocation } |
        Select-Object -First 1

    if (-not $SysDll)
    {
        Write-Host "  System runtime DLL not found in $($Latest.Name)" -ForegroundColor Yellow
        return
    }

    $Ver = $SysDll.VersionInfo.FileVersionRaw
    $Major = $Ver.Major
    $Minor = $Ver.Minor

    $MajorMinor = "0x{0:X8}" -f (($Major -shl 16) -bor $Minor)
    $Content = @"
// Auto-generated from system runtime $($Latest.Name) (v$Major.$Minor)
internal let WINDOWSAPPSDK_RELEASE_MAJORMINOR: UInt32 = $MajorMinor
"@

    $OutPath = Join-Path $ProjectRoot "generated\Sources\SwiftWinUIApplication\WindowsAppRuntimeVersion.swift"
    $OutDir = Split-Path $OutPath -Parent
    if (-not (Test-Path $OutDir))
    {
        New-Item -ItemType Directory -Path $OutDir | Out-Null
    }
    $Content | Out-File -FilePath $OutPath -Encoding utf8 -Force
    Write-Host "  System runtime $($Latest.Name) v$Major.$Minor ($MajorMinor)" -ForegroundColor DarkGray
}

# --- Main ---

$TargetArch = Resolve-Architecture
Write-Host "Architecture: $TargetArch" -ForegroundColor Cyan
Write-Host ""

$PackagesDir = Join-Path $ProjectRoot ".nuget-packages"
Write-Host "Installing packages..." -ForegroundColor Cyan

$ResolvedPackages = Resolve-PackageVersions -PackageIds $PackageIds

Write-Host "  Downloading packages (nuget.exe)..." -ForegroundColor DarkGray
Restore-Packages -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages
Write-Host ""

Write-Host ("Package".PadRight(55) + "Version") -ForegroundColor White
Write-Host ("-" * 55 + "-" * 20) -ForegroundColor DarkGray
foreach ($entry in $ResolvedPackages.GetEnumerator())
{
    Write-Host ($entry.Key.PadRight(55) + $entry.Value) -ForegroundColor Green
}
Write-Host ""

Install-WindowsAppRuntime -ProjectRoot $ProjectRoot -TargetArch $TargetArch
Write-Host ""

Write-Host "Copying required DLLs..." -ForegroundColor Cyan
Copy-RequiredDLLs -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages -TargetArch $TargetArch
Write-Host ""

Write-Host "Copying WinUI resources..." -ForegroundColor Cyan
Copy-WinUIResources -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages -TargetArch $TargetArch
Write-Host ""

Update-SwiftWinRTRsp -PackagesDir $PackagesDir -ResolvedPackages $ResolvedPackages
