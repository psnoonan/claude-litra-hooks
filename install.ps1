#!/usr/bin/env pwsh
# install.ps1 — Register Litra hooks into Claude Code settings

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot

# 1. Verify litra CLI is on PATH
$litraBin = (Get-Command litra -ErrorAction SilentlyContinue).Source
if (-not $litraBin) {
    Write-Host "ERROR: litra CLI not found on PATH. Install it first (see README)." -ForegroundColor Red
    exit 1
}

$version = & litra --version 2>$null
Write-Host "Found litra: $version" -ForegroundColor Green

# 2. Verify Beam LX is connected
$devices = (& litra devices 2>$null) -join "`n"
if ($devices -notmatch 'Beam LX') {
    Write-Host "ERROR: No Litra Beam LX detected. Is it connected via USB?" -ForegroundColor Red
    exit 1
}
Write-Host "Litra Beam LX detected." -ForegroundColor Green

# 3. Verify PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "ERROR: PowerShell 7+ required. Current: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}
Write-Host "PowerShell $($PSVersionTable.PSVersion) OK." -ForegroundColor Green

# 4. Merge hooks into ~/.claude/settings.json
$claudeDir = Join-Path $HOME '.claude'
$settingsPath = Join-Path $claudeDir 'settings.json'

if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

$existingSettings = @{}
if (Test-Path $settingsPath) {
    try {
        $existingSettings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        Write-Host "WARNING: Could not parse existing settings.json, backing up and creating new." -ForegroundColor Yellow
        Copy-Item $settingsPath "$settingsPath.bak"
        $existingSettings = @{}
    }
}

# Define event-to-script mapping
$hookMap = @{
    SessionStart     = @{ script = 'on-session-start.ps1'; timeout = 10 }
    UserPromptSubmit = @{ script = 'on-user-prompt-submit.ps1'; timeout = 5 }
    PreToolUse       = @{ script = 'on-pre-tool-use.ps1'; timeout = 5 }
    Stop             = @{ script = 'on-stop.ps1'; timeout = 5 }
    Notification     = @{ script = 'on-notification.ps1'; timeout = 5 }
    SessionEnd       = @{ script = 'on-session-end.ps1'; timeout = 10 }
}

# Build and merge hooks per event type — preserve existing hooks for other events
if (-not $existingSettings.ContainsKey('hooks')) { $existingSettings['hooks'] = @{} }
foreach ($eventType in $hookMap.Keys) {
    # Use forward slashes — Claude Code runs hooks via bash, which eats backslashes
    $scriptPath = (Join-Path $ProjectRoot 'hooks' $hookMap[$eventType].script) -replace '\\', '/'
    $existingSettings['hooks'][$eventType] = @(
        @{
            matcher = ''
            hooks   = @(
                @{
                    type    = 'command'
                    command = "pwsh -NoProfile -File $scriptPath"
                    timeout = $hookMap[$eventType].timeout
                }
            )
        }
    )
}

$existingSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
Write-Host "Hooks registered in $settingsPath" -ForegroundColor Green

# 5. Initialize sessions file
$sessionsFile = Join-Path $ProjectRoot '.sessions.json'
@{ sessions = @{} } | ConvertTo-Json -Depth 3 | Set-Content -Path $sessionsFile -Encoding UTF8
Write-Host "Session registry initialized." -ForegroundColor Green

# 6. Smoke test
Write-Host "Running smoke test..." -ForegroundColor Cyan
& litra back-on *>$null
& litra back-brightness --percentage 60 *>$null
& litra back-color --value 00CC44 *>$null
Start-Sleep -Seconds 1
& litra back-off *>$null

Write-Host ""
Write-Host "Installation complete! Litra hooks are now active." -ForegroundColor Green
Write-Host "Start a new Claude Code session to see it in action." -ForegroundColor Cyan
