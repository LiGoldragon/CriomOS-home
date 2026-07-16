import QtQuick
import QtQuick.Controls
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

  // Noctalia owns this shared one-hertz tick. This widget adds no display timer.
  readonly property var sharedNow: Time.now
  property int solarOffsetSeconds: 0
  property bool solarAvailable: false

  implicitWidth: solarLabel.implicitWidth + 12
  implicitHeight: 22

  function refreshSolarClock(status) {
    const match = /\(SolarClock\s+(-?\d+)\s+(\d+)\)/.exec(String(status));
    if (match) {
      solarOffsetSeconds = Number(match[1]);
      solarAvailable = true;
      return;
    }
    solarAvailable = false;
  }

  Process {
    id: solarStatusProcess

    command: [ "chroma", "GetSolarClock" ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.refreshSolarClock(this.text)
    }
    onExited: exitCode => {
      if (exitCode !== 0)
        root.solarAvailable = false;
    }
  }

  // A coarse local UDS status read keeps GeoClue freshness explicit; it never
  // performs a network request. Chroma refreshes its one GeoClue path at most
  // every four minutes, while Time.now drives the displayed seconds/minutes.
  Timer {
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      if (!solarStatusProcess.running)
        solarStatusProcess.running = true;
    }
  }

  Text {
    id: solarLabel

    anchors.centerIn: parent
    color: root.solarAvailable ? Color.mOnSurface : Color.mOnSurfaceVariant
    text: root.solarAvailable
      ? "☼ " + Qt.formatTime(new Date(root.sharedNow.getTime() + root.solarOffsetSeconds * 1000), "HH:mm:ss")
      : "☼ --:--:--"

    ToolTip.visible: solarHover.containsMouse
    ToolTip.text: root.solarAvailable
      ? "Solar time: local apparent solar time (UTC corrected by longitude and equation of time). Civil time is the Clock beside it."
      : "Solar time unavailable: waiting for a fresh authoritative GeoClue fix. Civil time is the Clock beside it."

    HoverHandler { id: solarHover }
  }
}
