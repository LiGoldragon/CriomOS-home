"""UPower events own one Mako notice; recovery withdraws that exact notice."""
import argparse
import asyncio
from dataclasses import dataclass
from enum import IntEnum
import json
from pathlib import Path
import signal
import uuid


class WarningLevel(IntEnum):
    UNKNOWN = 0
    NONE = 1
    DISCHARGING = 2
    LOW = 3
    CRITICAL = 4
    ACTION = 5


class BatteryState(IntEnum):
    UNKNOWN = 0
    CHARGING = 1
    DISCHARGING = 2
    EMPTY = 3
    FULLY_CHARGED = 4
    PENDING_CHARGE = 5
    PENDING_DISCHARGE = 6


@dataclass(frozen=True)
class PowerSnapshot:
    on_battery: bool
    state: BatteryState
    warning_level: WarningLevel
    percentage: float

    @classmethod
    def decode(cls, value):
        return cls(value['on_battery'], BatteryState(value['state']),
                   WarningLevel(value['warning_level']), value['percentage'])

    def warning(self):
        charging = self.state in (BatteryState.CHARGING, BatteryState.FULLY_CHARGED,
                                  BatteryState.PENDING_CHARGE)
        return self.warning_level if self.on_battery and not charging and self.warning_level >= WarningLevel.LOW else None


def event(kind, **fields):
    print(json.dumps({'event': kind, **fields}), flush=True)


class Controller:
    def __init__(self, notifier, configuration):
        self.notifier = notifier
        self.configuration = configuration
        self.level = None
        self.notice = None

    async def update(self, snapshot):
        level = snapshot.warning()
        if level is None:
            effect = await self.withdraw()
            self.level = None
            return effect
        if level == self.level:
            return 'unchanged'
        critical = level >= WarningLevel.CRITICAL
        notice = await self.notifier.post(
            self.configuration['critical_summary' if critical else 'low_summary'],
            self.configuration['body'].format(percentage=snapshot.percentage),
            critical, self.notice)
        self.notice = notice
        self.level = level
        event('posted', owner=notice.owner, identifier=notice.identifier, level=level.name)
        return 'posted'

    async def withdraw(self):
        if self.notice is None:
            return 'unchanged'
        notice = self.notice
        closed = await self.notifier.close(notice)
        self.notice = None
        if closed:
            event('withdrawn', owner=notice.owner, identifier=notice.identifier, reason='CloseNotification')
            return 'withdrawn'
        return 'unchanged'

    def server_replaced(self):
        # IDs belong to a particular bus owner, not the replacement server.
        self.notice = None
        self.level = None


@dataclass
class Notice:
    owner: str
    identifier: int
    closed: asyncio.Future


class SessionNotifier:
    def __init__(self, configuration, changed):
        self.configuration = configuration
        self.changed = changed
        self.bus = None
        self.owner = None
        self.proxy = None
        self.notices = {}

    async def connect(self):
        from dbus_next.aio import MessageBus
        self.bus = await MessageBus().connect()
        description = await self.bus.introspect('org.freedesktop.DBus', '/org/freedesktop/DBus')
        self.database = self.bus.get_proxy_object('org.freedesktop.DBus', '/org/freedesktop/DBus', description).get_interface('org.freedesktop.DBus')
        self.database.on_name_owner_changed(self.owner_changed)
        await self.bind()

    async def bind(self):
        owner = await self.database.call_get_name_owner('org.freedesktop.Notifications')
        description = await self.bus.introspect(owner, '/org/freedesktop/Notifications')
        proxy = self.bus.get_proxy_object(owner, '/org/freedesktop/Notifications', description).get_interface('org.freedesktop.Notifications')
        proxy.on_notification_closed(lambda identifier, reason: self.closed(owner, identifier, reason))
        self.owner, self.proxy = owner, proxy

    def owner_changed(self, name, previous, current):
        if name == 'org.freedesktop.Notifications' and previous == self.owner:
            for notice in self.notices.values():
                if not notice.closed.done():
                    notice.closed.set_result('server-gone')
            self.notices.clear()
            self.owner = None
        if name == 'org.freedesktop.Notifications' and current:
            self.changed('server')

    def closed(self, owner, identifier, reason):
        notice = self.notices.pop((owner, identifier), None)
        if notice is not None and not notice.closed.done():
            notice.closed.set_result(reason)

    async def post(self, summary, body, critical, previous):
        from dbus_next import Variant
        if self.owner is None:
            await self.bind()
        replacement = previous.identifier if previous is not None and previous.owner == self.owner and not previous.closed.done() else 0
        identifier = await self.proxy.call_notify(self.configuration['app_name'], replacement,
            self.configuration['icon'], summary, body, [],
            {'urgency': Variant('y', 2 if critical else 1),
             'category': Variant('s', self.configuration['category'])}, -1)
        if replacement == identifier and previous is not None:
            return previous
        notice = Notice(self.owner, identifier, asyncio.get_running_loop().create_future())
        self.notices[(notice.owner, identifier)] = notice
        return notice

    async def close(self, notice):
        if notice.closed.done():
            return False
        if notice.owner != self.owner:
            # The old server has gone; never send its ID to another owner.
            return False
        await self.proxy.call_close_notification(notice.identifier)
        reason = await asyncio.wait_for(asyncio.shield(notice.closed), self.configuration['close_timeout_seconds'])
        if reason != 3:
            raise RuntimeError('notification withdrawal was not acknowledged')
        return True

    def disconnect(self):
        if self.bus is not None:
            self.bus.disconnect()


class PowerSource:
    def __init__(self, changed):
        self.changed = changed
        self.bus = None

    async def connect(self):
        from dbus_next import BusType
        from dbus_next.aio import MessageBus
        self.bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
        description = await self.bus.introspect('org.freedesktop.UPower', '/org/freedesktop/UPower')
        root = self.bus.get_proxy_object('org.freedesktop.UPower', '/org/freedesktop/UPower', description)
        self.root = root.get_interface('org.freedesktop.DBus.Properties')
        self.root.on_properties_changed(self.properties_changed)
        path = await root.get_interface('org.freedesktop.UPower').call_get_display_device()
        description = await self.bus.introspect('org.freedesktop.UPower', path)
        self.device = self.bus.get_proxy_object('org.freedesktop.UPower', path, description).get_interface('org.freedesktop.DBus.Properties')
        self.device.on_properties_changed(self.properties_changed)

    def properties_changed(self, interface, changed, invalidated):
        if interface in ('org.freedesktop.UPower', 'org.freedesktop.UPower.Device'):
            self.changed('power')

    async def snapshot(self):
        # These reads answer an initial-subscription or PropertiesChanged event.
        root = await self.root.call_get_all('org.freedesktop.UPower')
        device = await self.device.call_get_all('org.freedesktop.UPower.Device')
        return PowerSnapshot(root['OnBattery'].value, BatteryState(device['State'].value),
            WarningLevel(device['WarningLevel'].value), device['Percentage'].value)

    def disconnect(self):
        if self.bus is not None:
            self.bus.disconnect()


async def run(configuration, prove):
    changes = asyncio.Queue()
    notifier = SessionNotifier(configuration, changes.put_nowait)
    source = None
    controller = Controller(notifier, configuration)
    loop = asyncio.get_running_loop()
    for number in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(number, changes.put_nowait, 'stop')
    try:
        await notifier.connect()
        if prove:
            # No PowerSource/system bus is constructed in this capability.
            for fixture in configuration['proof_events']:
                effect = await controller.update(PowerSnapshot.decode(fixture['state']))
                if effect != fixture['expect']:
                    raise RuntimeError('causal proof effect mismatch')
                event('proof-step', name=fixture['name'], effect=effect)
            return
        source = PowerSource(changes.put_nowait)
        await source.connect()
        changes.put_nowait('power')
        while True:
            cause = await changes.get()
            if cause == 'stop':
                break
            if cause == 'server':
                controller.server_replaced()
            await controller.update(await source.snapshot())
    finally:
        try:
            await controller.withdraw()
        finally:
            if source is not None:
                source.disconnect()
            notifier.disconnect()
            for number in (signal.SIGINT, signal.SIGTERM):
                loop.remove_signal_handler(number)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('capability', choices=('run', 'prove'))
    parser.add_argument('configuration', type=Path)
    arguments = parser.parse_args()
    configuration = json.loads(arguments.configuration.read_text())
    if arguments.capability == 'prove':
        configuration['app_name'] += ' proof ' + uuid.uuid4().hex
    asyncio.run(run(configuration, arguments.capability == 'prove'))


if __name__ == '__main__':
    main()
