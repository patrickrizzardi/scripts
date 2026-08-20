from dev_helper.commands.find_files import FindFilesOptions, build_find_args


def test_builds_a_find_command_with_no_excludes() -> None:
    opts = FindFilesOptions(search_path="~/", file_pattern="*.js", exclude_dirs=[])
    assert build_find_args(opts) == ["~/", "-type", "f", "-name", "*.js"]


def test_adds_not_path_per_excluded_directory() -> None:
    opts = FindFilesOptions(search_path=".", file_pattern="config.*", exclude_dirs=["node_modules"])
    assert build_find_args(opts) == [".", "-type", "f", "-name", "config.*", "-not", "-path", "*/node_modules/*"]
