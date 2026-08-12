param(
    [ValidateSet("Copy", "Junction")]
    [string]$Mode = "Copy",

    [string]$AddonPath = $env:XIVEQUIP_ADDON_PATH,

    [string]$ArchiveDir = $env:XIVEQUIP_ARCHIVE_DIR,

    [switch]$SkipTests,
    [switch]$RequireTests,

    [switch]$NoInstall,
    [switch]$NoArchive
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

# A release candidate always drops any -dev.N suffix -- a dev build is never
# itself a candidate, it's what led up to one. Once on -rc.N, repeated runs
# just bump N (a new candidate cut for the same target release), mirroring
# dev-build.ps1's own "bump whatever suffix is already there" behavior.
function Get-NextRcVersion {
    param([string]$Version)

    if ($Version -notmatch "^(?<Base>\d+\.\d+\.\d+)(?:-(?<Pre>dev|rc)\.(?<Num>\d+))?$") {
        throw "Version '$Version' does not match x.y.z, x.y.z-dev.N, or x.y.z-rc.N."
    }

    $base = $Matches.Base
    if ($Matches.Pre -eq "rc") {
        return "$base-rc.$([int]$Matches.Num + 1)"
    }

    return "$base-rc.1"
}

if (-not (Test-Path -LiteralPath $AddonDir)) {
    throw "XIVEquip directory not found at expected path: $AddonDir"
}
if (-not (Test-Path -LiteralPath $TocPath)) {
    throw "XIVEquip.toc not found at expected path: $TocPath"
}

if ([string]::IsNullOrWhiteSpace($AddonPath)) {
    $AddonPath = [Environment]::GetEnvironmentVariable("XIVEQUIP_ADDON_PATH", "User")
}
if ([string]::IsNullOrWhiteSpace($ArchiveDir)) {
    $ArchiveDir = [Environment]::GetEnvironmentVariable("XIVEQUIP_ARCHIVE_DIR", "User")
    if ([string]::IsNullOrWhiteSpace($ArchiveDir)) {
        $ArchiveDir = Join-Path $PSScriptRoot "..\XIVEquipArchives"
    }
}

if (-not $SkipTests) {
    $testScript = Join-Path $RepoRoot "tools\test.ps1"
    if (Test-Path -LiteralPath $testScript) {
        $luaCandidates = @("lua", "lua54", "lua5.4", "luajit")
        $lua = $luaCandidates | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
        if ($lua) {
            & $testScript
            if ($LASTEXITCODE -ne 0) {
                throw "Offline test suite failed -- a release candidate must not ship with failing tests. Rerun with -SkipTests only if you're certain."
            }
        } elseif ($RequireTests) {
            throw "No Lua runtime found. Install lua, lua54, lua5.4, or luajit, or rerun without -RequireTests."
        } else {
            Write-Warning "No Lua runtime found; skipping offline tests. Use -RequireTests to enforce them."
        }
    }
}

$currentVersion = Get-TocVersion -Path $TocPath
$nextVersion = Get-NextRcVersion -Version $currentVersion
Set-TocVersion -Path $TocPath -Version $nextVersion

Write-Host "Release candidate version: $currentVersion -> $nextVersion" -ForegroundColor Green

if (-not $NoInstall) {
    if ([string]::IsNullOrWhiteSpace($AddonPath)) {
        throw "No addon install path configured. Set XIVEQUIP_ADDON_PATH, pass -AddonPath, or run .\init-env.ps1."
    }

    $targetDir = $AddonPath
    $addonRoot = Split-Path -Parent $targetDir

    if (-not (Test-Path -LiteralPath $addonRoot)) {
        New-Item -ItemType Directory -Path $addonRoot | Out-Null
    }

    if (Test-Path -LiteralPath $targetDir) {
        Remove-Item -LiteralPath $targetDir -Recurse -Force
    }

    if ($Mode -eq "Junction") {
        New-Item -ItemType Junction -Path $targetDir -Target $AddonDir | Out-Null
        Write-Host "Installed addon junction:" -ForegroundColor Green
    } else {
        Copy-Item -LiteralPath $AddonDir -Destination $addonRoot -Recurse -Force
        Write-Host "Installed addon copy:" -ForegroundColor Green
    }

    Write-Host "  $targetDir"
}

if (-not $NoArchive) {
    if (-not (Test-Path -LiteralPath $ArchiveDir)) {
        New-Item -ItemType Directory -Path $ArchiveDir | Out-Null
    }

    # Unlike publish-build.ps1's final-release zip, a candidate's archived
    # copy keeps the -rc.N suffix in both the filename and its own toc --
    # it must be visibly distinct from (and never overwrite) a real release
    # zip for the same x.y.z, and multiple candidates for one release need
    # to coexist so testers can tell which cut they're running.
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("XIVEquipRC-" + [System.Guid]::NewGuid().ToString("N"))
    $stagingAddonDir = Join-Path $stagingRoot "XIVEquip"

    $zipName = "XIVEquip-$nextVersion.zip"
    $zipPath = Join-Path $ArchiveDir $zipName

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    try {
        New-Item -ItemType Directory -Path $stagingRoot | Out-Null
        Copy-Item -LiteralPath $AddonDir -Destination $stagingRoot -Recurse -Force

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

    Write-Host "Archived release candidate:" -ForegroundColor Green
    Write-Host "  $zipPath"
}
