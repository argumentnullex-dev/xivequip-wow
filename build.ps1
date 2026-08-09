$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "publish-build.ps1"
& $script @args
exit $LASTEXITCODE
