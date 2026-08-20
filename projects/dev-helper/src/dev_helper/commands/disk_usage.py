from __future__ import annotations

import os

from dev_helper.utils.command_exists import command_exists
from dev_helper.utils.print import print_error, print_header, print_success, print_warning
from dev_helper.utils.proc import run, run_inherit


def show_disk_usage() -> None:
    if not command_exists("du") or not command_exists("df"):
        print_error("Error: Required commands 'du' or 'df' are missing.")
        print_warning("Please install them using: sudo apt-get update && sudo apt-get install -y coreutils")
        return

    print_header("Disk Usage Information")
    print_success("Overall disk usage:")
    run_inherit(["df", "-h"])

    home = os.environ["HOME"]
    print_success(f"Largest directories in {home}:")
    du = run(["du", "-h", "--max-depth=1", home])
    largest = run(["sh", "-c", "sort -hr | head -n 5"], stdin=du.stdout)
    print(largest.stdout)
