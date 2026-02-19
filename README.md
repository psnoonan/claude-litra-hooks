# Litra Beam LX x Claude Code Hooks

Uses the 7-zone RGB backlight on a Logitech Litra Beam LX to show what each Claude Code instance is doing. Each session owns a slice of the light bar — purple means working, green means idle, amber means it needs your attention.

## Prerequisites

- **Logitech Litra Beam LX** connected via USB
- **[litra-rs CLI](https://github.com/timrogers/litra-rs)** on your PATH. Install using one of:
  - **Pre-built binary (recommended):** Download from [GitHub Releases](https://github.com/timrogers/litra-rs/releases) for Windows, macOS, or Linux
  - **Homebrew (macOS):** `brew install timrogers/tap/litra`
  - **Cargo:** `cargo install litra` (requires [Rust](https://rustup.rs/))
- **PowerShell 7+** (`pwsh`) — required on Windows, macOS, and Linux ([install guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell))

## Installation

```powershell
.\install.ps1
```

This will:
1. Verify litra CLI and device are available
2. Register hooks into `~/.claude/settings.json`
3. Run a quick smoke test (all zones flash green)

## How it works

### Zone allocation

The Beam LX has 7 RGB zones (left to right). Each Claude Code session gets a slice:

| Active Sessions | Session 1 | Session 2 | Session 3 |
|---|---|---|---|
| 1 | Zones 1-7 | — | — |
| 2 | Zones 1-4 | Zones 5-7 | — |
| 3 | Zones 1-3 | Zones 4-5 | Zones 6-7 |

### Colors

| Color | Hex | Meaning |
|---|---|---|
| Green | `00CC44` | Idle — session finished, waiting for input |
| Purple | `8833FF` | Working — tool use in progress |
| Amber | `FF8800` | Attention — needs user input |

When a session transitions to idle or attention, the backlight briefly pulses brighter to catch your eye.

### Hook events

| Event | Action |
|---|---|
| SessionStart | Register session, allocate zones, light green |
| PreToolUse | Set zones to purple |
| Stop | Pulse then set zones to green |
| Notification | Pulse then set zones to amber |
| SessionEnd | Release zones, rebalance, turn off if last |

## Testing

Run the manual test to simulate a full lifecycle:

```powershell
.\test.ps1
```

This walks through session start, tool use, notifications, and cleanup with 2-second pauses so you can visually verify each state.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes hooks from Claude Code settings and turns off the backlight. The scripts remain in the project folder.

## Troubleshooting

### Hooks not firing
Global hooks in `~/.claude/settings.json` may not load in some cases ([#11544](https://github.com/anthropics/claude-code/issues/11544), [#3579](https://github.com/anthropics/claude-code/issues/3579)). Workaround: symlink `.claude/settings.json` into your project repo.

### litra not found
Make sure `litra` is on your PATH. If installed via cargo, the default location is `~/.cargo/bin`. If using a pre-built binary, make sure the directory containing `litra` (or `litra.exe` on Windows) is in your PATH.

### Stale sessions
If zones are stuck, delete `.sessions.json` and restart. The hooks automatically clean up sessions whose PIDs are dead, and remove sessions older than 24 hours.

### Light not responding
Verify with `litra devices` that the Beam LX shows up. Try `litra back-on` manually. The device must be connected via USB (not Bluetooth).

## Future ideas

- Publish as a Claude Code plugin
- Add sound effects for state transitions
- Use front light toggle for "do not disturb" mode
- Support multiple Litra devices
