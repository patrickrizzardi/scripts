from dev_helper.utils.command_exists import command_exists


def test_returns_true_for_a_binary_that_is_definitely_on_path() -> None:
    assert command_exists("ls") is True


def test_returns_false_for_a_binary_that_does_not_exist() -> None:
    assert command_exists("definitely-not-a-real-command-xyz") is False
