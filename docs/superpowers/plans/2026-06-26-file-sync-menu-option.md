# File Sync Menu Option Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Set up file sync" option to `helper.sh` that configures a systemd user timer running rsync every 30s to keep source paths one-way synced to targets, with a management menu for adding/removing pairs.

**Architecture:** All new code lives in `helper.sh` as prefixed (`_rsync_*`) functions. Pure logic (selection parsing, file generation) is separated from interactive prompts so it can be unit tested with bats. A main guard (`BASH_SOURCE` check) prevents the menu loop from running when sourced by tests.

**Tech Stack:** Bash, rsync, systemd user services, bats (testing)

## Global Constraints

- All functions added to `helper.sh`; use existing color helpers (`print_error`, `print_success`, `print_info`, `print_warning`, `print_header`, `print_menu_item`)
- All menu functions end with `exit 0`
- Config dir: `~/.config/rsync-sync/`
- Systemd user units dir: `~/.config/systemd/user/`
- Pairs file: `~/.config/rsync-sync/pairs.conf` — format: `source|target` one per line
- Sync runner: `~/.config/rsync-sync/sync.sh`
- Timer interval: `OnUnitActiveSec=30s`, `AccuracySec=1s`
- rsync flags: `-a --delete` for directories, `-a` for files (checked at runtime)
- Errors during sync logged to `~/.config/rsync-sync/sync.log`
- `~` in user-entered paths must be expanded to `$HOME` before storing
- New menu item is number 8

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `helper.sh` | Modify | All new `_rsync_*` functions + `setup_file_sync` + menu item 8 + main loop guard |
| `tests/test_file_sync.bats` | Create | bats unit tests for all pure functions |

---

### Task 1: Test infrastructure

**Files:**
- Modify: `helper.sh` (lines 284–294 — main loop block)
- Modify: `package.json`
- Create: `tests/test_file_sync.bats`

**Interfaces:**
- Produces: `bats tests/` runs and passes; `helper.sh` can be sourced without executing the menu loop

- [ ] **Step 1: Install bats**

```bash
sudo apt-get install -y bats
bats --version
```
Expected: prints bats version (e.g. `1.10.0`)

- [ ] **Step 2: Add test script to package.json**

In `package.json`, add `"test:bash"` to the `scripts` block:

```json
"scripts": {
  "lint": "oxlint . --type-aware --quiet",
  "lint:fix": "oxlint . --type-aware --fix --quiet",
  "format": "prettier --write .",
  "format:check": "prettier --check .",
  "validate": "npm-run-all --parallel lint format",
  "test:bash": "bats tests/"
},
```

- [ ] **Step 3: Guard the main loop in `helper.sh`**

Wrap the last block (lines 284–294) so it only runs when the script is executed directly:

```bash
# Main menu loop
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    while true; do
        display_menu
        read -r choice

        if [[ -n "${menu_functions[$choice]}" ]]; then
            eval "${menu_functions[$choice]}"
        else
            print_error "Invalid choice. Please try again."
        fi
    done
fi
```

- [ ] **Step 4: Create `tests/test_file_sync.bats` with a sourcing sanity test**

```bash
#!/usr/bin/env bats

setup() {
    export HOME="$(mktemp -d)"
    # shellcheck source=../helper.sh
    source "${BATS_TEST_DIRNAME}/../helper.sh"
}

teardown() {
    rm -rf "$HOME"
}

@test "helper.sh sources without errors" {
    true
}
```

- [ ] **Step 5: Run tests to verify**

```bash
bats tests/
```
Expected: `1 test, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add helper.sh package.json tests/test_file_sync.bats
git commit -m "test: add bats infrastructure and main loop guard"
```

---

### Task 2: `_rsync_apply_selection` — parse multi-select input

**Files:**
- Modify: `helper.sh` (add function before `menu_items` array)
- Modify: `tests/test_file_sync.bats`

**Interfaces:**
- Produces: `_rsync_apply_selection SELECTION_STRING ITEM...` → prints one selected item per line (1-indexed)

- [ ] **Step 1: Write failing tests**

Add to `tests/test_file_sync.bats`:

```bash
@test "_rsync_apply_selection: returns items at selected positions" {
    run _rsync_apply_selection "1 3" "alpha" "beta" "gamma" "delta"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "gamma" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "_rsync_apply_selection: ignores out-of-range numbers" {
    run _rsync_apply_selection "1 99" "alpha" "beta"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "alpha" ]
}

@test "_rsync_apply_selection: ignores non-numeric tokens" {
    run _rsync_apply_selection "1 abc 2" "alpha" "beta" "gamma"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "beta" ]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/
```
Expected: `3 tests, 3 failures` (function not defined)

- [ ] **Step 3: Add `_rsync_apply_selection` to `helper.sh`**

Insert before the `# Define menu items in order` comment:

```bash
_rsync_apply_selection() {
    local selection="$1"
    shift
    local items=("$@")
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            local idx=$((num - 1))
            if [[ $idx -ge 0 && $idx -lt ${#items[@]} ]]; then
                echo "${items[$idx]}"
            fi
        fi
    done
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bats tests/
```
Expected: `4 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add helper.sh tests/test_file_sync.bats
git commit -m "feat: add _rsync_apply_selection for multi-select parsing"
```

---

### Task 3: `_rsync_build_pairs_from_dir` — build source|target pairs

**Files:**
- Modify: `helper.sh`
- Modify: `tests/test_file_sync.bats`

**Interfaces:**
- Consumes: `_rsync_apply_selection` output (selected item names)
- Produces: `_rsync_build_pairs_from_dir SOURCE_DIR TARGET_DIR ITEM...` → prints one `source|target` line per item

- [ ] **Step 1: Write failing tests**

```bash
@test "_rsync_build_pairs_from_dir: builds correct source|target lines" {
    run _rsync_build_pairs_from_dir "/mnt/c/src" "/home/user/dest" "plugins" "settings.json"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "/mnt/c/src/plugins|/home/user/dest/plugins" ]
    [ "${lines[1]}" = "/mnt/c/src/settings.json|/home/user/dest/settings.json" ]
}

@test "_rsync_build_pairs_from_dir: handles single item" {
    run _rsync_build_pairs_from_dir "/src" "/dest" "foo"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "/src/foo|/dest/foo" ]
    [ "${#lines[@]}" -eq 1 ]
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
bats tests/
```
Expected: `6 tests, 2 failures`

- [ ] **Step 3: Add function to `helper.sh`** (after `_rsync_apply_selection`)

```bash
_rsync_build_pairs_from_dir() {
    local source_dir="$1"
    local target_dir="$2"
    shift 2
    local items=("$@")
    for item in "${items[@]}"; do
        echo "${source_dir}/${item}|${target_dir}/${item}"
    done
}
```

- [ ] **Step 4: Run to confirm pass**

```bash
bats tests/
```
Expected: `6 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add helper.sh tests/test_file_sync.bats
git commit -m "feat: add _rsync_build_pairs_from_dir"
```

---

### Task 4: Config file content generators

**Files:**
- Modify: `helper.sh`
- Modify: `tests/test_file_sync.bats`

**Interfaces:**
- Produces:
  - `_rsync_generate_sync_sh_content` → prints sync.sh script body to stdout
  - `_rsync_generate_service_content` → prints systemd service file to stdout
  - `_rsync_generate_timer_content` → prints systemd timer file to stdout

- [ ] **Step 1: Write failing tests**

```bash
@test "_rsync_generate_sync_sh_content: uses rsync -a --delete for directories" {
    run _rsync_generate_sync_sh_content
    [ "$status" -eq 0 ]
    [[ "$output" == *"rsync -a --delete"* ]]
}

@test "_rsync_generate_sync_sh_content: uses rsync -a for files" {
    run _rsync_generate_sync_sh_content
    [[ "$output" == *'rsync -a "$source"'* ]]
}

@test "_rsync_generate_sync_sh_content: reads pairs.conf" {
    run _rsync_generate_sync_sh_content
    [[ "$output" == *"pairs.conf"* ]]
}

@test "_rsync_generate_sync_sh_content: logs errors to sync.log" {
    run _rsync_generate_sync_sh_content
    [[ "$output" == *"sync.log"* ]]
}

@test "_rsync_generate_service_content: uses %h for home dir" {
    run _rsync_generate_service_content
    [[ "$output" == *"%h/.config/rsync-sync/sync.sh"* ]]
}

@test "_rsync_generate_timer_content: sets 30s interval" {
    run _rsync_generate_timer_content
    [[ "$output" == *"OnUnitActiveSec=30s"* ]]
}

@test "_rsync_generate_timer_content: sets 1s accuracy" {
    run _rsync_generate_timer_content
    [[ "$output" == *"AccuracySec=1s"* ]]
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
bats tests/
```
Expected: `13 tests, 7 failures`

- [ ] **Step 3: Add all three generators to `helper.sh`** (after `_rsync_build_pairs_from_dir`)

```bash
_rsync_generate_sync_sh_content() {
    cat <<'EOF'
#!/bin/bash
PAIRS_FILE="$HOME/.config/rsync-sync/pairs.conf"
LOG_FILE="$HOME/.config/rsync-sync/sync.log"
mkdir -p "$(dirname "$LOG_FILE")"
while IFS='|' read -r source target; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    if [[ ! -e "$source" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): source not found: $source" >> "$LOG_FILE"
        continue
    fi
    if [[ -d "$source" ]]; then
        mkdir -p "$target"
        rsync -a --delete "${source}/" "${target}/" 2>>"$LOG_FILE" \
            || echo "$(date '+%Y-%m-%d %H:%M:%S'): rsync failed: $source → $target" >> "$LOG_FILE"
    else
        mkdir -p "$(dirname "$target")"
        rsync -a "$source" "$target" 2>>"$LOG_FILE" \
            || echo "$(date '+%Y-%m-%d %H:%M:%S'): rsync failed: $source → $target" >> "$LOG_FILE"
    fi
done < "$PAIRS_FILE"
EOF
}

_rsync_generate_service_content() {
    cat <<'EOF'
[Unit]
Description=rsync file sync
After=network.target

[Service]
Type=oneshot
ExecStart=%h/.config/rsync-sync/sync.sh

[Install]
WantedBy=default.target
EOF
}

_rsync_generate_timer_content() {
    cat <<'EOF'
[Unit]
Description=rsync file sync timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
}
```

- [ ] **Step 4: Run to confirm pass**

```bash
bats tests/
```
Expected: `13 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add helper.sh tests/test_file_sync.bats
git commit -m "feat: add rsync config file content generators"
```

---

### Task 5: `_rsync_write_config` — write config files to disk

**Files:**
- Modify: `helper.sh`
- Modify: `tests/test_file_sync.bats`

**Interfaces:**
- Consumes: `_rsync_generate_sync_sh_content`, `_rsync_generate_service_content`, `_rsync_generate_timer_content`
- Produces: `_rsync_write_config PAIR...` → creates all config files; no stdout output

- [ ] **Step 1: Write failing tests**

```bash
@test "_rsync_write_config: creates pairs.conf with all pairs" {
    _rsync_write_config "/src/a|/dest/a" "/src/b|/dest/b"
    [ -f "$HOME/.config/rsync-sync/pairs.conf" ]
    run cat "$HOME/.config/rsync-sync/pairs.conf"
    [ "${lines[0]}" = "/src/a|/dest/a" ]
    [ "${lines[1]}" = "/src/b|/dest/b" ]
}

@test "_rsync_write_config: sync.sh is executable" {
    _rsync_write_config "/src/a|/dest/a"
    [ -x "$HOME/.config/rsync-sync/sync.sh" ]
}

@test "_rsync_write_config: creates systemd service file" {
    _rsync_write_config "/src/a|/dest/a"
    [ -f "$HOME/.config/systemd/user/rsync-sync.service" ]
}

@test "_rsync_write_config: creates systemd timer file" {
    _rsync_write_config "/src/a|/dest/a"
    [ -f "$HOME/.config/systemd/user/rsync-sync.timer" ]
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
bats tests/
```
Expected: `17 tests, 4 failures`

- [ ] **Step 3: Add `_rsync_write_config` to `helper.sh`** (after the generators)

```bash
_rsync_write_config() {
    local pairs=("$@")
    local config_dir="$HOME/.config/rsync-sync"
    local systemd_dir="$HOME/.config/systemd/user"

    mkdir -p "$config_dir" "$systemd_dir"

    printf '%s\n' "${pairs[@]}" > "$config_dir/pairs.conf"

    _rsync_generate_sync_sh_content > "$config_dir/sync.sh"
    chmod +x "$config_dir/sync.sh"

    _rsync_generate_service_content > "$systemd_dir/rsync-sync.service"
    _rsync_generate_timer_content > "$systemd_dir/rsync-sync.timer"
}
```

- [ ] **Step 4: Run to confirm pass**

```bash
bats tests/
```
Expected: `17 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add helper.sh tests/test_file_sync.bats
git commit -m "feat: add _rsync_write_config"
```

---

### Task 6: `_rsync_install_service` — enable systemd timer

**Files:**
- Modify: `helper.sh`

**Interfaces:**
- Consumes: `_rsync_write_config` (files must already exist on disk)
- Produces: `_rsync_install_service` → enables and starts `rsync-sync.timer`; returns 1 and prints instructions if systemd is unavailable

Note: This function interacts with systemd — no automated test. Verify manually.

- [ ] **Step 1: Add `_rsync_install_service` to `helper.sh`** (after `_rsync_write_config`)

```bash
_rsync_install_service() {
    if ! command -v systemctl &>/dev/null; then
        print_error "systemd is not available."
        print_warning "To enable systemd in WSL, add the following to /etc/wsl.conf:"
        print_info "  [boot]"
        print_info "  systemd=true"
        print_warning "Then restart WSL: run 'wsl --shutdown' from Windows, then reopen."
        return 1
    fi

    loginctl enable-linger "$USER" 2>/dev/null || true
    systemctl --user daemon-reload
    systemctl --user enable --now rsync-sync.timer
}
```

- [ ] **Step 2: Run existing tests to confirm no regressions**

```bash
bats tests/
```
Expected: `17 tests, 0 failures`

- [ ] **Step 3: Commit**

```bash
git add helper.sh
git commit -m "feat: add _rsync_install_service"
```

---

### Task 7: Interactive functions — multi-select and add pairs

**Files:**
- Modify: `helper.sh`

**Interfaces:**
- Consumes: `_rsync_apply_selection`, `_rsync_build_pairs_from_dir`
- Produces:
  - `_rsync_multi_select_from_dir` → prints `source|target` lines to stdout
  - `_rsync_add_pairs` → prints `source|target` lines to stdout

- [ ] **Step 1: Add `_rsync_multi_select_from_dir` to `helper.sh`** (after `_rsync_install_service`)

```bash
_rsync_multi_select_from_dir() {
    print_warning "Make sure your terminal is cd'd into the parent folder you want to sync FROM."
    print_info "Current directory: $PWD"
    echo ""

    local items=()
    while IFS= read -r item; do
        items+=("$item")
    done < <(ls -1 "$PWD" 2>/dev/null)

    if [[ ${#items[@]} -eq 0 ]]; then
        print_error "No files or directories found in $PWD."
        return 1
    fi

    print_header "Select items to sync"
    for i in "${!items[@]}"; do
        print_menu_item "$((i + 1))." "${items[$i]}"
    done
    echo ""
    print_info "Enter numbers separated by spaces (e.g. 1 3 5):"
    read -r selection

    local selected=()
    mapfile -t selected < <(_rsync_apply_selection "$selection" "${items[@]}")

    if [[ ${#selected[@]} -eq 0 ]]; then
        print_error "No valid items selected."
        return 1
    fi

    print_info "Enter the target directory (e.g. ~/.claude):"
    read -r target_dir
    target_dir="${target_dir/#\~/$HOME}"

    if [[ -z "$target_dir" ]]; then
        print_error "Target directory cannot be empty."
        return 1
    fi

    _rsync_build_pairs_from_dir "$PWD" "$target_dir" "${selected[@]}"
}
```

- [ ] **Step 2: Add `_rsync_add_pairs` to `helper.sh`** (after `_rsync_multi_select_from_dir`)

```bash
_rsync_add_pairs() {
    print_header "Add Sync Pairs"
    print_menu_item "1." "Multi-select from current directory"
    print_menu_item "2." "Enter path manually"
    print_info "Your choice:"
    read -r mode_choice

    case "$mode_choice" in
        1)
            _rsync_multi_select_from_dir
            ;;
        2)
            print_info "Enter full source path:"
            read -r src_path
            src_path="${src_path/#\~/$HOME}"
            print_info "Enter full target path:"
            read -r tgt_path
            tgt_path="${tgt_path/#\~/$HOME}"
            if [[ -z "$src_path" || -z "$tgt_path" ]]; then
                print_error "Source and target paths cannot be empty."
                return 1
            fi
            echo "${src_path}|${tgt_path}"
            ;;
        *)
            print_error "Invalid choice."
            return 1
            ;;
    esac
}
```

- [ ] **Step 3: Run existing tests to confirm no regressions**

```bash
bats tests/
```
Expected: `17 tests, 0 failures`

- [ ] **Step 4: Manual smoke test — multi-select**

```bash
cd /tmp && mkdir -p test_sync_src && touch test_sync_src/a.txt test_sync_src/b.txt && cd test_sync_src
# Source helper.sh directly and call the function:
bash -c 'source /home/patrick/docs/development/scripts/helper.sh; _rsync_multi_select_from_dir' <<< $'1 2\n/tmp/test_sync_dest'
```
Expected: prints `/tmp/test_sync_src/a.txt|/tmp/test_sync_dest/a.txt` and `/tmp/test_sync_src/b.txt|/tmp/test_sync_dest/b.txt`

- [ ] **Step 5: Commit**

```bash
git add helper.sh
git commit -m "feat: add interactive add-pairs flow with multi-select"
```

---

### Task 8: Management menu functions — view, remove, service control

**Files:**
- Modify: `helper.sh`
- Modify: `tests/test_file_sync.bats`

**Interfaces:**
- Consumes: `_rsync_write_config` output files
- Produces:
  - `_rsync_view_pairs` → prints numbered pair list to terminal
  - `_rsync_remove_pair` → rewrites pairs.conf with selected line removed
  - `_rsync_manage_service` → calls `systemctl --user` start/stop/restart/status

- [ ] **Step 1: Write failing tests for `_rsync_view_pairs`**

```bash
@test "_rsync_view_pairs: shows message when no pairs configured" {
    run _rsync_view_pairs
    [ "$status" -eq 0 ]
    [[ "$output" == *"No sync pairs"* ]]
}

@test "_rsync_view_pairs: lists pairs from pairs.conf" {
    mkdir -p "$HOME/.config/rsync-sync"
    printf '/src/a|/dest/a\n/src/b|/dest/b\n' > "$HOME/.config/rsync-sync/pairs.conf"
    run _rsync_view_pairs
    [ "$status" -eq 0 ]
    [[ "$output" == *"/src/a"* ]]
    [[ "$output" == *"/dest/b"* ]]
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
bats tests/
```
Expected: `19 tests, 2 failures`

- [ ] **Step 3: Add `_rsync_view_pairs` to `helper.sh`** (after `_rsync_add_pairs`)

```bash
_rsync_view_pairs() {
    local pairs_file="$HOME/.config/rsync-sync/pairs.conf"
    if [[ ! -f "$pairs_file" ]] || [[ ! -s "$pairs_file" ]]; then
        print_warning "No sync pairs configured."
        return
    fi
    print_header "Current Sync Pairs"
    local i=1
    while IFS='|' read -r source target; do
        print_menu_item "$i." "$source → $target"
        ((i++))
    done < "$pairs_file"
}
```

- [ ] **Step 4: Run to confirm pass**

```bash
bats tests/
```
Expected: `19 tests, 0 failures`

- [ ] **Step 5: Add `_rsync_remove_pair` to `helper.sh`** (after `_rsync_view_pairs`)

```bash
_rsync_remove_pair() {
    local pairs_file="$HOME/.config/rsync-sync/pairs.conf"
    if [[ ! -f "$pairs_file" ]] || [[ ! -s "$pairs_file" ]]; then
        print_warning "No sync pairs configured."
        return
    fi

    _rsync_view_pairs
    echo ""
    print_info "Enter the number of the pair to remove (or 0 to cancel):"
    read -r choice

    [[ "$choice" == "0" ]] && return

    local line_count
    line_count=$(wc -l < "$pairs_file")

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt "$line_count" ]]; then
        print_error "Invalid selection."
        return 1
    fi

    local pair
    pair=$(sed -n "${choice}p" "$pairs_file")
    local display="${pair/|/ → }"
    print_warning "Remove: $display? (y/n)"
    read -r confirm

    [[ "$confirm" != "y" ]] && return

    sed -i "${choice}d" "$pairs_file"
    print_success "Pair removed."
    systemctl --user restart rsync-sync.timer 2>/dev/null || true
}
```

- [ ] **Step 6: Add `_rsync_manage_service` to `helper.sh`** (after `_rsync_remove_pair`)

```bash
_rsync_manage_service() {
    print_header "Service Control"
    print_menu_item "1." "Start"
    print_menu_item "2." "Stop"
    print_menu_item "3." "Restart"
    print_menu_item "4." "Status"
    print_info "Your choice:"
    read -r svc_choice

    case "$svc_choice" in
        1) systemctl --user start rsync-sync.timer && print_success "Started." ;;
        2) systemctl --user stop rsync-sync.timer && print_success "Stopped." ;;
        3) systemctl --user restart rsync-sync.timer && print_success "Restarted." ;;
        4) systemctl --user status rsync-sync.timer ;;
        *) print_error "Invalid choice." ;;
    esac
}
```

- [ ] **Step 7: Run all tests to confirm no regressions**

```bash
bats tests/
```
Expected: `19 tests, 0 failures`

- [ ] **Step 8: Commit**

```bash
git add helper.sh tests/test_file_sync.bats
git commit -m "feat: add view, remove, and service management functions"
```

---

### Task 9: `setup_file_sync` entry point + menu wiring

**Files:**
- Modify: `helper.sh` — add `setup_file_sync`, extend `menu_items`, extend `menu_functions`

**Interfaces:**
- Consumes: all `_rsync_*` functions
- Produces: menu item 8 runs the full setup/management flow

- [ ] **Step 1: Add `setup_file_sync` to `helper.sh`** (after `_rsync_manage_service`, before the `menu_items` array)

```bash
setup_file_sync() {
    local config_dir="$HOME/.config/rsync-sync"
    local pairs_file="$config_dir/pairs.conf"

    if ! command -v rsync &>/dev/null; then
        print_error "rsync is not installed."
        print_warning "Install it with: sudo apt-get install -y rsync"
        exit 0
    fi

    if [[ ! -f "$pairs_file" ]]; then
        print_header "File Sync Setup"
        print_info "No existing configuration found. Let's set one up."
        echo ""

        local pairs=()
        mapfile -t pairs < <(_rsync_add_pairs)

        if [[ ${#pairs[@]} -eq 0 ]]; then
            print_error "No pairs added. Exiting."
            exit 0
        fi

        _rsync_write_config "${pairs[@]}"
        _rsync_install_service || exit 0

        echo ""
        print_success "Sync configured! Active pairs:"
        _rsync_view_pairs
    else
        while true; do
            print_header "File Sync Manager"
            print_menu_item "1." "Add sync pairs"
            print_menu_item "2." "View existing pairs"
            print_menu_item "3." "Remove a sync pair"
            print_menu_item "4." "Start / Stop / Restart service"
            print_menu_item "5." "Exit"
            print_info "Your choice:"
            read -r mgmt_choice

            case "$mgmt_choice" in
                1)
                    local new_pairs=()
                    mapfile -t new_pairs < <(_rsync_add_pairs)
                    if [[ ${#new_pairs[@]} -gt 0 ]]; then
                        printf '%s\n' "${new_pairs[@]}" >> "$pairs_file"
                        systemctl --user restart rsync-sync.timer 2>/dev/null || true
                        print_success "Pairs added."
                    fi
                    ;;
                2) _rsync_view_pairs ;;
                3) _rsync_remove_pair ;;
                4) _rsync_manage_service ;;
                5) exit 0 ;;
                *) print_error "Invalid choice." ;;
            esac
            echo ""
        done
    fi
    exit 0
}
```

- [ ] **Step 2: Add menu item 8 to `helper.sh`**

In the `menu_items` array, add the new entry:

```bash
menu_items=(
    "Find a file with text in it"
    "Find files by name"
    "Show disk usage"
    "Show network connections"
    "Show system info"
    "Find port usage"
    "Compare git branches without commit history"
    "Set up file sync"
)
```

In the `menu_functions` map, add the new entry:

```bash
declare -A menu_functions=(
    ["1"]="search_text_in_files"
    ["2"]="find_files_by_name"
    ["3"]="show_disk_usage"
    ["4"]="show_network_connections"
    ["5"]="show_system_info"
    ["6"]="find_port_usage"
    ["7"]="compare_git_branches_without_commit_history"
    ["8"]="setup_file_sync"
)
```

- [ ] **Step 3: Run all tests to confirm no regressions**

```bash
bats tests/
```
Expected: `19 tests, 0 failures`

- [ ] **Step 4: Manual end-to-end smoke test — first run**

```bash
cd /tmp && mkdir -p smoke_src && touch smoke_src/file1.txt smoke_src/file2.txt && cd smoke_src
bash /home/patrick/docs/development/scripts/helper.sh
```
Select `8`, then `1` (multi-select), select both items with `1 2`, enter `/tmp/smoke_dest`, confirm setup.

Expected: systemd timer enabled, `/tmp/smoke_dest/file1.txt` and `/tmp/smoke_dest/file2.txt` appear within 30s.

- [ ] **Step 5: Manual end-to-end smoke test — management menu**

Run `bash helper.sh` again and select `8`.
Expected: management menu appears (not setup flow).

Verify "View existing pairs" shows the two pairs; verify "Remove a sync pair" works.

- [ ] **Step 6: Commit**

```bash
git add helper.sh
git commit -m "feat: add setup_file_sync menu option (option 8)"
```
