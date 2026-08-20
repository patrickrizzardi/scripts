from __future__ import annotations

import os
from dataclasses import dataclass

from dev_helper.commands.file_sync.config import get_config_dir
from dev_helper.commands.file_sync.watcher import (
    generate_fallback_service_content,
    generate_fallback_timer_content,
    generate_sync_script_content,
    generate_watch_script_content,
    generate_watch_service_content,
)
from dev_helper.utils.command_exists import command_exists
from dev_helper.utils.proc import run

LEGACY_UNIT_FILES = ("rsync-sync.service", "rsync-sync.timer")


@dataclass(frozen=True)
class InstallOk:
    warnings: list[str]


@dataclass(frozen=True)
class InstallFailed:
    error: str


InstallResult = InstallOk | InstallFailed


def is_systemd_available() -> bool:
    return command_exists("systemctl")


def _resolve_home(home: str | None) -> str:
    return home if home is not None else os.environ["HOME"]


def get_systemd_user_dir(home: str | None = None) -> str:
    return os.path.join(_resolve_home(home), ".config", "systemd", "user")


def _write_executable(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    os.chmod(path, 0o755)


def _write_unit(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


def write_service_files(home: str | None = None) -> None:
    config_dir = get_config_dir(home)
    systemd_dir = get_systemd_user_dir(home)
    os.makedirs(config_dir, exist_ok=True)
    os.makedirs(systemd_dir, exist_ok=True)

    _write_executable(os.path.join(config_dir, "sync.sh"), generate_sync_script_content())
    _write_executable(os.path.join(config_dir, "watch.sh"), generate_watch_script_content())

    _write_unit(os.path.join(systemd_dir, "rsync-sync-watch.service"), generate_watch_service_content())
    _write_unit(os.path.join(systemd_dir, "rsync-sync-fallback.service"), generate_fallback_service_content())
    _write_unit(os.path.join(systemd_dir, "rsync-sync-fallback.timer"), generate_fallback_timer_content())


# A pre-existing pairs.conf doesn't mean OUR systemd units were ever
# installed -- it can be leftover from an older release of this tool (or the
# legacy bash tool this replaces), which used a different unit name and never
# wrote the watch service at all. Checking for the watch unit itself is what
# actually tells first-run-needing-install apart from already-migrated.
def is_watcher_installed(home: str | None = None) -> bool:
    return os.path.exists(os.path.join(get_systemd_user_dir(home), "rsync-sync-watch.service"))


# Disabling the legacy timer alone leaves its unit files sitting on disk
# forever -- a stopped-but-present unit is dead weight with no purpose once
# the watcher replaces it. Removing the files fully retires it instead of
# just silencing it.
def remove_legacy_unit_files(home: str | None = None) -> None:
    systemd_dir = get_systemd_user_dir(home)
    for name in LEGACY_UNIT_FILES:
        path = os.path.join(systemd_dir, name)
        if os.path.exists(path):
            os.remove(path)


def install_commands() -> list[list[str]]:
    """The exact argv sequence install_service() runs, in order.

    Split out as pure data so it's testable without actually invoking systemctl.
    """
    return [
        ["loginctl", "enable-linger", os.environ.get("USER", "")],
        # Legacy cleanup: earlier versions of this tool installed a 30s polling
        # timer under this name -- disable it so it doesn't keep running
        # alongside the new watcher and double-sync.
        ["systemctl", "--user", "disable", "--now", "rsync-sync.timer"],
        ["systemctl", "--user", "daemon-reload"],
        ["systemctl", "--user", "enable", "--now", "rsync-sync-watch.service"],
        ["systemctl", "--user", "enable", "--now", "rsync-sync-fallback.timer"],
    ]


# `loginctl enable-linger` needs elevated privileges this tool never asks
# the user to grant (confirmed: fails "Access denied" for a plain user with
# no polkit rule for it) -- matching the original bash tool's `|| true` on
# the identical call, this must not block the rest of setup; lingering only
# affects whether sync survives a full logout, not whether it works at all.
# The legacy-timer disable is separately allowed to fail because the unit
# may never have existed on a fresh install.
def is_best_effort_command(cmd: str, args: list[str]) -> bool:
    return cmd == "loginctl" or "rsync-sync.timer" in args


def install_service() -> InstallResult:
    warnings: list[str] = []
    for cmd, *args in install_commands():
        result = run([cmd, *args])
        if result.exit_code != 0:
            if not is_best_effort_command(cmd, args):
                return InstallFailed(f"{cmd} {' '.join(args)} failed")
            if cmd == "loginctl":
                user = os.environ.get("USER", "$USER")
                warnings.append(
                    "Could not enable linger (needs elevated privileges) — sync will stop when you fully log out. "
                    f"Run 'sudo loginctl enable-linger {user}' to fix this."
                )
        # Once the legacy timer is disabled, its unit files are dead weight --
        # remove them here (before the next loop iteration's daemon-reload
        # picks up the removal) so it's fully retired, not just stopped.
        if cmd == "systemctl" and "disable" in args and "rsync-sync.timer" in args:
            remove_legacy_unit_files()
    return InstallOk(warnings)


def service_control_args(action: str) -> list[str]:
    return ["--user", action, "rsync-sync-watch.service"]


def restart_watcher() -> None:
    run(["systemctl", *service_control_args("restart")])
