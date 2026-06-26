#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print helper functions
print_error() {
    echo -e "${RED}$1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_header() {
    echo -e "${CYAN}========== $1 ==========${NC}"
}

print_menu_item() {
    echo -e "${GREEN}$1${NC} $2"
}

# Function to search for text in files
search_text_in_files() {
    print_info "Enter the path to search in (default: <current directory>):"
    read -r search_path
    search_path=${search_path:-.}

    print_info "Enter the text to search for:"
    read -r search_text

    print_info "Enter directories to exclude (comma-separated, or press Enter for no exclusions):"
    read -r exclude_dirs

    # Convert comma-separated list to --exclude-dir arguments
    exclude_args=""
    if [[ -n "$exclude_dirs" ]]; then
        IFS=',' read -ra dirs <<<"$exclude_dirs"
        for dir in "${dirs[@]}"; do
            exclude_args="$exclude_args --exclude-dir=$dir"
        done
    fi

    print_success "Searching for '$search_text' in $search_path..."
    grep -r $exclude_args "$search_text" "$search_path"
    exit 0
}

# Function to find files by name
find_files_by_name() {
    print_info "Enter the path to search in (default: ~/):"
    read -r search_path
    search_path=${search_path:-~/}

    print_info "Enter the file name pattern to search for (e.g., '*.js' or 'config.*'):"
    read -r file_pattern

    print_info "Enter directories to exclude (comma-separated, or press Enter for no exclusions):"
    read -r exclude_dirs

    # Convert comma-separated list to -not -path arguments
    exclude_args=""
    if [[ -n "$exclude_dirs" ]]; then
        IFS=',' read -ra dirs <<<"$exclude_dirs"
        for dir in "${dirs[@]}"; do
            exclude_args="$exclude_args -not -path '*/$dir/*'"
        done
    fi

    print_success "Searching for files matching '$file_pattern' in $search_path..."
    eval "find $search_path -type f -name '$file_pattern' $exclude_args"
    exit 0
}

# Function to show disk usage
show_disk_usage() {
    # Check for required commands
    if ! command -v du &>/dev/null || ! command -v df &>/dev/null; then
        print_error "Error: Required commands 'du' or 'df' are missing."
        print_warning "Please install them using:"
        echo "sudo apt-get update && sudo apt-get install -y coreutils"
        return 1
    fi

    # Get the actual user's home directory
    USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)

    print_header "=== Disk Usage Information ==="
    print_success "Overall disk usage:"
    df -h

    print_success "Largest directories in $USER_HOME:"
    du -h --max-depth=1 "$USER_HOME" | sort -hr | head -n 5
    exit 0
}

# Function to show network connections
show_network_connections() {
    # Check for ss
    if ! command -v ss &>/dev/null; then
        print_error "Error: 'ss' command is missing."
        print_warning "Please install it using:"
        echo "sudo apt-get update && sudo apt-get install -y iproute2"
        return 1
    fi

    print_info "Show all connections? (y/n, default: n):"
    read -r show_all
    show_all=${show_all:-n}

    print_header "=== Network Connections ==="

    if [[ "$show_all" == "y" ]]; then
        print_success "Showing all network connections..."
        print_success "\nTCP connections:"
        ss -tuln
        print_success "\nUDP connections:"
        ss -uln
    else
        print_success "Showing only listening connections..."
        print_success "\nTCP listening connections:"
        ss -tuln | grep LISTEN
        print_success "\nUDP listening connections:"
        ss -uln | grep LISTEN
    fi
    exit 0
}

# Function to show system info
show_system_info() {
    # Check for required commands
    if ! command -v lscpu &>/dev/null || ! command -v free &>/dev/null; then
        print_error "Error: Required commands 'lscpu' or 'free' are missing."
        print_warning "Please install them using:"
        echo "sudo apt-get update && sudo apt-get install -y procps lscpu"
        return 1
    fi

    print_header "=== System Information ==="
    print_success "OS: $(uname -a)"
    print_success "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | sed 's/^[ \t]*//')"
    print_success "Memory: $(free -h | grep Mem | awk '{print $2}') total"
    print_success "Disk: $(df -h / | tail -1 | awk '{print $2}') total"
    print_success "Uptime: $(uptime -p)"
    exit 0
}

# Function to find port usage
find_port_usage() {
    # Check for required commands
    if ! command -v ss &>/dev/null; then
        print_error "Error: 'ss' command is missing."
        print_warning "Please install it using:"
        echo "sudo apt-get update && sudo apt-get install -y iproute2"
        return 1
    fi

    print_info "Enter the port number to search for:"
    read -r port_number

    if ! [[ "$port_number" =~ ^[0-9]+$ ]]; then
        print_error "Error: Please enter a valid port number."
        return 1
    fi

    print_success "Searching for port $port_number..."
    print_header "=== Port Usage Information ==="

    # Show TCP connections with process info
    print_success "TCP connections:"
    tcp_connections=$(sudo ss -tulnp | grep ":$port_number")
    if [[ -n "$tcp_connections" ]]; then
        echo "$tcp_connections"
    else
        print_warning "No TCP connections found on port $port_number"
    fi

    # Show UDP connections with process info
    print_success "\nUDP connections:"
    udp_connections=$(sudo ss -ulnp | grep ":$port_number")
    if [[ -n "$udp_connections" ]]; then
        echo "$udp_connections"
    else
        print_warning "No UDP connections found on port $port_number"
    fi
    exit 0
}

compare_git_branches_without_commit_history() {
    # Check if you have are in a git repository
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        print_error "Error: Not in a git repository."
        return 1
    fi

    # Check if you have the colordiff command
    if ! command -v colordiff &>/dev/null; then
        print_error "Error: 'colordiff' command is missing."
        print_warning "Please install it using:"
        print_info "sudo apt-get update && sudo apt-get install -y colordiff"
        exit 0
    fi

    # base branch is the current branch in the terminal
    base_branch=$(git rev-parse --abbrev-ref HEAD)

    print_info "Enter the target branch name (default: main):"
    read -r target_branch
    target_branch=${target_branch:-main}

    mkdir -p /tmp/base /tmp/target

    git archive $base_branch | tar -x -C /tmp/base
    git archive $target_branch | tar -x -C /tmp/target

    diff -r -w -B -b -Z /tmp/base /tmp/target | colordiff

    # Get filenames that are different between branches
    filenames=$(diff -r -w -B -b -Z /tmp/base /tmp/target | grep -E "^(Only in|diff)" | sed 's/Only in //g' | sed 's/: /\//g' | sed 's/diff -r .*\/base\///g' | sed 's/ .*//g' | sort -u)
    if [[ -n "$filenames" ]]; then
        # Remove duplicate filenames IE the ones that start with /tmp/base/app would be the same as /tmp/target/app because they are the same file just in different locations
        filenames=$(echo "$filenames" | sed 's/\/tmp\/base\///g' | sed 's/\/tmp\/target\///g' | sort -u)
        print_header "Files that differ:"
        echo "$filenames"
    else
        print_warning "No file differences found"
    fi

    # Get number of files in the diff
    print_header "Number of files in the diff:"
    num_files=$(echo "$filenames" | grep -v "^$" | wc -l)
    print_success "$num_files"

    rm -rf /tmp/base /tmp/target
    exit 0
}

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

_rsync_build_pairs_from_dir() {
    local source_dir="$1"
    local target_dir="$2"
    shift 2
    local items=("$@")
    for item in "${items[@]}"; do
        echo "${source_dir}/${item}|${target_dir}/${item}"
    done
}

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

# Define menu items in order
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

# Define menu functions
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

# Function to display menu
display_menu() {
    print_header "\n=== Development Helper Menu ==="
    for i in "${!menu_items[@]}"; do
        print_menu_item "$((i + 1))." "${menu_items[$i]}"
    done
    print_header "=============================="
    print_info "Enter your choice (or press Ctrl+C to exit):"
}

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
