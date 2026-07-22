import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root

  property var screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property var pluginApi

  property string networkState: "unknown"
  property string connectivity: "unknown"
  property string connectionKind: "unknown"
  property string interfaceName: ""
  property bool vpnActive: false
  property var rssi: null
  property string quality: "unavailable"
  property color qualityColor: "#6b7280"
  property int signalBars: 0

  readonly property string runtimeDirectory: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string socketPath: runtimeDirectory.length > 0 ? runtimeDirectory + "/active-network/status.sock" : ""
  readonly property bool wifi: connectionKind === "wifi"
  readonly property string stateText: {
    if (networkState === "connecting") return "Connecting";
    if (networkState === "limited") return "Limited";
    if (networkState === "portal") return "Portal";
    if (networkState === "failed") return "Auth failed";
    if (networkState === "disconnected") return "Offline";
    if (networkState === "connected") return "Online";
    return "Network unknown";
  }
  readonly property color stateColor: {
    if (networkState === "failed" || networkState === "disconnected") return "#ef4444";
    if (networkState === "limited" || networkState === "portal" || networkState === "connecting") return "#f59e0b";
    return Color.mOnSurface;
  }
  readonly property string tooltipText: {
    const transport = connectionKind === "wifi" ? "Wi-Fi" : connectionKind === "ethernet" ? "Ethernet" : "Network";
    const link = wifi ? (rssi === null ? "RSSI unavailable" : String(rssi) + " dBm (" + quality + ")") : "";
    const tunnel = vpnActive ? " · VPN active" : "";
    const detail = interfaceName.length > 0 ? " on " + interfaceName : "";
    return transport + detail + ": " + stateText + " (connectivity: " + connectivity + ")" + (link.length > 0 ? " · " + link : "") + tunnel;
  }

  implicitWidth: content.implicitWidth + 12
  implicitHeight: 22

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

  function consumeStatusMessage(message) {
    try {
      const status = validateStatusEvent(JSON.parse(String(message)));
      if (status === null)
        return;
      networkState = status.state;
      connectivity = status.connectivity;
      connectionKind = status.kind;
      interfaceName = status.interface;
      vpnActive = status.vpn;
      rssi = status.rssi;
      quality = status.quality;
      qualityColor = status.qualityColor;
      signalBars = status.bars;
    } catch (_error) {
      // Ignore malformed partial lines; a subsequent JSON line restores state.
    }
  }

  function scheduleReconnect() {
    statusSocket.connected = false;
    reconnectTimer.restart();
  }

  Socket {
    id: statusSocket

    path: root.socketPath
    connected: root.socketPath.length > 0
    parser: SplitParser {
      onRead: message => root.consumeStatusMessage(message)
    }
    onConnectedChanged: {
      if (!connected)
        reconnectTimer.restart();
    }
    onError: _error => root.scheduleReconnect()
  }

  // The helper is signal-driven. This timer merely reconnects the local socket
  // after a shell or user-service restart; it never queries network state.
  Timer {
    id: reconnectTimer

    interval: 1000
    repeat: false
    running: false
    onTriggered: {
      if (root.socketPath.length > 0)
        statusSocket.connected = true;
    }
  }

  Row {
    id: content

    anchors.centerIn: parent
    spacing: 4

    Text {
      color: root.stateColor
      font.family: "IosevkaTerm Nerd Font"
      text: root.wifi ? "\uf1eb" : root.connectionKind === "ethernet" ? "⇄" : "?"
    }

    Text {
      color: root.stateColor
      text: root.wifi ? (root.rssi === null ? "-- dBm" : String(root.rssi) + " dBm") : root.stateText
    }

    Row {
      visible: root.wifi
      spacing: 1

      Repeater {
        model: 4

        Rectangle {
          width: 3
          height: 5 + index * 3
          anchors.bottom: parent.bottom
          radius: 1
          color: root.qualityColor
          opacity: index < root.signalBars ? 1.0 : 0.22
        }
      }
    }

    Rectangle {
      visible: root.vpnActive
      width: vpnLabel.implicitWidth + 6
      height: 13
      radius: 3
      color: "#64748b"

      Text {
        id: vpnLabel

        anchors.centerIn: parent
        color: "#ffffff"
        font.pixelSize: 9
        text: "VPN"
      }
    }
  }

  HoverHandler {
    onHoveredChanged: {
      if (hovered)
        TooltipService.show(root, root.tooltipText);
      else
        TooltipService.hide();
    }
  }
}
