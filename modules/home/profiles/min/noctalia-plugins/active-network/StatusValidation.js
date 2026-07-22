function expectedSignal(rssiValue) {
  if (rssiValue === null)
    return { quality: "unavailable", qualityColor: "#6b7280", bars: 0 };
  if (rssiValue >= -55)
    return { quality: "good", qualityColor: "#22c55e", bars: 4 };
  if (rssiValue >= -67)
    return { quality: "fair", qualityColor: "#eab308", bars: 3 };
  if (rssiValue >= -75)
    return { quality: "weak", qualityColor: "#f97316", bars: 2 };
  return { quality: "bad", qualityColor: "#ef4444", bars: 1 };
}

function isOneOf(value, allowed) {
  return allowed.indexOf(value) !== -1;
}

function validateStatusEvent(event) {
  if (event === null || typeof event !== "object" || Array.isArray(event))
    return null;
  if (!isOneOf(event.state, ["unknown", "connecting", "limited", "portal", "failed", "disconnected", "connected"])
      || !isOneOf(event.connectivity, ["unknown", "none", "portal", "limited", "full"])
      || !isOneOf(event.kind, ["unknown", "ethernet", "wifi"])
      || typeof event.interface !== "string" || event.interface.length > 15
      || typeof event.vpn !== "boolean" || typeof event.wifiActive !== "boolean")
    return null;

  const rssiValue = event.rssi;
  if (!(rssiValue === null || (typeof rssiValue === "number" && Number.isFinite(rssiValue)
        && Number.isInteger(rssiValue) && rssiValue >= -200 && rssiValue <= 0)))
    return null;
  if (typeof event.bars !== "number" || !Number.isInteger(event.bars)
      || event.bars < 0 || event.bars > 4)
    return null;

  const expected = expectedSignal(rssiValue);
  if (event.quality !== expected.quality || event.qualityColor !== expected.qualityColor
      || event.bars !== expected.bars)
    return null;
  if (event.kind !== "wifi" && event.wifiActive)
    return null;
  if ((event.kind !== "wifi" || !event.wifiActive) && rssiValue !== null)
    return null;

  return {
    state: event.state,
    connectivity: event.connectivity,
    kind: event.kind,
    interface: event.interface,
    vpn: event.vpn,
    rssi: rssiValue,
    quality: event.quality,
    qualityColor: event.qualityColor,
    bars: event.bars
  };
}
