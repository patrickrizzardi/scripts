from __future__ import annotations

import os
import re
import shutil
import tempfile

from dev_helper.utils.command_exists import command_exists
from dev_helper.utils.print import print_error, print_header, print_success, print_warning
from dev_helper.utils.proc import run, run_bytes, run_inherit
from dev_helper.utils.prompt import text_prompt


def strip_known_prefix(directory: str, base_dir: str, target_dir: str) -> str:
    if directory.startswith(base_dir):
        return directory[len(base_dir) :].removeprefix("/")
    if directory.startswith(target_dir):
        return directory[len(target_dir) :].removeprefix("/")
    return directory


def extract_diff_filenames(diff_output: str, work_dir: str) -> list[str]:
    names: set[str] = set()
    base_dir = f"{work_dir}/base"
    target_dir = f"{work_dir}/target"
    for line in diff_output.split("\n"):
        only_in = re.match(r"^Only in (.+): (.+)$", line)
        if only_in:
            directory = strip_known_prefix(only_in.group(1), base_dir, target_dir)
            filename = only_in.group(2)
            names.add(f"{directory}/{filename}" if directory else filename)
            continue
        diff_line = re.match(r"^diff -r \S*/base/(\S+) \S*/target/\S+$", line)
        if diff_line:
            names.add(diff_line.group(1))
    return sorted(names)


def compare_git_branches() -> None:
    if run(["git", "rev-parse", "--is-inside-work-tree"]).exit_code != 0:
        print_error("Error: Not in a git repository.")
        return

    if not command_exists("colordiff"):
        print_error("Error: 'colordiff' command is missing.")
        print_warning("Please install it using: sudo apt-get update && sudo apt-get install -y colordiff")
        return

    base_branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
    target_branch = text_prompt("Enter the target branch name:", default_value="main")

    work_dir = tempfile.mkdtemp(prefix="dev-helper-gitdiff-")
    base_dir = os.path.join(work_dir, "base")
    target_dir = os.path.join(work_dir, "target")

    try:
        for ref, directory in ((base_branch, base_dir), (target_branch, target_dir)):
            # The tarball is binary, so this leg stays on the bytes-oriented
            # runner -- decoding it to text and back would corrupt the archive.
            archive = run_bytes(["git", "archive", ref])
            os.makedirs(directory, exist_ok=True)
            run_bytes(["tar", "-x", "-C", directory], stdin=archive.stdout)

        diff_output = run(["diff", "-r", "-w", "-B", "-b", base_dir, target_dir]).stdout
        run_inherit(["colordiff"], stdin=diff_output)

        filenames = extract_diff_filenames(diff_output, work_dir)
        if filenames:
            print_header("Files that differ:")
            for filename in filenames:
                print(filename)
        else:
            print_warning("No file differences found")
        print_header("Number of files in the diff:")
        print_success(str(len(filenames)))
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
