#!/usr/bin/env pwsh
# test.ps1 — Manual test script to simulate the full hook lifecycle

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$Delay = 2

Import-Module (Join-Path $ProjectRoot 'LitraHooks.psm1') -Force

# Clean slate
$sessionsFile = Join-Path $ProjectRoot '.sessions.json'
@{ sessions = @{} } | ConvertTo-Json -Depth 3 | Set-Content -Path $sessionsFile -Encoding UTF8

function Show-Step {
    param([int]$Num, [string]$Desc, [string]$Expect)
    Write-Host ""
    Write-Host "=== Step ${Num}: ${Desc} ===" -ForegroundColor Cyan
    Write-Host "    Expected: $Expect" -ForegroundColor DarkGray
}

# Step 1: SessionStart for test-session-1
Show-Step 1 "SessionStart for test-session-1" "All 7 zones GREEN"
Register-Session -SessionId 'test-session-1' -Pid $PID
Start-Sleep -Seconds $Delay

# Step 2: PreToolUse for test-session-1
Show-Step 2 "PreToolUse for test-session-1" "All 7 zones PURPLE"
Set-SessionState -SessionId 'test-session-1' -State 'working'
Start-Sleep -Seconds $Delay

# Step 3: SessionStart for test-session-2
Show-Step 3 "SessionStart for test-session-2" "Zones 1-4 PURPLE, zones 5-7 GREEN"
Register-Session -SessionId 'test-session-2' -Pid $PID
Start-Sleep -Seconds $Delay

# Step 4: Notification for test-session-2
Show-Step 4 "Notification for test-session-2" "Zones 5-7 brightness pulse then AMBER"
Set-SessionState -SessionId 'test-session-2' -State 'attention'
Start-Sleep -Seconds $Delay

# Step 5: Stop for test-session-1
Show-Step 5 "Stop for test-session-1" "Zones 1-4 brightness pulse then GREEN"
Set-SessionState -SessionId 'test-session-1' -State 'idle'
Start-Sleep -Seconds $Delay

# Step 6: SessionEnd for test-session-1
Show-Step 6 "SessionEnd for test-session-1" "Session 2 expands to zones 1-7 AMBER"
Unregister-Session -SessionId 'test-session-1'
Start-Sleep -Seconds $Delay

# Step 7: Stop for test-session-2
Show-Step 7 "Stop for test-session-2" "All 7 zones brightness pulse then GREEN"
Set-SessionState -SessionId 'test-session-2' -State 'idle'
Start-Sleep -Seconds $Delay

# Step 8: SessionEnd for test-session-2
Show-Step 8 "SessionEnd for test-session-2" "Backlight OFF"
Unregister-Session -SessionId 'test-session-2'
Start-Sleep -Seconds $Delay

Write-Host ""
Write-Host "All tests complete!" -ForegroundColor Green
