import shutil


def command_exists(cmd: str) -> bool:
    return shutil.which(cmd) is not None
