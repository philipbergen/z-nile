--!strict
-- Touch: the phone's gestures as a pure fold over begin, move and end events, engine-free. A finger is classified
-- once, when it goes down: a named button (the first in the context's list that holds the point), else the screen's
-- left or right half, each used for swipes, for looking, or for nothing. A button sends a press when its finger goes
-- down and a release when it comes up; a swipe finger sends one straight-line swipe on release; a look finger sends a
-- pixel step per move. One finger holds a zone at a time.
--
-- Every point and rectangle is in screen pixels (origin the top-left of the device screen).
export type Rect = { x: number, y: number, w: number, h: number } -- half-open [x, x+w) x [y, y+h)
export type Use = "swipe" | "look" | "none"
export type Side = "left" | "right"
export type Button = { name: string, rect: Rect }
export type Context = { width: number, buttons: { Button }, left: Use, right: Use }
export type Phase = "begin" | "move" | "end"
export type Event = { id: number, phase: Phase, x: number, y: number }
export type Dir = "up" | "down" | "left" | "right"
export type Finger = { button: string?, side: Side?, use: Use, x0: number, y0: number, x: number, y: number }
export type State = { fingers: { [number]: Finger } }
export type Effect =
	{ kind: "press", name: string }
	| { kind: "release", name: string }
	| { kind: "swipe", dir: Dir }
	| { kind: "look", dx: number, dy: number }
-- Min/Max, the shape of an inset area.
export type Area = { Min: { X: number, Y: number }, Max: { X: number, Y: number } }

local Touch = {}
Touch.MIN_SWIPE = 48 -- px, straight line from finger-down to finger-up
Touch.AXIS_DEGREES = 30 -- the cone around each screen axis
Touch.MIN_TARGET = 44 -- px, the smallest side of a touch control

local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) ~= math.huge
end

function Touch.empty(): State
	return { fingers = {} }
end

function Touch.inside(r: Rect?, x: number, y: number): boolean
	return r ~= nil and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

-- What a finger down at (x, y) is: a button's name, or the half it is in and that half's use.
function Touch.zone(ctx: Context, x: number, y: number): (string?, Side, Use)
	local side: Side = if finite(ctx.width)
			and ctx.width > 0
			and x < ctx.width / 2
		then "left" :: Side
		else "right" :: Side
	local none: Use = "none"
	for _, b in ctx.buttons do
		if Touch.inside(b.rect, x, y) then
			return b.name, side, none
		end
	end
	local use: Use = if side == "left" then ctx.left else ctx.right
	return nil, side, use
end

-- The direction of a straight-line swipe from finger-down to finger-up, or nil. Screen-down is "down".
function Touch.swipe(dx: number, dy: number): Dir?
	if not finite(dx) or not finite(dy) then
		return nil
	end
	if math.sqrt(dx * dx + dy * dy) < Touch.MIN_SWIPE then
		return nil
	end
	local angle = math.atan2(math.abs(dy), math.abs(dx)) -- 0 horizontal .. pi/2 vertical
	local fromAxis = math.min(angle, math.pi / 2 - angle)
	if fromAxis > math.rad(Touch.AXIS_DEGREES) + 1e-9 then
		return nil
	end
	if angle <= math.pi / 4 then
		local h: Dir = if dx < 0 then "left" :: Dir else "right" :: Dir
		return h
	end
	local v: Dir = if dy > 0 then "down" :: Dir else "up" :: Dir
	return v
end

local function same(a: Finger, button: string?, side: Side): boolean
	if button ~= nil then
		return a.button == button
	end
	return a.button == nil and a.side == side
end

-- Folds one event into a fresh state and the effects it causes. The given state is never changed.
function Touch.track(state: State, event: Event, ctx: Context): (State, { Effect })
	local fingers: { [number]: Finger } = table.clone(state.fingers)
	local effects: { Effect } = {}
	local finger: Finger? = fingers[event.id]
	-- a begin or a move at a point that is not a number is dropped; an end always lifts its finger (no swipe)
	local bad = not finite(event.x) or not finite(event.y)
	local phase: Phase = event.phase
	if bad then
		if phase ~= "end" then
			return { fingers = fingers }, effects
		end
	end
	if phase == "begin" then
		if finger == nil then
			local button: string?, side: Side, use: Use = Touch.zone(ctx, event.x, event.y)
			if button ~= nil or use ~= "none" then
				local taken = false
				for _, f in fingers do
					taken = taken or same(f, button, side)
				end
				if not taken then
					fingers[event.id] = {
						button = button,
						side = side,
						use = use,
						x0 = event.x,
						y0 = event.y,
						x = event.x,
						y = event.y,
					}
					if button ~= nil then
						local pressed: Effect = { kind = "press", name = button }
						table.insert(effects, pressed)
					end
				end
			end
		end
	elseif phase == "move" then
		if finger then
			fingers[event.id] = {
				button = finger.button,
				side = finger.side,
				use = finger.use,
				x0 = finger.x0,
				y0 = finger.y0,
				x = event.x,
				y = event.y,
			}
			if finger.button == nil and finger.use == "look" then
				local moved: Effect = { kind = "look", dx = event.x - finger.x, dy = event.y - finger.y }
				table.insert(effects, moved)
			end
		end
	elseif phase == "end" then
		if finger then
			fingers[event.id] = nil
			if finger.button ~= nil then
				local released: Effect = { kind = "release", name = finger.button }
				table.insert(effects, released)
			elseif finger.use == "swipe" then
				local dir: Dir? = Touch.swipe(event.x - finger.x0, event.y - finger.y0)
				if dir ~= nil then
					local swiped: Effect = { kind = "swipe", dir = dir }
					table.insert(effects, swiped)
				end
			end
		end
	end
	return { fingers = fingers }, effects
end

-- Every finger lifted at once (the screen went away, the player respawned): a release for each held button, in
-- finger id order, and an empty state. No swipe is sent.
function Touch.reset(state: State): (State, { Effect })
	local ids: { number } = {}
	for id in state.fingers do
		table.insert(ids, id)
	end
	table.sort(ids)
	local effects: { Effect } = {}
	for _, id in ids do
		local b = state.fingers[id].button
		if b ~= nil then
			local released: Effect = { kind = "release", name = b }
			table.insert(effects, released)
		end
	end
	return { fingers = {} }, effects
end

-- An input position (measured from the core-UI area's top-left) in screen pixels. A nil area is the identity; a
-- non-finite origin component counts as 0 on its axis.
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
