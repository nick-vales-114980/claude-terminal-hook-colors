<#
.SYNOPSIS
    Installs or uninstalls Claude Terminal Hook Colors hooks.

.DESCRIPTION
    Registers hook scripts in Claude Code's settings.json that run directly
    from this repository. No files are copied to the user profile, avoiding
    execution-policy issues with scripts in protected directories.

.PARAMETER Uninstall
    Remove hooks from settings.json.

.EXAMPLE
    pwsh ./install.ps1
    pwsh ./install.ps1 -Uninstall
#>
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$hooksPath = Join-Path $repoRoot 'hooks'
$claudeDir = Join-Path $HOME '.claude'
$settingsPath = Join-Path $claudeDir 'settings.json'

# Marker used to identify our hooks in settings.json
$hookMarker = 'terminal-hook-colors'

function Test-Prerequisites {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Error "PowerShell 7+ is required. Current version: $($PSVersionTable.PSVersion)"
        return $false
    }
    if (-not (Test-Path $settingsPath)) {
        Write-Error "Claude Code settings not found at $settingsPath. Run 'claude' at least once first."
        return $false
    }
    $wt = Get-AppxPackage Microsoft.WindowsTerminal* -ErrorAction SilentlyContinue
    if (-not $wt) {
        Write-Warning "Windows Terminal not detected. These hooks are designed for Windows Terminal."
    }
    return $true
}

function Read-Settings {
    Get-Content $settingsPath -Raw | ConvertFrom-Json
}

function Write-Settings {
    param($Settings)
    $backupPath = "$settingsPath.bak"
    Copy-Item $settingsPath $backupPath -Force
    $Settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "  Backup saved to $backupPath" -ForegroundColor DarkGray
}

$script:HookTypes = @('UserPromptSubmit', 'Stop', 'Notification')

function Remove-HookEntries {
    param($Settings)
    if (-not $Settings.hooks) { return $Settings }

    foreach ($type in $script:HookTypes) {
        $entries = $Settings.hooks.$type
        if (-not $entries) { continue }

        $filtered = @()
        foreach ($entry in $entries) {
            $keep = $true
            foreach ($hook in $entry.hooks) {
                if ($hook.command -and $hook.command -like "*$hookMarker*") {
                    $keep = $false
                    break
                }
            }
            if ($keep) { $filtered += $entry }
        }

        if ($filtered.Count -eq 0) {
            $Settings.hooks.PSObject.Properties.Remove($type)
        } else {
            $Settings.hooks.$type = $filtered
        }
    }

    return $Settings
}

function Add-HookEntries {
    param($Settings)

    if (-not $Settings.hooks) {
        $Settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{})
    }

    $submitScript = (Join-Path $hooksPath 'on-prompt-submit.ps1') -replace '\\', '/'
    $stopScript = (Join-Path $hooksPath 'on-stop.ps1') -replace '\\', '/'
    $notifyScript = (Join-Path $hooksPath 'on-notification.ps1') -replace '\\', '/'

    $hookDefs = @{
        UserPromptSubmit = @{
            command = "pwsh -NoProfile -File `"$submitScript`""
            async   = $false
            matcher = $null
        }
        Stop = @{
            command = "pwsh -NoProfile -File `"$stopScript`""
            async   = $true
            matcher = $null
        }
        Notification = @{
            command = "pwsh -NoProfile -File `"$notifyScript`""
            async   = $true
            matcher = 'permission_prompt'
        }
    }

    foreach ($type in $hookDefs.Keys) {
        $def = $hookDefs[$type]
        $hookObj = [PSCustomObject]@{
            type    = 'command'
            command = $def.command
            shell   = 'powershell'
        }
        if ($def.async) {
            $hookObj | Add-Member -NotePropertyName 'async' -NotePropertyValue $true
        }

        $entryObj = [PSCustomObject]@{
            hooks = @($hookObj)
        }
        if ($def.matcher) {
            $entryObj | Add-Member -NotePropertyName 'matcher' -NotePropertyValue $def.matcher
        }

        $existing = $Settings.hooks.$type
        if ($existing) {
            $Settings.hooks.$type = @() + @($existing) + @($entryObj)
        } else {
            $Settings.hooks | Add-Member -NotePropertyName $type -NotePropertyValue @($entryObj) -Force
        }
    }

    return $Settings
}

# --- Main ---

if (-not (Test-Prerequisites)) { exit 1 }

if ($Uninstall) {
    Write-Host "`nUninstalling Claude Terminal Hook Colors..." -ForegroundColor Yellow

    $settings = Read-Settings
    $settings = Remove-HookEntries $settings
    Write-Settings $settings
    Write-Host "  Hooks removed from settings.json" -ForegroundColor Green

    Write-Host "`nUninstall complete." -ForegroundColor Green
    exit 0
}

# --- Install ---

Write-Host "`nInstalling Claude Terminal Hook Colors..." -ForegroundColor Cyan
Write-Host "  Hooks will run from: $hooksPath" -ForegroundColor DarkGray

# Start from default config each install so previous customizations don't leak
$defaultsPath = Join-Path $hooksPath 'config.defaults.json'
$configPath = Join-Path $hooksPath 'config.json'
Copy-Item $defaultsPath $configPath -Force
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "  Notification sounds play when Claude finishes a task or needs" -ForegroundColor DarkGray
Write-Host "  permission, so you can tab away without missing prompts." -ForegroundColor DarkGray
Write-Host "  Press Enter to enable (default), or type 'n' to disable." -ForegroundColor DarkGray

$enableSounds = Read-Host "  Enable notification sounds? [Y/n]"
if ($enableSounds -eq 'n') {
    $config.sounds.stop = $null
    $config.sounds.notification = $null
    Write-Host "  Sounds disabled" -ForegroundColor DarkGray
} else {
    Write-Host "  Sounds enabled" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Terminal tab colors change based on Claude's current state." -ForegroundColor DarkGray
Write-Host "  You can customize each color below, or press Enter to keep the default." -ForegroundColor DarkGray
Write-Host "  Format: rgb:RR/GG/BB (e.g. #4d0000 becomes rgb:4d/00/00)" -ForegroundColor DarkGray
Write-Host ""

$customProcessing = Read-Host "  Processing color (shown while Claude is working) [dark red: $($config.colors.processing)]"
if ($customProcessing) { $config.colors.processing = $customProcessing }

$customStopped = Read-Host "  Stopped color (shown when Claude finishes, resets after 15s) [dark green: $($config.colors.stopped)]"
if ($customStopped) { $config.colors.stopped = $customStopped }

$customPermission = Read-Host "  Permission color (shown when Claude needs your approval) [purple: $($config.colors.permission)]"
if ($customPermission) { $config.colors.permission = $customPermission }

$config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
Write-Host "  Config saved" -ForegroundColor Green

# Compile ConsoleApi DLL for faster hook startup
$csPath = Join-Path $hooksPath 'ConsoleApi.cs'
$dllPath = Join-Path $hooksPath 'ConsoleApi.dll'
if ([System.IO.File]::Exists($csPath)) {
    try {
        if ([System.IO.File]::Exists($dllPath)) { Remove-Item $dllPath -Force }
        Add-Type -Path $csPath -OutputAssembly $dllPath -OutputType Library -ErrorAction Stop
        Write-Host "  Compiled ConsoleApi.dll" -ForegroundColor Green
    } catch {
        Write-Warning "  DLL compilation failed (hooks will fall back to runtime compilation): $_"
    }
}

# Update settings.json
$settings = Read-Settings
$settings = Remove-HookEntries $settings
$settings = Add-HookEntries $settings
Write-Settings $settings
Write-Host "  Hooks added to settings.json" -ForegroundColor Green

Write-Host "`nInstall complete!" -ForegroundColor Green
Write-Host @"

  Hooks run directly from this repo. Do not move or delete it.

  Colors:
    Processing  = dark red ($($settings.hooks ? 'active' : 'check settings'))
    Stopped     = dark green (resets after 15s)
    Permission  = purple

  Customize:  Edit $hooksPath\config.json
  Uninstall:  pwsh $repoRoot\install.ps1 -Uninstall
"@ -ForegroundColor DarkGray
