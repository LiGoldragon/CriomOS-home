#!/usr/bin/env python3
"""Scenarios for the event-driven Mako battery warning state machine."""

import asyncio
import importlib.util
import pathlib
import sys


class FakeNotifications:
    def __init__(self) -> None:
        self.calls: list[tuple] = []
        self.next_id = 40

    async def notify(self, replaces_id: int, percentage: int, level: int, critical: bool) -> int:
        self.next_id += 1
        notification_id = replaces_id or self.next_id
        self.calls.append(("notify", replaces_id, notification_id, percentage, level, critical))
        return notification_id

    async def close(self, notification_id: int) -> None:
        self.calls.append(("close", notification_id))


async def scenarios(module: object) -> None:
    notifications = FakeNotifications()
    monitor = module.BatteryWarningMonitor(notifications)

    await monitor.update(percentage=10.5, state=2, on_battery=True, present=True)
    assert notifications.calls == []

    await monitor.update(percentage=10, state=2, on_battery=True, present=True)
    first_id = monitor.notification_id
    assert notifications.calls[-1] == ("notify", 0, first_id, 10, 10, False)

    await monitor.update(percentage=5, state=2, on_battery=True, present=True)
    assert notifications.calls[-1] == ("notify", first_id, first_id, 5, 5, True)

    await monitor.update(percentage=2, state=2, on_battery=True, present=True)
    assert notifications.calls[-1] == ("notify", first_id, first_id, 2, 2, True)

    await monitor.update(percentage=4, state=1, on_battery=False, present=True)
    assert notifications.calls[-1] == ("close", first_id)
    assert monitor.notification_id == 0

    await monitor.update(percentage=2, state=2, on_battery=True, present=True)
    assert notifications.calls[-1][0:2] == ("notify", 0)
    assert monitor.notification_id != first_id


def main() -> None:
    source = pathlib.Path(sys.argv[1])
    spec = importlib.util.spec_from_file_location("battery_notification", source)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    asyncio.run(scenarios(module))


if __name__ == "__main__":
    main()
