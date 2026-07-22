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

  function consumeStatusMessage(message) {
    try {
      const event = JSON.parse(String(message));
      networkState = String(event.state || "unknown");
      connectivity = String(event.connectivity || "unknown");
      connectionKind = String(event.kind || "unknown");
      interfaceName = String(event.interface || "");
      vpnActive = Boolean(event.vpn);
      rssi = event.rssi === null || event.rssi === undefined ? null : Number(event.rssi);
      quality = String(event.quality || "unavailable");
      qualityColor = String(event.qualityColor || "#6b7280");
      signalBars = Math.max(0, Math.min(4, Number(event.bars || 0)));
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
