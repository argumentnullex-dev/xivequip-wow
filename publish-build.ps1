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

if (-not (Test-Path -LiteralPath $AddonDir)) {
    throw "XIVEquip directory not found at expected path: $AddonDir"
}
if (-not (Test-Path -LiteralPath $TocPath)) {
    throw "XIVEquip.toc not found at expected path: $TocPath"
}

if ([string]::IsNullOrWhiteSpace($ArchiveDir)) {
    $ArchiveDir = [Environment]::GetEnvironmentVariable("XIVEQUIP_ARCHIVE_DIR", "User")
    if ([string]::IsNullOrWhiteSpace($ArchiveDir)) {
        $ArchiveDir = Join-Path $PSScriptRoot "..\XIVEquipArchives"
    }
}

$currentVersion = Get-TocVersion -Path $TocPath
$releaseVersion = $currentVersion -replace "-dev\.\d+$", ""

if ($releaseVersion -ne $currentVersion) {
    Set-TocVersion -Path $TocPath -Version $releaseVersion
    Write-Host "Publish version: $currentVersion -> $releaseVersion" -ForegroundColor Green
} else {
    Write-Host "Publish version: $releaseVersion" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $ArchiveDir)) {
    New-Item -ItemType Directory -Path $ArchiveDir | Out-Null
}

$zipName = "XIVEquip-$releaseVersion.zip"
$zipPath = Join-Path $ArchiveDir $zipName

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive `
    -Path $AddonDir `
    -DestinationPath $zipPath `
    -CompressionLevel Optimal

Write-Host "Build complete:" -ForegroundColor Green
Write-Host "  $zipPath"
