from __future__ import annotations

from dataclasses import dataclass

from dev_helper.utils.print import print_info
from dev_helper.utils.proc import run_inherit
from dev_helper.utils.prompt import text_prompt


@dataclass(frozen=True)
class FindFilesOptions:
    search_path: str
    file_pattern: str
    exclude_dirs: list[str]


def build_find_args(opts: FindFilesOptions) -> list[str]:
    args = [opts.search_path, "-type", "f", "-name", opts.file_pattern]
    for directory in opts.exclude_dirs:
        args += ["-not", "-path", f"*/{directory}/*"]
    return args


def find_files_by_name() -> None:
    search_path = text_prompt("Enter the path to search in:", default_value="~/")
    file_pattern = text_prompt("Enter the file name pattern (e.g. '*.js'):")
    exclude_input = text_prompt("Enter directories to exclude (comma-separated):", default_value="")
    exclude_dirs = [directory.strip() for directory in exclude_input.split(",")] if exclude_input else []

    print_info(f"Searching for files matching '{file_pattern}' in {search_path}...")
    args = build_find_args(FindFilesOptions(search_path, file_pattern, exclude_dirs))
    run_inherit(["find", *args])
