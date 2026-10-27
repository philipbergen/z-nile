--!strict
-- Touch: the phone's gestures as a pure fold over begin, move and end events, engine-free. A finger is
-- classified once, when it goes down: the snap control, the fire or the hop button (f0110), the turn half (left)
-- or the look half (right).
-- A turn finger is one straight-line swipe on release; a look finger is a pixel step per move.
--
-- Every point and rectangle here is in screen pixels (origin the top-left of the device screen).
local Hud = require("./Hud")
local View = require("./View")

export type Zone = "turn" | "look" | "snap" | "fire" | "hop"
export type Rect = { x: number, y: number, w: number, h: number } -- half-open [x, x+w) x [y, y+h)
export type Phase = "begin" | "move" | "end"
export type Event = { id: number, phase: Phase, x: number, y: number }
export type Finger = { zone: Zone, x0: number, y0: number, x: number, y: number }
export type State = { fingers: { [number]: Finger } }
export type Turn = "Left" | "Right" | "Back" | "Forward"
export type Effect =
	{ kind: "turn", intent: Turn }
	| { kind: "look", dx: number, dy: number }
	| { kind: "snap" }
	| { kind: "fire" }
	| { kind: "hop" }
export type Context = { width: number, snap: Rect?, fire: Rect?, hop: Rect? }
-- The touch controls' rectangles, as Touch.buttons places them.
export type Buttons = { snap: Rect, fire: Rect, hop: Rect }
-- Min/Max, the shape of an inset area.
export type Area = { Min: { X: number, Y: number }, Max: { X: number, Y: number } }
-- The HUD's sizes and its safe rectangle, as Hud.layout reports them.
export type Box = {
	margin: number,
	iconSize: number,
	textSize: number,
	barWidth: number,
	barHeight: number,
	safeX: number,
	safeY: number,
	safeW: number,
	safeH: number,
}

local Touch = {}
Touch.MIN_SWIPE = 48 -- px, straight line from finger-down to finger-up
Touch.AXIS_DEGREES = 30 -- the cone around each screen axis
Touch.MIN_TARGET = 44 -- px, the smallest side of a touch control

local function finite(v: number): boolean
	return v == v and math.abs(v) ~= math.huge
end

function Touch.empty(): State
	return { fingers = {} }
end

local function inside(r: Rect?, x: number, y: number): boolean
	return r ~= nil and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

function Touch.zone(width: number, x: number, y: number, snap: Rect?, fire: Rect?, hop: Rect?): Zone
	if inside(snap, x, y) then
		return "snap"
	end
	if inside(fire, x, y) then
		return "fire"
	end
	if inside(hop, x, y) then
		return "hop"
	end
	if finite(width) and width > 0 and x < width / 2 then
		return "turn"
	end
	return "look"
end

-- The intent of a straight-line swipe from finger-down to finger-up, or nil. Screen-down is Back.
function Touch.swipe(dx: number, dy: number): Turn?
	if not finite(dx) or not finite(dy) then
		return nil
	end
	if math.sqrt(dx * dx + dy * dy) < Touch.MIN_SWIPE then
		return nil
	end
	local angle = math.atan2(math.abs(dy), math.abs(dx)) -- 0 horizontal .. pi/2 vertical
	local fromAxis = math.min(angle, math.pi / 2 - angle)
	-- the epsilon absorbs the ulps of a vector built at exactly the cone's edge
	if fromAxis > math.rad(Touch.AXIS_DEGREES) + 1e-9 then
		return nil
	end
	local key = if angle <= math.pi / 4 then (if dx < 0 then "A" else "D") else (if dy > 0 then "S" else "W")
	return View.action(key) :: Turn
end

-- Folds one event into a fresh state and the effects it causes. The given state is never changed.
function Touch.track(state: State, event: Event, ctx: Context): (State, { Effect })
	local fingers: { [number]: Finger } = table.clone(state.fingers)
	local effects: { Effect } = {}
	local finger: Finger? = fingers[event.id]
	if event.phase == "begin" then
		if finger == nil then
			local zone: Zone = Touch.zone(ctx.width, event.x, event.y, ctx.snap, ctx.fire, ctx.hop)
			local taken = false
			for _, f in fingers do
				taken = taken or f.zone == zone
			end
			if not taken then
				fingers[event.id] = { zone = zone, x0 = event.x, y0 = event.y, x = event.x, y = event.y }
				if zone == "snap" then
					table.insert(effects, { kind = "snap" })
				elseif zone == "fire" then
					table.insert(effects, { kind = "fire" })
				elseif zone == "hop" then
					table.insert(effects, { kind = "hop" })
				end
			end
		end
	elseif event.phase == "move" then
		if finger then
			local moved: Finger =
				{ zone = finger.zone, x0 = finger.x0, y0 = finger.y0, x = event.x, y = event.y }
			fingers[event.id] = moved
			if finger.zone == "look" then
				table.insert(effects, { kind = "look", dx = event.x - finger.x, dy = event.y - finger.y })
			end
		end
	elseif event.phase == "end" then
		if finger then
			fingers[event.id] = nil
			if finger.zone == "turn" then
				local intent: Turn? = Touch.swipe(event.x - finger.x0, event.y - finger.y0)
				if intent then
					local turn: Effect = { kind = "turn", intent = intent }
					table.insert(effects, turn)
				end
			end
		end
	end
	return { fingers = fingers }, effects
end

-- An input position (measured from the core-UI area's top-left) in screen pixels. A nil area is the
-- identity; a non-finite origin component counts as 0 on its axis.
function Touch.toScreen(none: Area?, x: number, y: number): (number, number)
	if none == nil then
		return x, y
	end
	local ox = if finite(none.Min.X) then none.Min.X else 0
	local oy = if finite(none.Min.Y) then none.Min.Y else 0
	return x - ox, y - oy
end

-- The four HUD blocks in the margin bands of the safe rectangle: score top-left, level top-right, lives
-- bottom-left, the power bar bottom-right.
function Touch.blocks(box: Box): { score: Rect, level: Rect, lives: Rect, power: Rect }
	local x, y, w, h, m = box.safeX, box.safeY, box.safeW, box.safeH, box.margin
	local half = math.max(0, w / 2 - 2 * m)
	return {
		score = { x = x + m, y = y + m, w = half, h = box.textSize },
		level = { x = x + w / 2 + m, y = y + m, w = half, h = box.textSize },
		lives = { x = x + m, y = y + h - m - box.iconSize, w = math.max(0, w / 2 - m), h = box.iconSize },
		power = {
			x = x + w - m - box.barWidth,
			y = y + h - m - box.barHeight,
			w = box.barWidth,
			h = box.barHeight,
		},
	}
end

-- The snap control: a square of at least MIN_TARGET, bottom-aligned, one margin left of the power bar. It has
-- one placement; it never climbs into the forward view.
function Touch.snapRect(box: Box): Rect
	local side = math.max(Touch.MIN_TARGET, box.iconSize)
	return {
		x = box.safeX + box.safeW - 2 * box.margin - box.barWidth - side,
		y = box.safeY + box.safeH - box.margin - side,
		w = side,
		h = side,
	}
end

-- The hop button (f0110): Roblox's legacy touch jump button, in the safe rectangle (the touch GUI's frame).
function Touch.hopRect(box: Box): Rect
	local b = Hud.jumpButtons(box.safeX, box.safeY, box.safeW, box.safeH)[1]
	return { x = b.x, y = b.y, w = b.w, h = b.h }
end

-- The fire button (f0110): the hop button's size, one margin left of it, level with it unless that would
-- reach the snap control's band: then its bottom is one margin above the snap control's top.
function Touch.fireRect(box: Box): Rect
	local hop = Touch.hopRect(box)
	local snap = Touch.snapRect(box)
	local side = hop.w
	return {
		x = hop.x - box.margin - side,
		y = math.min(hop.y, snap.y - box.margin - side),
		w = side,
		h = side,
	}
end

-- Every touch control's rectangle.
function Touch.buttons(box: Box): Buttons
	return { snap = Touch.snapRect(box), fire = Touch.fireRect(box), hop = Touch.hopRect(box) }
end

-- The screen's size from the full-screen area, or the fallback while that area is empty or bad.
function Touch.screenSize(none: Area?, fallbackW: number, fallbackH: number): (number, number)
	if none then
		local w = none.Max.X - none.Min.X
		local h = none.Max.Y - none.Min.Y
		if finite(w) and finite(h) and w > 0 and h > 0 then
			return w, h
		end
	end
	return fallbackW, fallbackH
end

return Touch
