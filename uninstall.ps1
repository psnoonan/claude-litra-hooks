#!/usr/bin/env pwsh
# uninstall.ps1 — Remove Litra hooks from Claude Code settings

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot

# 1. Remove hooks from ~/.claude/settings.json
$settingsPath = Join-Path $HOME '.claude' 'settings.json'

if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($settings.ContainsKey('hooks')) {
            # Only remove event types that Litra hooks registered — preserve other hooks
            $litraEvents = @('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Stop', 'Notification', 'SessionEnd')
            $removed = $false
            foreach ($eventType in $litraEvents) {
                if ($settings['hooks'].ContainsKey($eventType)) {
                    $settings['hooks'].Remove($eventType)
                    $removed = $true
                }
            }
            # Clean up empty hooks section
            if ($settings['hooks'].Count -eq 0) {
                $settings.Remove('hooks')
            }
            $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
            if ($removed) {
                Write-Host "Litra hooks removed from $settingsPath" -ForegroundColor Green
            }
            else {
                Write-Host "No Litra hooks found in settings.json — nothing to remove." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "No hooks found in settings.json — nothing to remove." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "ERROR: Could not parse settings.json: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "No settings.json found at $settingsPath" -ForegroundColor Yellow
}

# 2. Turn off backlight
$litraBin = (Get-Command litra -ErrorAction SilentlyContinue).Source
if ($litraBin) {
    & litra back-off *>$null
    Write-Host "Backlight turned off." -ForegroundColor Green
}

# 3. Clean up runtime files
$sessionsFile = Join-Path $ProjectRoot '.sessions.json'
$lockFile = Join-Path $ProjectRoot '.sessions.lock'

if (Test-Path $sessionsFile) { Remove-Item $sessionsFile -Force }
if (Test-Path $lockFile) { Remove-Item $lockFile -Force }
Write-Host "Runtime files cleaned up." -ForegroundColor Green

Write-Host ""
Write-Host "Uninstall complete. Hook scripts and module remain in $ProjectRoot." -ForegroundColor Cyan
Write-Host "Delete the folder to fully remove: Remove-Item '$ProjectRoot' -Recurse" -ForegroundColor Cyan
