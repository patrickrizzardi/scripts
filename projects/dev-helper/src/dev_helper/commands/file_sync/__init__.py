from __future__ import annotations

from dev_helper.commands.file_sync.add_pairs import add_pairs_flow
from dev_helper.commands.file_sync.config import read_pairs, write_pairs
from dev_helper.commands.file_sync.remove_pair import remove_pair_flow
from dev_helper.commands.file_sync.service import (
    InstallFailed,
    install_service,
    is_systemd_available,
    is_watcher_installed,
    restart_watcher,
    service_control_args,
    write_service_files,
)
from dev_helper.commands.file_sync.view_pairs import view_pairs
from dev_helper.commands.file_sync.watcher import INOTIFY_INSTALL_COMMAND, is_inotify_tools_installed
from dev_helper.utils.command_exists import command_exists
from dev_helper.utils.print import print_error, print_header, print_info, print_success, print_warning
from dev_helper.utils.proc import run
from dev_helper.utils.prompt import Option, select_prompt


def _manage_service() -> None:
    action = select_prompt(
        "Service Control",
        [
            Option(value="start", label="Start"),
            Option(value="stop", label="Stop"),
            Option(value="restart", label="Restart"),
            Option(value="status", label="Status"),
        ],
    )
    result = run(["systemctl", *service_control_args(action)])
    if result.exit_code == 0:
        print_success(f"{action} succeeded.")
    else:
        print_error(f"Failed to {action} the watcher service.")

    # start/stop/restart apply to both sync mechanisms together, or a "stop"
    # leaves the fallback timer's 5-minute reconciliation quietly running (or
    # a later "start" never revives it) -- the user expects one on/off switch,
    # not two independently-tracked units. "status" stays scoped to the watch
    # service; showing two statuses at once isn't part of this action's job.
    if action in ("start", "stop", "restart"):
        run(["systemctl", "--user", action, "rsync-sync-fallback.timer"])


def setup_file_sync() -> None:
    if not command_exists("rsync"):
        print_error("rsync is not installed.")
        print_warning("Install it with: sudo apt-get install -y rsync")
        return

    if not is_inotify_tools_installed():
        print_error("inotify-tools is not installed (needed for instant sync).")
        print_warning(f"Install it with: {INOTIFY_INSTALL_COMMAND}")
        return

    if not is_systemd_available():
        print_error("systemd is not available.")
        print_warning("To enable systemd in WSL, add the following to /etc/wsl.conf:")
        print_info("  [boot]")
        print_info("  systemd=true")
        print_warning("Then restart WSL: run 'wsl --shutdown' from Windows, then reopen.")
        return

    pairs = read_pairs()

    if not pairs:
        print_header("File Sync Setup")
        print_info("No existing configuration found. Let's set one up.")
        new_pairs = add_pairs_flow(pairs)
        if not new_pairs:
            print_error("No pairs added. Exiting.")
            return
        write_pairs(new_pairs)
        write_service_files()
        installed = install_service()
        if isinstance(installed, InstallFailed):
            print_error(f"Watcher could not be enabled: {installed.error}")
            print_warning("Config was saved. Use 'Set up file sync' -> Service Control -> Start to retry.")
            return
        for warning in installed.warnings:
            print_warning(warning)
        print_success("Sync configured! Active pairs:")
        view_pairs(new_pairs)
        return

    # pairs.conf already has entries, but that alone doesn't prove OUR watcher
    # was ever installed -- it can be leftover from an older release of this
    # tool, or the legacy bash tool this replaces, neither of which wrote the
    # rsync-sync-watch.service unit. Treat that combination as a migration,
    # not "already fully set up": install the watcher now (which also disables
    # any legacy rsync-sync.timer as part of install_commands()) before landing
    # on the management menu.
    if not is_watcher_installed():
        print_header("File Sync Migration")
        print_info("Found existing sync pairs but no instant-sync watcher — installing it now.")
        write_service_files()
        installed = install_service()
        if isinstance(installed, InstallFailed):
            print_error(f"Watcher could not be enabled: {installed.error}")
            print_warning("Config was saved. Use 'Set up file sync' -> Service Control -> Start to retry.")
            return
        for warning in installed.warnings:
            print_warning(warning)
        print_success("Watcher installed and any legacy sync timer disabled.")

    while True:
        print_header("File Sync Manager")
        choice = select_prompt(
            "Your choice",
            [
                Option(value="add", label="Add sync pairs"),
                Option(value="view", label="View existing pairs"),
                Option(value="remove", label="Remove a sync pair"),
                Option(value="service", label="Start / Stop / Restart / Status watcher"),
                Option(value="exit", label="Exit"),
            ],
        )

        if choice == "add":
            added = add_pairs_flow(pairs)
            if added:
                pairs = [*pairs, *added]
                write_pairs(pairs)
                restart_watcher()
                print_success("Pairs added.")
        elif choice == "view":
            view_pairs(pairs)
        elif choice == "remove":
            updated = remove_pair_flow(pairs)
            if updated is not pairs:
                pairs = updated
                write_pairs(pairs)
                restart_watcher()
        elif choice == "service":
            _manage_service()
        else:
            return
