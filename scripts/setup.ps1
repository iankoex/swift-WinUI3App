& "$PSScriptRoot\install-packages.ps1" @args
if ($LASTEXITCODE -ne 0)
{ exit $LASTEXITCODE
}

& "$PSScriptRoot\generate-bindings.ps1" @args
if ($LASTEXITCODE -ne 0)
{ exit $LASTEXITCODE
}
