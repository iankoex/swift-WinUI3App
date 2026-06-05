Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Swift WinUI 3 App - Full Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Prerequisites ---
Write-Host "Step 1: Checking prerequisites..." -ForegroundColor Cyan
& "$PSScriptRoot\prerequisites.ps1"
if ($LASTEXITCODE -ne 0)
{
    Write-Host "Prerequisites check failed. Please resolve the issues above and re-run." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Step 2: Install NuGet packages ---
Write-Host "Step 2: Installing NuGet packages..." -ForegroundColor Cyan
& "$PSScriptRoot\install-packages.ps1" @args
if ($LASTEXITCODE -ne 0)
{
    Write-Host "NuGet package installation failed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Step 3: Generate Swift/WinRT bindings ---
Write-Host "Step 3: Generating Swift/WinRT bindings..." -ForegroundColor Cyan
& "$PSScriptRoot\generate-bindings.ps1" @args
if ($LASTEXITCODE -ne 0)
{
    Write-Host "Binding generation failed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Step 4: Generate icon resource ---
Write-Host "Step 4: Generating icon resource..." -ForegroundColor Cyan
& "$PSScriptRoot\generate-icon-resource.ps1"
if ($LASTEXITCODE -ne 0)
{
    Write-Host "Icon resource generation failed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Done ---
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  swift run App -c debug" -ForegroundColor DarkGray
Write-Host ""
