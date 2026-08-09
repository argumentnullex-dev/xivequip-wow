param(
    [switch]$ProcessOnly
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot

function Read-Setting {
    param(
        [string]$Name,
        [string]$Prompt,
        [string]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Default)) {
        $value = Read-Host "$Prompt"
    } else {
        $value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Name cannot be empty."
    }

    return $value.Trim()
}

function Set-EnvSetting {
    param(
        [string]$Name,
        [string]$Value
    )

    if ($ProcessOnly) {
        [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    } else {
        [Environment]::SetEnvironmentVariable($Name, $Value, "User")
        [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    }
}

$addonPath = Read-Setting `
    -Name "XIVEQUIP_ADDON_PATH" `
    -Prompt "XIVEquip addon install folder" `
    -Default $env:XIVEQUIP_ADDON_PATH

$savedVariablesDir = Read-Setting `
    -Name "XIVEQUIP_SAVED_VARIABLES_DIR" `
    -Prompt "XIVEquip SavedVariables folder" `
    -Default $env:XIVEQUIP_SAVED_VARIABLES_DIR

$archiveDirDefault = $env:XIVEQUIP_ARCHIVE_DIR
if ([string]::IsNullOrWhiteSpace($archiveDirDefault)) {
    $archiveDirDefault = Join-Path $RepoRoot "..\XIVEquipArchives"
}

$archiveDir = Read-Setting `
    -Name "XIVEQUIP_ARCHIVE_DIR" `
    -Prompt "Build archive output folder" `
    -Default $archiveDirDefault

Set-EnvSetting -Name "XIVEQUIP_ADDON_PATH" -Value $addonPath
Set-EnvSetting -Name "XIVEQUIP_SAVED_VARIABLES_DIR" -Value $savedVariablesDir
Set-EnvSetting -Name "XIVEQUIP_ARCHIVE_DIR" -Value $archiveDir

Write-Host "XIVEquip environment configured:" -ForegroundColor Green
Write-Host "  XIVEQUIP_ADDON_PATH=$addonPath"
Write-Host "  XIVEQUIP_SAVED_VARIABLES_DIR=$savedVariablesDir"
Write-Host "  XIVEQUIP_ARCHIVE_DIR=$archiveDir"

if (-not $ProcessOnly) {
    Write-Host ""
    Write-Host "Open a new terminal for these user environment variables to be available everywhere."
}
