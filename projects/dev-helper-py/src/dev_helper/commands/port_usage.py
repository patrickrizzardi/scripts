from __future__ import annotations

import re

from dev_helper.utils.command_exists import command_exists
from dev_helper.utils.print import print_error, print_header, print_success, print_warning
from dev_helper.utils.proc import sh
from dev_helper.utils.prompt import text_prompt


def is_valid_port_number(value: str) -> bool:
    return re.fullmatch(r"[0-9]+", value) is not None


def find_port_usage() -> None:
    if not command_exists("ss"):
        print_error("Error: 'ss' command is missing.")
        print_warning("Please install it using: sudo apt-get update && sudo apt-get install -y iproute2")
        return

    port_number = text_prompt(
        "Enter the port number to search for:",
        validate=lambda v: None if is_valid_port_number(v) else "Please enter a valid port number.",
    )

    print_success(f"Searching for port {port_number}...")
    print_header("Port Usage Information")

    print_success("TCP connections:")
    tcp = sh(f'sudo ss -tulnp | grep ":{port_number}"')
    if tcp.stdout.strip():
        print(tcp.stdout)
    else:
        print_warning(f"No TCP connections found on port {port_number}")

    print_success("UDP connections:")
    udp = sh(f'sudo ss -ulnp | grep ":{port_number}"')
    if udp.stdout.strip():
        print(udp.stdout)
    else:
        print_warning(f"No UDP connections found on port {port_number}")
