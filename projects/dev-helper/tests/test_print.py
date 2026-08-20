from dev_helper.utils.print import (
    format_error,
    format_header,
    format_info,
    format_menu_item,
    format_success,
    format_warning,
)


def test_format_error_wraps_in_red_and_resets() -> None:
    assert format_error("boom") == "\x1b[0;31mboom\x1b[0m"


def test_format_success_wraps_in_green_and_resets() -> None:
    assert format_success("done") == "\x1b[0;32mdone\x1b[0m"


def test_format_info_wraps_in_blue_and_resets() -> None:
    assert format_info("note") == "\x1b[0;34mnote\x1b[0m"


def test_format_warning_wraps_in_yellow_and_resets() -> None:
    assert format_warning("careful") == "\x1b[1;33mcareful\x1b[0m"


def test_format_header_wraps_in_cyan_with_border_markers() -> None:
    assert format_header("Menu") == "\x1b[0;36m========== Menu ==========\x1b[0m"


def test_format_menu_item_numbers_the_item_in_green_label_uncolored() -> None:
    assert format_menu_item("1.", "Find a file") == "\x1b[0;32m1.\x1b[0m Find a file"
