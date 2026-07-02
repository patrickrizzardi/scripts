# Design: Dev Helper CLI Rewrite (Bash → TypeScript/Bun)

## Overview

Replace `helper.sh` (bash, monolithic, numeric-menu) with an interactive TypeScript CLI running on
Bun inside Docker, living at `~/development/projects/dev-helper/`. Same 8 capabilities as today,
split one-file-per-command, driven by arrow-key/checkbox prompts instead of typed numbers. Two
functional upgrades ride along: instant (inotify-triggered) file sync instead of a 30s poll, and
duplicate-selection prevention in the multi-select add-pairs flow.

This design supersedes
[the original rsync-sync-menu-option design](./2026-06-26-rsync-sync-menu-option-design.md) for
the sync-trigger mechanism (timer → watcher) and target file layout (`helper.sh` → `dev-helper/`);
the pairs-file format, config paths, and remove/view flows it documents are unchanged and carried
forward as-is.

## Why Bun + Docker

This host has no Node/Bun installed natively — per this environment's standing rule, a missing
runtime is containerized rather than installed on the host. Patrick's stated reason: he doesn't
want CLI-tool runtimes accumulating on WSL; a container can be deleted outright with no leftover
package state. Bun is his language-runtime choice (not Node) — faster startup, built-in
TypeScript execution, no separate `ts-node`/build-watch step needed for a CLI this size.

**Image pin**: `oven/bun:1.3-alpine`. (Bun's actual release line is 1.x — there is no 3.3 release;
confirmed against Docker Hub's `oven/bun` tag list before writing this doc. Floating on the `1.3`
minor tag balances "pinned enough to be reproducible" against "not patch-chasing forever.")

**The container does not fully sandbox this tool** — several of its 8 functions inspect or mutate
*host* state (`du`/`df`, `ss`, `systemctl --user`, arbitrary host filesystem paths). To keep those
working, `docker-compose.yml` runs with `network_mode: host`, `pid: host`, and bind-mounts `$HOME`
plus `/run/user/$UID` (with `DBUS_SESSION_BUS_ADDRESS` passed through) so the container can reach
the host's user systemd/D-Bus session. This is a deliberate, named tradeoff: less isolation than a
typical container, in exchange for zero installed host runtimes and trivial teardown (`docker
compose down --rmi all` removes every trace).

## Directory Layout

```
~/development/projects/dev-helper/
├── docker-compose.yml
├── package.json
├── tsconfig.json
└── src/
    ├── index.ts              # menu loop entry point
    ├── utils/
    │   ├── print.ts          # color/print helpers (port of print_* from helper.sh)
    │   └── prompt.ts         # @clack/prompts wrappers (select, multiselect, text, confirm)
    └── commands/
        ├── searchText.ts
        ├── findFiles.ts
        ├── diskUsage.ts
        ├── network.ts
        ├── systemInfo.ts
        ├── portUsage.ts
        ├── gitDiff.ts
        └── fileSync/
            ├── config.ts     # pairs.conf read/write
            ├── addPairs.ts   # multi-select + manual entry; dedup filter lives here
            ├── viewPairs.ts
            ├── removePair.ts
            ├── watcher.ts    # generates the inotify watcher unit + script; missing-binary check
            └── service.ts    # systemctl --user wrappers
```

`helper.sh` is deleted once this CLI covers all 8 menu items — this is a full replacement, not a
parallel tool.

## Interactivity

`@clack/prompts` replaces every `read -r` in the original script:

- Main menu and the file-sync management menu → `select()` (arrow keys, Enter to choose)
- Multi-select add-pairs flow → `multiselect()` (space to toggle, Enter to confirm)
- Free-text inputs (paths, search terms, port numbers) → `text()` with the same defaults/validation
  the bash version had (e.g. port number regex, non-empty path checks)
- y/n confirmations (remove-pair, overwrite prompts) → `confirm()`

## Command Behavior (parity with `helper.sh`)

The 7 non-sync commands (`searchText`, `findFiles`, `diskUsage`, `network`, `systemInfo`,
`portUsage`, `gitDiff`) are direct ports of their bash counterparts — same prompts, same
underlying shell commands (`grep`, `find`, `du`/`df`, `ss`, `lscpu`/`free`, `git archive`/`diff`),
same missing-command checks with install-command hints. No behavior changes; only the prompt layer
and file location change.

## File Sync: What Changes vs. the 2026-06-26 Design

### 1. Sync trigger — inotify watcher replaces the 30s timer

The original design's `rsync-sync.timer` (`OnUnitActiveSec=30s`) is replaced by a long-running
`rsync-sync.service` (`Type=simple`, no timer) that runs `inotifywait -m -r` across every source
path listed in `pairs.conf`. On any `modify`/`create`/`delete`/`move` event, sync fires after a
~300ms debounce (collapses rapid-fire events like a save-triggered temp-file dance into one rsync
run).

A periodic fallback re-sync (every 5 minutes) runs alongside the watcher as a reconciliation pass —
inotify can silently miss events under sustained high event volume or when a watch-descriptor limit
is hit, and a mistaken belief that inotify is 100% reliable would leave real drift undetected. This
is a named engineering tradeoff, not scope creep: the watcher gives near-instant sync in the common
case, the fallback bounds the worst case.

Adding a new pair still restarts the watcher (was: restarts the timer) so the new source path is
picked up immediately.

**Dependency**: `inotifywait` (package `inotify-tools`) must exist on the **host** — the watcher is
a host-native systemd `--user` service, not a container process (see below). `watcher.ts` checks
`command -v inotifywait` before writing/enabling the unit and, if missing, prints the exact install
command (`sudo apt-get update && sudo apt-get install -y inotify-tools`) instead of failing
opaquely — same pattern `helper.sh` already used for `rsync`/`colordiff`/`ss`.

### 2. Sync daemon stays host-native, not containerized

Whether it's the old timer or the new watcher, the actual background sync process runs as a plain
host `systemd --user` unit. It must keep running whether or not the Bun container is up — a
container is not the right home for an always-on background daemon tied to the host's systemd user
session. The CLI's role in file-sync is limited to: generating `pairs.conf` / `sync.sh` / unit
files on the host filesystem (via the bind-mounted `$HOME`), and shelling out to `systemctl --user`
on the host (via the bind-mounted `/run/user/$UID` + forwarded `DBUS_SESSION_BUS_ADDRESS`).

### 3. Multi-select dedup

In the add-pairs multi-select flow, before listing `$PWD`'s contents as selectable items, filter
out any entry whose resolved path (`$PWD/$item`) already appears as a `source` in `pairs.conf`.
Prevents accidentally selecting (and thus double-adding) something already synced. Manual-entry
mode is unaffected — it's a single explicit path, not a list to dedup.

Everything else from the 2026-06-26 design carries forward unchanged: `pairs.conf` format
(`source|target` per line), `sync.sh`'s file-vs-directory rsync behavior, the view/remove flows,
`loginctl enable-linger`, and the "systemd unavailable in WSL" error message with `/etc/wsl.conf`
instructions.

## Error Handling

- `bun`/Docker unavailable: out of scope — this is the one dependency the tool assumes, same as
  bash itself was assumed for `helper.sh`.
- `inotifywait` missing on host: checked before watcher setup; install command printed, setup halts
  (config already written is preserved, same recovery pattern as the existing
  `_rsync_install_service` failure path).
- Source path deleted after a pair is added: watcher logs and skips (same as the timer version's
  existing "source not found" log line in `sync.sh`).
- systemd unavailable (WSL without `systemd=true`): unchanged from the 2026-06-26 design — clear
  message with `/etc/wsl.conf` instructions.
- Host systemd/D-Bus unreachable from inside the container (bind mounts misconfigured): CLI detects
  a failed `systemctl --user` call and prints a clear error rather than a raw stack trace.

## Testing

Existing `tests/` bats infrastructure in the `scripts` repo tested `helper.sh` directly; it does
not carry over since the tool is moving language and repo. The new project needs its own test
setup (unit tests for the dedup filter, pairs-file parsing, and watcher-unit generation are the
highest-value targets) — deferred to the implementation plan rather than specified here.
