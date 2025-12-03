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

# Define menu items in order
menu_items=(
    "Find a file with text in it"
    "Find files by name"
    "Show disk usage"
    "Show network connections"
    "Show system info"
    "Find port usage"
    "Compare git branches without commit history"
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
while true; do
    display_menu
    read -r choice

    if [[ -n "${menu_functions[$choice]}" ]]; then
        eval "${menu_functions[$choice]}"
    else
        print_error "Invalid choice. Please try again."
    fi
done
