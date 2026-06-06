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

# --- Step 2: Build swiftwinrt.exe (skip if already present) ---
Write-Host "Step 2: Ensuring swiftwinrt.exe is available..." -ForegroundColor Cyan
& "$PSScriptRoot\install-swiftwinrt.ps1"
if ($LASTEXITCODE -ne 0)
{
    Write-Host "swiftwinrt setup failed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Step 3: Restore SDK packages + stage runtime resources ---
Write-Host "Step 3: Restoring SDK packages and staging resources..." -ForegroundColor Cyan
& "$PSScriptRoot\install-packages.ps1" @args
if ($LASTEXITCODE -ne 0)
{
    Write-Host "SDK package restore failed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Step 4: Generate MSIX icon assets and AppIcon.res ---
Write-Host "Step 4: Generating icon assets..." -ForegroundColor Cyan
& "$PSScriptRoot\generate-icon-resource.ps1"
if ($LASTEXITCODE -ne 0)
{
    Write-Host "Icon asset generation failed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Step 5: Generate Swift/WinRT bindings ---
Write-Host "Step 5: Generating Swift/WinRT bindings..." -ForegroundColor Cyan
& "$PSScriptRoot\generate-bindings.ps1"
if ($LASTEXITCODE -ne 0)
{
    Write-Host "Binding generation failed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Done ---
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  swift run App -c debug         # build and run unpackaged" -ForegroundColor DarkGray
Write-Host "  .\scripts\package.ps1          # build and sign a self-contained MSIX" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Template placeholders to update in Platform\Package.appxmanifest:" -ForegroundColor White
Write-Host "  Identity.Name            (e.g. Contoso.MyApp)" -ForegroundColor DarkGray
Write-Host "  Identity.Publisher       (must match your signing cert)" -ForegroundColor DarkGray
Write-Host "  Identity.Version         (bump on every submission)" -ForegroundColor DarkGray
Write-Host "  Properties.DisplayName" -ForegroundColor DarkGray
Write-Host ""
