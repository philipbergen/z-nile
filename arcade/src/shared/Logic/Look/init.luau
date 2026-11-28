--!strict
-- Look: first-person free look and smoothing, engine-free (numbers in, numbers out). A look is a yaw and a pitch in
-- radians relative to the heading; a positive yaw turns left and a positive pitch looks up.
export type Look = { yaw: number, pitch: number }
export type Arrows = { up: boolean, down: boolean, left: boolean, right: boolean }
export type Dir = "up" | "down" | "left" | "right"
-- the look and whether it is springing back to the heading (after the arrows were let go)
export type Spring = { look: Look, spring: boolean }
export type Tuning = {
	radiansPerPixel: number, -- the mouse's (and a touch drag's) turn per pixel
	maxPitch: number, -- radians up or down
	turnSeconds: number, -- seconds per quarter turn: the eased turn's, the arrows' and the spring's rate
}
export type Partial = { radiansPerPixel: number?, maxPitch: number?, turnSeconds: number? }

local PI = math.pi
local TAU = 2 * math.pi

local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) ~= math.huge
end

local Look = {}
Look.DEFAULT =
	table.freeze({ radiansPerPixel = 0.004, maxPitch = math.rad(80), turnSeconds = 0.12 } :: Tuning)

function Look.tune(over: Partial?): Tuning
	local o: Partial = over or {}
	local d = Look.DEFAULT
	local t: Tuning = {
		radiansPerPixel = if o.radiansPerPixel ~= nil then o.radiansPerPixel else d.radiansPerPixel,
		maxPitch = if o.maxPitch ~= nil then o.maxPitch else d.maxPitch,
		turnSeconds = if o.turnSeconds ~= nil then o.turnSeconds else d.turnSeconds,
	}
	if not (finite(t.radiansPerPixel) and finite(t.maxPitch) and finite(t.turnSeconds)) then
		error("Look.tune: every value must be finite")
	end
	if t.radiansPerPixel <= 0 then
		error("Look.tune: radiansPerPixel must be above 0")
	end
	if t.maxPitch <= 0 then
		error("Look.tune: maxPitch must be above 0")
	end
	if t.maxPitch > PI / 2 then
		error("Look.tune: maxPitch must be at most pi/2")
	end
	if t.turnSeconds <= 0 then
		error("Look.tune: turnSeconds must be above 0")
	end
	return table.freeze(t)
end

-- An angle in (-pi, pi].
function Look.wrap(a: number): number
	local r = (a + PI) % TAU - PI
	if r == -PI then
		return PI
	end
	return r
end

-- `current` moved toward `target` the short way round by at most `maxDelta`, wrapped.
function Look.approach(current: number, target: number, maxDelta: number): number
	local diff = Look.wrap(target - current)
	if math.abs(diff) <= maxDelta then
		return Look.wrap(target)
	end
	return Look.wrap(current + (if diff > 0 then maxDelta else -maxDelta))
end

-- radians a second: a quarter turn in turnSeconds
function Look.rate(tuning: Tuning?): number
	local t = tuning or Look.DEFAULT
	return (PI / 2) / t.turnSeconds
end

local function step(dt: number, t: Tuning): number
	return Look.rate(t) * (if finite(dt) and dt > 0 then dt else 0)
end

-- The eased turn: a yaw `dt` seconds on toward `target` at Look.rate. With no yaw yet (nil) it is the target.
function Look.ease(current: number?, target: number, dt: number, tuning: Tuning?): number
	local t = tuning or Look.DEFAULT
	if current == nil or not finite(current) then
		return Look.wrap(target)
	end
	return Look.approach(current, target, step(dt, t))
end

local function clampPitch(p: number, t: Tuning): number
	return math.clamp(p, -t.maxPitch, t.maxPitch)
end

-- A mouse or drag of dx, dy pixels (screen right and down): right turns right, down looks down.
function Look.mouse(l: Look, dx: number, dy: number, tuning: Tuning?): Look
	local t = tuning or Look.DEFAULT
	if not finite(dx) or not finite(dy) then
		return { yaw = l.yaw, pitch = l.pitch }
	end
	local k = t.radiansPerPixel
	return { yaw = Look.wrap(l.yaw - dx * k), pitch = clampPitch(l.pitch - dy * k, t) }
end

-- A turn by radians (Pad.look's): yaw positive left, pitch positive up.
function Look.turn(l: Look, dyaw: number, dpitch: number, tuning: Tuning?): Look
	local t = tuning or Look.DEFAULT
	if not finite(dyaw) or not finite(dpitch) then
		return { yaw = l.yaw, pitch = l.pitch }
	end
	return { yaw = Look.wrap(l.yaw + dyaw), pitch = clampPitch(l.pitch + dpitch, t) }
end

function Look.snap(): Look
	return { yaw = 0, pitch = 0 }
end

function Look.rest(): Spring
	return { look = { yaw = 0, pitch = 0 }, spring = false }
end

function Look.arrows(): Arrows
	return { up = false, down = false, left = false, right = false }
end

-- The arrows held after `dir` went down (true) or up (false). A nil dir leaves them as they are.
function Look.press(a: Arrows, dir: Dir?, down: boolean): Arrows
	return {
		up = if dir == "up" then down else a.up,
		down = if dir == "down" then down else a.down,
		left = if dir == "left" then down else a.left,
		right = if dir == "right" then down else a.right,
	}
end

-- Where the held arrows look, in quarter turns from the heading, positive left: up 0, left 1, right -1, down 2;
-- two together give the half quarters between. Opposite arrows cancel. Nil when none is held.
function Look.quarters(a: Arrows): number?
	if not (a.up or a.down or a.left or a.right) then
		return nil
	end
	local side = (if a.left then 1 else 0) - (if a.right then 1 else 0)
	local ahead = (if a.up then 1 else 0) - (if a.down then 1 else 0)
	if side == 0 then
		return if ahead < 0 then 2 else 0
	end
	if ahead == 0 then
		return side
	end
	if ahead > 0 then
		return side * 0.5
	end
	return side * 1.5
end

-- One frame of the arrow look, after any other look input has moved `look`. While an arrow is held the look turns
-- from prev.look toward the arrows (pitch level) at Look.rate; once they are let go it springs back to the heading
-- at the same rate, until anything else moves the look, which takes over from there.
function Look.spring(prev: Spring, look: Look, a: Arrows, dt: number, tuning: Tuning?): Spring
	local t = tuning or Look.DEFAULT
	local s = step(dt, t)
	local function toward(from: Look, target: Look): Look
		local dp = math.clamp(target.pitch - from.pitch, -s, s)
		return { yaw = Look.approach(from.yaw, target.yaw, s), pitch = from.pitch + dp }
	end
	local q = Look.quarters(a)
	if q ~= nil then
		return { look = toward(prev.look, { yaw = Look.wrap(q * PI / 2), pitch = 0 }), spring = true }
	end
	if look.yaw ~= prev.look.yaw or look.pitch ~= prev.look.pitch then
		return { look = { yaw = look.yaw, pitch = look.pitch }, spring = false }
	end
	if prev.spring then
		local back = toward(look, { yaw = 0, pitch = 0 })
		return { look = back, spring = not (back.yaw == 0 and back.pitch == 0) }
	end
	return { look = { yaw = look.yaw, pitch = look.pitch }, spring = false }
end

-- How far between two snapshots the screen is, `elapsed` seconds after the later one arrived, at `rate` snapshots a
-- second: in 0..1, and 1 for a value that is not a number.
function Look.alpha(elapsed: number, rate: number): number
	local a = elapsed * rate
	if a ~= a then
		return 1
	end
	return math.clamp(a, 0, 1)
end

-- A value between `from` and `to` at blend `alpha` (clamped to 0..1; not a number is 1).
function Look.blend(from: number, to: number, alpha: number): number
	local a = if alpha ~= alpha then 1 else math.clamp(alpha, 0, 1)
	return from + (to - from) * a
end

-- An angle between `from` and `to` the short way round, wrapped.
function Look.blendYaw(from: number, to: number, alpha: number): number
	local a = if alpha ~= alpha then 1 else math.clamp(alpha, 0, 1)
	return Look.wrap(from + Look.wrap(to - from) * a)
end

return Look
