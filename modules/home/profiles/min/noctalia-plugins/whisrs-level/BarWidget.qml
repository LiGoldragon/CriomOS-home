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

  property string whisrsState: "idle"
  property real microphoneLevel: 0.0

  readonly property string runtimeDirectory: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string socketPath: runtimeDirectory.length > 0 ? runtimeDirectory + "/whisrs/level.sock" : ""
  readonly property bool active: whisrsState === "recording" || whisrsState === "transcribing"
  readonly property color barColor: {
    if (whisrsState === "transcribing")
      return Color.mSecondary;
    if (whisrsState === "recording")
      return Color.mPrimary;
    return Qt.alpha(Color.mOnSurfaceVariant, levelSocket.connected ? 0.38 : 0.18);
  }

  implicitWidth: 34
  implicitHeight: 22

  function consumeLevelMessage(message) {
    try {
      const event = JSON.parse(String(message));
      whisrsState = String(event.state || "idle");
      microphoneLevel = Math.max(0.0, Math.min(1.0, Number(event.level || 0.0)));
    } catch (error) {
      // Ignore malformed partial lines; the next newline-delimited event will
      // restore state.
    }
  }

  function scheduleReconnect() {
    whisrsState = "idle";
    microphoneLevel = 0.0;
    levelSocket.connected = false;
    reconnectTimer.restart();
  }

  Socket {
    id: levelSocket

    path: root.socketPath
    connected: root.socketPath.length > 0
    parser: SplitParser {
      onRead: message => root.consumeLevelMessage(message)
    }
    onConnectedChanged: {
      if (!connected)
        reconnectTimer.restart();
    }
    onError: _error => root.scheduleReconnect()
  }

  Timer {
    id: reconnectTimer

    interval: 1000
    repeat: false
    running: false
    onTriggered: {
      if (root.socketPath.length > 0)
        levelSocket.connected = true;
    }
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
        height: Math.round(4 + (root.active ? root.microphoneLevel : 0.0) * 16 * modelData)
        color: root.barColor
        opacity: root.active || levelSocket.connected ? 1.0 : 0.5

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
