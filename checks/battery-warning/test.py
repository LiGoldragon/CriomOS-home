"""Controller and real D-Bus adapter tests, on private synthetic buses only."""
import asyncio
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

from dbus_next import PropertyAccess
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method, dbus_property, signal

spec = importlib.util.spec_from_file_location('battery_warning', sys.argv.pop())
warning = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = warning
spec.loader.exec_module(warning)
CONFIGURATION = {'app_name':'Battery fixture','category':'device.battery','icon':'battery-caution',
    'low_summary':'Low','critical_summary':'Critical','body':'Battery: {percentage:.0f}%',
    'close_timeout_seconds':5}
LOW = {'on_battery':True,'state':2,'warning_level':3,'percentage':19.0}
CHARGING = {'on_battery':False,'state':1,'warning_level':1,'percentage':19.0}
RECOVERED = {'on_battery':True,'state':2,'warning_level':1,'percentage':21.0}


class Notifications(ServiceInterface):
    def __init__(self):
        super().__init__('org.freedesktop.Notifications')
        self.sequence = 100
        self.active = {42:'unrelated fixture'}
        self.posts = asyncio.Queue()
        self.withdrawals = asyncio.Queue()

    @method()
    def Notify(self, app:'s', replacement:'u', icon:'s', summary:'s', body:'s', actions:'as', hints:'a{sv}', timeout:'i') -> 'u':
        if replacement:
            identifier = replacement
        else:
            self.sequence += 1
            identifier = self.sequence
        self.active[identifier] = app
        self.posts.put_nowait((identifier, replacement, hints['urgency'].value, timeout))
        return identifier

    @method()
    def CloseNotification(self, identifier:'u'):
        assert identifier != 42
        assert identifier in self.active
        del self.active[identifier]
        self.withdrawals.put_nowait(identifier)
        self.NotificationClosed(identifier, 3)

    @signal()
    def NotificationClosed(self, identifier, reason) -> 'uu':
        return [identifier, reason]


class PowerRoot(ServiceInterface):
    def __init__(self):
        super().__init__('org.freedesktop.UPower')
        self.on_battery = False

    @method()
    def GetDisplayDevice(self) -> 'o':
        return '/org/freedesktop/UPower/devices/DisplayDevice'

    @dbus_property(access=PropertyAccess.READ)
    def OnBattery(self) -> 'b':
        return self.on_battery


class PowerDevice(ServiceInterface):
    def __init__(self):
        super().__init__('org.freedesktop.UPower.Device')
        self.state = 1
        self.warning_level = 1
        self.percentage = 80.0

    @dbus_property(access=PropertyAccess.READ)
    def State(self) -> 'u':
        return self.state

    @dbus_property(access=PropertyAccess.READ)
    def WarningLevel(self) -> 'u':
        return self.warning_level

    @dbus_property(access=PropertyAccess.READ)
    def Percentage(self) -> 'd':
        return self.percentage


class BatteryWarningTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.daemon = await asyncio.create_subprocess_exec('dbus-daemon','--session','--nofork','--print-address=1',
            stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.DEVNULL)
        address = (await self.daemon.stdout.readline()).decode().strip()
        self.environment = mock.patch.dict(os.environ,{'DBUS_SESSION_BUS_ADDRESS':address,'DBUS_SYSTEM_BUS_ADDRESS':address})
        self.environment.start()
        self.bus = await MessageBus(bus_address=address).connect()
        self.notifications = Notifications()
        self.root = PowerRoot()
        self.device = PowerDevice()
        self.bus.export('/org/freedesktop/Notifications',self.notifications)
        self.bus.export('/org/freedesktop/UPower',self.root)
        self.bus.export('/org/freedesktop/UPower/devices/DisplayDevice',self.device)
        await self.bus.request_name('org.freedesktop.Notifications')
        await self.bus.request_name('org.freedesktop.UPower')
        self.notifier = warning.SessionNotifier(CONFIGURATION,lambda cause:None)
        await self.notifier.connect()
        self.controller = warning.Controller(self.notifier,CONFIGURATION)

    async def asyncTearDown(self):
        await self.controller.withdraw()
        self.notifier.disconnect()
        self.bus.disconnect()
        self.daemon.terminate()
        await self.daemon.wait()
        self.environment.stop()

    async def update(self, value):
        return await self.controller.update(warning.PowerSnapshot.decode(value))

    async def test_charging_withdraws_exact_notice_and_rearms(self):
        for _ in range(2):
            self.assertEqual('posted',await self.update(LOW))
            identifier = self.controller.notice.identifier
            self.assertEqual('withdrawn',await self.update(CHARGING))
            self.assertEqual(identifier,await self.notifications.withdrawals.get())
        self.assertIn(42,self.notifications.active)

    async def test_level_recovery_withdraws_without_charger(self):
        await self.update(LOW)
        identifier = self.controller.notice.identifier
        self.assertEqual('withdrawn',await self.update(RECOVERED))
        self.assertEqual(identifier,await self.notifications.withdrawals.get())
        self.assertEqual('posted',await self.update(LOW))

    async def test_charging_state_alone_withdraws_despite_stale_warning(self):
        for state in (1,4,5):
            await self.update(LOW)
            self.assertEqual('withdrawn',await self.update({**LOW,'state':state}))

    async def test_external_power_alone_withdraws(self):
        await self.update(LOW)
        self.assertEqual('withdrawn',await self.update({**LOW,'on_battery':False}))

    async def test_repeated_level_does_not_repeat_notice(self):
        await self.update(LOW)
        self.assertEqual('unchanged',await self.update({**LOW,'percentage':18.0}))
        self.assertEqual(1,self.notifications.posts.qsize())

    async def test_critical_escalation_replaces_only_owned_notice(self):
        await self.update(LOW)
        identifier=self.controller.notice.identifier
        await self.update({**LOW,'warning_level':4})
        first=await self.notifications.posts.get()
        second=await self.notifications.posts.get()
        self.assertEqual((identifier,0,1,-1),first)
        self.assertEqual((identifier,identifier,2,-1),second)

    async def test_expiry_is_not_counted_as_causal_withdrawal(self):
        await self.update(LOW)
        identifier=self.controller.notice.identifier
        self.notifications.active.pop(identifier)
        self.notifications.NotificationClosed(identifier,1)
        await asyncio.wait_for(asyncio.shield(self.controller.notice.closed),5)
        self.assertEqual('unchanged',await self.update(CHARGING))
        self.assertTrue(self.notifications.withdrawals.empty())

    async def test_proof_capability_never_constructs_power_source(self):
        cfg={**CONFIGURATION,'proof_events':[
            {'name':'low','state':LOW,'expect':'posted'},
            {'name':'charging','state':CHARGING,'expect':'withdrawn'},
            {'name':'low-again','state':LOW,'expect':'posted'},
            {'name':'recovered','state':RECOVERED,'expect':'withdrawn'}]}
        with mock.patch.object(warning,'PowerSource',side_effect=AssertionError('hardware source forbidden')):
            await warning.run(cfg,True)
        self.assertEqual({42:'unrelated fixture'},self.notifications.active)

    async def test_real_properties_changed_adapter_drives_withdrawal(self):
        changed=asyncio.Queue()
        source=warning.PowerSource(changed.put_nowait)
        try:
            await source.connect()
            self.root.on_battery=True
            self.device.state=2
            self.device.warning_level=3
            self.device.percentage=19.0
            self.device.emit_properties_changed({'State':2,'WarningLevel':3,'Percentage':19.0})
            await asyncio.wait_for(changed.get(),5)
            await self.controller.update(await source.snapshot())
            identifier=self.controller.notice.identifier
            self.root.on_battery=False
            self.root.emit_properties_changed({'OnBattery':False})
            await asyncio.wait_for(changed.get(),5)
            self.assertEqual('withdrawn',await self.controller.update(await source.snapshot()))
            self.assertEqual(identifier,await self.notifications.withdrawals.get())
        finally:
            source.disconnect()


if __name__ == '__main__':
    unittest.main()
