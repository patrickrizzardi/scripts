from __future__ import annotations

from typing import Literal

from dev_helper.utils.command_exists import command_exists
from dev_helper.utils.print import print_error, print_header, print_success, print_warning
from dev_helper.utils.proc import run_inherit
from dev_helper.utils.prompt import confirm_prompt


def build_ss_args(show_all: bool, proto: Literal["tcp", "udp"]) -> list[str]:
    if proto == "tcp":
        return ["-tun"] if show_all else ["-tln"]
    else:
        return ["-un"] if show_all else ["-uln"]


def show_network_connections() -> None:
    if not command_exists("ss"):
        print_error("Error: 'ss' command is missing.")
        print_warning("Please install it using: sudo apt-get update && sudo apt-get install -y iproute2")
        return

    show_all = confirm_prompt("Show all connections? (default: listening only)")

    print_header("Network Connections")
    if show_all:
        print_success("Showing all network connections...")
    else:
        print_success("Showing only listening connections...")

    print_success("TCP connections:")
    run_inherit(["ss", *build_ss_args(show_all, "tcp")])
    print_success("UDP connections:")
    run_inherit(["ss", *build_ss_args(show_all, "udp")])
