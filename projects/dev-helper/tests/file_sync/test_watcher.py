import re

from dev_helper.commands.file_sync.watcher import (
    INOTIFY_INSTALL_COMMAND,
    generate_fallback_service_content,
    generate_fallback_timer_content,
    generate_sync_script_content,
    generate_watch_script_content,
    generate_watch_service_content,
)


def test_sync_script_uses_rsync_a_delete_for_directories() -> None:
    assert "rsync -a --delete" in generate_sync_script_content()


def test_sync_script_uses_rsync_a_for_files() -> None:
    assert 'rsync -a "$source"' in generate_sync_script_content()


def test_sync_script_reads_pairs_conf() -> None:
    assert "pairs.conf" in generate_sync_script_content()


# WHY: a deleted source (file or whole directory) must delete the target
# on the next sync too -- otherwise a removed source silently leaves a
# stale copy behind forever, whether it's a single file or an entire
# folder. rm -rf handles both target shapes with one code path.
def test_sync_script_deletes_the_target_when_a_previously_synced_source_is_gone() -> None:
    assert 'rm -rf "$target"' in generate_sync_script_content()


def test_sync_script_only_deletes_the_target_if_it_still_exists() -> None:
    # The deletion branch must be gated on the target actually being
    # present -- a source that was never synced yet has no target to delete.
    content = generate_sync_script_content()
    assert re.search(r'if \[\[ -e "\$target" \]\]; then\s*\n\s*rm -rf "\$target"', content)


# WHY: this shell is emitted from Python string literals now. A plain (non-raw)
# literal would silently eat the backslash in the `\#*` comment guard, so bash
# would compare against the glob `#*` instead of a literal leading '#' -- these
# assert the raw-string escaping survived the port.
def test_sync_script_keeps_the_literal_backslash_hash_comment_guard() -> None:
    assert r'"$source" == \#*' in generate_sync_script_content()


def test_watch_script_keeps_bash_array_expansions_uninterpolated() -> None:
    content = generate_watch_script_content()
    assert '"${sources[@]}"' in content
    assert "${#sources[@]}" in content


def test_watch_script_watches_with_inotifywait_recursively() -> None:
    assert "inotifywait -m -r -e modify,create,delete,move" in generate_watch_script_content()


def test_watch_script_debounces_before_re_running_sync_sh() -> None:
    assert "read -r -t 0.3" in generate_watch_script_content()


def test_watch_script_calls_sync_sh_after_a_change() -> None:
    assert "sync.sh" in generate_watch_script_content()


def test_watch_service_is_a_long_running_type_simple_unit_pointing_at_watch_sh() -> None:
    content = generate_watch_service_content()
    assert "Type=simple" in content
    assert "%h/.config/rsync-sync/watch.sh" in content


def test_fallback_service_runs_sync_sh_as_a_oneshot() -> None:
    content = generate_fallback_service_content()
    assert "Type=oneshot" in content
    assert "%h/.config/rsync-sync/sync.sh" in content


def test_fallback_timer_fires_every_5_minutes() -> None:
    assert "OnUnitActiveSec=5min" in generate_fallback_timer_content()


def test_inotify_install_command_names_the_inotify_tools_package() -> None:
    assert "inotify-tools" in INOTIFY_INSTALL_COMMAND
