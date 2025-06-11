#!/bin/bash

# Get the directory of this script (not the calling script)
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Source the constants utility
source "$SCRIPT_DIR/constants.sh"

# Function to display a selection menu and return the selected option
# Usage: selectMenu "Menu Title" "Default Option" "Option1" "Option2" ...
# Returns: The selected option
select_menu() {
    local title="$1"
    local default_option="$2"
    local options=("${@:3}")

    display_menu "$title" "$default_option" "${options[@]}"

    # Read user input
    local choice
    echo -n "Enter choice: " >&2
    read choice

    # If user just pressed enter, use default
    if [ -z "$choice" ]; then
        print_success "Using default: $default_option"
        echo "$default_option"
        return
    fi

    # Check if choice is a number
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        # Convert to zero-based index
        local index=$((choice - 1))

        # Check if the index is valid
        if [ "$index" -ge 0 ] && [ "$index" -lt "${#options[@]}" ]; then
            print_success "Selected: ${options[$index]}"
            echo "${options[$index]}"
            return
        fi
    fi

    # If we get here, the choice wasn't valid, so use default
    print_warning "Invalid choice, using default: $default_option"
    echo "$default_option"
}

display_menu() {
    local title="$1"
    local default_option="$2"
    local options=("${@:3}")

    echo "" >&2
    print_header "$title"
    for i in "${!options[@]}"; do
        print_menu_item "$((i + 1))." "${options[$i]}"
    done
    print_footer
    print_info "Enter your choice (default: $default_option, or press Ctrl+C to exit):"
}
