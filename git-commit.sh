#!/bin/bash

# Get the directory of this script (not the calling script)
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/scriptUtils/constants.sh"
source "$SCRIPT_DIR/scriptUtils/selectMenu.sh"

# Create a new git commit with the current date and time and place the cursor in the commit message
# This script is meant to be used as an alias in the .bashrc file
# Usage: alias commit="bash ~/git-commit.sh"

# Display help message
show_help() {
    print_header "Git Commit Helper"
    echo "A script to help create structured and consistent git commits."
    echo ""
    print_info "Usage:"
    echo "  commit [options]"
    echo ""
    print_info "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -s, --skip-ai  Skip AI suggestion and use manual input only"
    echo "  -d, --debug    Enable debug mode to show detailed API information"
    echo ""
    print_info "Environment Variables:"
    echo "  CLAUDE_API_KEY  Your Claude API key (required unless using --skip-ai)"
    echo "  USE_EMOJI      Set to 'true' to always use emojis in commit messages"
    echo "                 Example: export USE_EMOJI=true"
    echo "  DEBUG          Set to 'true' to enable debug mode for API troubleshooting"
    echo "                 Example: DEBUG=true commit"
    echo ""
    print_info "Available Commit Types:"
    for type in "${!COMMIT_TYPES[@]}"; do
        emoji=$(get_commit_emoji "$type")
        echo "  $type: ${COMMIT_TYPES[$type]} $emoji"
    done
    echo ""
    print_info "Features:"
    echo "  - Follows conventional commit format"
    echo "  - Supports commit scopes"
    echo "  - Optional emoji support"
    echo "  - AI-powered commit message suggestions using Claude API"
    echo "  - AI analysis of git diff to suggest relevant commit messages"
    echo "  - Automatic staging of changes if needed"
    echo ""
    print_info "Example usage:"
    echo "  commit                   # Run the full commit process"
    echo "  commit -h                # Show this help message"
    echo "  commit -s                # Skip AI suggestions"
    echo "  commit -d                # Run with debug mode enabled"
    echo ""
}

# Define commit types and their descriptions
declare -A COMMIT_TYPES
COMMIT_TYPES=(
    ["feature"]="New functionality or enhancement (will be converted to 'feat')"
    ["fix"]="Bug fixes or error corrections"
    ["docs"]="Documentation changes only"
    ["test"]="Adding or modifying tests"
    ["refactor"]="Code improvements without changing functionality"
    ["chore"]="Routine tasks, maintenance, dependencies"
    ["ci"]="Changes to CI configuration files and scripts"
)

# Parse command line arguments
parse_arguments() {
    SKIP_AI=false
    DEBUG=${DEBUG:-false}

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            show_help
            exit 0
            ;;
        -s | --skip-ai)
            SKIP_AI=true
            shift
            ;;
        -d | --debug)
            DEBUG=true
            shift
            ;;
        *)
            # Unknown option
            print_error "Unknown option: $1"
            print_info "Use --help to see available options"
            exit 1
            ;;
        esac
    done

    # Convert string to boolean for DEBUG if it was set via environment variable
    if [[ "$DEBUG" == "true" ]]; then
        DEBUG=true
        print_warning "Debug mode is ON. Will show detailed API information."
    else
        DEBUG=false
    fi

    # Show message if skipping AI
    if $SKIP_AI; then
        print_warning "Skipping AI suggestions, using manual input only."
    fi

    # Check for emoji preference in environment
    DEFAULT_USE_EMOJI=${USE_EMOJI:-false}
    # Convert string to boolean
    if [[ "$DEFAULT_USE_EMOJI" == "true" ]]; then
        DEFAULT_USE_EMOJI=true
    else
        DEFAULT_USE_EMOJI=false
    fi
}

# Check for API key and required dependencies
check_api_key() {
    if [ -z "$CLAUDE_API_KEY" ]; then
        print_error "Error: CLAUDE_API_KEY environment variable is not set."
        print_warning "Please set it before running this script:"
        print_warning "export CLAUDE_API_KEY=\"your-api-key\""
        return 1
    fi

    # Check for jq (required for JSON handling)
    if ! command -v jq &>/dev/null; then
        print_error "Error: jq is not installed but is required for JSON processing."
        print_warning "Please install jq using your package manager:"
        print_warning "For Ubuntu/Debian: sudo apt-get install jq"
        print_warning "For macOS: brew install jq"
        return 1
    fi

    return 0
}

# Create a temporary file with content
create_temp_file() {
    local content="$1"
    local temp_file=$(mktemp)
    echo "$content" >"$temp_file"
    echo "$temp_file"
}

# Create a JSON payload for Claude API using jq
create_claude_payload() {
    local prompt="$1"
    local system_message="$2"
    local temp_json=$(mktemp)

    # Use jq to properly create the JSON object with escaped strings
    jq -n --arg system "$system_message" --arg prompt "$prompt" '{
        "model": "claude-sonnet-4-20250514",
        "max_tokens": 300,
        "system": $system,
        "messages": [
            {
                "role": "user",
                "content": $prompt
            }
        ]
    }' >"$temp_json"

    echo "$temp_json"
}

# Call Claude API with given prompt
call_claude_api() {
    local prompt=$1
    local system_message=$2
    local api_url="https://api.anthropic.com/v1/messages"

    print_info "Sending request to Claude API..."

    # Create the JSON payload using our helper function
    local payload_file=$(create_claude_payload "$prompt" "$system_message")

    # Debug information
    if $DEBUG; then
        print_info "Request payload:"
        cat "$payload_file"
    fi

    # Make the API call using the payload file
    local response
    if $DEBUG; then
        # Use verbose mode and save both response and debug info
        local debug_file="/tmp/claude_api_debug.log"
        print_info "Saving API debug info to $debug_file"

        # Send stdout to one file and stderr (verbose output) to debug file
        curl -v -X POST \
            -H "x-api-key: $CLAUDE_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -H "content-type: application/json" \
            -d @"$payload_file" \
            "$api_url" >/tmp/claude_api_response.json 2>"$debug_file"

        response=$(cat /tmp/claude_api_response.json)
    else
        # Normal quiet mode
        response=$(
            curl -s -X POST \
                -H "x-api-key: $CLAUDE_API_KEY" \
                -H "anthropic-version: 2023-06-01" \
                -H "content-type: application/json" \
                -d @"$payload_file" \
                "$api_url"
        )
    fi

    # Remove the temp file
    rm "$payload_file"

    # Check for curl errors
    if [ $? -ne 0 ]; then
        print_error "ERROR: Failed to communicate with Claude API"
        return 1
    fi

    # Check for empty response
    if [ -z "$response" ]; then
        print_error "ERROR: Empty response from Claude API"
        return 1
    fi

    # Debug - print full response
    if $DEBUG; then
        print_info "Raw response: $response"
        print_info "Response saved to /tmp/claude_api_response.json for inspection"
        print_info "Curl debug info saved to /tmp/claude_api_debug.log"
    fi

    # Check if the response contains an error field specifically
    if echo "$response" | grep -q '"error":'; then
        error_message=$(echo "$response" | jq -r '.error.message // .error.type // .error // "Unknown error"')
        print_error "API Error: $error_message"

        if [[ "$error_message" == "Unknown error" ]] || $DEBUG; then
            print_warning "Full error response: $response"
        fi

        # Print a more helpful message for common errors
        if [[ "$error_message" == *"not valid JSON"* ]]; then
            print_warning "This is likely due to special characters in your input. Try simplifying your adjustment request."
        fi

        return 1
    fi

    # Extract the completion from the response using multiple approaches
    local completion=""

    # First attempt: Extract from content array with type text
    completion=$(echo "$response" | jq -r '.content[] | select(.type == "text") | .text' 2>/dev/null)

    # Second attempt: Try a more direct approach
    if [ -z "$completion" ]; then
        if $DEBUG; then
            print_warning "First extraction method failed, trying direct content text extraction..."
        fi
        completion=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)
    fi

    # Third attempt: Use grep as a fallback
    if [ -z "$completion" ]; then
        if $DEBUG; then
            print_warning "JQ extraction failed, trying grep fallback..."
        fi
        completion=$(echo "$response" | grep -o '"text":"[^"]*"' | head -1 | sed 's/"text":"//;s/"$//')
    fi

    # If still no content, return error
    if [ -z "$completion" ]; then
        print_error "ERROR: Failed to extract content from the API response"
        if $DEBUG; then
            print_warning "Raw response: $response"
        fi
        echo "ERROR: Failed to extract content from API response"
        return 1
    fi

    # Debug - show extracted completion
    if $DEBUG; then
        print_success "Successfully extracted completion: $completion"
    fi

    echo "$completion"
    return 0
}

# Show git diff preview
show_diff_preview() {
    print_header "Changes to be committed:"
    git diff --cached --color | cat
    echo ""
}

# Function to get emoji for commit type
get_commit_emoji() {
    local commit_type=$1

    case "$commit_type" in
    "feat" | "feature") echo "✨" ;; # Sparkles for new features
    "fix") echo "🐛" ;;              # Bug for fixes
    "docs") echo "📚" ;;             # Books for documentation
    "test") echo "🧪" ;;             # Test tube for tests
    "refactor") echo "♻️" ;;        # Recycle for refactoring
    "chore") echo "🔧" ;;            # Wrench for chores
    "ci") echo "👷" ;;               # Construction worker for CI changes
    *) echo "" ;;                   # No emoji for unknown types
    esac
}

# Handle changes staging
check_and_stage_changes() {
    # Check if there are any staged changes
    if ! git diff --cached --quiet; then
        # Show diff preview
        show_diff_preview
        return 0
    else
        print_warning "No staged changes found!"
        print_info "Would you like to stage all changes? [y/n]"
        read -p "" stage_all

        # Accept both uppercase and lowercase
        if [[ "$stage_all" == "y" || "$stage_all" == "Y" ]]; then
            git add -A
            print_success "All changes staged."
            show_diff_preview
            return 0
        else
            print_error "No changes to commit. Exiting."
            return 1
        fi
    fi
}

# Predict commit type using AI
predict_commit_type() {
    local git_diff=$1

    print_info "Predicting commit type based on git diff..."

    # Create system message for type prediction
    local type_system_message="You are a git commit type classifier. 
Analyze the git diff and determine the most appropriate commit type.
Respond ONLY with one of these commit types and nothing else:
- feat: for new features or significant enhancements
- fix: for bug fixes
- docs: for documentation changes only
- test: for adding or modifying tests
- refactor: for code improvements without changing functionality
- chore: for routine tasks, maintenance, dependencies
- ci: for changes to CI configuration files and scripts

Based on the changes in the git diff, respond with ONLY the commit type (e.g. 'feat', 'fix', etc.) and no other text."

    # Create prompt for AI to analyze diff for type prediction
    local type_prompt="Here is the git diff for the staged changes. Please analyze it and determine the most appropriate commit type:

$git_diff

Respond with ONLY the commit type (e.g. 'feat', 'fix', etc.) and no other text."

    # Call Claude API for type prediction
    local ai_type_prediction=$(call_claude_api "$type_prompt" "$type_system_message")

    # Check if API call was successful
    if [[ $ai_type_prediction == ERROR* ]] || [ -z "$ai_type_prediction" ]; then
        print_error "Failed to predict commit type. Please select manually."
        return 1
    else
        # Clean up the response and set it as commit type
        local predicted_type=$(echo "$ai_type_prediction" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        print_success_special "AI predicted commit type: " "$predicted_type"
        echo "$predicted_type"
        return 0
    fi
}

# Validate predicted commit type
validate_commit_type() {
    local commit_type=$1

    local is_valid=false
    for type in "${!COMMIT_TYPES[@]}"; do
        if [[ "$commit_type" == "$type" || ("$commit_type" == "feat" && "$type" == "feature") ]]; then
            is_valid=true
            break
        fi
    done

    echo "$is_valid"
}

# Select commit type
select_commit_type() {
    local git_diff=$1

    # Extract commit types for selection menu
    local commit_type_names=("${!COMMIT_TYPES[@]}")
    local commit_type_descriptions=()

    # Create array of descriptions for display
    for type in "${commit_type_names[@]}"; do
        commit_type_descriptions+=("$type: ${COMMIT_TYPES[$type]}")
    done

    # Add option for AI to predict commit type
    if ! $SKIP_AI; then
        commit_type_descriptions=("ai_predict: Let AI predict commit type based on changes" "${commit_type_descriptions[@]}")
    fi

    # Set default option - use index instead of full text since select_menu expects simple identifiers
    local default_option="feature"
    if ! $SKIP_AI; then
        default_option="1" # First option (ai_predict) when AI is enabled
    fi

    # Display menu with descriptions
    local commit_type=$(select_menu "Commit type" "$default_option" "${commit_type_descriptions[@]}")

    # Extract just the type from the selection (remove description)
    commit_type=$(echo "$commit_type" | cut -d':' -f1)

    # Handle the case where "1" is returned instead of "ai_predict"
    if [[ "$commit_type" == "1" ]] && ! $SKIP_AI; then
        commit_type="ai_predict"
    fi

    # If AI prediction is requested and not skipping AI
    if [ "$commit_type" == "ai_predict" ] && ! $SKIP_AI; then
        local predicted_type=$(predict_commit_type "$git_diff")

        # Check if prediction was successful
        if [[ $predicted_type == ERROR* ]] || [ -z "$predicted_type" ]; then
            # Display menu with descriptions again for manual selection
            commit_type=$(select_menu "Commit type" "feature" "${commit_type_descriptions[@]:1}")
            commit_type=$(echo "$commit_type" | cut -d':' -f1)
        else
            commit_type="$predicted_type"

            # Validate that the predicted type is valid
            local is_valid=$(validate_commit_type "$commit_type")

            if [[ "$is_valid" != "true" ]]; then
                print_warning "AI predicted an invalid commit type. Please select manually."
                # Display menu with descriptions again for manual selection
                commit_type=$(select_menu "Commit type" "feature" "${commit_type_descriptions[@]:1}")
                commit_type=$(echo "$commit_type" | cut -d':' -f1)
            fi
        fi
    fi

    # Normalize some commit types to conventional format
    if [ "$commit_type" == "feature" ]; then
        commit_type="feat"
    fi

    print_success_special "Selected commit type: " "$commit_type"
    echo "$commit_type"
}

# Get commit scope
get_commit_scope() {
    # Ask for scope (optional)
    print_info "Enter scope (optional, e.g., 'auth', 'ui', etc.):"
    read -p "Scope: " scope
    echo "$scope"
}

# Determine if emoji should be used
should_use_emoji() {
    # Ask if user wants to use emoji
    if $DEFAULT_USE_EMOJI; then
        use_emoji="y"
        print_info "Using emoji by default (set by USE_EMOJI environment variable)"
    else
        print_info "Use emoji in commit message? [y/n]"
        read -p "" use_emoji
    fi

    if [[ "$use_emoji" == "y" || "$use_emoji" == "Y" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Generate commit message using AI
generate_ai_commit_message() {
    local git_diff=$1
    local formatted_type=$2
    local emoji=$3

    # Create system message for git diff analysis
    local diff_system_message="You are a git commit message assistant. 
Analyze the git diff and suggest a commit message following the conventional commit format.

Format the message in two parts:
1. FIRST LINE: A concise summary (under 50 chars) that clearly states what was changed
2. BODY: A detailed explanation SEPARATED BY A BLANK LINE from the summary

The first line should:
- Be specific and clear about what was changed
- Start with the commit type followed by a colon
- Be written in imperative mood (e.g., 'fix', not 'fixed')
- Include the specific component/module affected (e.g., 'websocket auth')

The body should be clear and informative:
- Explain what the system expected vs what was happening
- Describe the impact in plain language
- Be direct and to the point
- Use simple, clear technical explanations"

    if [ -n "$emoji" ]; then
        diff_system_message="$diff_system_message
Start the first line with: $emoji $formatted_type:"
    else
        diff_system_message="$diff_system_message
Start the first line with: $formatted_type:"
    fi

    diff_system_message="$diff_system_message

Examples:
1. Good commit message example:
   fix(websocket auth): remove base64 encoding from access token

   Server expects raw tokens, not base64-encoded. This fixes authentication
   failures where the websocket connection was being rejected due to the
   server being unable to validate the encoded token format.

2. Another good example:
   feat(user auth): add remember me checkbox to login form

   Implements persistent login with secure HttpOnly cookies.
   Users can now stay logged in between sessions without
   needing to re-authenticate each time they visit."

    # Create prompt for AI to analyze diff
    local diff_prompt="Here is the git diff for the staged changes. Please analyze it and suggest a clear commit message using the commit type '$formatted_type':

$git_diff

In the commit body, explain the change in simple, direct terms focusing on what was expected vs. what was happening. Use clear language like 'Server expects X, but was receiving Y' when applicable."

    # Call Claude API for diff analysis
    print_info "Generating AI suggestion based on git diff..."
    local ai_suggestion=$(call_claude_api "$diff_prompt" "$diff_system_message")

    echo "$ai_suggestion"
}

# Get manual commit info
get_manual_commit_info() {
    # Get manual input
    print_info "What was changed?"
    read -p "Change description: " what_changed

    print_info "Reason for the change (optional)?"
    read -p "Reason: " reason

    echo "$what_changed|$reason"
}

# Generate commit message manually
generate_manual_commit_message() {
    local formatted_type=$1
    local emoji=$2
    local what_changed=$3
    local reason=$4
    local system_message=$5

    # If skipping AI, construct a conventional commit message directly
    if $SKIP_AI; then
        if [ -n "$emoji" ]; then
            local completion="$emoji $formatted_type: $what_changed"
        else
            local completion="$formatted_type: $what_changed"
        fi

        if [ -n "$reason" ]; then
            completion="$completion ($reason)"
        fi

        print_success_special "Commit message: " "$completion"
        echo "$completion"
        return
    fi

    print_info "Generating commit message..."

    # Create the initial prompt content
    local user_prompt="Generate a concise and clear commit message for the following changes: 'Type: $formatted_type; Changes: $what_changed'"

    if [ -n "$emoji" ]; then
        user_prompt="Generate a concise and clear commit message for the following changes: 'Type: $formatted_type; Emoji: $emoji; Changes: $what_changed'"
    fi

    if [ -n "$reason" ]; then
        user_prompt="$user_prompt; Reason: $reason"
    fi

    user_prompt="$user_prompt. 
The message should clearly state the actions taken, the reasons for those actions, and include specific details about the modifications. 
Start with the commit type followed by a colon (e.g., 'fix: '). 
Keep it brief and informative."

    local completion=$(call_claude_api "$user_prompt" "$system_message")

    # Check if API call was successful
    if [[ $completion == ERROR* ]] || [ -z "$completion" ]; then
        print_error "API call failed or returned empty response."
        print_warning "Falling back to a basic commit message format."

        # Use direct format as fallback
        if [ -n "$emoji" ]; then
            completion="$emoji $formatted_type: $what_changed"
        else
            completion="$formatted_type: $what_changed"
        fi

        if [ -n "$reason" ]; then
            completion="$completion ($reason)"
        fi
    fi

    print_success_special "Commit message: " "$completion"
    echo "$completion"
}

# Adjust commit message based on user feedback
adjust_commit_message() {
    local completion=$1
    local system_message=$2

    print_info "What would you like to adjust in the commit message?"
    print_header "Your instruction (e.g., 'Please make the reason clear and more detailed.'):"
    read adjustment_instruction

    # Build the prompt for adjusting the commit message
    print_info "Processing adjustment request..."

    # Create the prompt content
    local prompt_content="Given the current commit message: 
\"$completion\"

Please adjust it according to this instruction: 
\"$adjustment_instruction\"

Make the message concise and clear while following the instruction.
Ensure it effectively communicates the key actions and reasons."

    # Use the prompt content directly
    local adjustment_prompt="$prompt_content"

    print_info "Adjusting commit message..."
    local adjusted_completion=$(call_claude_api "$adjustment_prompt" "$system_message")

    # Check if API call was successful
    if [[ $adjusted_completion == ERROR* ]]; then
        print_error "$adjusted_completion"
        print_warning "Please try a different adjustment or simplify your request."
        print_warning "Avoid special characters or complex formatting in your instructions."
        echo "ERROR"
    else
        print_success_special "Adjusted commit message: " "$adjusted_completion"
        echo "$adjusted_completion"
    fi
}

# Create commit with message
create_commit() {
    local message=$1

    # Create a new git commit with the message, handle multi-line messages
    # Write to temp file to preserve line breaks
    local commit_msg_file=$(mktemp)
    echo "$message" >"$commit_msg_file"

    # Use the file for the commit message
    git commit -F "$commit_msg_file"
    rm "$commit_msg_file"
    print_success_special "Commit created " "successfully!"
}

# Function to generate commit message
generate_commit() {
    # Check if API key is available
    if ! $SKIP_AI; then
        check_api_key || return 1
    fi

    # Check and stage changes if needed
    check_and_stage_changes || return 1

    # Get the git diff for AI analysis
    git_diff=$(git diff --cached)

    # Select commit type
    commit_type=$(select_commit_type "$git_diff")

    # Get scope
    scope=$(get_commit_scope)

    # Format commit type with scope if provided
    formatted_type="$commit_type"
    if [ -n "$scope" ]; then
        formatted_type="$commit_type($scope)"
        print_success_special "Using scope: " "$scope"
    fi

    # Determine if emoji should be used
    use_emoji=$(should_use_emoji)

    emoji=""
    if [[ "$use_emoji" == "true" ]]; then
        emoji=$(get_commit_emoji "$commit_type")
        if [ -n "$emoji" ]; then
            print_success_special "Using emoji: " "$emoji"
        else
            print_warning "No emoji found for commit type: $commit_type"
        fi
    fi

    # Define system message for Claude
    system_message="Generate a concise commit message (max 50 chars) following the format: '$formatted_type: description; reason'."

    if [ -n "$emoji" ]; then
        system_message="Generate a concise commit message (max 50 chars) following the format: '$emoji $formatted_type: description; reason'."
    fi

    system_message="$system_message
Use present tense with imperative tone.
Include specific details about files and changes but maintain brevity.
Separate thoughts with semicolons and avoid references to individuals.
For fixes, mention both what was fixed and the cause of the issue where appropriate.
When adjusting a commit message, maintain context of previous adjustments and apply the requested changes to the most recent version."

    # Try AI suggestion if not skipped
    if ! $SKIP_AI; then
        # Analyze git diff to suggest a commit message
        print_info "Analyzing git diff to suggest a commit message..."

        if [ -z "$git_diff" ]; then
            print_warning "No staged changes found for analysis."
        else
            # Generate commit message using AI
            ai_suggestion=$(generate_ai_commit_message "$git_diff" "$formatted_type" "$emoji")

            # Check if API call was successful
            if [[ $ai_suggestion == ERROR* ]] || [ -z "$ai_suggestion" ]; then
                print_error "Failed to generate AI suggestion."
            else
                # Display the AI suggestion (handle multi-line messages)
                print_success_block "AI suggests:" "$ai_suggestion"
                print_info "Use this suggestion? [y/n]"
                read -p "" use_ai_suggestion

                # Accept any valid yes response
                if [[ "$use_ai_suggestion" == "y" || "$use_ai_suggestion" == "Y" || "$use_ai_suggestion" == "" ]]; then
                    print_success "Using AI suggestion as commit message"
                    create_commit "$ai_suggestion"
                    return 0
                fi
            fi
        fi
    fi

    # If we get here, either AI was skipped, AI suggestion failed, or user declined the suggestion
    # Get manual input
    manual_info=$(get_manual_commit_info)
    what_changed=$(echo "$manual_info" | cut -d'|' -f1)
    reason=$(echo "$manual_info" | cut -d'|' -f2)

    # Generate the commit message based on manual input
    completion=$(generate_manual_commit_message "$formatted_type" "$emoji" "$what_changed" "$reason" "$system_message")

    # Loop to allow for endless feedback until the user is satisfied
    while true; do
        print_info "Do you want to commit this message? [y/n]"
        print_warning "(y: yes, n: no - adjust message)"
        read -p "" confirm

        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            create_commit "$completion"
            break
        else
            adjusted_completion=$(adjust_commit_message "$completion" "$system_message")

            if [[ "$adjusted_completion" != "ERROR" ]]; then
                # Save the previous completion for context
                previous_completion="$completion"
                completion="$adjusted_completion" # Update completion for the next iteration
            fi
        fi
    done
}

# Main script execution
main() {
    parse_arguments "$@"
    generate_commit
}

main "$@"
