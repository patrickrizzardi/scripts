#!/bin/bash

# Smart Git Commit Helper
# Intelligently groups changes into logical commits with AI-powered suggestions
# Usage: commit [options]

# Get the directory of this script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/scriptUtils/constants.sh"
source "$SCRIPT_DIR/scriptUtils/selectMenu.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

CLAUDE_API_VERSION="2023-06-01"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"  # Fast and accurate

# ============================================================================
# CLEANUP & SIGNAL HANDLING
# ============================================================================

cleanup_on_exit() {
    local exit_code=$?

    # Clean up temp files (common patterns used by this script)
    rm -f /tmp/claude_api_response.json 2>/dev/null
    rm -f /tmp/claude_api_debug.log 2>/dev/null

    # If interrupted (non-zero exit), show warning
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 1 ]; then
        echo ""
        print_warning "Script interrupted!"
        print_info "Your git staging area may be in an inconsistent state"
        print_info "Run 'git status' to check current state"
    fi
}

# Set up trap for cleanup on exit, interrupt, and termination
trap cleanup_on_exit EXIT INT TERM

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_progress() {
    local step="$1"
    local total="$2"
    local message="$3"

    if $VERBOSE; then
        print_info "[$step/$total] $message"
    fi
}

# ============================================================================
# HELP & DOCUMENTATION
# ============================================================================

show_help() {
    print_header "Smart Git Commit Helper"
    echo "Create structured, conventional commits with AI-powered suggestions"
    echo ""
    print_info "Usage:"
    echo "  commit [options]"
    echo ""
    print_info "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -s, --single         Single commit mode (create one commit with all changes)"
    echo "  -m, --manual         Manual mode (skip AI and use manual input only)"
    echo "  -d, --debug          Show detailed API debug information"
    echo "  -v, --verbose        Show progress indicators during execution"
    echo "  --dry-run            Preview mode - show what would happen without creating commits"
    echo "  --co-author <email>  Add co-author to commit (format: 'Name <email>')"
    echo ""
    print_info "Environment Variables:"
    echo "  CLAUDE_API_KEY  Claude API key (required unless using --manual)"
    echo "  CLAUDE_MODEL    Claude model to use (default: claude-sonnet-4-20250514)"
    echo "  USE_EMOJI       Set to 'true' to always use emojis (export USE_EMOJI=true)"
    echo "  DEBUG           Enable debug mode (DEBUG=true commit)"
    echo ""
    print_info "Commit Types:"
    echo "  feat     - New features or enhancements"
    echo "  fix      - Bug fixes"
    echo "  docs     - Documentation only"
    echo "  test     - Tests"
    echo "  refactor - Code improvements"
    echo "  chore    - Maintenance, dependencies"
    echo "  ci       - CI/CD changes"
    echo ""
    print_info "Workflows:"
    echo ""
    echo "  GROUPED MODE (default):"
    echo "    Intelligently splits changes into multiple atomic commits"
    echo "    • AI analyzes all changes and identifies logical groups"
    echo "    • Suggests separate commits by feature/fix/type"
    echo "    • Silently auto-detects scope for each commit"
    echo "    • Creates clean, reviewable commit history"
    echo "    • Each group gets its own tailored commit message"
    echo ""
    echo "  SINGLE COMMIT MODE (-s/--single flag):"
    echo "    Creates one commit with all staged changes"
    echo "    • AI analyzes changes and suggests commit message"
    echo "    • Silently auto-detects scope from changed files"
    echo "    • Interactive editing and adjustments"
    echo "    • Falls back to manual mode if AI fails"
    echo ""
    print_info "AI Features:"
    echo "  • Automatic commit type detection (feat/fix/docs/etc.)"
    echo "  • Silent scope auto-detection from file paths (no prompts!)"
    echo "  • Smart commit message generation with WHY and impact"
    echo "  • Change grouping for atomic commits"
    echo ""
    print_info "Examples:"
    echo "  commit                    # Grouped commits with AI (default)"
    echo "  commit -s                 # Single commit mode with AI"
    echo "  commit -s -m              # Manual single commit (no AI)"
    echo "  commit -m                 # Manual grouped commits (no AI)"
    echo "  USE_EMOJI=true commit     # Grouped commits with emojis"
    echo ""
}

# ============================================================================
# COMMIT TYPES
# ============================================================================

declare -A COMMIT_TYPES
COMMIT_TYPES=(
    ["feat"]="New features or enhancements"
    ["fix"]="Bug fixes"
    ["docs"]="Documentation only"
    ["test"]="Tests"
    ["refactor"]="Code improvements"
    ["chore"]="Maintenance, dependencies"
    ["ci"]="CI/CD changes"
)

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_arguments() {
    SKIP_AI=false
    DEBUG=${DEBUG:-false}
    VERBOSE=false
    DRY_RUN=false
    GROUP_COMMITS=true  # Default to grouped mode
    CO_AUTHORS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            show_help
            exit 0
            ;;
        -s | --single)
            GROUP_COMMITS=false  # Single commit mode
            shift
            ;;
        -m | --manual)
            SKIP_AI=true
            shift
            ;;
        -d | --debug)
            DEBUG=true
            shift
            ;;
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --co-author)
            if [ -z "$2" ]; then
                print_error "--co-author requires an argument"
                print_info "Format: --co-author 'Name <email@example.com>'"
                exit 1
            fi
            CO_AUTHORS+=("$2")
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            print_info "Use --help to see available options"
            exit 1
            ;;
        esac
    done

    # Set debug mode
    [[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false
    $DEBUG && print_warning "Debug mode enabled"

    # Show verbose mode
    $VERBOSE && print_info "Verbose mode enabled"

    # Show dry-run mode
    if $DRY_RUN; then
        print_warning "DRY-RUN MODE: No commits will be created"
        print_info "This is a preview only - git history will not be modified"
    fi

    # Show co-authors
    if [ ${#CO_AUTHORS[@]} -gt 0 ]; then
        print_info "Co-authors: ${#CO_AUTHORS[@]}"
        for author in "${CO_AUTHORS[@]}"; do
            echo "  - $author"
        done
    fi

    # Show AI skip message
    $SKIP_AI && print_warning "AI suggestions disabled (manual mode)"

    # Show grouping message
    if $GROUP_COMMITS; then
        print_info "Grouped commit mode (use -s/--single to disable)"
    else
        print_info "Single commit mode"
    fi

    # Set emoji preference
    DEFAULT_USE_EMOJI=${USE_EMOJI:-false}
    [[ "$DEFAULT_USE_EMOJI" == "true" ]] && DEFAULT_USE_EMOJI=true || DEFAULT_USE_EMOJI=false
}

# ============================================================================
# VALIDATION & CHECKS
# ============================================================================

check_api_key() {
    if [ -z "$CLAUDE_API_KEY" ]; then
        print_error "CLAUDE_API_KEY not set"
        print_warning "Set it with: export CLAUDE_API_KEY=\"your-api-key\""
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        print_error "jq is required but not installed"
        print_warning "Install: apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        return 1
    fi

    return 0
}

check_has_any_changes() {
    # Check for any changes (staged OR unstaged OR untracked)
    # Used by grouped mode - DOES NOT stage anything, just checks

    # Check both staged and unstaged changes
    local has_unstaged=false
    local has_staged=false

    git diff --quiet 2>/dev/null || has_unstaged=true
    git diff --cached --quiet 2>/dev/null || has_staged=true

    # Check for untracked files (excluding .gitignore)
    local untracked_count=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)

    # If we have ANY changes (staged, unstaged, or untracked)
    if $has_unstaged || $has_staged || [ $untracked_count -gt 0 ]; then
        local staged_count=$(git diff --cached --name-only --find-renames 2>/dev/null | wc -l)
        local unstaged_count=$(git diff --name-only --find-renames 2>/dev/null | wc -l)

        print_info "Found changes: $staged_count staged, $unstaged_count unstaged, $untracked_count untracked"
        print_info "Files will be staged per-group when creating commits"
        return 0
    fi

    # No changes at all
    print_error "No changes detected in repository"
    print_info "Make some changes first, then run commit again"
    return 1
}

check_and_stage_changes() {
    # Check for staged changes and offer to stage all
    # Used by single commit mode only

    if ! git diff --cached --quiet; then
        show_diff_preview
        return 0
    fi

    print_warning "No staged changes found"
    print_question "Stage all changes? [y/n]"
    read -p "" stage_all

    if [[ "$stage_all" =~ ^[Yy]$ ]]; then
        safe_git_add_all || return 1
        show_diff_preview
        return 0
    fi

    print_error "No changes to commit"
    return 1
}

# ============================================================================
# SAFE GIT ADD FUNCTIONS
# ============================================================================

safe_git_add() {
    local file="$1"

    # Check if file should be ignored
    if git check-ignore -q "$file" 2>/dev/null; then
        print_warning "Skipping ignored file: $file"
        return 1
    fi

    # Get the full git status for this file
    local git_status=$(git status --porcelain "$file" 2>/dev/null | awk '{print $1}')

    # Handle renames (R or RM status codes)
    # For renames, we need to stage both old and new paths
    if [[ "$git_status" =~ R ]]; then
        # Extract old -> new paths from status
        # Format: "R  old path.txt -> new path.txt" or "RM old path.txt -> new path.txt"
        local rename_info=$(git status --porcelain "$file" 2>/dev/null)

        # Remove status code prefix (R or RM) and leading spaces
        local paths=$(echo "$rename_info" | sed 's/^R[M]* *//')

        # Extract old and new paths (handles spaces in filenames)
        local old_path=$(echo "$paths" | sed 's/ -> .*//')
        local new_path=$(echo "$paths" | sed 's/.* -> //')

        # Stage both paths to capture the rename
        git add "$old_path" "$new_path" 2>/dev/null
        return $?
    fi

    # Handle deletions (D or MD status codes)
    if [[ "$git_status" =~ D ]]; then
        # File is deleted - stage the deletion
        git add "$file" 2>/dev/null
        return $?
    fi

    # Check if file exists on filesystem for normal adds/modifications
    if [ ! -e "$file" ]; then
        print_warning "File doesn't exist and not tracked by git: $file"
        return 1
    fi

    # Safe to add
    git add "$file" 2>/dev/null
    return $?
}

safe_git_add_all() {
    print_info "Staging changes (respecting .gitignore)..."

    # Use git add -A which:
    # - Automatically detects and stages renames properly
    # - Respects .gitignore by default
    # - Handles deletions, modifications, and new files
    git add -A 2>/dev/null

    local staged_count=$(git diff --cached --name-only | wc -l)

    if [ $staged_count -eq 0 ]; then
        print_error "No files staged"
        return 1
    fi

    # Check if any renames were detected
    local rename_count=$(git diff --cached --name-status | grep -c "^R" || echo "0")
    if [ $rename_count -gt 0 ]; then
        print_success "Staged $staged_count file(s), including $rename_count rename(s)"
    else
        print_success "Staged $staged_count file(s)"
    fi

    return 0
}

_get_committable_files() {
    # Get all changed files (staged, unstaged, and untracked)
    # Use --find-renames to detect renames properly
    # Include deletions (D) - safe_git_add handles them correctly
    local all_files=$(
        {
            git diff --name-only --find-renames --diff-filter=ACMRD;
            git diff --cached --name-only --find-renames --diff-filter=ACMRD;
            git ls-files --others --exclude-standard;
        } | sort -u
    )

    # Filter out ignored files
    local committable_files=""
    local ignored_count=0

    while IFS= read -r file; do
        if [ -n "$file" ]; then
            if git check-ignore -q "$file" 2>/dev/null; then
                ((ignored_count++))
            else
                committable_files="$committable_files$file"$'\n'
            fi
        fi
    done <<< "$all_files"

    # Show warning if files were filtered
    if [ $ignored_count -gt 0 ]; then
        print_warning "Filtered out $ignored_count ignored file(s) from analysis"
    fi

    echo -n "$committable_files"
}

# ============================================================================
# API FUNCTIONS
# ============================================================================

_create_claude_payload() {
    local prompt="$1"
    local system_message="$2"
    local temp_json=$(mktemp) || return 1
    local temp_prompt=$(mktemp) || { rm -f "$temp_json"; return 1; }
    local temp_system=$(mktemp) || { rm -f "$temp_json" "$temp_prompt"; return 1; }

    # Clean control characters (but don't truncate - Haiku has 200K token context!)
    echo "$prompt" | sed 's/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g' >"$temp_prompt"
    echo "$system_message" | sed 's/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g' >"$temp_system"

    jq -n \
        --arg model "$CLAUDE_MODEL" \
        --rawfile prompt "$temp_prompt" \
        --rawfile system "$temp_system" \
        '{
            "model": $model,
            "max_tokens": 8000,
            "system": $system,
            "messages": [{"role": "user", "content": $prompt}]
        }' >"$temp_json"

    rm "$temp_prompt" "$temp_system"
    echo "$temp_json"
}

_extract_completion() {
    local response="$1"
    local completion=""

    # Try multiple extraction methods
    completion=$(echo "$response" | jq -r '.content[] | select(.type == "text") | .text' 2>/dev/null)

    if [ -z "$completion" ]; then
        completion=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)
    fi

    if [ -z "$completion" ]; then
        completion=$(echo "$response" | grep -o '"text":"[^"]*"' | head -1 | sed 's/"text":"//;s/"$//')
    fi

    echo "$completion"
}

_estimate_api_cost() {
    local prompt="$1"
    local system_message="$2"

    # Rough token estimation (1 token ≈ 4 characters)
    local prompt_chars=${#prompt}
    local system_chars=${#system_message}
    local total_chars=$((prompt_chars + system_chars))
    local estimated_input_tokens=$((total_chars / 4))
    local estimated_output_tokens=1000  # Max tokens we set

    # Claude Sonnet 4 pricing (as of 2025)
    # Input: $3 per million tokens
    # Output: $15 per million tokens
    local input_cost=$(echo "scale=4; $estimated_input_tokens * 3 / 1000000" | bc 2>/dev/null || echo "0.00")
    local output_cost=$(echo "scale=4; $estimated_output_tokens * 15 / 1000000" | bc 2>/dev/null || echo "0.02")
    local total_cost=$(echo "scale=4; $input_cost + $output_cost" | bc 2>/dev/null || echo "0.02")

    if $VERBOSE; then
        print_info "Estimated API call cost:"
        echo "  Input tokens: ~$estimated_input_tokens (\$$input_cost)"
        echo "  Output tokens: ~$estimated_output_tokens (\$$output_cost)"
        echo "  Total: ~\$$total_cost"
    fi
}

call_claude_api() {
    local prompt="$1"
    local system_message="$2"
    local context="${3:-}"  # Optional context message
    local api_url="https://api.anthropic.com/v1/messages"

    # Show cost estimate if verbose
    _estimate_api_cost "$prompt" "$system_message"

    if [ -n "$context" ]; then
        print_info "Calling Claude API ($context)..."
    else
        print_info "Calling Claude API..."
    fi

    # Create payload
    local payload_file=$(_create_claude_payload "$prompt" "$system_message")

    $DEBUG && cat "$payload_file"

    # Make API call
    local response
    if $DEBUG; then
        curl -v -X POST \
            -H "x-api-key: $CLAUDE_API_KEY" \
            -H "anthropic-version: $CLAUDE_API_VERSION" \
            -H "content-type: application/json" \
            -d @"$payload_file" \
            "$api_url" >/tmp/claude_api_response.json 2>/tmp/claude_api_debug.log
        response=$(cat /tmp/claude_api_response.json)
        print_info "Debug info saved to /tmp/claude_api_debug.log"
    else
        response=$(curl -s -X POST \
            -H "x-api-key: $CLAUDE_API_KEY" \
            -H "anthropic-version: $CLAUDE_API_VERSION" \
            -H "content-type: application/json" \
            -d @"$payload_file" \
            "$api_url")
    fi

    rm "$payload_file"

    # Check for errors
    if [ -z "$response" ]; then
        print_error "Empty API response"
        print_warning "Possible causes:"
        print_warning "  - Network connectivity issues"
        print_warning "  - API endpoint unreachable"
        print_warning "  - Request timeout"
        print_info "Try running with --debug flag for more details"
        return 1
    fi

    if echo "$response" | grep -q '"error":'; then
        local error_type=$(echo "$response" | jq -r '.error.type // "unknown"')
        local error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"')

        print_error "Claude API Error: $error_type"
        print_warning "Message: $error_msg"

        # Provide specific help based on error type
        case "$error_type" in
            "invalid_request_error")
                print_info "Check that your API key is valid and has proper permissions"
                ;;
            "authentication_error")
                print_info "API key authentication failed"
                print_info "Verify CLAUDE_API_KEY is set correctly"
                ;;
            "rate_limit_error")
                print_info "Rate limit exceeded - wait a moment and try again"
                ;;
            "overloaded_error")
                print_info "Claude API is overloaded - try again in a few moments"
                ;;
            *)
                print_info "Run with --debug for full error details"
                ;;
        esac

        $DEBUG && print_warning "Full response: $response"
        return 1
    fi

    # Extract completion
    local completion=$(_extract_completion "$response")

    if [ -z "$completion" ]; then
        print_error "Failed to extract completion from response"
        $DEBUG && print_warning "Raw response: $response"
        return 1
    fi

    $DEBUG && print_success "Extracted: $completion"

    echo "$completion"
    return 0
}

# ============================================================================
# DISPLAY & FORMATTING
# ============================================================================

show_diff_preview() {
    print_header "Changes to be committed"
    git diff --cached --find-renames --color | cat
    echo ""
}

get_commit_emoji() {
    local type=$1
    case "$type" in
    feat | feature) echo "✨" ;;
    fix) echo "🐛" ;;
    docs) echo "📚" ;;
    test) echo "🧪" ;;
    refactor) echo "♻️" ;;
    chore) echo "🔧" ;;
    ci) echo "👷" ;;
    *) echo "" ;;
    esac
}

_validate_and_normalize_type() {
    local type="$1"

    # Normalize and validate commit type
    case "$type" in
        feat|fix|docs|test|refactor|chore|ci)
            # Valid types - return as-is
            echo "$type"
            return 0
            ;;
        feature)
            # Normalize feature -> feat
            echo "feat"
            return 0
            ;;
        bug|bugfix)
            # Normalize bug/bugfix -> fix
            echo "fix"
            return 0
            ;;
        documentation)
            # Normalize documentation -> docs
            echo "docs"
            return 0
            ;;
        *)
            # Invalid type - warn and default to chore
            print_warning "Invalid commit type '$type', defaulting to 'chore'"
            echo "chore"
            return 1
            ;;
    esac
}

_format_commit_type() {
    local type="$1"
    local scope="$2"

    # Validate and normalize type
    type=$(_validate_and_normalize_type "$type")

    if [ -n "$scope" ]; then
        echo "$type($scope)"
    else
        echo "$type"
    fi
}

# ============================================================================
# AI ANALYSIS
# ============================================================================

_predict_commit_type() {
    local git_diff="$1"

    print_info "Analyzing changes to predict commit type..."

    local system_msg="You are a git commit type classifier. Analyze the diff and respond with ONLY one word from this list:
- feat (new features/enhancements)
- fix (bug fixes)
- docs (documentation only)
- test (tests)
- refactor (code improvements)
- chore (maintenance/dependencies)
- ci (CI/CD changes)

Respond with just the type, nothing else."

    local prompt="Analyze this git diff and determine the commit type:

$git_diff"

    local predicted_type=$(call_claude_api "$prompt" "$system_msg" "predicting commit type")

    if [ -z "$predicted_type" ]; then
        return 1
    fi

    # Clean and normalize
    predicted_type=$(echo "$predicted_type" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    # Validate
    case "$predicted_type" in
    feat | fix | docs | test | refactor | chore | ci)
        print_success "AI predicted: $predicted_type"
        echo "$predicted_type"
        return 0
        ;;
    *)
        print_warning "AI predicted invalid type: $predicted_type"
        return 1
        ;;
    esac
}

_detect_scope() {
    local files="$1"
    local git_diff="$2"

    # Silent scope detection - no user-facing messages

    local system_msg="You are a git commit scope detector. Analyze the changed files and git diff to determine an appropriate scope.

The scope should:
- Be a single word or short phrase (e.g., 'auth', 'api', 'ui', 'Button', 'database')
- Represent the primary area/module/component affected
- Be lowercase unless it's a component name (e.g., 'Button', 'UserProfile')
- Be NONE if changes span too many unrelated areas

Examples:
- Files: src/auth/login.js, src/auth/middleware.js → Scope: auth
- Files: components/Button/Button.tsx, components/Button/styles.css → Scope: Button
- Files: api/users.js, api/posts.js, api/comments.js → Scope: api
- Files: src/utils/format.js, src/services/api.js, tests/e2e/login.test.js → Scope: NONE (too broad)

Respond with ONLY the scope word or NONE, nothing else."

    local prompt="Changed files:
$files

Git diff summary:
$git_diff

What is the appropriate scope for this commit?"

    local detected_scope=$(call_claude_api "$prompt" "$system_msg" "detecting scope")

    if [ -z "$detected_scope" ]; then
        return 1
    fi

    # Clean up response
    detected_scope=$(echo "$detected_scope" | tr -d '[:space:]')

    # Check if NONE
    if [[ "$detected_scope" == "NONE" || "$detected_scope" == "none" ]]; then
        # No scope detected - return empty silently
        echo ""
        return 0
    fi

    # Validate scope format
    # - Max 20 characters
    # - Only alphanumeric, dash, underscore
    # - No spaces (already trimmed)
    if [ ${#detected_scope} -gt 20 ]; then
        print_warning "AI scope too long (${#detected_scope} chars): '$detected_scope', ignoring"
        echo ""
        return 1
    fi

    if ! [[ "$detected_scope" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_warning "AI scope contains invalid characters: '$detected_scope', ignoring"
        echo ""
        return 1
    fi

    # Return detected scope (caller will display it)
    echo "$detected_scope"
    return 0
}

_analyze_and_group_changes() {
    local git_status="$1"
    local git_diff="$2"

    print_info "Analyzing changes to identify logical groups..."

    local system_msg="You are a git commit grouping expert. Analyze ALL changes and group them into logical, atomic commits.

CRITICAL RULES:
1. Group by FUNCTIONAL UNIT, not by file type or commit type
2. Documentation MUST stay with the code it documents
3. Tests MUST stay with the code they test
4. Each group should be a complete, shippable unit of work

Good grouping examples:
✓ GROUP 1: refactor (CORS middleware + its docs + its tests)
✓ GROUP 2: refactor (auth hook + its docs + its tests)

Bad grouping examples:
✗ GROUP 1: refactor (CORS code)
✗ GROUP 2: refactor (auth code)
✗ GROUP 3: docs (all documentation)

Each group should:
- Represent ONE logical change (one feature, one refactor, one fix)
- Include ALL related files (code + docs + tests for that change)
- Be independently reviewable and deployable
- Have a clear, focused purpose

CRITICAL FORMAT RULES:
1. NO introductory text, explanations, or commentary before the groups
2. NO markdown formatting (no bold, no italics, no code blocks)
3. Start IMMEDIATELY with GROUP 1: <type>
4. Use plain text only

Respond in this EXACT format (no deviations):
GROUP 1: <type>
Scope: <scope-or-NONE>
Description: <what this functional unit does>
Files:
- <code file>
- <related doc file>
- <related test file>

GROUP 2: <type>
Scope: <scope-or-NONE>
Description: <what this functional unit does>
Files:
- <code file>
- <related doc file>

SCOPE RULES:
- Single word or short phrase (e.g., 'auth', 'api', 'Button', 'database')
- Lowercase unless component name
- NONE if too broad or unclear
- Maximum 20 characters

Only create multiple groups if changes are truly UNRELATED (different features/fixes).
If all changes are part of one logical unit, suggest just ONE group."

    local prompt="Here are ALL the current changes in the working directory:

Git status:
$git_status

Git diff summary (all changes from HEAD):
$git_diff

Group these changes into logical, atomic commits by FUNCTIONAL UNIT:
- Which files belong to the SAME feature/fix/refactor?
- Keep docs WITH their related code
- Keep tests WITH their related code
- Separate only if truly UNRELATED changes

Examples:
- CORS refactor + CORS docs = ONE GROUP
- Auth refactor + Auth docs = SEPARATE GROUP (different feature)
- Button component + Button tests + Button docs = ONE GROUP

Note: You're analyzing ALL changes. We'll stage each group separately when creating commits."

    print_info "Calling AI to analyze change patterns..."
    local grouping_suggestion=$(call_claude_api "$prompt" "$system_msg" "analyzing and grouping changes")

    echo "$grouping_suggestion"
}

_get_changed_files() {
    # Get list of all changed files (staged and unstaged, unique)
    # Use --find-renames to properly detect renamed files
    {
        git diff --name-only --find-renames;
        git diff --cached --name-only --find-renames;
    } | sort -u
}

select_commit_type() {
    local git_diff="$1"

    # Build menu options
    local menu_options=()
    if ! $SKIP_AI; then
        menu_options+=("ai: Let AI predict based on changes")
    fi

    for type in feat fix docs test refactor chore ci; do
        menu_options+=("$type: ${COMMIT_TYPES[$type]}")
    done

    # Set default
    local default="ai"
    $SKIP_AI && default="feat"

    # Show menu
    local selected=$(select_menu "Commit type" "$default" "${menu_options[@]}")
    local commit_type=$(echo "$selected" | cut -d':' -f1)

    # Handle AI prediction
    if [[ "$commit_type" == "ai" && ! $SKIP_AI ]]; then
        local predicted=$(_predict_commit_type "$git_diff")
        if [ $? -eq 0 ] && [ -n "$predicted" ]; then
            commit_type="$predicted"
        else
            print_warning "AI prediction failed, selecting manually"
            selected=$(select_menu "Commit type" "feat" "${menu_options[@]:1}")
            commit_type=$(echo "$selected" | cut -d':' -f1)
        fi
    fi

    # Normalize
    [[ "$commit_type" == "feature" ]] && commit_type="feat"

    print_success "Commit type: $commit_type"
    echo "$commit_type"
}

get_commit_scope() {
    local files="$1"
    local git_diff="$2"

    # Auto-detect scope silently if AI is available
    if ! $SKIP_AI && [ -n "$files" ]; then
        local detected=$(_detect_scope "$files" "$git_diff")

        # Show what was detected (if anything)
        if [ -n "$detected" ]; then
            print_success "Scope: $detected"
        fi

        echo "$detected"
        return 0
    fi

    # No AI or no files - no scope
    echo ""
}

should_use_emoji() {
    if $DEFAULT_USE_EMOJI; then
        print_info "Using emoji (USE_EMOJI=true)"
        echo "true"
        return
    fi

    local use_emoji
    read -p "Use emoji? [y/n] " use_emoji

    [[ "$use_emoji" =~ ^[Yy]$ ]] && echo "true" || echo "false"
}

_generate_scope_and_message() {
    local git_diff="$1"
    local files="$2"
    local commit_type="$3"
    local emoji="$4"

    # Calculate max summary length based on worst-case (with 20-char scope)
    local worst_case_prefix="$commit_type(xxxxxxxxxxxxxxxxxxxx):"
    [ -n "$emoji" ] && worst_case_prefix="$emoji $worst_case_prefix"
    local worst_case_length=${#worst_case_prefix}
    local safe_max_length=$((72 - worst_case_length - 1))

    local system_msg="You are a git commit expert. Analyze the changes and provide both scope and commit message.

RESPONSE FORMAT (follow exactly):
SCOPE: <scope-or-NONE>
MESSAGE:
<commit message>

SCOPE DETECTION RULES:
- Single word or short phrase (e.g., 'auth', 'api', 'Button', 'database')
- Lowercase unless it's a component name
- NONE if changes span too many unrelated areas
- Maximum 20 characters

COMMIT MESSAGE FORMAT:
1. SUMMARY LINE: ${commit_type}(<scope>): clear imperative summary
2. BLANK LINE
3. BODY (1-3 paragraphs): WHY this change was made

CRITICAL SUMMARY LINE RULES:
- MUST be under 72 characters total
- Description after prefix MUST be maximum ${safe_max_length} characters
- NO exceptions - hard requirement
- Use short, clear words

Summary guidelines:
- Imperative mood ('add' not 'added', 'fix' not 'fixed')
- Specific but concise
- Focus on key outcome

Body guidelines:
- Explain motivation/reasoning
- Describe what was wrong/missing
- Explain impact
- Be concise but informative"

    local prompt="Changed files:
$files

Git diff:
$git_diff

Provide the scope and commit message for this $commit_type change.

CRITICAL: Summary line MUST be under 72 characters including scope."

    print_info "Generating scope and commit message..."
    local response=$(call_claude_api "$prompt" "$system_msg" "generating scope and message")

    echo "$response"
}

_generate_ai_commit_message() {
    local git_diff="$1"
    local formatted_type="$2"
    local emoji="$3"

    local prefix="$formatted_type:"
    [ -n "$emoji" ] && prefix="$emoji $prefix"
    local prefix_length=${#prefix}
    local max_summary_length=$((72 - prefix_length - 1))  # -1 for the space after prefix

    local system_msg="You are a git commit message expert. Create a concise, well-structured conventional commit message.

Format:
1. SUMMARY LINE: ${prefix} clear imperative summary
2. BLANK LINE
3. BODY (1-3 paragraphs): Explain WHY this change was made, what problem it solves, and the impact

CRITICAL SUMMARY LINE RULES:
- MUST be under 72 characters total (including '${prefix} ')
- The description after '${prefix} ' MUST be maximum ${max_summary_length} characters
- NO exceptions - this is a hard requirement
- If you can't fit it in ${max_summary_length} chars, use shorter words
- Examples of length-compliant summaries:
  * feat(auth): add session timeout (26 chars after prefix)
  * fix(api): handle missing userId (28 chars after prefix)
  * refactor(db): optimize query performance (38 chars after prefix)

Summary line guidelines:
- Imperative mood ('add' not 'added', 'fix' not 'fixed')
- Be specific but concise
- Focus on the key outcome
- Use short, clear words

Body guidelines:
- Explain the motivation/reasoning
- Describe what was wrong or missing
- Explain the impact of the change
- Be concise but informative

Good examples:
feat(auth): add session timeout for inactive users

Implements automatic logout after 30 minutes of inactivity to improve
security. Previously, sessions remained active indefinitely, which posed
a risk when users left devices unattended.

fix(api): handle missing userId in request validation

Requests without userId were causing 500 errors. Added validation to
return 400 with clear error message when userId is missing. This improves
API reliability and makes debugging easier for clients."

    local prompt="Analyze this git diff and create a commit message with prefix '$prefix':

$git_diff

CRITICAL: The summary line MUST be under 72 characters total. The description after '${prefix} ' can only be ${max_summary_length} characters maximum.

Focus on WHY this change matters, not just WHAT changed."

    print_info "Generating AI commit message..."
    local message=$(call_claude_api "$prompt" "$system_msg" "generating commit message")

    echo "$message"
}

# ============================================================================
# USER INPUT
# ============================================================================

_get_manual_input() {
    print_info "Describe the change:"
    read -p "" description
    echo "$description"
}

_adjust_commit_message() {
    local current_message="$1"

    print_info "How should this be adjusted?"
    read -p "" instruction

    local system_msg="Adjust the commit message based on user feedback while maintaining conventional commit format.

Keep:
- Summary line (max 72 chars)
- Blank line separator
- Body with clear explanation
- Commit type prefix and emoji if present

Apply the requested changes while preserving the overall structure."

    local prompt="Current commit message:
$current_message

User's adjustment request:
$instruction

Adjust the message accordingly while maintaining format and structure."

    print_info "Adjusting message..."
    local adjusted=$(call_claude_api "$prompt" "$system_msg" "adjusting message")

    if [ -z "$adjusted" ]; then
        print_error "Adjustment failed"
        return 1
    fi

    print_success_block "Adjusted message:" "$adjusted"
    echo "$adjusted"
}

_create_manual_message() {
    local formatted_type="$1"
    local emoji="$2"
    local description="$3"

    local prefix="$formatted_type:"
    [ -n "$emoji" ] && prefix="$emoji $prefix"

    echo "$prefix $description"
}

_add_trailers() {
    local message="$1"

    # Add co-author trailers
    if [ ${#CO_AUTHORS[@]} -gt 0 ]; then
        # Ensure blank line before trailers
        if ! echo "$message" | tail -1 | grep -q "^$"; then
            message="$message"$'\n'
        fi

        for author in "${CO_AUTHORS[@]}"; do
            message="$message"$'\n'"Co-authored-by: $author"
        done
    fi

    echo "$message"
}

_validate_commit_message() {
    local message="$1"

    # Extract first line (summary)
    local summary_line=$(echo "$message" | head -1)
    local summary_length=${#summary_line}

    # Check summary line length
    if [ $summary_length -gt 72 ]; then
        print_warning "Summary line is $summary_length characters (recommended max: 72)"
        print_warning "Long summary: ${summary_line:0:80}..."
        print_question "Continue anyway? [y/n]"
        read -p "" confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    # Check for blank line after summary (if there's a body)
    local line_count=$(echo "$message" | wc -l)
    if [ $line_count -gt 1 ]; then
        local second_line=$(echo "$message" | sed -n '2p')
        if [ -n "$second_line" ]; then
            print_warning "Missing blank line after summary"
            print_info "Conventional commits should have a blank line between summary and body"
            print_question "Continue anyway? [y/n]"
            read -p "" confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi

    return 0
}

create_commit() {
    local message="$1"

    # Validate commit message format
    if ! _validate_commit_message "$message"; then
        print_error "Commit message validation failed"
        return 1
    fi

    # Add trailers (co-authors, etc.)
    message=$(_add_trailers "$message")

    # DRY-RUN MODE: Show what would happen and return
    if $DRY_RUN; then
        print_success "DRY-RUN: Would create commit with message:"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$message"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        print_info "Staged files that would be committed:"
        git diff --cached --name-status
        return 0
    fi

    # ACTUAL COMMIT MODE
    local temp_file=$(mktemp) || {
        print_error "Failed to create temporary file"
        return 1
    }

    echo "$message" >"$temp_file"

    if git commit -F "$temp_file"; then
        rm "$temp_file"
        print_success "Commit created successfully!"
        return 0
    else
        local exit_code=$?
        rm "$temp_file"
        print_error "Commit failed (exit code: $exit_code)"
        print_warning "This could be due to:"
        print_warning "  - Pre-commit hook failure"
        print_warning "  - Nothing staged to commit"
        print_warning "  - Commit message validation failure"
        return 1
    fi
}

# ============================================================================
# GROUPED COMMIT WORKFLOW
# ============================================================================

_parse_groups() {
    local grouping_text="$1"

    # Save to temp file for parsing
    local temp_file=$(mktemp) || {
        print_error "Failed to create temporary file"
        echo "0"
        return 1
    }

    echo "$grouping_text" > "$temp_file"

    # Count groups
    local group_count=$(grep -c "^GROUP [0-9]*:" "$temp_file" || echo "0")

    rm "$temp_file"
    echo "$group_count"
}

_extract_group_info() {
    local grouping_text="$1"
    local group_num="$2"

    # Extract the specific group section
    local group_section=$(echo "$grouping_text" | awk "/^GROUP $group_num:/ {flag=1; next} /^GROUP [0-9]*:/ {flag=0} flag")

    # Extract type (from first line)
    local type=$(echo "$grouping_text" | grep "^GROUP $group_num:" | sed 's/GROUP [0-9]*: //' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    # Extract scope
    local scope=$(echo "$group_section" | grep "^Scope:" | sed 's/Scope: //' | tr -d '[:space:]')
    [ "$scope" = "NONE" ] && scope=""

    # Extract description
    local description=$(echo "$group_section" | grep "^Description:" | sed 's/Description: //')

    # Extract files (lines starting with -) and join with safe delimiter
    # Use ::||:: as delimiter (very unlikely to appear in filenames)
    local files=$(echo "$group_section" | grep "^- " | sed 's/^- //' | awk '{printf "%s::||::", $0}' | sed 's/::||::$//')

    # Return as a structured string (we'll parse this later)
    echo "TYPE:$type"
    echo "SCOPE:$scope"
    echo "DESC:$description"
    echo "FILES:$files"
}

_commit_single_group() {
    local group_num="$1"
    local type="$2"
    local scope="$3"
    local description="$4"
    local files="$5"
    local use_emoji="$6"

    print_header "Creating commit for Group $group_num"
    print_info "Type: $type"
    [ -n "$scope" ] && print_info "Scope: $scope"
    print_info "Description: $description"
    print_info "Files:"
    echo "$files" | while read -r file; do
        echo "  - $file"
    done
    echo ""

    # Reset staging area (handle both normal repos and empty repos without HEAD)
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        # Normal repo with commits - use reset
        git reset HEAD >/dev/null 2>&1
    else
        # Empty repo without HEAD - unstage all files
        git rm --cached -r . >/dev/null 2>&1 || true
    fi

    # Stage only the files for this group
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            safe_git_add "$file"
        fi
    done <<< "$files"

    # Check if we actually staged anything
    if git diff --cached --quiet; then
        print_warning "No changes staged for this group, skipping..."
        return 1
    fi

    # Get diff for this group only
    local group_diff=$(git diff --cached --find-renames)

    # Get emoji if needed
    local emoji=""
    if [[ "$use_emoji" == "true" ]]; then
        emoji=$(get_commit_emoji "$type")
    fi

    # Format type with scope (scope already provided from grouping!)
    local formatted_type=$(_format_commit_type "$type" "$scope")

    # Generate commit message using the scope we already have
    if ! $SKIP_AI; then
        local commit_message=$(_generate_ai_commit_message "$group_diff" "$formatted_type" "$emoji")

        if [ -z "$commit_message" ]; then
            print_warning "AI generation failed, falling back to manual"
            commit_message="$formatted_type: $description"
            [ -n "$emoji" ] && commit_message="$emoji $commit_message"
        fi
    else
        # Manual mode - no AI
        commit_message="$formatted_type: $description"
        [ -n "$emoji" ] && commit_message="$emoji $commit_message"
    fi

    # Show message and confirm
    print_success_block "Proposed commit message:" "$commit_message"
    print_info "Create this commit? [y/n/a/e] (yes/skip/abort-all/adjust)"
    read -p "" confirm

    case "$confirm" in
        y|Y|"")
            create_commit "$commit_message"
            return 0
            ;;
        a|A)
            print_warning "Aborting all remaining commits"
            return 2  # Special return code for abort-all
            ;;
        e|E)
            # Allow adjusting with AI
            commit_message=$(_adjust_commit_message "$commit_message")
            if [ $? -eq 0 ]; then
                create_commit "$commit_message"
                return 0
            fi
            return 1
            ;;
        n|N)
            print_warning "Skipping this commit"
            return 1
            ;;
        *)
            print_warning "Invalid option, skipping this commit"
            return 1
            ;;
    esac
}

_handle_grouped_workflow() {
    print_header "Intelligent Commit Grouping Mode"

    # Get only committable files (respecting .gitignore)
    local committable_files=$(_get_committable_files)

    if [ -z "$committable_files" ]; then
        print_error "No committable changes found"
        return 1
    fi

    # Build git status and diff for only committable files
    local git_status=""
    local git_diff=""

    while IFS= read -r file; do
        if [ -n "$file" ]; then
            # Add to status
            local status_line=$(git status --short "$file" 2>/dev/null)
            [ -n "$status_line" ] && git_status="$git_status$status_line"$'\n'

            # Add to diff stats (with rename detection)
            local diff_line=$(git diff HEAD --stat --find-renames "$file" 2>/dev/null)
            [ -n "$diff_line" ] && git_diff="$git_diff$diff_line"$'\n'
        fi
    done <<< "$committable_files"

    print_info "Analyzing committable changes in working directory..."

    # Analyze and get grouping suggestions
    local grouping_suggestion=$(_analyze_and_group_changes "$git_status" "$git_diff")

    if [ -z "$grouping_suggestion" ]; then
        print_error "Failed to analyze changes for grouping"
        return 1
    fi

    # Validate AI response format
    if ! echo "$grouping_suggestion" | grep -q "^GROUP [0-9]*:"; then
        print_error "AI returned unexpected format"
        print_warning "Expected format: GROUP N: <type>"
        print_warning "Response preview (first 500 chars):"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$grouping_suggestion" | head -c 500
        local total_length=${#grouping_suggestion}
        if [ $total_length -gt 500 ]; then
            echo "... [truncated, total length: $total_length chars]"
        fi
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        print_info "Possible causes:"
        print_info "  - API call failed (check --debug output)"
        print_info "  - Response truncated (diff too large)"
        print_info "  - AI confused by unusual file patterns"
        print_info "Try: commit --debug (to see full API response)"
        print_info "Or:  commit -s (single commit mode)"
        return 1
    fi

    # Show the grouping suggestion
    print_success_block "AI Grouping Analysis:" "$grouping_suggestion"

    # Validate: Check if all files are accounted for
    local all_files_from_groups=$(echo "$grouping_suggestion" | grep "^- " | sed 's/^- //' | sort -u)
    local total_committable=$(echo "$committable_files" | grep -c "^")
    local total_in_groups=$(echo "$all_files_from_groups" | grep -c "^")

    if [ "$total_in_groups" -lt "$total_committable" ]; then
        print_warning "AI included $total_in_groups of $total_committable changed files"
        print_info "Some files were excluded from grouping (may not match the pattern)"
        print_info "You can commit remaining files separately after this"
    fi

    # Parse number of groups
    local group_count=$(_parse_groups "$grouping_suggestion")

    if [ "$group_count" -eq 0 ]; then
        print_error "No groups identified"
        return 1
    fi

    if [ "$group_count" -eq 1 ]; then
        # Only one group - proceed without extra confirmation
        print_success "Found 1 logical group"
        echo ""
    else
        # Multiple groups - confirm before creating multiple commits
        print_success "Found $group_count logical groups"
        echo ""
        print_question "Proceed with creating $group_count separate commits? [y/n]"
        read -p "" proceed
        if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
            print_warning "Grouping cancelled"
            return 1
        fi
    fi

    # Ask about emoji AFTER showing groups, BEFORE creating commits
    local use_emoji=$(should_use_emoji)

    # Save original staged state
    local temp_patch=$(mktemp) || {
        print_error "Failed to create temporary file"
        return 1
    }
    git diff --cached --find-renames > "$temp_patch"

    # Loop through each group and create commits
    local commits_created=0
    for ((i=1; i<=group_count; i++)); do
        print_header "Processing Group $i of $group_count"

        # Extract group info
        local group_info=$(_extract_group_info "$grouping_suggestion" "$i")
        local type=$(echo "$group_info" | grep "^TYPE:" | cut -d: -f2-)
        local scope=$(echo "$group_info" | grep "^SCOPE:" | cut -d: -f2-)
        local desc=$(echo "$group_info" | grep "^DESC:" | cut -d: -f2-)
        local files_raw=$(echo "$group_info" | grep "^FILES:" | cut -d: -f2-)

        # Validate extracted data
        if [ -z "$type" ] || [ -z "$files_raw" ]; then
            print_warning "Group $i missing type or files, skipping..."
            $DEBUG && print_warning "Type: '$type', Files: '$files_raw'"
            continue
        fi

        # Convert delimiter-separated files back to newline-separated
        # Split on ::||:: delimiter and convert to newlines
        # Use awk instead of sed for reliable newline handling
        local files=$(echo "$files_raw" | awk '{gsub(/::|\|\|::/, "\n"); print}')

        # Commit this group
        _commit_single_group "$i" "$type" "$scope" "$desc" "$files" "$use_emoji"
        local commit_result=$?

        if [ $commit_result -eq 0 ]; then
            # Commit succeeded
            ((commits_created++))
        elif [ $commit_result -eq 2 ]; then
            # Abort all remaining commits
            print_info "Stopped at group $i of $group_count"
            break
        fi
        # commit_result == 1 means skip, continue to next

        echo ""
    done

    # Restore any remaining staged changes that weren't committed
    if [ -f "$temp_patch" ] && [ -s "$temp_patch" ]; then
        print_info "Restoring any uncommitted staged changes..."
        git apply --cached "$temp_patch" 2>/dev/null || true
    fi

    # Clean up temp file
    [ -f "$temp_patch" ] && rm "$temp_patch"

    print_success "Created $commits_created commit(s) successfully!"
    return 0
}

# ============================================================================
# MAIN COMMIT FLOW
# ============================================================================

_handle_ai_workflow() {
    local git_diff="$1"
    local formatted_type="$2"
    local emoji="$3"

    # Generate AI suggestion
    local ai_message=$(_generate_ai_commit_message "$git_diff" "$formatted_type" "$emoji")

    if [ -z "$ai_message" ]; then
        print_error "AI generation failed"
        return 1
    fi

    # Show suggestion
    print_success_block "AI suggestion:" "$ai_message"
    print_info "Action? [y/n/m] (yes/adjust/manual)"
    read -p "" choice

    case "$choice" in
    y | Y | "")
        create_commit "$ai_message"
        return 0
        ;;
    n | N)
        # Adjustment loop
        local current="$ai_message"
        while true; do
            current=$(_adjust_commit_message "$current")
            [ $? -ne 0 ] && continue

            print_info "Action? [y/n/m] (yes/adjust again/manual)"
            read -p "" action

            case "$action" in
            y | Y | "")
                create_commit "$current"
                return 0
                ;;
            m | M)
                return 1 # Fall through to manual
                ;;
            esac
        done
        ;;
    esac

    return 1 # Fall through to manual
}

_handle_manual_workflow() {
    local formatted_type="$1"
    local emoji="$2"

    print_warning "Manual mode"

    while true; do
        local description=$(_get_manual_input)
        local message=$(_create_manual_message "$formatted_type" "$emoji" "$description")

        print_success_special "Message: " "$message"
        print_info "Commit? [y/n] (yes/re-enter)"
        read -p "" confirm

        if [[ "$confirm" =~ ^[Yy]?$ ]]; then
            create_commit "$message"
            return 0
        fi
    done
}

generate_commit() {
    # Step 1: Validate prerequisites
    print_progress 1 5 "Validating prerequisites"
    if ! $SKIP_AI; then
        check_api_key || return 1
    fi

    # Step 2: Branch based on workflow mode
    if $GROUP_COMMITS; then
        # ===== GROUPED COMMIT WORKFLOW =====
        if $SKIP_AI; then
            print_error "Grouped commits require AI analysis. Cannot use --manual without --single."
            print_info "Try: commit -s -m  (for manual single commit)"
            return 1
        fi

        # Check for any changes (don't stage yet)
        print_progress 2 5 "Checking for changes"
        check_has_any_changes || return 1

        # Handle grouped workflow (emoji prompt happens inside after showing groups)
        print_progress 3 5 "Analyzing and grouping changes"
        _handle_grouped_workflow
        return $?
    fi

    # ===== SINGLE COMMIT WORKFLOW =====

    # Determine emoji usage early for single commit mode
    local use_emoji=$(should_use_emoji)

    # Ensure we have staged changes
    print_progress 2 5 "Staging changes"
    check_and_stage_changes || return 1

    # Step 5: Get git diff and changed files
    print_progress 3 5 "Analyzing changes"
    local git_diff=$(git diff --cached --find-renames)
    local changed_files=$(git diff --cached --name-only --find-renames)

    # Step 6: Select commit type
    local commit_type=$(select_commit_type "$git_diff")

    # Step 7: Get emoji if needed
    local emoji=""
    if [[ "$use_emoji" == "true" ]]; then
        emoji=$(get_commit_emoji "$commit_type")
        [ -n "$emoji" ] && print_success "Emoji: $emoji"
    fi

    # Step 8: Generate scope and commit message in one AI call (faster!)
    print_progress 4 5 "Generating commit message"
    if ! $SKIP_AI && [ -n "$git_diff" ]; then
        local response=$(_generate_scope_and_message "$git_diff" "$changed_files" "$commit_type" "$emoji")

        # Parse scope from response
        local scope=$(echo "$response" | grep "^SCOPE:" | cut -d' ' -f2-)
        [ "$scope" = "NONE" ] && scope=""
        [ -n "$scope" ] && print_success "Scope: $scope"

        # Parse message from response
        local commit_message=$(echo "$response" | sed -n '/^MESSAGE:/,$p' | tail -n +2)

        if [ -z "$commit_message" ]; then
            print_warning "AI generation failed, falling back to manual"
            local formatted_type=$(_format_commit_type "$commit_type" "$scope")
            _handle_manual_workflow "$formatted_type" "$emoji"
            return $?
        fi

        # Show and confirm message
        print_success_block "AI suggestion:" "$commit_message"
        print_info "Action? [y/n/m] (yes/adjust/manual)"
        read -p "" choice

        case "$choice" in
        y | Y | "")
            create_commit "$commit_message"
            return 0
            ;;
        n | N)
            # Adjustment loop
            local current="$commit_message"
            while true; do
                current=$(_adjust_commit_message "$current")
                [ $? -ne 0 ] && continue

                print_info "Action? [y/n/m] (yes/adjust again/manual)"
                read -p "" action

                case "$action" in
                y | Y | "")
                    create_commit "$current"
                    return 0
                    ;;
                m | M)
                    local formatted_type=$(_format_commit_type "$commit_type" "$scope")
                    _handle_manual_workflow "$formatted_type" "$emoji"
                    return $?
                    ;;
                esac
            done
            ;;
        m | M)
            local formatted_type=$(_format_commit_type "$commit_type" "$scope")
            _handle_manual_workflow "$formatted_type" "$emoji"
            return $?
            ;;
        esac
    else
        # Manual mode from the start
        local formatted_type=$(_format_commit_type "$commit_type" "")
        _handle_manual_workflow "$formatted_type" "$emoji"
    fi
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_git_state() {
    # Check for merge in progress
    if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
        print_warning "Merge in progress detected"
        print_info "You're in the middle of a merge. This tool will create a merge commit."
        print_question "Continue? [y/n]"
        read -p "" confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Aborted. Complete or abort the merge first."
            return 1
        fi
    fi

    # Check for rebase in progress
    if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
        print_warning "Rebase in progress detected"
        print_info "You're in the middle of a rebase. This will commit the current rebase step."
        print_question "Continue? [y/n]"
        read -p "" confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Aborted. Complete or abort the rebase first."
            return 1
        fi
    fi

    # Check for cherry-pick in progress
    if [ -f .git/CHERRY_PICK_HEAD ]; then
        print_warning "Cherry-pick in progress detected"
        print_question "Continue with cherry-pick commit? [y/n]"
        read -p "" confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    return 0
}

check_diff_size() {
    # Get total diff size (all changes)
    # Handle empty repos (no HEAD) by using different diff command
    local diff_size
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        diff_size=$(git diff HEAD 2>/dev/null | wc -c)
    else
        # Empty repo - check working directory changes only
        diff_size=$(git diff 2>/dev/null | wc -c)
    fi

    # Warn if diff is very large (>100KB)
    if [ $diff_size -gt 100000 ]; then
        local diff_kb=$((diff_size / 1024))
        print_warning "Very large diff detected: ${diff_kb}KB"
        print_info "Large changes might:"
        print_info "  - Take longer to analyze"
        print_info "  - Cost more API tokens"
        print_info "  - Be harder to review"

        # In grouped mode, the script will handle splitting automatically
        if $GROUP_COMMITS; then
            print_info "Grouped mode will attempt to split this into logical commits automatically"
            print_question "Continue with automatic grouping? [y/n]"
            read -p "" response
            case "$response" in
                y|Y|"")
                    print_info "Proceeding with automatic grouping..."
                    return 0
                    ;;
                *)
                    print_info "Aborted. You can:"
                    print_info "  - Manually split changes and commit separately"
                    print_info "  - Use single commit mode: commit -s"
                    return 1
                    ;;
            esac
        else
            # In single commit mode, suggest splitting manually
            print_question "Consider splitting into smaller commits? [y/n/continue]"
            read -p "" response
            case "$response" in
                y|Y)
                    print_info "Aborted. Split your changes and run again."
                    return 1
                    ;;
                n|N)
                    print_info "Continuing anyway..."
                    return 0
                    ;;
                *)
                    return 0
                    ;;
            esac
        fi
    fi

    return 0
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    parse_arguments "$@"

    # Verify we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "Not a git repository"
        print_info "Run 'git init' to create a repository or navigate to an existing one"
        return 1
    fi

    # Check git state (merge, rebase, etc.)
    check_git_state || return 1

    # Check diff size and warn if large
    check_diff_size || return 1

    generate_commit
}

main "$@"
