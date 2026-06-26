# Design: File Sync Menu Option (rsync timer)

## Overview

Add a new "Set up file sync" option to `helper.sh`. Uses a systemd user timer running rsync every 30s — not lsyncd — because the primary use case involves syncing from a Windows filesystem path (`/mnt/c/`) where inotify (required by lsyncd) does not fire for Windows-side edits.

## Files Created on Setup

| Path | Purpose |
|---|---|
| `~/.config/rsync-sync/pairs.conf` | One `source\|target` per line |
| `~/.config/rsync-sync/sync.sh` | Loops pairs and runs rsync |
| `~/.config/systemd/user/rsync-sync.service` | Runs sync.sh |
| `~/.config/systemd/user/rsync-sync.timer` | Fires every 30s |

## First Run Flow (no existing config)

1. Check rsync is installed — always present on Ubuntu, but verify and print install hint if missing
2. Walk through the add-pair flow (see below) — user adds one or more pairs before setup completes
3. Write `pairs.conf`, `sync.sh`, and systemd unit files
4. Run `loginctl enable-linger $USER` so the timer survives terminal close (no sudo required — users can linger themselves)
5. Run `systemctl --user daemon-reload && systemctl --user enable --now rsync-sync.timer`
6. Print confirmation with active pairs listed

## Subsequent Runs (config exists)

Show management menu:

```
1. Add sync pairs
2. View existing pairs
3. Remove a sync pair
4. Start / Stop / Restart service
5. Exit
```

## Add Pair Flow

Prompt:

```
How would you like to select source(s)?
1. Multi-select from current directory
2. Enter path manually
```

### Multi-select mode

- Print warning: "Make sure your terminal is cd'd into the parent folder you want to sync FROM"
- List all files and directories in `$PWD` as a numbered menu
- User enters space-separated numbers to select items (e.g. `1 3 5`)
- Ask for a single target directory
- Each selected item maps to `target/item-name` — creates one pair per item
- Example: selecting `plugins` and `settings.json` from `/mnt/c/Users/Patrick/.claude/` with target `~/.claude/` creates:
  - `/mnt/c/Users/Patrick/.claude/plugins | ~/.claude/plugins`
  - `/mnt/c/Users/Patrick/.claude/settings.json | ~/.claude/settings.json`

### Manual mode

- Prompt for source path, then target path
- Creates one pair

After adding pairs, if a service already exists: rewrite `pairs.conf` and restart the timer. If this is first setup: continue to systemd install.

## Remove Pair Flow

- Display numbered list of current pairs
- User picks a number
- Confirm: `Remove /foo/bar → /baz? (y/n)`
- Rewrite `pairs.conf`, restart timer

## sync.sh Behavior

For each `source|target` pair:
- If source is a directory: `rsync -a --delete "source/" "target/"`
- If source is a file: `rsync -a "source" "target/"`

Detects file vs directory at runtime so it handles both correctly.

## Systemd Timer

`OnUnitActiveSec=30s` with `AccuracySec=1s`. Runs as the current user — no sudo required for the sync itself. `loginctl enable-linger` is the only step requiring sudo (or run as root).

## helper.sh Integration

- Add `"Set up file sync"` to `menu_items` array
- Add `"N"="setup_file_sync"` to `menu_functions` (N = next available number, currently 8)
- Implement `setup_file_sync()` function using existing color/print helpers

## Error Handling

- Source path does not exist at sync time: rsync exits non-zero, log to `~/.config/rsync-sync/sync.log`; service continues for remaining pairs
- Config file missing when management menu is invoked: treat as first run
- systemd not available (WSL without systemd enabled): print clear message with instructions to enable (`/etc/wsl.conf` → `[boot] systemd=true`, then restart WSL)
