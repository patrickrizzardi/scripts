#!/bin/bash

blue_text='\033[0;36m'
red_text='\033[0;31m'
green_text='\033[0;32m'
bold_text='\033[1m'
color_reset='\033[0m'

# Default service name
service="app"
instructions="\n${blue_text}${bold_text}Select the service you want to run ${color_reset}[Use arrows to move cursor, Enter to select]"

# Get the services from the docker-compose file and remove the leading spaces and the colon
exclude_patterns="(cache|default)"
options=($(grep -oP '^\s{2}\w+:' docker-compose.yml | grep -vE "^\s{2}($exclude_patterns):" | tr -d ':' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'))

function Menu {
    local indicator_arrow="${green_text}${bold_text}>${color_reset}"
    local selected_options=0
    local length=${#options[@]}
    local instructions_printed=false

    # Print the menu
    function Print_Menu {
        # Clear what was previously printed
        tput cuu $length
        tput ed

        if [[ $instructions_printed == false ]]; then
            echo -e $instructions
            instructions_printed=true
        fi

        for ((i = 0; i < length; i++)); do
            if [[ $i -eq $selected_options ]]; then
                echo -e "${indicator_arrow} ${options[$i]}"
            else
                echo "  ${options[$i]}"
            fi
        done
    }

    Print_Menu

    # Read the key pressed
    while read -rsn1 key; do
        case $key in
        A) # Up
            if [[ $selected_options -gt 0 ]]; then
                ((selected_options--))
            fi
            Print_Menu

            ;;
        B) # Down
            if [[ $selected_options -lt $((length - 1)) ]]; then
                ((selected_options++))
            fi
            Print_Menu
            ;;

        "") # Enter
            break
            ;;
        esac
    done

    service=${options[$selected_options]}
}

# Run docker command with appropriate flags
run_docker_command() {
    local service=$1
    shift

    # Try with ports first, if it fails try without
    docker compose run --rm --service-ports -it "$service" "$@" ||
        docker compose run --rm -it "$service" "$@"

}

# If no arguments provided, show the menu to select the service
if [ $# -eq 0 ]; then
    Menu
    # Run the selected service with no additional arguments
    run_docker_command "$service"
else
    # Get the first argument as service name
    service="$1"
    shift # Remove the first argument

    # Run with the remaining arguments
    run_docker_command "$service" "$@"
fi
