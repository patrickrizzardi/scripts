import os
import subprocess
from pathlib import Path

from dev_helper.commands.file_sync.service import (
    install_commands,
    is_best_effort_command,
    is_watcher_installed,
    remove_legacy_unit_files,
    service_control_args,
    write_service_files,
)


def _systemd_dir(home: Path) -> str:
    return os.path.join(str(home), ".config", "systemd", "user")


def _config_dir(home: Path) -> str:
    return os.path.join(str(home), ".config", "rsync-sync")


def test_writes_sync_sh_watch_sh_and_all_four_unit_files(tmp_path: Path) -> None:
    write_service_files(str(tmp_path))
    assert os.path.exists(os.path.join(_config_dir(tmp_path), "sync.sh"))
    assert os.path.exists(os.path.join(_config_dir(tmp_path), "watch.sh"))
    assert os.path.exists(os.path.join(_systemd_dir(tmp_path), "rsync-sync-watch.service"))
    assert os.path.exists(os.path.join(_systemd_dir(tmp_path), "rsync-sync-fallback.service"))
    assert os.path.exists(os.path.join(_systemd_dir(tmp_path), "rsync-sync-fallback.timer"))


def test_sync_sh_and_watch_sh_are_executable(tmp_path: Path) -> None:
    write_service_files(str(tmp_path))
    sync_mode = os.stat(os.path.join(_config_dir(tmp_path), "sync.sh")).st_mode
    watch_mode = os.stat(os.path.join(_config_dir(tmp_path), "watch.sh")).st_mode
    assert sync_mode & 0o111 != 0
    assert watch_mode & 0o111 != 0


# WHY: these scripts are generated as text and then executed by systemd, where
# a syntax error surfaces only as a silently dead unit. `bash -n` catches a
# botched heredoc or a mangled quote at test time instead.
def test_generated_scripts_are_valid_bash(tmp_path: Path) -> None:
    write_service_files(str(tmp_path))
    for name in ("sync.sh", "watch.sh"):
        path = os.path.join(_config_dir(tmp_path), name)
        result = subprocess.run(["bash", "-n", path], capture_output=True, text=True, check=False)
        assert result.returncode == 0, f"{name} is not valid bash: {result.stderr}"


def test_install_commands_disables_legacy_timer_then_enables_watch_service_and_fallback_timer() -> None:
    commands = install_commands()
    assert ["systemctl", "--user", "disable", "--now", "rsync-sync.timer"] in commands
    assert ["systemctl", "--user", "daemon-reload"] in commands
    assert ["systemctl", "--user", "enable", "--now", "rsync-sync-watch.service"] in commands
    assert ["systemctl", "--user", "enable", "--now", "rsync-sync-fallback.timer"] in commands


# WHY: the legacy-disable has to run before daemon-reload, or the reload picks
# up a unit that is about to be removed and systemd keeps a stale job around.
def test_install_commands_disables_the_legacy_timer_before_daemon_reload() -> None:
    commands = install_commands()
    disable_index = commands.index(["systemctl", "--user", "disable", "--now", "rsync-sync.timer"])
    reload_index = commands.index(["systemctl", "--user", "daemon-reload"])
    assert disable_index < reload_index


# WHY: distinguishes "never configured" from "configured by an older
# version of this tool" (e.g. a pre-watcher release, or the legacy bash
# tool this replaces) -- pairs.conf existing alone doesn't mean OUR
# systemd units were ever installed, and treating it as if it did skips
# the migration that disables the legacy timer.
def test_is_watcher_installed_false_when_the_watch_service_unit_was_never_written(tmp_path: Path) -> None:
    assert is_watcher_installed(str(tmp_path)) is False


def test_is_watcher_installed_true_after_write_service_files_has_run(tmp_path: Path) -> None:
    write_service_files(str(tmp_path))
    assert is_watcher_installed(str(tmp_path)) is True


# WHY: disabling the legacy timer alone leaves its unit files sitting on
# disk forever -- a silenced-but-not-removed unit is exactly the kind of
# residue no-duct-tape forbids. This proves the files are actually gone,
# not just stopped.
def test_deletes_both_legacy_unit_files_when_present(tmp_path: Path) -> None:
    systemd_dir = _systemd_dir(tmp_path)
    os.makedirs(systemd_dir, exist_ok=True)
    for name, body in (("rsync-sync.service", "fake legacy service"), ("rsync-sync.timer", "fake legacy timer")):
        with open(os.path.join(systemd_dir, name), "w", encoding="utf-8") as handle:
            handle.write(body)

    remove_legacy_unit_files(str(tmp_path))

    assert not os.path.exists(os.path.join(systemd_dir, "rsync-sync.service"))
    assert not os.path.exists(os.path.join(systemd_dir, "rsync-sync.timer"))


def test_remove_legacy_unit_files_is_a_no_op_when_they_never_existed(tmp_path: Path) -> None:
    os.makedirs(_systemd_dir(tmp_path), exist_ok=True)
    remove_legacy_unit_files(str(tmp_path))  # must not raise


# WHY: `loginctl enable-linger` requires elevated privileges on some
# systems (confirmed: fails with "Access denied" for a non-root user with
# no polkit rule granting it) -- the original bash tool treated this exact
# failure as non-fatal (`|| true`). Turning it into a hard blocker here
# would regress that: a user without linger permission could never
# install the watcher at all, even though linger only affects whether
# sync survives a full logout, not whether it works.
def test_loginctl_is_best_effort_regardless_of_args() -> None:
    assert is_best_effort_command("loginctl", ["enable-linger", "patrick"]) is True


def test_systemctl_disable_of_the_legacy_timer_is_best_effort() -> None:
    assert is_best_effort_command("systemctl", ["--user", "disable", "--now", "rsync-sync.timer"]) is True


def test_systemctl_daemon_reload_is_load_bearing_not_best_effort() -> None:
    assert is_best_effort_command("systemctl", ["--user", "daemon-reload"]) is False


def test_systemctl_enable_of_the_watch_service_is_load_bearing_not_best_effort() -> None:
    assert is_best_effort_command("systemctl", ["--user", "enable", "--now", "rsync-sync-watch.service"]) is False


def test_service_control_args_start_targets_the_watch_service() -> None:
    assert service_control_args("start") == ["--user", "start", "rsync-sync-watch.service"]


def test_service_control_args_status_targets_the_watch_service() -> None:
    assert service_control_args("status") == ["--user", "status", "rsync-sync-watch.service"]
