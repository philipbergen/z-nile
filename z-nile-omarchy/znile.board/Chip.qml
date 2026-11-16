import QtQuick
import qs.Commons

// A small rounded tag: a glyph and a short label in one tint.
Rectangle {
  id: chip

  property string glyph: ""
  property string label: ""
  property color tint: "white"
  property bool active: false
  property real fontSize: Style.font.caption

  signal clicked()

  height: text.implicitHeight + Style.space(6)
  width: text.implicitWidth + Style.space(14)
  radius: height / 2
  color: Util.alpha(tint, active ? 0.32 : (area.containsMouse && area.enabled ? 0.2 : 0.12))
  border.width: active ? 1 : 0
  border.color: Util.alpha(tint, 0.7)

  Behavior on color { ColorAnimation { duration: Style.duration(120) } }

  PlainLabel {
    id: text
    anchors.centerIn: parent
    text: chip.glyph !== "" ? chip.glyph + " " + chip.label : chip.label
    font.pixelSize: chip.fontSize
    color: chip.tint
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: false
    onClicked: chip.clicked()
  }

  // Interactive chips opt in.
  property alias interactive: area.enabled
}
