import pytest

from dev_helper.commands.port_usage import is_valid_port_number
from dev_helper.utils.prompt import Option, to_questionary_verdict


# WHY: this adapter is the one piece of genuinely new logic the port
# introduced -- @clack validators answer "what's wrong?" (a message, or None
# for fine), questionary's answer "is it fine?" (True, or a message). Getting
# the polarity backwards would reject every valid input, or accept every
# invalid one, and neither shows up until someone types at a live prompt.
def test_verdict_is_true_when_the_validator_reports_no_error() -> None:
    verdict = to_questionary_verdict(lambda v: None if is_valid_port_number(v) else "Please enter a valid port number.")
    assert verdict("8080") is True


def test_verdict_is_the_error_message_when_the_validator_rejects() -> None:
    verdict = to_questionary_verdict(lambda v: None if is_valid_port_number(v) else "Please enter a valid port number.")
    assert verdict("abc") == "Please enter a valid port number."


# WHY: an empty error string is still an error. Returning it verbatim keeps
# questionary in the invalid state; collapsing it to True (a truthiness check
# instead of an `is None` check) would let the input through.
def test_an_empty_error_message_still_counts_as_invalid() -> None:
    verdict = to_questionary_verdict(lambda _: "")
    assert verdict("anything") == ""


def test_option_carries_the_value_and_its_display_label() -> None:
    option = Option(value="add", label="Add sync pairs")
    assert (option.value, option.label) == ("add", "Add sync pairs")


# WHY: cancelling a prompt must end the process, not fall through and return
# None into code annotated as returning str -- every call site would then have
# to defend against a None it can't see in the types.
def test_ask_exits_the_process_on_cancel() -> None:
    from dev_helper.utils import prompt

    class CancellingQuestion:
        def unsafe_ask(self) -> object:
            raise KeyboardInterrupt

    with pytest.raises(SystemExit) as excinfo:
        prompt._ask(CancellingQuestion())  # type: ignore[arg-type]
    assert excinfo.value.code == 0
