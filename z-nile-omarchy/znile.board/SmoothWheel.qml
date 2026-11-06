import QtQuick
import qs.Commons

// Touchpad and wheel scrolling that follows the fingers. A two-finger swipe
// moves the content by exactly the swipe (Qt's default turns each touchpad
// event into a smoothed wheel step, which lags), lifting the fingers keeps
// it gliding briefly, and a mouse wheel steps a fixed distance. Vertical
// swipes go to `vflick`, sideways ones (or Shift+wheel) to `hflick`.
WheelHandler {
  id: h

  property Flickable vflick: null
  property Flickable hflick: null
  property real wheelStep: Style.space(110)

  property real _vy: 0        // px/s, recent swipe speed
  property real _vx: 0
  property double _last: 0

  target: null
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

  function _clampY(f, y) { return Math.max(f.originY, Math.min(f.originY + Math.max(0, f.contentHeight - f.height), y)) }
  function _clampX(f, x) { return Math.max(f.originX, Math.min(f.originX + Math.max(0, f.contentWidth - f.width), x)) }

  function _glide(anim, f, prop, to) {
    anim.stop()
    anim.target = f
    anim.property = prop
    anim.to = to
    anim.start()
  }

  onWheel: function(ev) {
    var touch = ev.pixelDelta.x !== 0 || ev.pixelDelta.y !== 0
    var dx = touch ? ev.pixelDelta.x : ev.angleDelta.x / 120 * wheelStep
    var dy = touch ? ev.pixelDelta.y : ev.angleDelta.y / 120 * wheelStep
    if (!touch && (ev.modifiers & Qt.ShiftModifier)) { dx = dy; dy = 0 }

    var vertical = Math.abs(dy) >= Math.abs(dx)
    var f = vertical ? vflick : hflick
    if (!f) { ev.accepted = false; return }

    // Speed for the glide, smoothed over the last few events.
    var now = Date.now()
    var dt = now - _last
    _last = now
    var d = vertical ? dy : dx
    var v = dt > 0 && dt < 80 ? d / dt * 1000 : 0
    if (vertical) _vy = dt < 80 ? 0.6 * _vy + 0.4 * v : v
    else _vx = dt < 80 ? 0.6 * _vx + 0.4 * v : v

    if (touch) {
      glideY.stop(); glideX.stop()
      if (vertical) f.contentY = _clampY(f, f.contentY - dy)
      else f.contentX = _clampX(f, f.contentX - dx)
      // Fingers lifted (no events for a moment): glide on, easing out.
      _lastFlick = f
      _lastVertical = vertical
      lifted.restart()
    } else if (vertical) {
      var fromY = glideY.running ? glideY.to : f.contentY
      _glide(glideY, f, "contentY", _clampY(f, fromY - dy))
    } else {
      var fromX = glideX.running ? glideX.to : f.contentX
      _glide(glideX, f, "contentX", _clampX(f, fromX - dx))
    }
    ev.accepted = true
  }

  property Flickable _lastFlick: null
  property bool _lastVertical: true
  property Timer lifted: Timer {
    interval: 45
    onTriggered: {
      var f = h._lastFlick
      if (!f) return
      var vel = h._lastVertical ? h._vy : h._vx
      if (Math.abs(vel) > 150) {
        if (h._lastVertical) h._glide(h.glideY, f, "contentY", h._clampY(f, f.contentY - vel * 0.28))
        else h._glide(h.glideX, f, "contentX", h._clampX(f, f.contentX - vel * 0.28))
      }
      h._vy = 0; h._vx = 0
    }
  }

  property NumberAnimation glideY: NumberAnimation { duration: Style.duration(420); easing.type: Easing.OutCubic }
  property NumberAnimation glideX: NumberAnimation { duration: Style.duration(420); easing.type: Easing.OutCubic }
}
