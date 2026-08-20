from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from dev_helper.utils.command_exists import command_exists
from dev_helper.utils.print import print_error, print_header, print_success, print_warning
from dev_helper.utils.proc import run


@dataclass(frozen=True)
class SystemInfo:
    os: str
    cpu: str
    memory: str
    disk: str
    uptime: str


def format_system_info(info: SystemInfo) -> list[str]:
    return [
        f"OS: {info.os}",
        f"CPU: {info.cpu}",
        f"Memory: {info.memory}",
        f"Disk: {info.disk}",
        f"Uptime: {info.uptime}",
    ]


def _run_text(argv: Sequence[str]) -> str:
    return run(argv).stdout.strip()


def show_system_info() -> None:
    if not command_exists("lscpu") or not command_exists("free"):
        print_error("Error: Required commands 'lscpu' or 'free' are missing.")
        print_warning("Please install them using: sudo apt-get update && sudo apt-get install -y procps lscpu")
        return

    cpu_model_pipeline = r"lscpu | grep 'Model name' | cut -d: -f2 | sed 's/^[ \t]*//'"
    memory_total_pipeline = "free -h | grep Mem | awk '{print $2}'"
    disk_total_pipeline = "df -h / | tail -1 | awk '{print $2}'"

    os_name = _run_text(["uname", "-a"])
    cpu = _run_text(["sh", "-c", cpu_model_pipeline])
    memory_total = _run_text(["sh", "-c", memory_total_pipeline])
    disk_total = _run_text(["sh", "-c", disk_total_pipeline])
    uptime = _run_text(["uptime", "-p"])

    info = SystemInfo(
        os=os_name,
        cpu=cpu,
        memory=f"{memory_total} total",
        disk=f"{disk_total} total",
        uptime=uptime,
    )

    print_header("System Information")
    for line in format_system_info(info):
        print_success(line)
