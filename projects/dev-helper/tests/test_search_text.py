from dev_helper.commands.search_text import SearchTextOptions, build_grep_args


def test_builds_a_recursive_grep_with_no_excludes() -> None:
    opts = SearchTextOptions(search_path=".", search_text="TODO", exclude_dirs=[])
    assert build_grep_args(opts) == ["-r", "TODO", "."]


def test_adds_one_exclude_dir_per_excluded_directory() -> None:
    opts = SearchTextOptions(search_path="src", search_text="foo", exclude_dirs=["node_modules", "dist"])
    assert build_grep_args(opts) == ["-r", "--exclude-dir=node_modules", "--exclude-dir=dist", "foo", "src"]
