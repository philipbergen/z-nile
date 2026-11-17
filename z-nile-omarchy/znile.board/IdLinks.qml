import QtQuick
import qs.Commons

// Text whose ticket and raft ids are links, for the details rows. Words
// wrap like text; an id the board knows is accent-coloured and clickable.
Flow {
  id: links

  property string text: ""
  property var known: ({})          // id -> item (the model's byId)
  property color color: "white"
  property color linkColor: "white"
  property real fontSize: Style.font.bodySmall
  property bool italic: false

  // When set, the whole text is one link to this page instead.
  property string url: ""

  signal open(string id)
  signal openUrl(string url)

  readonly property var words: String(text).split(/\s+/).filter(function(w) { return w !== "" })

  spacing: 0

  PlainLabel {
    visible: links.url !== ""
    width: links.width
    text: links.text
    wrapMode: Text.Wrap
    color: links.linkColor
    font.pixelSize: links.fontSize
    font.underline: whole.containsMouse
    MouseArea {
      id: whole
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: links.openUrl(links.url)
    }
  }

  Repeater {
    model: links.url === "" ? links.words : []
    PlainLabel {
      required property string modelData
      // An id may carry punctuation: "c0136;" or "(c0136)".
      readonly property var parts: /^([^A-Za-z0-9]*)([fdcR][0-9]{4})(.*)$/.exec(modelData)
      readonly property string id: parts && links.known[parts[2]] ? parts[2] : ""
      text: modelData + " "
      color: id !== "" ? links.linkColor : links.color
      font.pixelSize: links.fontSize
      font.italic: links.italic
      font.underline: id !== "" && link.containsMouse
      MouseArea {
        id: link
        anchors.fill: parent
        enabled: parent.id !== ""
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: links.open(parent.id)
      }
    }
  }
}
