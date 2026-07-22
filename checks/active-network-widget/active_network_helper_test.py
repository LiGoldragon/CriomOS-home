#!/usr/bin/env python3
"""Focused contract tests for the Active Network helper, run by its Nix check."""

from __future__ import annotations

import importlib.util
import json
import sys
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

print("active-network helper contract tests passed")
