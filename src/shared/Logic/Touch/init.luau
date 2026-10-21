--!strict
-- Touch: the phone's gestures as a pure fold over begin, move and end events, engine-free. A finger is
-- classified once, when it goes down: the snap control, the turn half (left) or the look half (right).
-- A turn finger is one straight-line swipe on release; a look finger is a pixel step per move.
--
-- Every point and rectangle here is in screen pixels (origin the top-left of the device screen).
local View = require("./View")

export type Zone = "turn" | "look" | "snap"
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
export type Context = { width: number, snap: Rect? }
-- Min/Max, the shape of an inset area.
export type Area = { Min: { X: number, Y: number }, Max: { X: number, Y: number } }

local Touch = {}
Touch.MIN_SWIPE = 48 -- px, straight line from finger-down to finger-up
Touch.AXIS_DEGREES = 30 -- the cone around each screen axis

local function finite(v: number): boolean
	return v == v and math.abs(v) ~= math.huge
end

function Touch.empty(): State
	return { fingers = {} }
end

function Touch.zone(width: number, x: number, y: number, snap: Rect?): Zone
	if snap and x >= snap.x and y >= snap.y and x < snap.x + snap.w and y < snap.y + snap.h then
		return "snap"
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
			local zone: Zone = Touch.zone(ctx.width, event.x, event.y, ctx.snap)
			local taken = false
			for _, f in fingers do
				taken = taken or f.zone == zone
			end
			if not taken then
				fingers[event.id] = { zone = zone, x0 = event.x, y0 = event.y, x = event.x, y = event.y }
				if zone == "snap" then
					table.insert(effects, { kind = "snap" })
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
