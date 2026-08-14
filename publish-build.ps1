param(
    [string]$ArchiveDir = $env:XIVEQUIP_ARCHIVE_DIR
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$AddonDir = Join-Path $RepoRoot "XIVEquip"
$TocPath = Join-Path $AddonDir "XIVEquip.toc"

function Get-TocVersion {
    param([string]$Path)

    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^##\s*Version:" } | Select-Object -First 1
    if (-not $line) {
        throw "No '## Version:' line found in $Path."
    }

    return ($line -replace "^##\s*Version:\s*", "").Trim()
}

function Set-TocVersion {
    param(
        [string]$Path,
        [string]$Version
    )

    $content = Get-Content -LiteralPath $Path
    $updated = $content | ForEach-Object {
        if ($_ -match "^##\s*Version:") {
            "## Version: $Version"
        } else {
            $_
        }
    }
    Set-Content -LiteralPath $Path -Value $updated
}

# Final publishing accepts a clean release version or either development
# suffix used by this repository. In every case the archive and staged TOC
# receive the bare x.y.z release:
#   2.0.0-dev.99 -> 2.0.0
#   2.0.0-rc.12  -> 2.0.0
#   2.0.0        -> 2.0.0
function Get-ReleaseVersion {
    param([string]$Version)

    if ($Version -notmatch "^(?<Base>\d+\.\d+\.\d+)(?:-(?:dev|rc)\.\d+)?$") {
        throw "Version '$Version' does not match x.y.z, x.y.z-dev.N, or x.y.z-rc.N."
    }

    return $Matches.Base
}

if (-not (Test-Path -LiteralPath $AddonDir)) {
    throw "XIVEquip directory not found at expected path: $AddonDir"
}
if (-not (Test-Path -LiteralPath $TocPath)) {
    throw "XIVEquip.toc not found at expected path: $TocPath"
}

# A final release is never allowed to silently skip verification. The shared
# test entry point already owns supported-Lua discovery and produces a clear
# error when no runtime is installed, so publishing reuses it unconditionally
# instead of copying RC's optional-test machinery or exposing a normal skip.
$testScript = Join-Path $RepoRoot "tools\test.ps1"
if (-not (Test-Path -LiteralPath $testScript)) {
    throw "Offline test runner not found at expected path: $testScript"
}

Write-Host "Running required offline test suite..." -ForegroundColor Cyan
& $testScript
if ($LASTEXITCODE -ne 0) {
    throw "Offline test suite failed -- final publishing is blocked."
}

if ([string]::IsNullOrWhiteSpace($ArchiveDir)) {
    $ArchiveDir = [Environment]::GetEnvironmentVariable("XIVEQUIP_ARCHIVE_DIR", "User")
    if ([string]::IsNullOrWhiteSpace($ArchiveDir)) {
        $ArchiveDir = Join-Path $PSScriptRoot "..\XIVEquipArchives"
    }
}

$currentVersion = Get-TocVersion -Path $TocPath
$releaseVersion = Get-ReleaseVersion -Version $currentVersion

if ($releaseVersion -ne $currentVersion) {
    Write-Host "Publish version: $currentVersion -> $releaseVersion" -ForegroundColor Green
} else {
    Write-Host "Publish version: $releaseVersion" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $ArchiveDir)) {
    New-Item -ItemType Directory -Path $ArchiveDir | Out-Null
}

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("XIVEquipPublish-" + [System.Guid]::NewGuid().ToString("N"))
$stagingAddonDir = Join-Path $stagingRoot "XIVEquip"
$stagingTocPath = Join-Path $stagingAddonDir "XIVEquip.toc"

$zipName = "XIVEquip-$releaseVersion.zip"
$zipPath = Join-Path $ArchiveDir $zipName

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

try {
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    Copy-Item -LiteralPath $AddonDir -Destination $stagingRoot -Recurse -Force
    Set-TocVersion -Path $stagingTocPath -Version $releaseVersion

    Compress-Archive `
        -Path $stagingAddonDir `
        -DestinationPath $zipPath `
        -CompressionLevel Optimal
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

Write-Host "Build complete:" -ForegroundColor Green
Write-Host "  $zipPath"
