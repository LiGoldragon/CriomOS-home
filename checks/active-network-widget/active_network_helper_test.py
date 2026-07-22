#!/usr/bin/env python3
"""Focused contract tests for the Active Network helper, run by its Nix check."""

from __future__ import annotations

import asyncio
import importlib.util
import json
import stat
import sys
import tempfile
from pathlib import Path

helper_path = Path(sys.argv[1])
fixtures = Path(sys.argv[2])
widget_path = Path(sys.argv[3])
spec = importlib.util.spec_from_file_location("active_network_helper", helper_path)
assert spec is not None and spec.loader is not None
helper = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = helper
spec.loader.exec_module(helper)

states = json.loads((fixtures / "network-states.json").read_text())
widget_events = json.loads((fixtures / "widget-status-events.json").read_text())
widget_source = widget_path.read_text()


def projection(name: str) -> dict:
    fixture = states[name]
    return helper.project_network_state(
        fixture["manager"], fixture["activeConnections"], fixture["devices"]
    )


# PrimaryConnection selects its own Wi-Fi device even when Ethernet coexists;
# VPN is secondary metadata and TUN never becomes an Ethernet/Wi-Fi label.
primary_wifi = projection("primaryWifiWithVpn")
assert primary_wifi["kind"] == "wifi"
assert primary_wifi["interface"] == "wlp0s20f3"
assert primary_wifi["vpn"] is True
assert primary_wifi["wifiActive"] is True
primary_ethernet = projection("primaryEthernetWithWifi")
assert primary_ethernet["kind"] == "ethernet"
assert primary_ethernet["interface"] == "enp0s31f6"
assert primary_ethernet["connectivity"] == "unknown"  # UNKNOWN is never offline.
tunnel_only = projection("tunnelOnly")
assert tunnel_only["kind"] == "unknown"
assert tunnel_only["vpn"] is True

# Every required explicit state has an independent NetworkManager fixture.
for name, expected in {
    "connecting": "connecting",
    "limited": "limited",
    "portal": "portal",
    "failed": "failed",
    "disconnected": "disconnected",
}.items():
    assert projection(name)["state"] == expected, name

# Generated iw fixtures verify truthful current-link dBm parsing, not a
# fabricated conversion from NetworkManager percentage strength.
assert helper.parse_iw_link((fixtures / "iw-active-link.txt").read_text()) == -55
assert helper.parse_iw_link((fixtures / "iw-disconnected.txt").read_text()) is None

# Exact documented quality thresholds and colors.
for rssi, expected in [
    (-55, ("good", "#22c55e", 4)),
    (-56, ("fair", "#eab308", 3)),
    (-67, ("fair", "#eab308", 3)),
    (-68, ("weak", "#f97316", 2)),
    (-75, ("weak", "#f97316", 2)),
    (-76, ("bad", "#ef4444", 1)),
]:
    quality = helper.signal_quality(rssi)
    assert (quality["quality"], quality["qualityColor"], quality["bars"]) == expected

# Refresh is active-Wi-Fi-only and cannot occur more often than five seconds.
cache = helper.RssiCache()
assert not cache.refresh_due(False, 0)
assert cache.refresh_due(True, 0)
cache.mark_attempt(0)
assert not cache.refresh_due(True, 4.999)
assert cache.refresh_due(True, 5)
cache.record(-60, 5)
assert cache.visible_value(35) == -60
assert cache.visible_value(35.001) is None


def expected_widget_signal(rssi: int | None) -> tuple[str, str, int]:
    quality = helper.signal_quality(rssi)
    return quality["quality"], quality["qualityColor"], quality["bars"]


def valid_widget_event(event: object) -> bool:
    if not isinstance(event, dict):
        return False
    if event.get("state") not in {
        "unknown", "connecting", "limited", "portal", "failed", "disconnected", "connected"
    }:
        return False
    if event.get("connectivity") not in {"unknown", "none", "portal", "limited", "full"}:
        return False
    if event.get("kind") not in {"unknown", "ethernet", "wifi"}:
        return False
    if not isinstance(event.get("interface"), str) or len(event["interface"]) > 15:
        return False
    if not isinstance(event.get("vpn"), bool) or not isinstance(event.get("wifiActive"), bool):
        return False
    rssi = event.get("rssi")
    if rssi is not None and (type(rssi) is not int or not -200 <= rssi <= 0):
        return False
    bars = event.get("bars")
    if type(bars) is not int or not 0 <= bars <= 4:
        return False
    if (event.get("quality"), event.get("qualityColor"), bars) != expected_widget_signal(rssi):
        return False
    return not ((event["kind"] != "wifi" or not event["wifiActive"]) and rssi is not None)


# The fixture is a generated, non-personal status contract. It proves the
# expected bad enum/type/inconsistent-value cases stay rejected, while source
# assertions pin those rules to the QML validation boundary before mutation.
for event in widget_events["valid"]:
    assert valid_widget_event(event), event
for event in widget_events["invalid"]:
    assert not valid_widget_event(event), event
for source_fragment in [
    "function validateStatusEvent(event)",
    "Number.isFinite(rssiValue)",
    "Number.isInteger(rssiValue)",
    "Number.isInteger(event.bars)",
    "const status = validateStatusEvent(JSON.parse(String(message)));",
    "if (status === null)",
    "networkState = status.state;",
]:
    assert source_fragment in widget_source, source_fragment


class FakeServer:
    def __init__(self) -> None:
        self.closed = False
        self.waited = False

    def close(self) -> None:
        self.closed = True

    async def wait_closed(self) -> None:
        self.waited = True


class DisconnectingBus:
    def __init__(self) -> None:
        self.disconnected = False

    async def wait_for_disconnect(self) -> None:
        return None

    def disconnect(self) -> None:
        self.disconnected = True


class SlowWriter:
    def __init__(self) -> None:
        self.closed = False
        self.writes: list[bytes] = []
        self.drain_started = asyncio.Event()
        self.never_drains = asyncio.Event()

    def is_closing(self) -> bool:
        return self.closed

    def write(self, line: bytes) -> None:
        self.writes.append(line)

    async def drain(self) -> None:
        self.drain_started.set()
        await self.never_drains.wait()

    def close(self) -> None:
        self.closed = True


async def lifecycle_and_socket_tests() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        socket_path = Path(temporary) / "active-network" / "status.sock"
        service = helper.ActiveNetworkHelper("iw", socket_path)
        fake_server = FakeServer()
        fake_bus = DisconnectingBus()

        async def fake_create_socket() -> FakeServer:
            socket_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            socket_path.touch()
            return fake_server

        async def fake_connect_system_bus() -> None:
            service.bus = fake_bus

        async def fake_refresh() -> None:
            return None

        service.create_socket = fake_create_socket
        service.connect_system_bus = fake_connect_system_bus
        service.refresh = fake_refresh
        try:
            await service.run()
        except helper.SystemBusDisconnected:
            pass
        else:
            raise AssertionError("a system D-Bus disconnect must fail for systemd restart")
        assert fake_server.closed and fake_server.waited
        assert fake_bus.disconnected
        assert not socket_path.exists()

        socket_service = helper.ActiveNetworkHelper("iw", socket_path)
        first_server = await socket_service.create_socket()
        assert stat.S_ISSOCK(socket_path.stat().st_mode)
        await socket_service.close_socket_server(first_server)
        assert not socket_path.exists()
        replacement_server = await socket_service.create_socket()
        assert stat.S_ISSOCK(socket_path.stat().st_mode)
        await socket_service.close_socket_server(replacement_server)
        socket_path.write_text("not a socket")
        try:
            await socket_service.create_socket()
        except RuntimeError:
            pass
        else:
            raise AssertionError("helper must refuse non-socket replacement")


async def slow_client_backpressure_test() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        service = helper.ActiveNetworkHelper("iw", Path(temporary) / "status.sock")
        slow = SlowWriter()
        service.clients.add(slow)
        original_timeout = helper.CLIENT_DRAIN_TIMEOUT_SECONDS
        helper.CLIENT_DRAIN_TIMEOUT_SECONDS = 0.01
        try:
            service.model = {"sequence": 1}
            service.broadcast()
            delivery = service.client_deliveries[slow]
            task = delivery.task
            assert task is not None
            # The task has not run yet: the second state replaces, rather than
            # queues behind, the first state for this stalled client.
            service.model = {"sequence": 2}
            service.broadcast()
            assert delivery.latest == b'{"sequence":2}\n'
            await task
        finally:
            helper.CLIENT_DRAIN_TIMEOUT_SECONDS = original_timeout
        assert slow.drain_started.is_set()
        assert slow.writes == [b'{"sequence":2}\n']
        assert slow.closed
        assert slow not in service.clients
        assert slow not in service.client_deliveries


async def async_contract_tests() -> None:
    await lifecycle_and_socket_tests()
    await slow_client_backpressure_test()


asyncio.run(async_contract_tests())
print("active-network helper contract tests passed")
