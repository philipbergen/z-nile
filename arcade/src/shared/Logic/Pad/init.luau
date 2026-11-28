--!strict
-- Pad: the controller's generic folds, engine-free. No button map lives here: each place keeps its own. The left stick
-- folds into one direction a push (with hysteresis in tilt and in angle), the right stick looks at a rate, and the
-- most recently used controller drives.
export type Dir = "up" | "down" | "left" | "right"
export type Axes = "both" | "horizontal"
export type Steer = { held: Dir? } -- the sector the stick is engaged in, nil when released
export type Tuning = {
	on: number, -- tilt that engages a sector
	off: number, -- tilt below which the stick is released (and the least that takes over the controller)
	margin: number, -- degrees past the diagonal an engaged stick must turn to change sector
	axes: Axes, -- "horizontal": only left and right, folded on the x tilt alone
	lookDead: number, -- radial dead zone of the look stick
	lookYaw: number, -- radians a second at full tilt, sideways
	lookPitch: number, -- radians a second at full tilt, up and down
	invert: boolean, -- pushing up looks down
}
export type Partial = {
	on: number?,
	off: number?,
	margin: number?,
	axes: Axes?,
	lookDead: number?,
	lookYaw: number?,
	lookPitch: number?,
	invert: boolean?,
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local DEFAULT_AXES: Axes = "both"

local Pad = {}
Pad.DEFAULT = table.freeze({
	on = 0.6,
	off = 0.4,
	margin = 15,
	axes = DEFAULT_AXES,
	lookDead = 0.15,
	lookYaw = 3,
	lookPitch = 2,
	invert = false,
} :: Tuning)

function Pad.tune(over: Partial?): Tuning
	local o: Partial = over or {}
	local d = Pad.DEFAULT
	local axes: Axes = if o.axes ~= nil then o.axes else d.axes
	local t: Tuning = {
		on = if o.on ~= nil then o.on else d.on,
		off = if o.off ~= nil then o.off else d.off,
		margin = if o.margin ~= nil then o.margin else d.margin,
		axes = axes,
		lookDead = if o.lookDead ~= nil then o.lookDead else d.lookDead,
		lookYaw = if o.lookYaw ~= nil then o.lookYaw else d.lookYaw,
		lookPitch = if o.lookPitch ~= nil then o.lookPitch else d.lookPitch,
		invert = if o.invert ~= nil then o.invert else d.invert,
	}
	if not (finite(t.on) and finite(t.off) and finite(t.margin)) then
		error("Pad.tune: on, off and margin must be finite")
	end
	if not (finite(t.lookDead) and finite(t.lookYaw) and finite(t.lookPitch)) then
		error("Pad.tune: the look values must be finite")
	end
	if t.off <= 0 then
		error("Pad.tune: off must be above 0")
	end
	if t.off >= t.on then
		error("Pad.tune: off must be below on")
	end
	if t.on > 1 then
		error("Pad.tune: on must be at most 1")
	end
	if t.margin < 0 then
		error("Pad.tune: margin must not be negative")
	end
	if t.margin >= 45 then
		error("Pad.tune: margin must be below 45 degrees")
	end
	if t.axes ~= "both" and t.axes ~= "horizontal" then
		error("Pad.tune: axes must be both or horizontal")
	end
	if t.lookDead < 0 then
		error("Pad.tune: lookDead must not be negative")
	end
	if t.lookDead >= 1 then
		error("Pad.tune: lookDead must be below 1")
	end
	if t.lookYaw < 0 or t.lookPitch < 0 then
		error("Pad.tune: look rates must not be negative")
	end
	if type(t.invert) ~= "boolean" then
		error("Pad.tune: invert must be a boolean")
	end
	return table.freeze(t)
end

function Pad.isPad(inputType: string): boolean
	local n = tonumber(string.match(inputType, "^Gamepad(%d)$"))
	return n ~= nil and n >= 1 and n <= 8
end

-- The controller that drives now: an input from a controller of `magnitude` (1 for a button, the tilt for a stick)
-- takes over when it is at least the tuning's `off`; any other input keeps the one before.
function Pad.track(active: string?, inputType: string, magnitude: number, tuning: Tuning?): string?
	local t = tuning or Pad.DEFAULT
	if Pad.isPad(inputType) and finite(magnitude) and magnitude >= t.off then
		return inputType
	end
	return active
end

function Pad.steerStart(): Steer
	return { held = nil }
end

local AXIS: { [Dir]: number } = { up = 90, down = -90, left = 180, right = 0 }

local function off(x: number, y: number, held: Dir): number
	local deg = math.deg(math.atan2(y, x))
	local d = math.abs(deg - AXIS[held]) % 360
	return if d > 180 then 360 - d else d
end

local function sector(x: number, y: number): Dir
	local up: Dir, down: Dir, right: Dir, left: Dir = "up", "down", "right", "left"
	if math.abs(y) >= math.abs(x) then
		return if y >= 0 then up else down
	end
	return if x > 0 then right else left
end

local function steerX(s: Steer, x: number, t: Tuning): (Steer, Dir?)
	local r = math.abs(x)
	local right: Dir, left: Dir = "right", "left"
	local now: Dir = if x > 0 then right else left
	local held: Dir? = s.held
	if held == nil or held == "up" or held == "down" then
		if r >= t.on then
			return { held = now }, now
		end
		return { held = nil }, nil
	end
	if r < t.off then
		return { held = nil }, nil
	end
	if now ~= held then
		-- the other side: it changes at the on tilt, and short of it the stick is released (a held state never
		-- points the other way)
		if r >= t.on then
			return { held = now }, now
		end
		return { held = nil }, nil
	end
	return { held = held }, nil
end

-- One reading of the stick (x right, y up): the new state and the direction to send, if any.
function Pad.steer(s: Steer, x: number, y: number, tuning: Tuning?): (Steer, Dir?)
	local t = tuning or Pad.DEFAULT
	if not finite(x) or not finite(y) then
		return { held = nil }, nil
	end
	if t.axes == "horizontal" then
		return steerX(s, x, t)
	end
	local r = math.sqrt(x * x + y * y)
	local held: Dir? = s.held
	if held == nil then
		if r >= t.on then
			local now: Dir = sector(x, y)
			return { held = now }, now
		end
		return { held = nil }, nil
	end
	if r < t.off then
		return { held = nil }, nil
	end
	if r >= t.on and off(x, y, held) > 45 + t.margin + 1e-9 then
		local now: Dir = sector(x, y)
		return { held = now }, now
	end
	return { held = held }, nil
end

-- One reading of the look stick over `dt` seconds: the yaw and pitch to turn by, in radians (yaw positive left,
-- pitch positive up), for Look.turn.
function Pad.look(x: number, y: number, dt: number, tuning: Tuning?): (number, number)
	local t = tuning or Pad.DEFAULT
	if not finite(x) or not finite(y) or not finite(dt) or dt <= 0 then
		return 0, 0
	end
	local r = math.sqrt(x * x + y * y)
	if r <= t.lookDead then
		return 0, 0
	end
	local scaled = (math.min(r, 1) - t.lookDead) / (1 - t.lookDead)
	local a = scaled * scaled
	local dyaw = -a * (x / r) * t.lookYaw * dt
	local dpitch = a * (y / r) * t.lookPitch * dt
	return dyaw, if t.invert then -dpitch else dpitch
end

return Pad
