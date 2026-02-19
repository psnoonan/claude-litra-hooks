# LitraHooks.psm1 — Core module for Litra Beam LX Claude Code hooks

$script:ProjectRoot = $PSScriptRoot
$script:SessionsFile = Join-Path $script:ProjectRoot '.sessions.json'
$script:LockFile = Join-Path $script:ProjectRoot '.sessions.lock'
$script:LitraBin = 'litra'

$script:StateColors = @{
    idle      = '00CC44'
    working   = '8833FF'
    attention = 'FF8800'
    off       = '000000'
}

# Zone layout table: session count -> array of zone arrays (ordered by session index)
$script:ZoneLayouts = @{
    1 = @(, @(1, 2, 3, 4, 5, 6, 7))
    2 = @(@(1, 2, 3, 4), @(5, 6, 7))
    3 = @(@(1, 2, 3), @(4, 5), @(6, 7))
}

# --- Registry Management ---

function Invoke-WithLock {
    param([scriptblock]$ScriptBlock)

    $lockDir = Split-Path $script:LockFile -Parent
    if (-not (Test-Path $lockDir)) {
        New-Item -ItemType Directory -Path $lockDir -Force *>$null
    }

    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open(
            $script:LockFile,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        & $ScriptBlock
    }
    catch [System.IO.IOException] {
        $retries = 10
        $acquired = $false
        for ($i = 0; $i -lt $retries; $i++) {
            Start-Sleep -Milliseconds 500
            try {
                $lockStream = [System.IO.File]::Open(
                    $script:LockFile,
                    [System.IO.FileMode]::OpenOrCreate,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None
                )
                $acquired = $true
                break
            }
            catch [System.IO.IOException] {
                # Keep trying
            }
        }
        if ($acquired) {
            & $ScriptBlock
        }
        else {
            Write-Warning "LitraHooks: could not acquire lock after $retries retries, skipping."
        }
    }
    finally {
        if ($lockStream) {
            $lockStream.Close()
            $lockStream.Dispose()
        }
    }
}

function Get-Registry {
    if (-not (Test-Path $script:SessionsFile)) {
        return @{ sessions = @{} }
    }
    try {
        $content = Get-Content -Path $script:SessionsFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            return @{ sessions = @{} }
        }
        $parsed = $content | ConvertFrom-Json -ErrorAction Stop

        # Convert PSObject to hashtable for easier manipulation
        $registry = @{ sessions = @{} }
        if ($parsed.sessions) {
            foreach ($prop in $parsed.sessions.PSObject.Properties) {
                # ConvertFrom-Json auto-converts ISO 8601 strings to DateTime.
                # Normalize back to round-trip string so ParseExact('o') works.
                $regAt = $prop.Value.registered_at
                if ($regAt -is [DateTime]) {
                    $regAt = $regAt.ToUniversalTime().ToString('o')
                }
                $session = @{
                    zones         = @($prop.Value.zones)
                    state         = $prop.Value.state
                    pid           = $prop.Value.pid
                    registered_at = [string]$regAt
                }
                $registry.sessions[$prop.Name] = $session
            }
        }
        return $registry
    }
    catch {
        return @{ sessions = @{} }
    }
}

function Save-Registry {
    param([hashtable]$Registry)

    # Convert to a structure that serializes cleanly
    $output = @{ sessions = @{} }
    foreach ($key in $Registry.sessions.Keys) {
        $s = $Registry.sessions[$key]
        $output.sessions[$key] = @{
            zones         = @($s.zones)
            state         = [string]$s.state
            pid           = [int]$s.pid
            registered_at = [string]$s.registered_at
        }
    }
    $output | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SessionsFile -Encoding UTF8 -NoNewline
}

function Remove-StaleSessions {
    param([hashtable]$Registry)

    $removed = $false
    $toRemove = @()

    foreach ($key in $Registry.sessions.Keys) {
        $session = $Registry.sessions[$key]
        $procId = $session.pid
        try {
            $proc = Get-Process -Id $procId -ErrorAction Stop
        }
        catch {
            $toRemove += $key
        }
    }

    foreach ($key in $toRemove) {
        $Registry.sessions.Remove($key)
        $removed = $true
    }

    # Also remove sessions older than 24 hours as a fallback
    $cutoff = (Get-Date).AddHours(-24).ToUniversalTime()
    $toRemove = @()
    foreach ($key in $Registry.sessions.Keys) {
        $session = $Registry.sessions[$key]
        try {
            # Use ParseExact with round-trip format to avoid locale-dependent parsing
            $regTime = [DateTime]::ParseExact(
                $session.registered_at, 'o',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind
            ).ToUniversalTime()
            if ($regTime -lt $cutoff) {
                $toRemove += $key
            }
        }
        catch {
            # Can't parse date, remove it
            $toRemove += $key
        }
    }
    foreach ($key in $toRemove) {
        $Registry.sessions.Remove($key)
        $removed = $true
    }

    return $removed
}

# --- Zone Allocation ---

function Update-ZoneAllocations {
    param([hashtable]$Registry)

    $sessionCount = $Registry.sessions.Count
    if ($sessionCount -eq 0) { return }

    # Cap at 3 sessions for zone layouts
    $layoutKey = [Math]::Min($sessionCount, 3)
    $layouts = $script:ZoneLayouts[$layoutKey]

    # Order sessions by registration time (earliest first)
    $ordered = $Registry.sessions.GetEnumerator() |
        Sort-Object { $_.Value.registered_at } |
        Select-Object -ExpandProperty Key

    $index = 0
    foreach ($sessionId in $ordered) {
        if ($index -lt $layouts.Count) {
            $Registry.sessions[$sessionId].zones = @($layouts[$index])
        }
        else {
            # More than 3 sessions — extra sessions get no zones
            $Registry.sessions[$sessionId].zones = @()
        }
        $index++
    }
}

# --- Light Control (internal helpers) ---

# WARNING: All litra calls MUST be sequential — one at a time. The Litra Beam LX
# uses a single USB HID handle. Concurrent access (Start-Job, Start-Process,
# ForEach-Object -Parallel, background processes) will corrupt the handle and make
# the device unresponsive until a USB replug. This includes fire-and-forget patterns.
# Each litra.exe call takes ~1s (USB HID round-trip). This is irreducible.

function Set-Zones {
    param(
        [int[]]$Zones,
        [string]$ColorHex
    )

    if ($Zones.Count -eq 0) { return }

    if ($Zones.Count -eq 7) {
        # All zones — single call, no --zone flag (omitting --zone targets all 7)
        & $script:LitraBin back-color --value $ColorHex *>$null
    }
    else {
        foreach ($z in $Zones) {
            & $script:LitraBin back-color --value $ColorHex --zone $z *>$null
        }
    }
}

function Set-AllSessionZones {
    param([hashtable]$Registry)

    foreach ($key in $Registry.sessions.Keys) {
        $session = $Registry.sessions[$key]
        $color = $script:StateColors[$session.state]
        if (-not $color) { $color = $script:StateColors['off'] }
        Set-Zones -Zones $session.zones -ColorHex $color
    }
}

function Invoke-TransitionFlash {
    param(
        [int[]]$Zones,
        [string]$ColorHex
    )

    # Brightness pulse: bright -> color -> settle (sequential — see warning above Set-Zones)
    & $script:LitraBin back-brightness --percentage 100 *>$null
    Set-Zones -Zones $Zones -ColorHex $ColorHex
    Start-Sleep -Milliseconds 300
    & $script:LitraBin back-brightness --percentage 60 *>$null
}

# --- Session Lifecycle ---

function Register-Session {
    param(
        [string]$SessionId,
        [int]$Pid
    )

    Invoke-WithLock {
        $registry = Get-Registry
        Remove-StaleSessions $registry *>$null

        $isFirst = ($registry.sessions.Count -eq 0)

        $registry.sessions[$SessionId] = @{
            zones         = @()
            state         = 'idle'
            pid           = $Pid
            registered_at = (Get-Date).ToUniversalTime().ToString('o')
        }

        Update-ZoneAllocations $registry

        if ($isFirst) {
            & $script:LitraBin back-on *>$null
            & $script:LitraBin back-brightness --percentage 60 *>$null
        }

        Save-Registry $registry
        Set-AllSessionZones $registry
    }
}

function Unregister-Session {
    param([string]$SessionId)

    Invoke-WithLock {
        $registry = Get-Registry

        if ($registry.sessions.ContainsKey($SessionId)) {
            # Turn off this session's zones before removing
            $zones = $registry.sessions[$SessionId].zones
            Set-Zones -Zones $zones -ColorHex $script:StateColors['off']
            $registry.sessions.Remove($SessionId)
        }

        Remove-StaleSessions $registry *>$null

        if ($registry.sessions.Count -eq 0) {
            Save-Registry $registry
            & $script:LitraBin back-off *>$null
        }
        else {
            Update-ZoneAllocations $registry
            Save-Registry $registry
            Set-AllSessionZones $registry
        }
    }
}

# --- State Changes ---

function Set-SessionState {
    param(
        [string]$SessionId,
        [string]$State
    )

    Invoke-WithLock {
        $registry = Get-Registry

        if (-not $registry.sessions.ContainsKey($SessionId)) {
            return
        }

        $registry.sessions[$SessionId].state = $State
        Save-Registry $registry

        $zones = $registry.sessions[$SessionId].zones
        $color = $script:StateColors[$State]

        if ($State -eq 'attention' -or $State -eq 'idle') {
            Invoke-TransitionFlash -Zones $zones -ColorHex $color
        }
        else {
            # Working state — just paint, no flash
            Set-Zones -Zones $zones -ColorHex $color
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-WithLock'
    'Get-Registry'
    'Save-Registry'
    'Remove-StaleSessions'
    'Update-ZoneAllocations'
    'Register-Session'
    'Unregister-Session'
    'Set-SessionState'
    'Set-Zones'
    'Set-AllSessionZones'
    'Invoke-TransitionFlash'
)
