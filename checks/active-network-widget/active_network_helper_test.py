#!/usr/bin/env python3
"""Focused contract tests for the Active Network helper, run by its Nix check."""

from __future__ import annotations

import asyncio
import importlib.util
import json
import socket
import stat
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path

helper_path = Path(sys.argv[1])
fixtures = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("active_network_helper", helper_path)
assert spec is not None and spec.loader is not None
helper = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = helper
spec.loader.exec_module(helper)

states = json.loads((fixtures / "network-states.json").read_text())

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


async def wait_until(predicate: Callable[[], bool], timeout: float = 1) -> None:
    deadline = asyncio.get_running_loop().time() + timeout
    while not predicate():
        if asyncio.get_running_loop().time() >= deadline:
            raise AssertionError("timed out waiting for socket delivery state")
        await asyncio.sleep(0.005)


async def next_ndjson_with_sequence(
    reader: asyncio.StreamReader, sequence: int
) -> dict[str, object]:
    while True:
        line = await asyncio.wait_for(reader.readline(), timeout=1)
        assert line.endswith(b"\n"), line
        event = json.loads(line)
        if event.get("sequence") == sequence:
            return event


async def fast_peer_vs_slow_peer_socket_delivery_test() -> None:
    """A non-reading Unix peer is evicted without blocking a healthy peer."""
    with tempfile.TemporaryDirectory() as temporary:
        service = helper.ActiveNetworkHelper("iw", Path(temporary) / "status.sock")
        original_timeout = helper.CLIENT_DRAIN_TIMEOUT_SECONDS
        helper.CLIENT_DRAIN_TIMEOUT_SECONDS = 0.05
        server = await service.create_socket()
        fast_writer: asyncio.StreamWriter | None = None
        slow_writer: asyncio.StreamWriter | None = None
        try:
            fast_reader, fast_writer = await asyncio.open_unix_connection(
                str(service.socket_path), limit=512 * 1024
            )
            await wait_until(lambda: len(service.clients) == 1)
            fast_server_writer = next(iter(service.clients))
            _slow_reader, slow_writer = await asyncio.open_unix_connection(
                str(service.socket_path), limit=1
            )
            await wait_until(lambda: len(service.clients) == 2)
            slow_server_writer = next(
                writer for writer in service.clients if writer is not fast_server_writer
            )
            slow_socket = slow_server_writer.get_extra_info("socket")
            assert slow_socket is not None
            slow_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)

            # The slow Unix peer has a deliberately small send buffer and
            # never reads. Its timed drain must evict it, while the fast peer
            # reads concurrently and receives complete latest-state NDJSON.
            service.model = {"sequence": 1, "padding": "x" * (128 * 1024)}
            service.broadcast()
            first = await next_ndjson_with_sequence(fast_reader, 1)
            assert first == service.model
            await wait_until(lambda: slow_server_writer not in service.clients)
            assert slow_server_writer not in service.client_deliveries

            service.model = {"sequence": 2}
            service.broadcast()
            second = await next_ndjson_with_sequence(fast_reader, 2)
            assert second == {"sequence": 2}
            assert len(service.clients) == 1
        finally:
            helper.CLIENT_DRAIN_TIMEOUT_SECONDS = original_timeout
            service.close_clients()
            if fast_writer is not None:
                fast_writer.close()
                await fast_writer.wait_closed()
            if slow_writer is not None:
                slow_writer.close()
                await slow_writer.wait_closed()
            await service.close_socket_server(server)


async def async_contract_tests() -> None:
    await lifecycle_and_socket_tests()
    await slow_client_backpressure_test()
    await fast_peer_vs_slow_peer_socket_delivery_test()


asyncio.run(async_contract_tests())
print("active-network helper contract tests passed")
