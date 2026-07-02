import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property var pluginApi

  property string listenerState: "idle"
  property real microphoneLevel: 0.0
  property bool hasSeenEvent: false
  property int activityTick: 0

  readonly property string runtimeDirectory: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string socketPath: runtimeDirectory.length > 0 ? runtimeDirectory + "/listener/status.sock" : ""
  readonly property bool recording: listenerState === "recording"
  readonly property bool transcribing: listenerState === "transcribing"
  readonly property bool active: recording || transcribing
  readonly property color barColor: {
    if (listenerState === "copied")
      return "#22c55e";
    if (listenerState === "transcribing")
      return "#facc15";
    if (listenerState === "recording" || listenerState === "error")
      return "#ef4444";
    return Qt.alpha(Color.mOnSurfaceVariant, statusSocket.connected ? 0.38 : 0.18);
  }

  implicitWidth: 34
  implicitHeight: 22

  function consumeStatusMessage(message) {
    try {
      const event = JSON.parse(String(message));
      const nextState = String(event.state || "idle");

      if (hasSeenEvent && listenerState !== nextState) {
        if (nextState === "copied")
          notify("Listener", "Transcription copied to clipboard");
        else if (nextState === "error")
          notify("Listener", "Transcription failed");
      }

      listenerState = nextState;
      microphoneLevel = Math.max(0.0, Math.min(1.0, Number(event.level || 0.0)));
      hasSeenEvent = true;
    } catch (error) {
      // Ignore malformed partial lines; the next newline-delimited event will
      // restore state.
    }
  }

  function notify(summary, body) {
    notificationProcess.command = [
      "notify-send",
      "--app-name=Listener",
      "--expire-time=2500",
      summary,
      body
    ];
    notificationProcess.running = true;
  }

  function scheduleReconnect() {
    listenerState = "idle";
    microphoneLevel = 0.0;
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

  Process {
    id: notificationProcess

    running: false
  }

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

  Timer {
    interval: 110
    repeat: true
    running: root.transcribing
    onTriggered: root.activityTick = root.activityTick + 1
  }

  Row {
    anchors.centerIn: parent
    spacing: 2

    Repeater {
      model: [0.48, 0.76, 1.0, 0.76, 0.48]

      Rectangle {
        width: 3
        radius: 1.5
        anchors.verticalCenter: parent.verticalCenter
        height: {
          if (root.recording)
            return Math.round(4 + root.microphoneLevel * 16 * modelData);
          if (root.transcribing)
            return Math.round(7 + (Math.sin(root.activityTick * 0.9 + index) + 1.0) * 4 * modelData);
          if (root.listenerState === "copied" || root.listenerState === "error")
            return 12;
          return 4;
        }
        color: root.barColor
        opacity: root.active || root.listenerState === "copied" || root.listenerState === "error" || statusSocket.connected ? 1.0 : 0.5

        Behavior on height {
          NumberAnimation {
            duration: 80
            easing.type: Easing.OutCubic
          }
        }
        Behavior on color {
          ColorAnimation {
            duration: 120
          }
        }
      }
    }
  }
}
