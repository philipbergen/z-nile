import QtQuick
import qs.Commons

// Text that never interprets markup: every string here can come from a
// tracker file.
Text {
  textFormat: Text.PlainText
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  renderType: Text.NativeRendering
}
