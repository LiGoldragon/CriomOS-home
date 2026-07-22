#!/usr/bin/env python3
"""Push NetworkManager state to the Active Network Noctalia widget.

NetworkManager D-Bus signals are the source of connection, device, and
connectivity updates.  The only timed work is an active-Wi-Fi current-link
``iw dev IFACE link`` query, used because NetworkManager exposes strength as a
percentage rather than truthful dBm.  It does not request or perform a scan.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import re
import stat
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

from dbus_next import BusType
from dbus_next.aio import MessageBus

NM_SERVICE = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
NM_INTERFACE = "org.freedesktop.NetworkManager"
ACTIVE_INTERFACE = "org.freedesktop.NetworkManager.Connection.Active"
DEVICE_INTERFACE = "org.freedesktop.NetworkManager.Device"
PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"
DBUS_INTERFACE = "org.freedesktop.DBus"

ETHERNET = 1
WIFI = 2
TUNNEL_TYPES = {16, 17, 29}
ACTIVE = 2
DEVICE_ACTIVATED = 100
DEVICE_NEED_AUTH = 60
DEVICE_FAILED = 120
CONNECTING_DEVICE_STATES = {40, 50, 70, 80, 90}

RSSI_REFRESH_SECONDS = 5
RSSI_STALE_SECONDS = 30
IW_TIMEOUT_SECONDS = 2
CLIENT_DRAIN_TIMEOUT_SECONDS = 1

RSSI_PATTERN = re.compile(r"^\s*signal:\s*(-?\d+)\s+dBm\s*$", re.MULTILINE)


class SystemBusDisconnected(RuntimeError):
    """Tell systemd to restart after the system bus disappears."""


def parse_iw_link(output: str) -> int | None:
    """Return current-link RSSI from `iw dev IFACE link`, never a percentage."""
    match = RSSI_PATTERN.search(output)
    return int(match.group(1)) if match else None


def signal_quality(rssi: int | None) -> dict[str, Any]:
    """Map actual RSSI to the documented Active Network presentation bands."""
    if rssi is None:
        return {"quality": "unavailable", "qualityColor": "#6b7280", "bars": 0}
    # Good >= -55 dBm (green); Fair -56..-67 dBm (yellow);
    # Weak -68..-75 dBm (orange); Bad <= -76 dBm (red).
    if rssi >= -55:
        return {"quality": "good", "qualityColor": "#22c55e", "bars": 4}
    if rssi >= -67:
        return {"quality": "fair", "qualityColor": "#eab308", "bars": 3}
    if rssi >= -75:
        return {"quality": "weak", "qualityColor": "#f97316", "bars": 2}
    return {"quality": "bad", "qualityColor": "#ef4444", "bars": 1}


def connectivity_name(value: int) -> str:
    return {
        0: "unknown",
        1: "none",
        2: "portal",
        3: "limited",
        4: "full",
    }.get(value, "unknown")


def _active_by_path(active_connections: Sequence[Mapping[str, Any]]) -> dict[str, Mapping[str, Any]]:
    return {str(connection.get("path", "/")): connection for connection in active_connections}


def _device_by_path(devices: Sequence[Mapping[str, Any]]) -> dict[str, Mapping[str, Any]]:
    return {str(device.get("path", "/")): device for device in devices}


def _is_tunnel(connection: Mapping[str, Any], devices: Mapping[str, Mapping[str, Any]]) -> bool:
    connection_type = str(connection.get("type", "")).lower()
    if bool(connection.get("vpn", False)) or connection_type in {"vpn", "wireguard", "tun"}:
        return True
    return any(int(devices.get(str(path), {}).get("type", 0)) in TUNNEL_TYPES for path in connection.get("devices", []))


def project_network_state(
    manager: Mapping[str, Any],
    active_connections: Sequence[Mapping[str, Any]],
    devices: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Project NetworkManager objects into the widget's deliberately small model.

    Only the device attached to PrimaryConnection is eligible for the main
    Ethernet/Wi-Fi representation. ActivatingConnection is used only while
    there is no primary connection. This avoids choosing whichever active
    Ethernet or Wi-Fi device happens to be listed first.
    """
    active_by_path = _active_by_path(active_connections)
    devices_by_path = _device_by_path(devices)
    primary_path = str(manager.get("primaryConnection", "/"))
    activating_path = str(manager.get("activatingConnection", "/"))
    selected = active_by_path.get(primary_path)
    if selected is None and primary_path == "/":
        selected = active_by_path.get(activating_path)

    physical: Mapping[str, Any] | None = None
    if selected is not None:
        for device_path in selected.get("devices", []):
            device = devices_by_path.get(str(device_path))
            if device is not None and int(device.get("type", 0)) in {ETHERNET, WIFI}:
                physical = device
                break

    manager_state = int(manager.get("state", 0))
    connectivity = int(manager.get("connectivity", 0))
    selected_state = int(selected.get("state", 0)) if selected is not None else 0
    device_state = int(physical.get("state", 0)) if physical is not None else 0

    if device_state in {DEVICE_NEED_AUTH, DEVICE_FAILED}:
        status = "failed"
    elif manager_state == 40 or selected_state == 1 or device_state in CONNECTING_DEVICE_STATES:
        status = "connecting"
    elif manager_state in {10, 20, 30} or (selected is None and manager_state != 0):
        status = "disconnected"
    elif manager_state == 0:
        status = "unknown"
    elif connectivity == 2:
        status = "portal"
    elif manager_state in {50, 60} or connectivity in {1, 3}:
        status = "limited"
    else:
        status = "connected"

    device_type = int(physical.get("type", 0)) if physical is not None else 0
    kind = "wifi" if device_type == WIFI else "ethernet" if device_type == ETHERNET else "unknown"
    interface = str(physical.get("interface", "")) if physical is not None else ""
    vpn = any(_is_tunnel(connection, devices_by_path) for connection in active_connections)
    wifi_active = kind == "wifi" and selected_state == ACTIVE and device_state == DEVICE_ACTIVATED

    return {
        "state": status,
        "connectivity": connectivity_name(connectivity),
        "kind": kind,
        "interface": interface,
        "vpn": vpn,
        "wifiActive": wifi_active,
        "primaryConnection": primary_path,
    }


@dataclass
class ClientDelivery:
    """At most one not-yet-written model is retained per socket client."""

    latest: bytes | None = None
    task: asyncio.Task[None] | None = None


@dataclass
class RssiCache:
    interface: str = ""
    value: int | None = None
    successful_at: float | None = None
    attempted_at: float | None = None

    def reset(self, interface: str) -> None:
        self.interface = interface
        self.value = None
        self.successful_at = None
        self.attempted_at = None

    def refresh_due(self, wifi_active: bool, now: float) -> bool:
        return wifi_active and (self.attempted_at is None or now - self.attempted_at >= RSSI_REFRESH_SECONDS)

    def mark_attempt(self, now: float) -> None:
        self.attempted_at = now

    def record(self, value: int | None, now: float) -> None:
        if value is not None:
            self.value = value
            self.successful_at = now

    def visible_value(self, now: float) -> int | None:
        if self.value is None or self.successful_at is None:
            return None
        if now - self.successful_at > RSSI_STALE_SECONDS:
            return None
        return self.value


class ActiveNetworkHelper:
    def __init__(self, iw_path: str, socket_path: Path) -> None:
        self.iw_path = iw_path
        self.socket_path = socket_path
        self.bus: MessageBus | None = None
        self.proxies: dict[str, Any] = {}
        self.watched: set[tuple[str, str]] = set()
        self.clients: set[asyncio.StreamWriter] = set()
        self.client_deliveries: dict[asyncio.StreamWriter, ClientDelivery] = {}
        self.refresh_task: asyncio.Task[None] | None = None
        self.rssi_task: asyncio.Task[None] | None = None
        self.rssi_cache = RssiCache()
        self.wifi_interface = ""
        self.model: dict[str, Any] = self.unavailable_model()

    @staticmethod
    def unavailable_model() -> dict[str, Any]:
        return {
            "state": "unknown",
            "connectivity": "unknown",
            "kind": "unknown",
            "interface": "",
            "vpn": False,
            "wifiActive": False,
            "rssi": None,
            **signal_quality(None),
        }

    async def proxy(self, path: str) -> Any:
        if path not in self.proxies:
            assert self.bus is not None
            introspection = await self.bus.introspect(NM_SERVICE, path)
            self.proxies[path] = self.bus.get_proxy_object(NM_SERVICE, path, introspection)
        return self.proxies[path]

    async def get_properties(self, path: str, interface: str) -> dict[str, Any]:
        proxy = await self.proxy(path)
        properties = proxy.get_interface(PROPERTIES_INTERFACE)
        values = await properties.call_get_all(interface)
        return {name: value.value for name, value in values.items()}

    def request_refresh(self, *_args: Any) -> None:
        if self.refresh_task is None or self.refresh_task.done():
            self.refresh_task = asyncio.create_task(self.refresh())

    async def watch(self, path: str, interface: str, state_signal: bool = False) -> None:
        key = (path, interface)
        if key in self.watched:
            return
        proxy = await self.proxy(path)
        properties = proxy.get_interface(PROPERTIES_INTERFACE)
        properties.on_properties_changed(self.request_refresh)
        if state_signal:
            state_interface = proxy.get_interface(interface)
            handler = getattr(state_interface, "on_state_changed", None)
            if handler is not None:
                handler(self.request_refresh)
        self.watched.add(key)

    async def read_network(self) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
        manager = await self.get_properties(NM_PATH, NM_INTERFACE)
        manager_model = {
            "state": manager.get("State", 0),
            "connectivity": manager.get("Connectivity", 0),
            "primaryConnection": str(manager.get("PrimaryConnection", "/")),
            "activatingConnection": str(manager.get("ActivatingConnection", "/")),
        }
        await self.watch(NM_PATH, NM_INTERFACE, state_signal=True)

        active_connections: list[dict[str, Any]] = []
        device_paths: set[str] = set()
        for path in manager.get("ActiveConnections", []):
            path = str(path)
            properties = await self.get_properties(path, ACTIVE_INTERFACE)
            connection = {
                "path": path,
                "devices": [str(device) for device in properties.get("Devices", [])],
                "type": str(properties.get("Type", "")),
                "state": properties.get("State", 0),
                "vpn": properties.get("Vpn", False),
            }
            active_connections.append(connection)
            device_paths.update(connection["devices"])
            await self.watch(path, ACTIVE_INTERFACE, state_signal=True)

        devices: list[dict[str, Any]] = []
        for path in device_paths:
            properties = await self.get_properties(path, DEVICE_INTERFACE)
            devices.append(
                {
                    "path": path,
                    "type": properties.get("DeviceType", 0),
                    "interface": str(properties.get("Interface", "")),
                    "state": properties.get("State", 0),
                }
            )
            await self.watch(path, DEVICE_INTERFACE, state_signal=True)
        return manager_model, active_connections, devices

    def with_rssi(self, model: Mapping[str, Any]) -> dict[str, Any]:
        complete = dict(model)
        rssi = self.rssi_cache.visible_value(time.monotonic()) if complete.get("wifiActive") else None
        complete["rssi"] = rssi
        complete.update(signal_quality(rssi))
        return complete

    async def refresh(self) -> None:
        try:
            manager, active_connections, devices = await self.read_network()
            model = project_network_state(manager, active_connections, devices)
        except Exception:
            self.proxies.clear()
            self.watched.clear()
            self.model = self.unavailable_model()
            self.broadcast()
            return

        wifi_interface = str(model["interface"]) if model["wifiActive"] else ""
        if wifi_interface != self.wifi_interface:
            self.stop_rssi_refresh()
            self.wifi_interface = wifi_interface
            if wifi_interface:
                self.rssi_cache.reset(wifi_interface)
                self.rssi_task = asyncio.create_task(self.refresh_rssi(wifi_interface))
            else:
                self.rssi_cache.reset("")
        self.model = self.with_rssi(model)
        self.broadcast()

    def stop_rssi_refresh(self) -> None:
        if self.rssi_task is not None:
            self.rssi_task.cancel()
            self.rssi_task = None

    async def current_link_rssi(self, interface: str) -> int | None:
        process: asyncio.subprocess.Process | None = None
        try:
            process = await asyncio.create_subprocess_exec(
                self.iw_path,
                "dev",
                interface,
                "link",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            stdout, _ = await asyncio.wait_for(process.communicate(), timeout=IW_TIMEOUT_SECONDS)
        except (OSError, asyncio.TimeoutError):
            if process is not None:
                with contextlib.suppress(ProcessLookupError):
                    process.kill()
                with contextlib.suppress(ProcessLookupError):
                    await process.wait()
            return None
        if process.returncode != 0:
            return None
        return parse_iw_link(stdout.decode("utf-8", errors="replace"))

    async def refresh_rssi(self, interface: str) -> None:
        """One immediate snapshot, then at most one current-link query per 5 seconds."""
        try:
            while self.wifi_interface == interface:
                now = time.monotonic()
                if self.rssi_cache.refresh_due(True, now):
                    self.rssi_cache.mark_attempt(now)
                    self.rssi_cache.record(await self.current_link_rssi(interface), time.monotonic())
                    self.model = self.with_rssi(self.model)
                    self.broadcast()
                next_attempt = (self.rssi_cache.attempted_at or time.monotonic()) + RSSI_REFRESH_SECONDS
                await asyncio.sleep(max(0, next_attempt - time.monotonic()))
        except asyncio.CancelledError:
            raise

    def schedule_delivery(self, writer: asyncio.StreamWriter, line: bytes) -> None:
        delivery = self.client_deliveries.setdefault(writer, ClientDelivery())
        delivery.latest = line
        if delivery.task is None or delivery.task.done():
            delivery.task = asyncio.create_task(self.deliver_latest(writer, delivery))

    async def deliver_latest(self, writer: asyncio.StreamWriter, delivery: ClientDelivery) -> None:
        """Send one latest-state line at a time and evict slow clients.

        Keeping only ``delivery.latest`` bounds helper memory to one small
        NDJSON model per client.  ``drain`` is timed so a client that stops
        reading cannot hold a task or transport buffer indefinitely.
        """
        try:
            while delivery.latest is not None:
                line = delivery.latest
                delivery.latest = None
                if writer.is_closing():
                    return
                writer.write(line)
                await asyncio.wait_for(
                    writer.drain(), timeout=CLIENT_DRAIN_TIMEOUT_SECONDS
                )
        except (ConnectionError, RuntimeError, asyncio.TimeoutError):
            self.evict_client(writer, delivery)
        finally:
            if self.client_deliveries.get(writer) is delivery:
                delivery.task = None
                if delivery.latest is not None and writer in self.clients:
                    delivery.task = asyncio.create_task(self.deliver_latest(writer, delivery))

    def evict_client(
        self,
        writer: asyncio.StreamWriter,
        delivery: ClientDelivery | None = None,
    ) -> None:
        self.clients.discard(writer)
        existing = self.client_deliveries.pop(writer, None)
        active_delivery = delivery or existing
        task = active_delivery.task if active_delivery is not None else None
        if task is not None and task is not asyncio.current_task() and not task.done():
            task.cancel()
        with contextlib.suppress(ConnectionError, RuntimeError):
            writer.close()

    def close_clients(self) -> None:
        for writer in tuple(self.clients):
            self.evict_client(writer)

    def broadcast(self) -> None:
        line = (json.dumps(self.model, separators=(",", ":")) + "\n").encode()
        for writer in tuple(self.clients):
            self.schedule_delivery(writer, line)

    async def client_connected(self, _reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.clients.add(writer)
        self.broadcast()
        try:
            await writer.wait_closed()
        finally:
            self.evict_client(writer)

    async def create_socket(self) -> asyncio.AbstractServer:
        self.socket_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if self.socket_path.exists():
            if not stat.S_ISSOCK(self.socket_path.stat().st_mode):
                raise RuntimeError(f"refusing to replace non-socket {self.socket_path}")
            self.socket_path.unlink()
        server = await asyncio.start_unix_server(self.client_connected, path=str(self.socket_path))
        os.chmod(self.socket_path, 0o600)
        return server

    async def close_socket_server(self, server: asyncio.AbstractServer) -> None:
        server.close()
        await server.wait_closed()
        with contextlib.suppress(FileNotFoundError):
            self.socket_path.unlink()

    async def connect_system_bus(self) -> None:
        self.bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
        dbus_proxy = self.bus.get_proxy_object(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            await self.bus.introspect("org.freedesktop.DBus", "/org/freedesktop/DBus"),
        )

        def on_name_owner_changed(name: str, _old_owner: str, _new_owner: str) -> None:
            if name == NM_SERVICE:
                self.proxies.clear()
                self.watched.clear()
                self.request_refresh()

        dbus_proxy.get_interface(DBUS_INTERFACE).on_name_owner_changed(on_name_owner_changed)

    async def run(self) -> None:
        server = await self.create_socket()
        try:
            await self.connect_system_bus()
            await self.refresh()
            assert self.bus is not None
            await self.bus.wait_for_disconnect()
            # Returning successfully would bypass Restart=on-failure and leave
            # the widget reconnecting to a socket that no longer has a helper.
            raise SystemBusDisconnected("system D-Bus disconnected")
        finally:
            self.stop_rssi_refresh()
            self.close_clients()
            if self.bus is not None:
                self.bus.disconnect()
            await self.close_socket_server(server)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iw", default="iw", help="path to the packaged iw executable")
    parser.add_argument(
        "--socket",
        default=os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), "active-network", "status.sock"),
        help="runtime socket path",
    )
    args = parser.parse_args()
    if not args.socket or not os.path.isabs(args.socket):
        raise SystemExit("active-network-helper needs an absolute XDG_RUNTIME_DIR socket path")
    asyncio.run(ActiveNetworkHelper(args.iw, Path(args.socket)).run())


if __name__ == "__main__":
    main()
