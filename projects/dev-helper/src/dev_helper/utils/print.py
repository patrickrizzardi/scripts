RED = "\x1b[0;31m"
GREEN = "\x1b[0;32m"
YELLOW = "\x1b[1;33m"
BLUE = "\x1b[0;34m"
CYAN = "\x1b[0;36m"
RESET = "\x1b[0m"


def format_error(msg: str) -> str:
    return f"{RED}{msg}{RESET}"


def format_success(msg: str) -> str:
    return f"{GREEN}{msg}{RESET}"


def format_info(msg: str) -> str:
    return f"{BLUE}{msg}{RESET}"


def format_warning(msg: str) -> str:
    return f"{YELLOW}{msg}{RESET}"


def format_header(msg: str) -> str:
    return f"{CYAN}========== {msg} =========={RESET}"


def format_menu_item(num: str, label: str) -> str:
    return f"{GREEN}{num}{RESET} {label}"


def print_error(msg: str) -> None:
    print(format_error(msg))


def print_success(msg: str) -> None:
    print(format_success(msg))


def print_info(msg: str) -> None:
    print(format_info(msg))


def print_warning(msg: str) -> None:
    print(format_warning(msg))


def print_header(msg: str) -> None:
    print(format_header(msg))


def print_menu_item(num: str, label: str) -> None:
    print(format_menu_item(num, label))
