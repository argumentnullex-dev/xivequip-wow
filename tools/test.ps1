$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$candidates = @("lua", "lua54", "lua5.4", "luajit")

foreach ($candidate in $candidates) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
        & $cmd.Source (Join-Path $repoRoot "tests\runner.lua") $repoRoot
        exit $LASTEXITCODE
    }
}

Write-Error "No Lua runtime found. Install lua, lua54, lua5.4, or luajit to run the offline tests."
exit 1
