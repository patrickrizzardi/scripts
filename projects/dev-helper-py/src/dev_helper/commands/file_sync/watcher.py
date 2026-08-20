from __future__ import annotations

from dev_helper.utils.command_exists import command_exists

INOTIFY_INSTALL_COMMAND = "sudo apt-get update && sudo apt-get install -y inotify-tools"


def is_inotify_tools_installed() -> bool:
    return command_exists("inotifywait")


# The generated shell below is deliberately written as raw string literals: the
# bash is copied verbatim, so `$var`, `${arr[@]}` and `\#*` need no escaping
# the way they did inside the TypeScript template literals this replaces.
def generate_sync_script_content() -> str:
    return r"""#!/bin/bash
PAIRS_FILE="$HOME/.config/rsync-sync/pairs.conf"
LOG_FILE="$HOME/.config/rsync-sync/sync.log"
mkdir -p "$(dirname "$LOG_FILE")"
while IFS='|' read -r source target; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    if [[ ! -e "$source" ]]; then
        if [[ -e "$target" ]]; then
            rm -rf "$target"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): source removed, deleted target: $source -> $target" >> "$LOG_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S'): source not found: $source" >> "$LOG_FILE"
        fi
        continue
    fi
    if [[ -d "$source" ]]; then
        mkdir -p "$target"
        rsync -a --delete "${source}/" "${target}/" 2>>"$LOG_FILE" \
            || echo "$(date '+%Y-%m-%d %H:%M:%S'): rsync failed: $source -> $target" >> "$LOG_FILE"
    else
        mkdir -p "$(dirname "$target")"
        rsync -a "$source" "$target" 2>>"$LOG_FILE" \
            || echo "$(date '+%Y-%m-%d %H:%M:%S'): rsync failed: $source -> $target" >> "$LOG_FILE"
    fi
done < "$PAIRS_FILE"
"""


def generate_watch_script_content() -> str:
    return r"""#!/bin/bash
PAIRS_FILE="$HOME/.config/rsync-sync/pairs.conf"
SYNC_SCRIPT="$HOME/.config/rsync-sync/sync.sh"
LOG_FILE="$HOME/.config/rsync-sync/sync.log"
mkdir -p "$(dirname "$LOG_FILE")"

sources=()
while IFS='|' read -r source target; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    [[ -e "$source" ]] && sources+=("$source")
done < "$PAIRS_FILE"

if [[ ${#sources[@]} -eq 0 ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): no sources to watch, exiting" >> "$LOG_FILE"
    exit 0
fi

inotifywait -m -r -e modify,create,delete,move "${sources[@]}" | while read -r _; do
    # Perf: drain any additional events for 300ms before syncing — collapses a
    # save's burst of modify/create/delete events into a single rsync run.
    while read -r -t 0.3 _; do :; done
    "$SYNC_SCRIPT"
done
"""


def generate_watch_service_content() -> str:
    return """[Unit]
Description=rsync file sync watcher
After=network.target

[Service]
Type=simple
ExecStart=%h/.config/rsync-sync/watch.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
"""


def generate_fallback_service_content() -> str:
    return """[Unit]
Description=rsync file sync fallback reconciliation
After=network.target

[Service]
Type=oneshot
ExecStart=%h/.config/rsync-sync/sync.sh
"""


def generate_fallback_timer_content() -> str:
    return """[Unit]
Description=rsync file sync fallback timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=5s

[Install]
WantedBy=timers.target
"""
