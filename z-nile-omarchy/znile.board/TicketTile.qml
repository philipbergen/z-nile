import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// One ticket or raft card. All tracker text is untrusted and drawn as
// PlainText. The card drags itself (Board.qml reparents it while it flies)
// and reports clicks; it knows nothing about priority.
Rectangle {
  id: tile

  property var item: null
  property var board: null          // Board.qml root: colours and fonts
  property bool selected: false
  property string dragKey: ""

  readonly property string itemId: item ? item.id : ""
  readonly property color typeColor: board ? board.typeColor(item) : Commons.Color.accent
  readonly property color stageColor: board ? board.stageColor(item ? item.stage : "new") : Commons.Color.accent
  readonly property bool blocked: item ? item.blockedBy.length > 0 : false
  readonly property bool dragging: dragging_
  property bool dragging_: false
  readonly property bool hovered: mouse.containsMouse

  signal clicked()
  signal dive()
  signal openId(string id)   // a linked ticket or raft id was clicked
  signal openUrl(string url) // a pull request chip was clicked

  // A short glow when the board jumps to this card.
  function pulse() { pulseAnim.restart() }
  Rectangle {
    id: glow
    anchors.fill: parent
    anchors.margins: -3
    radius: tile.radius + 3
    color: "transparent"
    border.width: 3
    border.color: Commons.Color.accent
    opacity: 0
    z: 50
    SequentialAnimation {
      id: pulseAnim
      NumberAnimation { target: glow; property: "opacity"; to: 1; duration: Style.duration(160); easing.type: Easing.OutCubic }
      PauseAnimation { duration: 500 }
      NumberAnimation { target: glow; property: "opacity"; to: 0; duration: Style.duration(600); easing.type: Easing.OutCubic }
    }
  }

  implicitHeight: body.implicitHeight + Style.space(20)
  radius: Math.max(6, Style.cornerRadius)
  color: board ? board.surface : Commons.Color.background
  border.width: selected ? 2 : 1
  border.color: selected ? typeColor : Util.alpha(Commons.Color.foreground, hovered ? 0.22 : 0.08)
  opacity: dragging ? 0.92 : (item && item.stage === "done" ? 0.62 : 1)
  scale: dragging ? 1.03 : 1
  z: dragging ? 100 : 0

  Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
  Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

  Drag.active: dragging_
  Drag.source: tile
  Drag.keys: [dragKey]
  Drag.hotSpot.x: width / 2
  Drag.hotSpot.y: Style.space(14)

  // Type stripe down the left edge.
  Rectangle {
    width: 4
    radius: 2
    color: tile.typeColor
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 6 }
  }

  Column {
    id: body
    spacing: Style.space(7)
    anchors {
      left: parent.left; right: parent.right; top: parent.top
      leftMargin: Style.space(18); rightMargin: Style.space(12); topMargin: Style.space(10)
    }

    // id · project · emergent
    Row {
      spacing: Style.space(7)
      width: parent.width

      TypeBadge {
        letter: tile.board ? tile.board.typeLetter(tile.item) : ""
        tint: tile.typeColor
        anchors.verticalCenter: parent.verticalCenter
      }
      PlainLabel {
        text: tile.itemId
        font.bold: true
        font.pixelSize: Style.font.body
        color: Commons.Color.foreground
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        visible: !!tile.item && tile.item.project !== ""
        height: projectText.implicitHeight + 4
        width: projectText.implicitWidth + Style.space(12)
        radius: height / 2
        color: Util.alpha(Commons.Color.foreground, 0.07)
        anchors.verticalCenter: parent.verticalCenter
        PlainLabel {
          id: projectText
          anchors.centerIn: parent
          text: tile.item ? tile.item.project : ""
          font.pixelSize: Style.font.caption
          color: Util.alpha(Commons.Color.foreground, 0.75)
        }
      }
      PlainLabel {
        visible: !!tile.item && tile.item.emergent
        text: ""
        color: tile.board ? tile.board.hue("orange", Commons.Color.urgent) : Commons.Color.urgent
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    PlainLabel {
      width: parent.width
      text: tile.item ? tile.item.title : ""
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
      font.pixelSize: Style.font.subtitle
      color: Commons.Color.foreground
    }

    // Pipeline: five segments, lit up to this item's stage, then its status.
    Item {
      width: parent.width
      height: stageText.implicitHeight

      Row {
        id: segments
        spacing: 3
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
          model: 5
          Rectangle {
            required property int index
            width: Style.space(16); height: 4; radius: 2
            color: tile.item && index <= tile.item.stageIndex
              ? tile.stageColor : Util.alpha(Commons.Color.foreground, 0.1)
          }
        }
      }
      PlainLabel {
        id: stageText
        anchors { left: segments.right; leftMargin: Style.space(8); right: parent.right; verticalCenter: parent.verticalCenter }
        text: tile.item ? tile.item.stage + (tile.item.status && tile.item.status !== tile.item.stage ? " · " + tile.item.status : "") : ""
        elide: Text.ElideRight
        font.pixelSize: Style.font.caption
        color: Util.alpha(Commons.Color.foreground, 0.6)
      }
    }

    // Chips: raft, members, blockers, dependencies.
    Flow {
      width: parent.width
      spacing: Style.space(5)
      visible: chipRaft.visible || chipMembers.visible || chipBlocked.visible || chipPartly.visible || chipAfter.visible || chipDeps.visible || prRepeater.count > 0

      // Open pull requests: green when ready, dim while draft.
      Repeater {
        id: prRepeater
        model: tile.item ? tile.item.prs : []
        Chip {
          required property var modelData
          glyph: "\uf126"
          label: "#" + modelData.number + (modelData.draft ? " draft" : "")
          tint: modelData.draft ? Util.alpha(Commons.Color.foreground, 0.75)
            : (tile.board ? tile.board.hue("green", Commons.Color.accent) : Commons.Color.accent)
          interactive: true
          onClicked: tile.openUrl(modelData.url)
        }
      }
      IdChip { id: chipRaft; visible: !!tile.item && tile.item.raft !== ""; glyph: "\uf1b3"; ids: tile.item && tile.item.raft ? [tile.item.raft] : []; tint: tile.board ? tile.board.hue("magenta", Commons.Color.accent) : Commons.Color.accent; onOpen: function(id) { tile.openId(id) } }
      IdChip { id: chipMembers; visible: !!tile.item && tile.item.kind === "raft"; glyph: "\uf0ca"; prefix: !tile.item ? "" : tile.item.issues.length === 0 ? "no tickets" : tile.item.issues.length + (tile.item.issues.length === 1 ? " ticket:" : " tickets:"); ids: tile.item ? tile.item.issues : []; tint: Commons.Color.foreground; onOpen: function(id) { tile.openId(id) } }
      IdChip { id: chipBlocked; visible: tile.blocked; glyph: "\uf023"; prefix: "blocked by"; ids: tile.item ? tile.item.blockedBy : []; tint: Commons.Color.urgent; onOpen: function(id) { tile.openId(id) } }
      IdChip { id: chipPartly; visible: !!tile.item && tile.item.kind === "raft" && tile.item.issues.length > 1 && tile.item.blockedMembers.length > 0; glyph: "\uf023"; prefix: tile.item ? tile.item.blockedMembers.length + " of " + tile.item.issues.length + " blocked:" : ""; ids: tile.item ? tile.item.blockedMembers.map(function(b) { return b.id }) : []; tint: Commons.Color.urgent; onOpen: function(id) { tile.openId(id) } }
      IdChip { id: chipAfter; visible: !!tile.item && tile.item.after.length > 0; glyph: "\uf160"; prefix: "after"; ids: tile.item ? tile.item.after : []; tint: Commons.Color.foreground; onOpen: function(id) { tile.openId(id) } }
      Chip { id: chipDeps; visible: !!tile.item && !tile.blocked && tile.item.after.length === 0 && tile.item.dependsOn.length > 0; glyph: "\uf0c1"; label: tile.item ? String(tile.item.dependsOn.length) : ""; tint: Commons.Color.foreground }
    }

    // Cost so far: agent time and tokens.
    PlainLabel {
      visible: text !== ""
      width: parent.width
      text: tile.item && tile.item.cost && Model.costLine(tile.item.cost) !== "" ? "\uf017  " + Model.costLine(tile.item.cost) : ""
      elide: Text.ElideRight
      font.pixelSize: Style.font.caption
      color: Util.alpha(Commons.Color.foreground, 0.55)
    }

    // Next step and the dive-in action.
    Item {
      width: parent.width
      height: Math.max(nextText.implicitHeight, diveButton.height)

      PlainLabel {
        id: nextText
        anchors { left: parent.left; right: diveButton.left; rightMargin: Style.space(6); verticalCenter: parent.verticalCenter }
        text: tile.item && tile.item.command ? "→ " + tile.item.command : ""
        elide: Text.ElideRight
        font.pixelSize: Style.font.caption
        color: Util.alpha(Commons.Color.foreground, 0.5)
      }

      Rectangle {
        id: diveButton
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        height: diveText.implicitHeight + Style.space(8)
        width: diveText.implicitWidth + Style.space(16)
        radius: height / 2
        opacity: tile.hovered || tile.selected || diveMouse.containsMouse ? 1 : 0
        color: diveMouse.containsMouse ? tile.typeColor : Util.alpha(tile.typeColor, 0.16)
        Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
        PlainLabel {
          id: diveText
          anchors.centerIn: parent
          text: "\uf120  " + (tile.board && tile.board.service && tile.board.service.agentName ? tile.board.service.agentName : "Dive in")
          font.pixelSize: Style.font.caption
          font.bold: true
          color: diveMouse.containsMouse ? Commons.Color.background : tile.typeColor
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    z: -1 // below the card's content, so the Dive in button gets its own clicks
    hoverEnabled: true
    preventStealing: true
    cursorShape: dragging_ ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    drag.target: tile.dragKey !== "" ? tile : undefined
    drag.threshold: 6
    onClicked: tile.clicked()
    onDoubleClicked: tile.dive()
  }

  // Release the drop while Drag is still active, then land.
  Connections {
    target: mouse.drag
    function onActiveChanged() {
      if (mouse.drag.active) { tile.dragging_ = true; return }
      tile.Drag.drop()
      tile.dragging_ = false
    }
  }

  MouseArea {
    id: diveMouse
    parent: diveButton
    anchors.fill: parent
    hoverEnabled: true
    enabled: diveButton.opacity > 0
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.dive()
  }
}
