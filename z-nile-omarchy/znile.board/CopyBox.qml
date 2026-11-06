import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// A command in a dark box with a copy icon. Clicking anywhere on it puts the
// command on the clipboard, ready to paste into a CLI.
Rectangle {
  id: box

  property string command: ""
  property color background: Qt.darker(Commons.Color.background, 1.3)
  property color tint: Commons.Color.foreground

  signal copied(string command)

  property bool justCopied: false

  implicitWidth: row.implicitWidth + Style.space(20)
  implicitHeight: row.implicitHeight + Style.space(10)
  radius: Math.max(5, Style.cornerRadius)
  color: area.pressed ? Qt.lighter(background, 1.6) : (area.containsMouse ? Qt.lighter(background, 1.3) : background)
  border.width: 1
  border.color: Util.alpha(justCopied ? Commons.Color.accent : tint, justCopied ? 0.8 : (area.containsMouse ? 0.25 : 0.1))

  Behavior on color { ColorAnimation { duration: Style.duration(100) } }
  Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    spacing: Style.space(12)

    PlainLabel {
      text: box.command
      color: box.tint
      font.family: "monospace"
      font.pixelSize: Style.font.bodySmall
      anchors.verticalCenter: parent.verticalCenter
    }
    PlainLabel {
      // copy, then a check for a moment once copied
      text: box.justCopied ? "" : ""
      color: box.justCopied ? Commons.Color.accent : Util.alpha(box.tint, area.containsMouse ? 0.9 : 0.5)
      font.pixelSize: Style.font.bodySmall
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Timer { id: reset; interval: 1400; onTriggered: box.justCopied = false }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (box.command === "") return
      // One argv element after --: nothing is parsed by a shell.
      Quickshell.execDetached(["wl-copy", "--", box.command])
      box.justCopied = true
      reset.restart()
      box.copied(box.command)
    }
  }
}
