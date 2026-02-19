#!/usr/bin/env pwsh
$input_json = $input | Out-String
$hookData = $input_json | ConvertFrom-Json

$sessionId = $hookData.session_id
if ($sessionId -notmatch '^[a-f0-9\-]{32,64}$') { exit 0 }

Import-Module (Join-Path $PSScriptRoot '..' 'LitraHooks.psm1') -Force

Set-SessionState -SessionId $sessionId -State 'working'

exit 0
