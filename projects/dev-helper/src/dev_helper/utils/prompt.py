from __future__ import annotations

import sys
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Generic, TypeVar, cast

import questionary
from questionary import Choice, Question

from dev_helper.utils.print import print_error

T = TypeVar("T", bound=str)


@dataclass(frozen=True)
class Option(Generic[T]):
    value: T
    label: str


def _ask(question: Question) -> object:
    """Ask a question, treating Ctrl+C / Ctrl+D as "cancel the whole tool".

    questionary's own ask() swallows KeyboardInterrupt and returns None, which
    would make a cancel indistinguishable from a falsy answer (an unchecked
    checkbox list, a "no" confirm). unsafe_ask() lets the interrupt through so
    cancelling exits deliberately, the way @clack's isCancel() guard did.
    """
    try:
        return question.unsafe_ask()
    except (KeyboardInterrupt, EOFError):
        print_error("Cancelled.")
        sys.exit(0)


def select_prompt(message: str, options: Sequence[Option[T]]) -> T:
    choices = [Choice(title=option.label, value=option.value) for option in options]
    return cast(T, _ask(questionary.select(message, choices=choices)))


def multiselect_prompt(message: str, options: Sequence[Option[T]]) -> list[T]:
    """Multi-select that allows submitting nothing.

    questionary's checkbox() defaults to `validate=lambda a: True`, i.e. an
    empty selection is accepted — matching @clack's `required: false`. Callers
    rely on that: add_pairs treats an empty list as "user changed their mind"
    and returns without writing config.
    """
    choices = [Choice(title=option.label, value=option.value) for option in options]
    return cast("list[T]", _ask(questionary.checkbox(message, choices=choices)))


def to_questionary_verdict(validate: Callable[[str], str | None]) -> Callable[[str], bool | str]:
    """Bridge the two validator conventions.

    @clack validators return an error message, or None when the input is fine.
    questionary's return True when it's fine, or the error message string.
    Keeping the @clack shape as this tool's public contract means the call
    sites read the same as before the port; this adapter is the only place
    that knows about the difference.
    """

    def verdict(value: str) -> bool | str:
        error = validate(value)
        return True if error is None else error

    return verdict


def text_prompt(
    message: str,
    *,
    default_value: str = "",
    validate: Callable[[str], str | None] | None = None,
) -> str:
    """Free-text prompt.

    Note the one visible difference from @clack: questionary pre-fills
    `default_value` into the editable buffer instead of showing it as a dimmed
    placeholder. Submitting without typing yields the same value either way.
    """
    question = questionary.text(
        message,
        default=default_value,
        validate=to_questionary_verdict(validate) if validate is not None else None,
    )
    return cast(str, _ask(question))


def confirm_prompt(message: str) -> bool:
    return cast(bool, _ask(questionary.confirm(message)))
