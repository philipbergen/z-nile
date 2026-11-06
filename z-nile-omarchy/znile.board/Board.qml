import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// The znile board: a normal (tiled) window with every ticket and raft in
// stage columns, an overview of the pipeline and recent activity, filters,
// and a detail pane. Summoned by the bar icon:
//   omarchy-shell shell toggle znile.board '{}'
Item {
  id: root

  // ---- plugin lifecycle (the shell sets these)
  property var shell: null
  property var service: null
  property bool closingFromHost: false
  readonly property bool opened: window.visible

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    if (service) service.refresh()
    // Optional payload {"select": "<id>"} opens with that card's details.
    var wanted = "", big = false
    try {
      var parsed = JSON.parse(String(payloadJson || "{}"))
      wanted = String(parsed.select || "")
      big = parsed.max === true
      if (parsed.newTicket === true) Qt.callLater(function() { newDialog.open() })
    } catch (e) {}
    Qt.callLater(function() {
      keys.forceActiveFocus()
      if (/^[fdcR][0-9]{4}$/.test(wanted)) selectById(wanted, big)
    })
  }

  // Jumps to a card by id: shows the view and filters it needs, scrolls it
  // into view, opens its details beside it and makes it glow.
  function selectById(id, big) { focusId(id, big) }
  function focusId(id, big) {
    var item = model.byId[id]
    if (!item) { if (service) service.say(id + " isn't on the board"); return }
    if (!Model.matches(item, filters)) {
      blockedOnly = false; projectFilter = []; typeFilter = []; search.text = ""
    }
    var wanted = item.kind === "raft" ? "rafts" : "tickets"
    if (view !== wanted) view = wanted
    if (item.stage === "done") showDone = true
    maximized = false
    Qt.callLater(function() { reveal(id, !!big, 0) })
  }
  function reveal(id, big, tries) {
    var list = findList(keys, id)
    if (list) list.positionViewAtIndex(list.cardIds.indexOf(id), ListView.Contain)
    Qt.callLater(function() {
      var tile = findTile(keys, id)
      if (!tile && tries < 4) { reveal(id, big, tries + 1); return }
      if (tile) {
        // Bring its column into view when the board scrolls sideways.
        var p = tile.mapToItem(boardFlick.contentItem, 0, 0)
        var pad = Style.space(12)
        var x = boardFlick.contentX
        if (p.x - pad < x) x = p.x - pad
        else if (p.x + tile.width + pad > x + boardFlick.width) x = p.x + tile.width + pad - boardFlick.width
        boardFlick.contentX = Math.max(0, Math.min(boardFlick.contentWidth - boardFlick.width, x))
        tile.pulse()
      }
      selectedId = ""
      select(id, tile)
      maximized = big
    })
  }
  function findList(node, id) {
    if (!node) return null
    if (node.cardIds !== undefined && node.cardIds.indexOf(id) >= 0) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = findList(kids[i], id)
      if (hit) return hit
    }
    return null
  }
  function findTile(node, id) {
    if (!node) return null
    if (node.itemId === id && node.dragKey !== undefined) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = findTile(kids[i], id)
      if (hit) return hit
    }
    if (node.contentItem && node.contentItem !== node) return findTile(node.contentItem, id)
    return null
  }

  function close() {
    closingFromHost = true
    window.visible = false
  }

  // ---- view state
  property string view: "tickets"      // "tickets" | "rafts"
  property bool showDone: false
  property var projectFilter: []
  property var typeFilter: []
  property string query: ""
  property string selectedId: ""

  readonly property var model: service ? service.model : Model.normalize({})
  readonly property var items: view === "rafts" ? model.rafts : model.issues // znile calls tickets "issues"
  property bool blockedOnly: false
  property bool maximized: false
  readonly property var filters: ({ projects: projectFilter, types: typeFilter, query: query, blocked: blockedOnly })
  readonly property int blockedCount: Model.stageCounts(items.filter(function(it) { return it.stage !== "done" }), { blocked: true }).total
  readonly property var orders: {
    var out = {}
    if (!service) return out
    for (var i = 0; i < Model.STAGES.length; i++)
      out[Model.STAGES[i]] = service.orderFor(view + ":" + Model.STAGES[i])
    return out
  }
  readonly property var cols: Model.columns(items, filters, orders, showDone)
  readonly property var counts: Model.stageCounts(items, filters)
  readonly property var activity: Model.activity(model.stats)
  readonly property var week: Model.weekSummary(model.stats)
  readonly property var projectCounts: Model.projectCounts(items)
  readonly property var selected: selectedId !== "" ? (model.byId[selectedId] || null) : null

  // ---- palette, from the theme's own named colours
  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property color surface: hue("lighter_background", Util.alpha(fg, 0.05))
  readonly property color sunken: hue("dark_background", Qt.darker(bg, 1.15))

  // Inline `code` in descriptions: the theme's orange on its selection tint.
  readonly property var codeStyle: ({
    color: hex(hue("orange", hue("yellow", Commons.Color.accent))),
    background: hex(hue("selection", hue("lighter_background", Util.alpha(fg, 0.12))))
  })
  function hex(c) {
    var q = Qt.color(c)
    function two(v) { var h = Math.round(v * 255).toString(16); return h.length < 2 ? "0" + h : h }
    return "#" + two(q.r) + two(q.g) + two(q.b)
  }
  function hue(name, fallback) { return service ? service.hue(name, fallback) : fallback }
  function typeColor(item) {
    var t = item ? (item.label || item.type) : ""
    if (t === "feature") return hue("blue", Commons.Color.accent)
    if (t === "defect") return hue("red", Commons.Color.urgent)
    if (t === "chore") return hue("yellow", fg)
    if (t === "mix") return hue("magenta", Commons.Color.accent)
    return Util.alpha(fg, 0.6)
  }
  function typeLetter(item) {
    if (!item) return ""
    if (item.kind === "raft") return "R"
    var t = item.type || item.label
    return t === "feature" ? "F" : t === "defect" ? "D" : t === "chore" ? "C" : "?"
  }
  function stageColor(stage) {
    if (stage === "new") return hue("dark_foreground", Util.alpha(fg, 0.5))
    if (stage === "preparing") return hue("yellow", fg)
    if (stage === "prepared") return hue("cyan", Commons.Color.accent)
    if (stage === "active") return hue("green", Commons.Color.accent)
    return hue("magenta", Util.alpha(fg, 0.5))
  }
  function stageTitle(stage) {
    return { new: "New", preparing: "Preparing", prepared: "Prepared", active: "Active", done: "Done" }[stage] || stage
  }
  function toggleIn(list, value) {
    var out = list.slice()
    var at = out.indexOf(value)
    if (at >= 0) out.splice(at, 1)
    else out.push(value)
    return out
  }
  // The card the popup opened from, and its rect in the window.
  property Item anchorTile: null
  property var anchorRect: null
  function select(id, tile) {
    // Clicking the open card again toggles the big view.
    if (selectedId === id) { maximized = !maximized; return }
    selectedId = id
    anchorTile = tile || null
    reposition()
  }
  function reposition() {
    if (!anchorTile || !anchorTile.visible) return
    var p = anchorTile.mapToItem(keys, 0, 0)
    anchorRect = { x: p.x, y: p.y, width: anchorTile.width, height: anchorTile.height }
  }
  onSelectedIdChanged: if (selectedId === "") { anchorTile = null; anchorRect = null; maximized = false }
  function dive(item) { if (service && item) service.dive(item) }
  function focusBoard() { keys.forceActiveFocus() }
  // Arrow and page keys scroll the open card's description.
  function scrollBody(key) {
    var f = bodyFlick, page = f.height * 0.9, line = Style.space(40)
    var dy = key === Qt.Key_Down ? line : key === Qt.Key_Up ? -line
      : key === Qt.Key_PageDown ? page : key === Qt.Key_PageUp ? -page : 0
    var dx = key === Qt.Key_Right ? line * 2 : key === Qt.Key_Left ? -line * 2 : 0
    if (dx === 0 && dy === 0) return false
    f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + dy))
    f.contentX = Math.max(0, Math.min(f.contentWidth - f.width, f.contentX + dx))
    return true
  }
  function openWeb(item) { if (item) openUrl(item.url) }
  // Only github.com pages of this repo's files and pull requests open.
  function openUrl(url) {
    if (/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/(pull\/[0-9]+|blob\/main\/[\w.\/-]+)$/.test(String(url)))
      Quickshell.execDetached(["xdg-open", String(url)])
  }
  // The popup's key/value rows. `warn` rows are blockers; `dim` rows explain.
  function detailRows(it) {
    if (!it) return []
    var rows = [
      { k: "stage", v: it.stage + (it.status && it.status !== it.stage ? "  ·  " + it.status : "") },
      { k: "design", v: it.design || "–" }
    ]
    if (it.kind === "raft") {
      rows.push({ k: "tickets", v: it.issues.join(" ") || "none" })
      if (it.dependsOn.length > 0) rows.push({ k: "after rafts", v: it.dependsOn.join(" ") })
      if (it.blockedBy.length > 0) {
        rows.push({ k: "blocked by", v: it.blockedBy.join(" "), warn: true })
        var why = it.blockedMembers.map(function(b) { return b.id + " needs " + b.by.join(", ") })
        if (why.length > 0) rows.push({ k: "because", v: why.join("; "), warn: true })
        rows.push({ k: "", v: it.blockedMembers.length < it.issues.length
          ? "The raft ships as one PR, so one blocked ticket holds back all " + it.issues.length + "."
          : "Nothing in it can start until those are done.", dim: true })
      }
    } else {
      rows.push({ k: "raft", v: it.raft || "– (not in a raft yet)" })
      if (it.blockedBy.length > 0) {
        rows.push({ k: "blocked by", v: it.blockedBy.join(" "), warn: true })
        if (it.raft) rows.push({ k: "", v: "This holds back its whole raft, " + it.raft + ".", dim: true })
      }
      if (it.after.length > 0) rows.push({ k: "after", v: it.after.join(" ") + "  (same raft: order only)" })
      var other = it.dependsOn.filter(function(d) { return it.blockedBy.indexOf(d) < 0 && it.after.indexOf(d) < 0 })
      if (other.length > 0) rows.push({ k: "depends on", v: other.join(" ") + "  (done)" })
    }
    for (var p = 0; p < it.prs.length; p++) {
      var pr = it.prs[p]
      rows.push({ k: p === 0 ? (it.prs.length > 1 ? "pull requests" : "pull request") : "",
        v: "#" + pr.number + (pr.draft ? " (draft)" : "") + "  " + pr.title, url: pr.url })
    }
    var cost = it.cost ? Model.costLine(it.cost) : ""
    if (cost !== "") {
      var lines = it.cost.added > 0 || it.cost.removed > 0 ? "   (+" + Math.round(it.cost.added) + " / −" + Math.round(it.cost.removed) + " lines)" : ""
      rows.push({ k: it.kind === "raft" ? "cost (raft)" : "cost", v: cost + lines })
      var phases = Model.phaseLine(it.cost)
      if (phases !== "") rows.push({ k: "", v: phases, dim: true })
    } else {
      rows.push({ k: "cost", v: "nothing recorded yet", dim: true })
    }
    rows.push(it.command ? { k: "next", v: "", cmd: it.command } : { k: "next", v: "–" })
    return rows
  }
  function drop(stage, ids, id, beforeId) {
    if (!service || id === beforeId) return
    service.reprioritize(view + ":" + stage, ids, id, beforeId)
  }

  FloatingWindow {
    id: window
    visible: false
    title: "Z-nile board"
    color: root.bg
    implicitWidth: 1440
    implicitHeight: 900
    minimumSize: Qt.size(820, 560)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("znile.board")
    }

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (newDialog.shown) {
          if (event.key === Qt.Key_Escape) { newDialog.close(); event.accepted = true }
          return
        }
        // Single-letter keys, unless typing in the search.
        var plain = !search.activeFocus && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0
        if (plain && event.key === Qt.Key_N) { newDialog.open(); event.accepted = true; return }
        if (plain && event.key === Qt.Key_R) { root.view = "rafts"; root.selectedId = ""; event.accepted = true; return }
        if (plain && event.key === Qt.Key_T) { root.view = "tickets"; root.selectedId = ""; event.accepted = true; return }
        if (event.key === Qt.Key_Escape) {
          if (root.maximized) root.maximized = false
          else if (root.selectedId !== "") root.selectedId = ""
          else if (search.text !== "") search.text = ""
          else root.close()
          event.accepted = true
        } else if (root.selectedId !== "" && root.scrollBody(event.key)) {
          event.accepted = true
        } else if (event.key === Qt.Key_Slash) {
          search.forceActiveFocus(); event.accepted = true
        } else if (event.key === Qt.Key_F5 || (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier))) {
          if (root.service) root.service.refresh(); event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          root.view = root.view === "tickets" ? "rafts" : "tickets"; event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(20)
        spacing: Style.space(16)

        // ---------------------------------------------------- header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(14)

          Column {
            Layout.fillWidth: true
            spacing: 2
            PlainLabel {
              text: "Z-nile"
              font.pixelSize: Style.font.display
              font.bold: true
              color: root.fg
            }
            PlainLabel {
              text: root.service && root.service.error !== ""
                ? root.service.error
                : root.model.issues.length + " tickets · " + root.model.rafts.length + " rafts · "
                  + root.model.projects.length + " projects" + (root.model.fetchedAt ? " · updated " + root.model.fetchedAt.slice(11, 16) : "")
                  + (root.view === "rafts" ? "   —   a raft is a group of tickets delivered together as one PR" : "   —   a ticket is one feature, defect or chore")
              width: parent.width
              elide: Text.ElideRight
              color: root.service && root.service.error !== "" ? Commons.Color.urgent : Util.alpha(root.fg, 0.55)
              font.pixelSize: Style.font.bodySmall
            }
          }

          // Tickets | Rafts
          Rectangle {
            radius: height / 2
            color: root.sunken
            implicitHeight: viewRow.implicitHeight + 6
            implicitWidth: viewRow.implicitWidth + 6
            Row {
              id: viewRow
              anchors.centerIn: parent
              Repeater {
                model: [{ key: "tickets", label: "Tickets" }, { key: "rafts", label: "Rafts" }]
                Rectangle {
                  required property var modelData
                  readonly property bool on: root.view === modelData.key
                  radius: height / 2
                  height: segText.implicitHeight + Style.space(10)
                  width: segText.implicitWidth + Style.space(28)
                  color: on ? root.surface : "transparent"
                  border.width: on ? 1 : 0
                  border.color: Util.alpha(root.fg, 0.12)
                  Behavior on color { ColorAnimation { duration: Style.duration(140) } }
                  PlainLabel {
                    id: segText
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    color: parent.on ? root.fg : Util.alpha(root.fg, 0.55)
                    font.bold: parent.on
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.view = parent.modelData.key; root.selectedId = "" }
                  }
                }
              }
            }
          }

          // New ticket (N): pick project and AI, open it in a terminal.
          Rectangle {
            radius: height / 2
            implicitHeight: newText.implicitHeight + Style.space(10)
            implicitWidth: newText.implicitWidth + Style.space(24)
            color: newArea.containsMouse ? Qt.lighter(Commons.Color.accent, 1.1) : Commons.Color.accent
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            PlainLabel {
              id: newText
              anchors.centerIn: parent
              text: "\uf067  New ticket"
              color: root.bg
              font.bold: true
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: newArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: newDialog.open()
            }
          }

          // The AI CLI dive-ins open in; click to switch.
          Chip {
            visible: !!root.service && root.service.agents.length > 0
            glyph: "\uf120"
            label: root.service ? root.service.agentName : ""
            tint: Commons.Color.accent
            interactive: true
            fontSize: Style.font.bodySmall
            onClicked: {
              var list = root.service.agents
              var at = -1
              for (var i = 0; i < list.length; i++) if (list[i].id === root.service.agent) at = i
              root.service.chooseAgent(list[(at + 1) % list.length].id)
            }
          }

          Chip {
            glyph: ""
            label: "Done"
            tint: root.stageColor("done")
            active: root.showDone
            interactive: true
            fontSize: Style.font.bodySmall
            onClicked: root.showDone = !root.showDone
          }

          Rectangle {
            width: Style.space(34); height: width; radius: width / 2
            color: refreshArea.containsMouse ? root.surface : "transparent"
            PlainLabel {
              anchors.centerIn: parent
              text: ""
              color: Util.alpha(root.fg, 0.8)
              font.pixelSize: Style.font.title
              RotationAnimation on rotation {
                running: !!root.service && root.service.loading
                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                onStopped: parent.rotation = 0
              }
            }
            MouseArea {
              id: refreshArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.service) root.service.refresh()
            }
          }
        }

        // ---------------------------------------------------- overview
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(24)

          // Pipeline: one bar, a segment per stage.
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Item {
              id: pipe
              Layout.fillWidth: true
              implicitHeight: 12
              readonly property var stages: root.showDone ? Model.STAGES : Model.STAGES.slice(0, 4)
              readonly property int total: {
                var t = 0
                for (var i = 0; i < stages.length; i++) t += root.counts[stages[i]]
                return Math.max(1, t)
              }
              Row {
                anchors.fill: parent
                spacing: 3
                Repeater {
                  model: pipe.stages
                  Rectangle {
                    required property string modelData
                    height: pipe.height
                    radius: height / 2
                    visible: root.counts[modelData] > 0
                    width: Math.max(height, (pipe.width - 3 * (pipe.stages.length - 1)) * root.counts[modelData] / pipe.total)
                    color: root.stageColor(modelData)
                    Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
                  }
                }
              }
            }

            Row {
              spacing: Style.space(18)
              Repeater {
                model: pipe.stages
                Row {
                  required property string modelData
                  spacing: Style.space(6)
                  Rectangle {
                    width: 8; height: 8; radius: 4
                    color: root.stageColor(parent.modelData)
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  PlainLabel {
                    text: root.stageTitle(parent.modelData)
                    color: Util.alpha(root.fg, 0.65)
                    font.pixelSize: Style.font.bodySmall
                  }
                  PlainLabel {
                    text: String(root.counts[parent.modelData])
                    color: root.fg
                    font.bold: true
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          // Last 30 days: opened (dim, up) vs closed (green, down).
          ColumnLayout {
            spacing: Style.space(4)
            visible: root.activity.length > 0

            Canvas {
              id: spark
              Layout.preferredWidth: Style.space(260)
              Layout.preferredHeight: Style.space(44)
              readonly property var data: root.activity
              readonly property color openColor: Util.alpha(root.fg, 0.35)
              readonly property color closeColor: root.stageColor("active")
              onDataChanged: requestPaint()
              onOpenColorChanged: requestPaint()
              onCloseColorChanged: requestPaint()
              onWidthChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var n = data.length
                if (n === 0) return
                var max = 1
                for (var i = 0; i < n; i++) max = Math.max(max, data[i].opened, data[i].closed)
                var mid = height / 2
                var step = width / n
                var bw = Math.max(1, step - 2)
                for (var j = 0; j < n; j++) {
                  var x = j * step + 1
                  var up = (mid - 1) * Math.sqrt(data[j].opened / max)
                  var down = (mid - 1) * Math.sqrt(data[j].closed / max)
                  ctx.fillStyle = openColor
                  ctx.fillRect(x, mid - up, bw, up)
                  ctx.fillStyle = closeColor
                  ctx.fillRect(x, mid + 1, bw, down)
                }
              }
            }
            PlainLabel {
              text: root.week
                ? "This week · " + root.week.closed + " closed · " + root.week.opened + " opened · " + root.week.hours + " h"
                : "Last 30 days"
              color: Util.alpha(root.fg, 0.55)
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---------------------------------------------------- filters
        Flow {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Rectangle {
            width: Style.space(260)
            implicitHeight: search.implicitHeight + Style.space(14)
            radius: height / 2
            color: root.sunken
            border.width: search.activeFocus ? 1 : 0
            border.color: Commons.Color.accent
            PlainLabel {
              id: searchGlyph
              anchors { left: parent.left; leftMargin: Style.space(12); verticalCenter: parent.verticalCenter }
              text: ""
              color: Util.alpha(root.fg, 0.5)
            }
            TextInput {
              id: search
              anchors { left: searchGlyph.right; right: parent.right; leftMargin: Style.space(8); rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
              color: root.fg
              selectionColor: Util.alpha(Commons.Color.accent, 0.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              clip: true
              onTextChanged: root.query = text
              Keys.onEscapePressed: { text = ""; keys.forceActiveFocus() }
              PlainLabel {
                visible: search.text === ""
                text: "Search id, title, raft…  ( / )"
                color: Util.alpha(root.fg, 0.35)
              }
            }
          }

          Repeater {
            model: root.model.projects
            Chip {
              required property string modelData
              label: modelData + "  " + (root.projectCounts[modelData] || 0)
              tint: root.fg
              active: root.projectFilter.indexOf(modelData) >= 0
              interactive: true
              fontSize: Style.font.bodySmall
              onClicked: root.projectFilter = root.toggleIn(root.projectFilter, modelData)
            }
          }

          Item { width: Style.space(10); height: 1 }

          Chip {
            glyph: "\uf023"
            label: "blocked  " + root.blockedCount
            tint: Commons.Color.urgent
            active: root.blockedOnly
            interactive: true
            fontSize: Style.font.bodySmall
            onClicked: root.blockedOnly = !root.blockedOnly
          }

          Repeater {
            model: ["feature", "defect", "chore"]
            Chip {
              required property string modelData
              glyph: modelData === "feature" ? "F" : modelData === "defect" ? "D" : "C"
              label: modelData
              tint: root.typeColor({ type: modelData })
              active: root.typeFilter.indexOf(modelData) >= 0
              interactive: true
              fontSize: Style.font.bodySmall
              onClicked: root.typeFilter = root.toggleIn(root.typeFilter, modelData)
            }
          }
        }

        // ---------------------------------------------------- board + detail
        Flickable {
          id: boardFlick
          onContentXChanged: root.reposition()
          onWidthChanged: root.reposition()
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          readonly property real minColumn: Style.space(250)
          contentWidth: Math.max(width, root.cols.length * minColumn + (root.cols.length - 1) * Style.space(14))
          contentHeight: height
          flickableDirection: Flickable.HorizontalFlick
          interactive: contentWidth > width
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
          SmoothWheel { hflick: boardFlick }

          RowLayout {
            width: boardFlick.contentWidth
            height: boardFlick.height
            spacing: Style.space(14)

            Repeater {
              model: root.cols

              Rectangle {
                id: column
                required property var modelData
                readonly property string stage: modelData.stage
                readonly property var ids: modelData.items.map(function(it) { return it.id })

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: Math.max(8, Style.cornerRadius)
                color: root.sunken

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(10)

                  RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Style.space(4)
                    spacing: Style.space(8)
                    Rectangle {
                      width: 10; height: 10; radius: 5
                      color: root.stageColor(column.stage)
                    }
                    PlainLabel {
                      text: root.stageTitle(column.stage)
                      color: root.fg
                      font.bold: true
                      font.pixelSize: Style.font.title
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                      radius: height / 2
                      implicitHeight: countText.implicitHeight + 4
                      implicitWidth: Math.max(implicitHeight, countText.implicitWidth + Style.space(12))
                      color: Util.alpha(root.stageColor(column.stage), 0.18)
                      PlainLabel {
                        id: countText
                        anchors.centerIn: parent
                        text: String(column.modelData.items.length)
                        color: root.stageColor(column.stage)
                        font.bold: true
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }

                  ListView {
                    id: list
                  onContentYChanged: root.reposition()
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Style.space(8)
                    model: column.modelData.items
                  readonly property var cardIds: column.ids
                  // Build cards a few screens ahead so scrolling never waits.
                  cacheBuffer: Style.space(1600)

                  SmoothWheel { vflick: list; hflick: boardFlick }
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                      id: slot
                      required property var modelData
                      width: list.width - Style.space(6)
                      height: tile.height

                      DropArea {
                        id: dropHere
                        anchors.fill: parent
                        keys: [root.view + ":" + column.stage]
                        onDropped: function(drop) {
                          if (drop.source && drop.source.itemId) {
                            root.drop(column.stage, column.ids, drop.source.itemId, slot.modelData.id)
                            drop.accept()
                          }
                        }
                      }

                      // Where the dragged card will land: just above this one.
                      Rectangle {
                        visible: dropHere.containsDrag && dropHere.drag.source !== tile
                        width: parent.width; height: 3; radius: 2
                        y: -Style.space(5)
                        color: Commons.Color.accent
                      }

                      TicketTile {
                        id: tile
                        board: root
                        item: slot.modelData
                        width: slot.width
                        selected: root.selectedId === slot.modelData.id
                        dragKey: root.view + ":" + column.stage
                        onClicked: root.select(slot.modelData.id, tile)
                        onDive: root.dive(slot.modelData)
                      onOpenId: function(id) { root.focusId(id) }
                      onOpenUrl: function(url) { root.openUrl(url) }

                        states: State {
                          when: tile.dragging
                          ParentChange { target: tile; parent: dragLayer }
                        }
                      }
                    }

                    // Drop past the last card to move one to the end.
                    footer: Item {
                      width: list.width - Style.space(6)
                      height: Style.space(60)
                      DropArea {
                        id: dropEnd
                        anchors.fill: parent
                        keys: [root.view + ":" + column.stage]
                        onDropped: function(drop) {
                          if (drop.source && drop.source.itemId) {
                            root.drop(column.stage, column.ids, drop.source.itemId, "")
                            drop.accept()
                          }
                        }
                      }
                      Rectangle {
                        visible: dropEnd.containsDrag
                        width: parent.width; height: 3; radius: 2
                        y: Style.space(3)
                        color: Commons.Color.accent
                      }
                    }

                    PlainLabel {
                      anchors.centerIn: parent
                      visible: list.count === 0
                      text: "Nothing here"
                      color: Util.alpha(root.fg, 0.3)
                    }
                  }
                }
              }
            }

          }
        }
      }

      // ------------------------------------------------ detail popup
      // Opens beside the clicked card (right of it when there is room, else
      // left), and follows it while the board scrolls.
      Rectangle {
        id: detail
        visible: root.selected !== null
        z: 500
        readonly property real margin: Style.space(12)
        readonly property real gap: Style.space(10)
        width: root.maximized ? keys.width - 2 * margin : Math.min(Style.space(460), keys.width - 2 * margin)
        height: root.maximized ? keys.height - 2 * margin : Math.min(Style.space(620), keys.height - 2 * margin)
        x: {
          if (root.maximized) return margin
          var r = root.anchorRect
          if (!r) return keys.width - width - margin
          var right = r.x + r.width + gap
          if (right + width <= keys.width - margin) return right
          var left = r.x - gap - width
          if (left >= margin) return left
          return Math.max(margin, keys.width - width - margin)
        }
        y: {
          if (root.maximized) return margin
          var r = root.anchorRect
          var top = r ? r.y - Style.space(8) : margin
          return Math.max(margin, Math.min(top, keys.height - height - margin))
        }
        radius: Math.max(8, Style.cornerRadius)
        color: root.surface
        border.width: 1
        border.color: Util.alpha(root.typeColor(root.selected), 0.6)

        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
        Behavior on x { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

        // Clicks on the popup's empty areas toggle the big view, and never
        // reach the board below.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onClicked: root.maximized = !root.maximized
          onWheel: function(w) { w.accepted = true }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            TypeBadge {
              letter: root.typeLetter(root.selected)
              tint: root.typeColor(root.selected)
              size: Style.space(28)
              fontSize: Style.font.subtitle
            }
            PlainLabel {
              Layout.leftMargin: Style.space(4)
              text: root.selected ? root.selected.id : ""
              color: root.fg
              font.bold: true
              font.pixelSize: Style.font.heading
            }
            PlainLabel {
              visible: !!root.selected && root.selected.project !== ""
              Layout.leftMargin: Style.space(4)
              text: root.selected ? root.selected.project : ""
              color: Util.alpha(root.fg, 0.55)
              font.pixelSize: Style.font.bodySmall
            }
            Item { Layout.fillWidth: true }
            Repeater {
              model: [
                { glyph: "\uf09b", tip: "github", on: !!root.selected && root.selected.url !== "" },
                { glyph: root.maximized ? "\uf066" : "\uf065", tip: "size", on: true },
                { glyph: "\uf00d", tip: "close", on: true }
              ]
              Rectangle {
                required property var modelData
                visible: modelData.on
                width: Style.space(30); height: width; radius: width / 2
                color: headArea.containsMouse ? Util.alpha(root.fg, 0.1) : "transparent"
                PlainLabel {
                  anchors.centerIn: parent
                  text: parent.modelData.glyph
                  color: Util.alpha(root.fg, headArea.containsMouse ? 0.95 : 0.6)
                  font.pixelSize: Style.font.title
                }
                MouseArea {
                  id: headArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var t = parent.modelData.tip
                    if (t === "github") root.openWeb(root.selected)
                    else if (t === "size") root.maximized = !root.maximized
                    else root.selectedId = ""
                  }
                }
              }
            }
          }

          PlainLabel {
            Layout.fillWidth: true
            text: root.selected ? root.selected.title : ""
            wrapMode: Text.Wrap
            color: root.fg
            font.pixelSize: Style.font.title
            font.bold: true
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)
            Repeater {
              model: root.detailRows(root.selected)
              RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(12)
                PlainLabel {
                  Layout.preferredWidth: Style.space(96)
                  Layout.alignment: Qt.AlignTop
                  text: parent.modelData.k
                  color: Util.alpha(root.fg, 0.5)
                  font.pixelSize: Style.font.bodySmall
                }
                // The next command: copy it with one click.
                CopyBox {
                  visible: !!parent.modelData.cmd
                  command: parent.modelData.cmd || ""
                  background: root.hue("darker_background", Qt.darker(root.bg, 1.35))
                  tint: root.fg
                  onCopied: function(cmd) { if (root.service) root.service.say("copied " + cmd + " — paste it into your CLI") }
                }
                Item { visible: !!parent.modelData.cmd; Layout.fillWidth: true }
                IdLinks {
                  visible: !parent.modelData.cmd
                  Layout.fillWidth: true
                  text: parent.modelData.v
                  known: root.model.byId
                  color: parent.modelData.warn ? Commons.Color.urgent : (parent.modelData.dim ? Util.alpha(root.fg, 0.55) : root.fg)
                  linkColor: parent.modelData.warn ? Commons.Color.urgent : Commons.Color.accent
                  fontSize: Style.font.bodySmall
                  italic: !!parent.modelData.dim
                  url: parent.modelData.url || ""
                  onOpen: function(id) { root.focusId(id) }
                  onOpenUrl: function(url) { root.openUrl(url) }
                }
              }
            }
          }

          // The description, on a darker panel for reading.
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Math.max(6, Style.cornerRadius)
            color: root.hue("darker_background", Qt.darker(root.bg, 1.35))
            border.width: 1
            border.color: Util.alpha(root.fg, 0.06)

            Flickable {
              id: bodyFlick
              anchors.fill: parent
              anchors.margins: Style.space(14)
              clip: true
              // Text wraps at the view; code blocks and diagrams that can't
              // wrap run wider and scroll sideways.
              contentWidth: Math.max(width, bodyText.contentWidth + Style.space(8))
              contentHeight: bodyText.implicitHeight
              flickableDirection: Flickable.AutoFlickIfNeeded
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
              ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
              SmoothWheel { vflick: bodyFlick; hflick: bodyFlick }

              MouseArea {
                width: bodyFlick.contentWidth
                height: Math.max(bodyFlick.height, bodyFlick.contentHeight)
                onClicked: root.maximized = !root.maximized
              }

              // Markdown from a tracker file: Model.safeMarkdown has already
              // turned any HTML and images into inert text.
              Text {
                id: bodyText
                width: bodyFlick.width - Style.space(8)
                textFormat: Text.MarkdownText
                text: root.selected ? Model.safeMarkdown(root.selected.body, root.codeStyle) : ""
                wrapMode: Text.Wrap
                color: root.fg
                linkColor: Commons.Color.accent
                // Prose in the desktop's sans font; Qt draws `code` and
                // fenced blocks in the system monospace font.
                font.family: "sans-serif"
                font.pixelSize: Style.font.body
                lineHeight: 1.15
              }
            }
          }

          // Which AI CLI to open in; the choice is remembered.
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)
            visible: !!root.service && root.service.agents.length > 1
            PlainLabel {
              text: "Open in"
              color: Util.alpha(root.fg, 0.5)
              font.pixelSize: Style.font.bodySmall
              height: Style.space(24)
              verticalAlignment: Text.AlignVCenter
            }
            Repeater {
              model: root.service ? root.service.agents : []
              Chip {
                required property var modelData
                label: modelData.name
                tint: root.service && root.service.agent === modelData.id ? Commons.Color.accent : root.fg
                active: !!root.service && root.service.agent === modelData.id
                interactive: true
                fontSize: Style.font.bodySmall
                onClicked: root.service.chooseAgent(modelData.id)
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: diveLabel.implicitHeight + Style.space(16)
            radius: height / 2
            color: diveDetail.containsMouse ? root.typeColor(root.selected) : Util.alpha(root.typeColor(root.selected), 0.18)
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            PlainLabel {
              id: diveLabel
              anchors.centerIn: parent
              text: "\uf120  Dive in with " + (root.service && root.service.agentName ? root.service.agentName : "the AI CLI") + "  (new terminal)"
              font.bold: true
              color: diveDetail.containsMouse ? root.bg : root.typeColor(root.selected)
            }
            MouseArea {
              id: diveDetail
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dive(root.selected)
            }
          }
        }
      }

      // The card being dragged flies above everything.
      Item { id: dragLayer; anchors.fill: parent; z: 1000 }

      NewTicketDialog {
        id: newDialog
        anchors.fill: parent
        z: 2000
        board: root
      }

      // Notice toast.
      Rectangle {
        id: toast
        property string text: ""
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Style.space(24) }
        z: 2001
        radius: height / 2
        height: toastText.implicitHeight + Style.space(16)
        width: toastText.implicitWidth + Style.space(32)
        color: root.surface
        border.width: 1
        border.color: Util.alpha(Commons.Color.accent, 0.6)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
        PlainLabel { id: toastText; anchors.centerIn: parent; text: toast.text; color: root.fg }
        Timer { id: toastTimer; interval: 3500; onTriggered: toast.opacity = 0 }
        Connections {
          target: root.service
          function onNoticeSerialChanged() {
            toast.text = root.service.notice
            toast.opacity = 1
            toastTimer.restart()
          }
        }
      }
    }
  }
}
