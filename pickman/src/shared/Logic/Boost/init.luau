--!strict
-- Boost: the speed boost escape (f0143), engine-free and counted in steps, so the server and the camera agree on
-- it. A boost raises the player's step to FACTOR times the level's speed (never more than a tile a step) for TICKS
-- steps, then cools down. It mirrors Hop (an intent, a span counted in steps, a cooldown). The double tap that asks
-- for it is a client gesture folded here over real seconds (Boost.tap); the server only sees the intent.

export type Status = "ready" | "boosting" | "cooling"
export type Taps = { last: number? } -- real seconds of the last unpaired forward press

local Boost = {}
Boost.INTENT = "Boost" -- the wire string on the Intent remote
Boost.FACTOR = 1.5 -- G2: the boosted step covers round(speed * FACTOR) units
Boost.TICKS = 22 -- G3: steps a boost lasts (1.47 s of real time at Session.STEP_RATE 15)
Boost.COOLDOWN = 90 -- G4: steps after a boost ends before the next may start (6 s of real time)
Boost.WINDOW = 0.3 -- G1: real seconds from one forward press to the next that make a double tap
Boost.FOV = 8 -- G6: degrees the camera's field of view widens while boosting
Boost.RAMP = 2 -- G6: steps the widening takes at each end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function round(v: number): number
	return math.floor(v + 0.5)
end

function Boost.isIntent(raw: any): boolean
	return raw == Boost.INTENT
end

-- May a boost start at step `tick`, the last having started at `last` (nil: never)? A last that is nil or not
-- finite never blocks; a tick that is not finite never starts one.
function Boost.canStart(last: number?, tick: number): boolean
	if not finite(tick) then
		return false
	end
	if last == nil or not finite(last) then
		return true
	end
	return tick >= last + Boost.TICKS + Boost.COOLDOWN
end

-- Whether step `tick` is boosted: the starting step and the TICKS - 1 after it.
function Boost.active(last: number?, tick: number): boolean
	if last == nil or not finite(last) or not finite(tick) then
		return false
	end
	return last <= tick and tick < last + Boost.TICKS
end

-- The step's speed: round(speed * FACTOR) when active, never more than `cap` (a tile a step); else `speed`.
function Boost.speed(speed: number, active: boolean, cap: number): number
	if not active then
		return speed
	end
	return math.min(round(speed * Boost.FACTOR), cap)
end

-- What the HUD says at the frame of step `tick`: boosting while that step is boosted, ready when a boost asked now
-- would start in the next step, else cooling.
function Boost.status(last: number?, tick: number): Status
	if Boost.active(last, tick) then
		return "boosting"
	elseif Boost.canStart(last, tick + 1) then
		return "ready"
	end
	return "cooling"
end

function Boost.taps(): Taps
	return { last = nil }
end

-- Folds a forward press at `now` (real seconds, the client's clock). A press within WINDOW of the remembered one is
-- a double tap: it returns true and forgets both, so a triple tap boosts once. A first press, or one after the
-- window, is remembered. A press at a non-finite time, or earlier than the remembered one (a clock that went
-- back), returns false and remembers nothing, so it can never pair.
function Boost.tap(t: Taps, now: number): (Taps, boolean)
	if not finite(now) then
		return { last = nil }, false
	end
	local last = t.last
	if last == nil then
		return { last = now }, false
	end
	if now < last then
		return { last = nil }, false
	end
	if now - last <= Boost.WINDOW then
		return { last = nil }, true
	end
	return { last = now }, false
end

-- Degrees the field of view widens at shown tick `t` (fractional). Step N moves the world from shown tick N - 1 to
-- N, so a boost started in step `last` is fast over the shown ticks last - 1 to last + TICKS - 1: with
-- u = t - (last - 1) steps, 0 outside [0, TICKS), else FOV ramped over RAMP steps at each end.
function Boost.fov(last: number?, t: number): number
	if last == nil or not finite(last) or not finite(t) then
		return 0
	end
	local u = t - (last - 1)
	if u < 0 or u >= Boost.TICKS then
		return 0
	end
	return Boost.FOV * math.min(1, u / Boost.RAMP, (Boost.TICKS - u) / Boost.RAMP)
end

return Boost
