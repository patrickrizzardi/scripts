from dev_helper.commands.git_diff import extract_diff_filenames


def test_extracts_filenames_from_only_in_lines() -> None:
    assert extract_diff_filenames("Only in /tmp/base/src: extra.ts\n", "/tmp") == ["src/extra.ts"]


def test_extracts_filenames_from_diff_r_lines_and_dedups_base_target() -> None:
    output = "\n".join(
        [
            "diff -r /tmp/base/src/app.ts /tmp/target/src/app.ts",
            "1c1",
            "< old",
            "---",
            "> new",
        ]
    )
    assert extract_diff_filenames(output, "/tmp") == ["src/app.ts"]


def test_returns_an_empty_list_when_there_are_no_differences() -> None:
    assert extract_diff_filenames("", "/tmp") == []


# WHY: mkdtemp() generates a randomly-suffixed workDir at runtime (e.g.
# /tmp/dev-helper-gitdiff-Ab12), not the hardcoded /tmp/base|target the old
# implementation assumed -- this reproduces that real-world prefix and
# asserts it strips cleanly, with no leftover temp-dir path.
def test_strips_a_realistic_random_suffixed_work_dir_prefix_from_only_in_lines() -> None:
    work_dir = "/tmp/dev-helper-gitdiff-Ab12"
    assert extract_diff_filenames(f"Only in {work_dir}/base/src: extra.ts\n", work_dir) == ["src/extra.ts"]
