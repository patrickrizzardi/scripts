from dev_helper.commands.network import build_ss_args


def test_tcp_listening_only() -> None:
    assert build_ss_args(False, "tcp") == ["-tln"]


def test_udp_listening_only() -> None:
    assert build_ss_args(False, "udp") == ["-uln"]


def test_tcp_show_all_connections() -> None:
    assert build_ss_args(True, "tcp") == ["-tun"]


def test_udp_show_all_connections() -> None:
    assert build_ss_args(True, "udp") == ["-un"]
