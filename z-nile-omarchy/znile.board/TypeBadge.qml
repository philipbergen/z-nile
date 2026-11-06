import QtQuick
import qs.Commons

// The type letter (F, D, C, R) in a tinted circle, as on the cards.
Rectangle {
  id: badge

  property string letter: ""
  property color tint: "white"
  property real size: Style.space(18)
  property real fontSize: Style.font.caption

  width: size
  height: size
  radius: size / 2
  color: Util.alpha(tint, 0.18)

  PlainLabel {
    anchors.centerIn: parent
    text: badge.letter
    color: badge.tint
    font.bold: true
    font.pixelSize: badge.fontSize
  }
}
