#!/usr/bin/env python3
"""Publish UPower battery transitions through the desktop notification service."""

from __future__ import annotations

import asyncio
from typing import Protocol

from dbus_next import BusType, Variant
from dbus_next.aio import MessageBus
from dbus_next.errors import DBusError

UPOWER_SERVICE = "org.freedesktop.UPower"
UPOWER_PATH = "/org/freedesktop/UPower"
UPOWER_INTERFACE = "org.freedesktop.UPower"
UPOWER_DEVICE_INTERFACE = "org.freedesktop.UPower.Device"
PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"
NOTIFICATION_SERVICE = "org.freedesktop.Notifications"
NOTIFICATION_PATH = "/org/freedesktop/Notifications"
NOTIFICATION_INTERFACE = "org.freedesktop.Notifications"
DBUS_SERVICE = "org.freedesktop.DBus"
DBUS_PATH = "/org/freedesktop/DBus"
DBUS_INTERFACE = "org.freedesktop.DBus"

PLUGGED_STATES = {1, 4, 5}  # charging, fully charged, pending charge
WARNING_LEVELS = (10, 5, 2)


class Notifications(Protocol):
    async def notify(self, replaces_id: int, percentage: int, level: int, critical: bool) -> int: ...

    async def close(self, notification_id: int) -> None: ...


class BatteryWarningMonitor:
    """Level-triggered warnings whose one active notification follows AC state."""

    def __init__(self, notifications: Notifications) -> None:
        self.notifications = notifications
        self.fired_level: int | None = None
        self.notification_id = 0

    async def update(self, *, percentage: float, state: int, on_battery: bool, present: bool) -> None:
        if not present or not on_battery or state in PLUGGED_STATES:
            if self.notification_id:
                await self.notifications.close(self.notification_id)
                self.notification_id = 0
            self.fired_level = None
            return

        percent = max(0, min(100, int(percentage + 0.5)))
        level = next((candidate for candidate in reversed(WARNING_LEVELS) if percent <= candidate), None)
        if level is None:
            self.fired_level = None
            return

        if self.fired_level is None or level < self.fired_level:
            self.notification_id = await self.notifications.notify(
                self.notification_id, percent, level, level <= 5
            )
            self.fired_level = level
        elif level > self.fired_level:
            # A partial recharge arms the deeper level for the next descent.
            self.fired_level = level


class FreedesktopNotifications:
    def __init__(self, interface: object) -> None:
        self.interface = interface

    @classmethod
    async def connect(cls, bus: MessageBus) -> "FreedesktopNotifications":
        bus_intro = await bus.introspect(DBUS_SERVICE, DBUS_PATH)
        bus_interface = bus.get_proxy_object(DBUS_SERVICE, DBUS_PATH, bus_intro).get_interface(DBUS_INTERFACE)
        ready = asyncio.Event()

        def name_owner_changed(name: str, _old_owner: str, new_owner: str) -> None:
            if name == NOTIFICATION_SERVICE and new_owner:
                ready.set()

        bus_interface.on_name_owner_changed(name_owner_changed)
        if await bus_interface.call_name_has_owner(NOTIFICATION_SERVICE):
            ready.set()
        await ready.wait()

        intro = await bus.introspect(NOTIFICATION_SERVICE, NOTIFICATION_PATH)
        interface = bus.get_proxy_object(
            NOTIFICATION_SERVICE, NOTIFICATION_PATH, intro
        ).get_interface(NOTIFICATION_INTERFACE)
        return cls(interface)

    async def notify(self, replaces_id: int, percentage: int, level: int, critical: bool) -> int:
        summary = "Battery critically low" if critical else "Battery low"
        return await self.interface.call_notify(
            "Battery",
            replaces_id,
            "battery-caution",
            summary,
            f"Battery charge is {percentage}%.",
            [],
            {"urgency": Variant("y", 2 if critical else 1)},
            -1,
        )

    async def close(self, notification_id: int) -> None:
        try:
            await self.interface.call_close_notification(notification_id)
        except DBusError:
            # Mako may already have expired the bounded notification.
            pass


async def run() -> None:
    system_bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    session_bus = await MessageBus().connect()
    notifications = await FreedesktopNotifications.connect(session_bus)
    monitor = BatteryWarningMonitor(notifications)

    upower_intro = await system_bus.introspect(UPOWER_SERVICE, UPOWER_PATH)
    upower_object = system_bus.get_proxy_object(UPOWER_SERVICE, UPOWER_PATH, upower_intro)
    upower = upower_object.get_interface(UPOWER_INTERFACE)
    upower_properties = upower_object.get_interface(PROPERTIES_INTERFACE)
    device_path = await upower.call_get_display_device()
    device_intro = await system_bus.introspect(UPOWER_SERVICE, device_path)
    device_properties = system_bus.get_proxy_object(
        UPOWER_SERVICE, device_path, device_intro
    ).get_interface(PROPERTIES_INTERFACE)

    changed = asyncio.Event()
    upower_properties.on_properties_changed(lambda *_args: changed.set())
    device_properties.on_properties_changed(lambda *_args: changed.set())
    changed.set()

    while True:
        await changed.wait()
        changed.clear()
        root = await upower_properties.call_get_all(UPOWER_INTERFACE)
        device = await device_properties.call_get_all(UPOWER_DEVICE_INTERFACE)
        await monitor.update(
            percentage=float(device["Percentage"].value),
            state=int(device["State"].value),
            on_battery=bool(root["OnBattery"].value),
            present=bool(device["IsPresent"].value),
        )


if __name__ == "__main__":
    asyncio.run(run())
