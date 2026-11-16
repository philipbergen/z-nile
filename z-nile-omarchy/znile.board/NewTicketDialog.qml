import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// "New ticket": pick the project and the AI, optionally say what it's about,
// and one big button opens that AI in a new terminal to capture it.
// Covers the board with a scrim; Esc or a click outside closes it.
Item {
  id: dlg

  property var board: null          // Board.qml root: colours, service, model
  property bool shown: false
  property string project: ""
  property string agent: ""

  readonly property var service: board ? board.service : null
  readonly property var projects: board ? board.model.projects : []
  readonly property var agents: service ? service.agents : []
  readonly property var chosenAgent: {
    for (var i = 0; i < agents.length; i++) if (agents[i].id === agent) return agents[i]
    return agents.length > 0 ? agents[0] : null
  }

  function open() {
    if (projects.indexOf(project) < 0) {
      // Start on the project the board is filtered to, if just one.
      var f = board ? board.projectFilter : []
      project = f.length === 1 ? f[0] : (projects.length > 0 ? projects[0] : "")
    }
    agent = service ? service.agent : ""
    about.text = ""
    shown = true
    Qt.callLater(function() { about.forceActiveFocus() })
  }
  function close() {
    shown = false
    if (board) board.focusBoard()
  }
  function go() {
    if (!service || project === "" || !chosenAgent) return
    service.chooseAgent(chosenAgent.id)
    service.newTicket(project, chosenAgent.id, about.text)
    close()
  }

  visible: opacity > 0
  opacity: shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

  // Scrim: dims the board; a click on it closes.
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Commons.Color.background, 0.72)
    MouseArea { anchors.fill: parent; onClicked: dlg.close(); onWheel: function(w) { w.accepted = true } }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(560), parent.width - Style.space(40))
    height: body.implicitHeight + Style.space(40)
    radius: Math.max(10, Style.cornerRadius)
    color: dlg.board ? dlg.board.surface : Commons.Color.background
    border.width: 1
    border.color: Util.alpha(Commons.Color.accent, 0.6)
    scale: dlg.shown ? 1 : 0.97
    Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

    MouseArea { anchors.fill: parent }   // clicks inside don't reach the scrim

    Keys.onEscapePressed: dlg.close()

    ColumnLayout {
      id: body
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(20) }
      spacing: Style.space(14)

      RowLayout {
        Layout.fillWidth: true
        PlainLabel {
          text: "New ticket"
          color: Commons.Color.foreground
          font.bold: true
          font.pixelSize: Style.font.heading
        }
        Item { Layout.fillWidth: true }
        PlainLabel {
          text: ""
          color: Util.alpha(Commons.Color.foreground, 0.6)
          font.pixelSize: Style.font.title
          MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: dlg.close() }
        }
      }

      PlainLabel { text: "Project"; color: Util.alpha(Commons.Color.foreground, 0.55); font.pixelSize: Style.font.bodySmall }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Repeater {
          model: dlg.projects
          Chip {
            required property string modelData
            label: modelData
            tint: dlg.project === modelData ? Commons.Color.accent : Commons.Color.foreground
            active: dlg.project === modelData
            interactive: true
            fontSize: Style.font.body
            onClicked: dlg.project = modelData
          }
        }
      }

      PlainLabel { text: "AI"; color: Util.alpha(Commons.Color.foreground, 0.55); font.pixelSize: Style.font.bodySmall }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Repeater {
          model: dlg.agents
          Chip {
            required property var modelData
            glyph: ""
            label: modelData.name
            tint: dlg.chosenAgent && dlg.chosenAgent.id === modelData.id ? Commons.Color.accent : Commons.Color.foreground
            active: !!dlg.chosenAgent && dlg.chosenAgent.id === modelData.id
            interactive: true
            fontSize: Style.font.body
            onClicked: dlg.agent = modelData.id
          }
        }
      }

      PlainLabel { text: "What's it about? (optional: otherwise the AI asks)"; color: Util.alpha(Commons.Color.foreground, 0.55); font.pixelSize: Style.font.bodySmall }
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(96)
        radius: Math.max(6, Style.cornerRadius)
        color: dlg.board ? dlg.board.hue("darker_background", Qt.darker(Commons.Color.background, 1.35)) : Commons.Color.background
        border.width: 1
        border.color: about.activeFocus ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.1)
        Flickable {
          id: aboutFlick
          anchors.fill: parent
          anchors.margins: Style.space(10)
          clip: true
          contentHeight: about.contentHeight
          TextEdit {
            id: about
            width: aboutFlick.width
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            color: Commons.Color.foreground
            selectionColor: Util.alpha(Commons.Color.accent, 0.4)
            font.family: "sans-serif"
            font.pixelSize: Style.font.body
            // Ctrl+Enter opens; plain Enter makes a new line.
            Keys.onPressed: function(event) {
              if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                dlg.go(); event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                dlg.close(); event.accepted = true
              }
            }
          }
        }
      }

      // The big button.
      Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(4)
        implicitHeight: goLabel.implicitHeight + Style.space(26)
        radius: Math.max(8, Style.cornerRadius)
        readonly property bool ready: dlg.project !== "" && dlg.chosenAgent !== null
        opacity: ready ? 1 : 0.4
        color: goArea.containsMouse && ready ? Qt.lighter(Commons.Color.accent, 1.1) : Commons.Color.accent
        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
        PlainLabel {
          id: goLabel
          anchors.centerIn: parent
          text: dlg.chosenAgent
            ? "  Open " + dlg.chosenAgent.name + " in a terminal" + (dlg.project ? "  ·  " + dlg.project : "")
            : "No AI CLI installed"
          color: Commons.Color.background
          font.bold: true
          font.pixelSize: Style.font.title
        }
        MouseArea {
          id: goArea
          anchors.fill: parent
          hoverEnabled: true
          enabled: parent.ready
          cursorShape: Qt.PointingHandCursor
          onClicked: dlg.go()
        }
      }

      PlainLabel {
        Layout.fillWidth: true
        text: "Ctrl+Enter opens it · Esc closes"
        horizontalAlignment: Text.AlignHCenter
        color: Util.alpha(Commons.Color.foreground, 0.4)
        font.pixelSize: Style.font.caption
      }
    }
  }
}
