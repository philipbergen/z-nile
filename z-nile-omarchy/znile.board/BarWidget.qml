import QtQuick
import qs.Commons
import qs.Ui

// The bar icon: the kanban glyph and how many tickets are active. A click
// toggles the board window; right click refreshes.
BarWidget {
  id: root
  moduleName: "znile.board"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("znile.board") : null
  readonly property int activeCount: service ? service.activeCount : 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  TextMetrics {
    id: countMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: button.labelText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelText: root.activeCount > 0 ? String(root.activeCount) : ""
    slotSize: Style.bar.iconSlot + (labelText === "" ? 0 : countMetrics.advanceWidth + Style.space(4))
    tooltipText: root.service
      ? (root.service.error !== ""
        ? "znile: " + root.service.error
        : "znile: " + root.service.activeCount + " active · " + root.service.openCount + " open")
      : "znile board"
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) { if (root.service) root.service.refresh() }
      else root.bar.run("omarchy-shell shell toggle znile.board '{}'")
    }
  }
}
