param(
    [ValidateSet("Patch", "Minor", "Major")]
    [string]$Bump = "Patch",

    [ValidateSet("Copy", "Junction")]
    [string]$Mode = "Copy",

    [string]$AddonPath = $env:XIVEQUIP_ADDON_PATH,

    [switch]$SkipTests,
    [switch]$RequireTests,

    [switch]$NoInstall
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

function Get-NextDevVersion {
    param(
        [string]$Version,
        [string]$BumpKind
    )

    if ($Version -notmatch "^(?<Major>\d+)\.(?<Minor>\d+)\.(?<Patch>\d+)(?:-dev\.(?<Dev>\d+))?$") {
        throw "Version '$Version' does not match x.y.z or x.y.z-dev.N."
    }

    $major = [int]$Matches.Major
    $minor = [int]$Matches.Minor
    $patch = [int]$Matches.Patch
    $dev = $Matches.Dev

    if ($dev) {
        return "$major.$minor.$patch-dev.$([int]$dev + 1)"
    }

    switch ($BumpKind) {
        "Major" {
            $major += 1
            $minor = 0
            $patch = 0
        }
        "Minor" {
            $minor += 1
            $patch = 0
        }
        default {
            $patch += 1
        }
    }

    return "$major.$minor.$patch-dev.1"
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

if (-not $SkipTests) {
    $testScript = Join-Path $RepoRoot "tools\test.ps1"
    if (Test-Path -LiteralPath $testScript) {
        $luaCandidates = @("lua", "lua54", "lua5.4", "luajit")
        $lua = $luaCandidates | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
        if ($lua) {
            & $testScript
        } elseif ($RequireTests) {
            throw "No Lua runtime found. Install lua, lua54, lua5.4, or luajit, or rerun without -RequireTests."
        } else {
            Write-Warning "No Lua runtime found; skipping offline tests. Use -RequireTests to enforce them."
        }
    }
}

$currentVersion = Get-TocVersion -Path $TocPath
$nextVersion = Get-NextDevVersion -Version $currentVersion -BumpKind $Bump
Set-TocVersion -Path $TocPath -Version $nextVersion

Write-Host "Development version: $currentVersion -> $nextVersion" -ForegroundColor Green

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
