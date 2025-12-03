# Color definitions
red='\033[0;31m'        # Red for error messages
green='\033[0;32m'      # Green for success messages
yellow='\033[1;33m'     # Yellow for warnings
blue='\033[0;34m'       # Blue for info messages
magenta='\033[0;35m'    # Magenta for special messages
cyan='\033[0;36m'       # Cyan for headers
white='\033[1;37m'      # Bright white for readable content
bold='\033[1m'          # Bold text
dim='\033[2m'           # Dimmed text
reset='\033[0m'         # No Color (reset)

# Bright/bold versions for better contrast
bold_cyan='\033[1;36m'  # Bold cyan for headers
bold_green='\033[1;32m' # Bold green for emphasis
bold_blue='\033[1;34m'  # Bold blue for important info

# Print functions - all redirected to stderr by default
# so they don't interfere with command substitution
print_error() {
    echo -e "${red}✗ $1${reset}" >&2
}

print_success() {
    echo -e "${green}✓ $1${reset}" >&2
}

print_warning() {
    echo -e "${yellow}⚠ $1${reset}" >&2
}

print_info() {
    echo -e "${bold_blue}ℹ $1${reset}" >&2
}

print_header() {
    echo -e "\n${bold_cyan}━━━━━ $1 ━━━━━${reset}" >&2
}

print_footer() {
    echo -e "${cyan}==============================${reset}" >&2
}

print_menu_item() {
    echo -e "${green}$1${reset} $2" >&2
}

print_success_special() {
    echo -e "${green}$1${magenta}$2${reset}" >&2
}

# For printing multi-line content with a title
# Usage: print_success_block "Title" "$multi_line_content"
print_success_block() {
    local title="$1"
    local content="$2"

    echo "" >&2
    echo -e "${bold_green}▸ $title${reset}" >&2
    echo -e "${white}$content${reset}" >&2
    echo "" >&2
}

# For printing questions/prompts that need user input
# Usage: print_question "Is this correct?"
print_question() {
    echo -e "${bold_cyan}? $1${reset}" >&2
}
