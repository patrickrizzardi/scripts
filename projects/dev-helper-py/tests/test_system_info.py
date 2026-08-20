from dev_helper.commands.system_info import SystemInfo, format_system_info


def test_formats_each_field_with_its_label() -> None:
    info = SystemInfo(
        os="Linux 6.6.0",
        cpu="AMD Ryzen 9",
        memory="32G total",
        disk="512G total",
        uptime="up 3 days",
    )
    assert format_system_info(info) == [
        "OS: Linux 6.6.0",
        "CPU: AMD Ryzen 9",
        "Memory: 32G total",
        "Disk: 512G total",
        "Uptime: up 3 days",
    ]
