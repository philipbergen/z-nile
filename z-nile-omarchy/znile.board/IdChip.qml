import QtQuick
import qs.Commons

// A chip whose ticket and raft ids are links: "🔒 blocked by c0117 c0118".
// Clicking an id emits open(id); the rest of the chip is inert.
Rectangle {
  id: chip

  property string glyph: ""
  property string prefix: ""
  property var ids: []
  property color tint: "white"
  property real fontSize: Style.font.caption

  signal open(string id)

  height: row.implicitHeight + Style.space(6)
  width: Math.min(row.implicitWidth + Style.space(14), parent ? parent.width : row.implicitWidth + Style.space(14))
  radius: height / 2
  color: Util.alpha(tint, 0.12)
  clip: true

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)

    PlainLabel {
      visible: text !== ""
      text: chip.glyph + (chip.glyph !== "" && chip.prefix !== "" ? " " : "") + chip.prefix
      color: chip.tint
      font.pixelSize: chip.fontSize
    }
    Repeater {
      model: chip.ids
      PlainLabel {
        required property string modelData
        text: modelData
        color: chip.tint
        font.pixelSize: chip.fontSize
        font.bold: link.containsMouse
        font.underline: link.containsMouse
        MouseArea {
          id: link
          anchors.fill: parent
          anchors.margins: -3
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: chip.open(parent.modelData)
        }
      }
    }
  }
}
