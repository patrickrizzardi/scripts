from dev_helper.commands.port_usage import is_valid_port_number


def test_accepts_a_plain_numeric_string() -> None:
    assert is_valid_port_number("8080") is True


def test_rejects_a_non_numeric_string() -> None:
    assert is_valid_port_number("abc") is False


def test_rejects_an_empty_string() -> None:
    assert is_valid_port_number("") is False


def test_rejects_a_negative_number() -> None:
    assert is_valid_port_number("-1") is False


# WHY: re.match() would accept "80abc" by matching only the prefix, and a
# bare re.fullmatch with $ would accept a trailing newline ("8080\n") -- both
# would send a bogus string into the `grep ":$port"` shell interpolation.
def test_rejects_a_numeric_prefix_followed_by_junk() -> None:
    assert is_valid_port_number("80abc") is False


def test_rejects_a_numeric_string_with_a_trailing_newline() -> None:
    assert is_valid_port_number("8080\n") is False
