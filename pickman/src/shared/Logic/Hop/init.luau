--!strict
-- Hop: the spy hop (f0101), engine-free and counted in steps, so the server and the camera agree on it. A hop
-- lifts the eye on a parabola and lands again; while the eye is above the wall tops the player is airborne:
-- no ghost catches them, they eat nothing, and they pass over a frightened ghost.

local Hop = {}
Hop.INTENT = "Hop" -- the wire string on the Intent remote ("Jump" stays an invalid intent)
Hop.RISE = 14 -- studs the eye rises at the top of a hop
Hop.TICKS = 12 -- steps from take-off to landing (0.8 s of real time at Session.STEP_RATE 15)
Hop.COOLDOWN = 8 -- steps after landing before the next hop (0.53 s; the user's 0.5 s, never shorter)
Hop.CLEARANCE = 5 -- studs of rise that put the eye above the wall tops (View.SCALE: wall 9 - eye 4)
Hop.LONG_TICKS = 19 -- a long hop (f0126's "longer jumps" boon): airborne 15 steps, 1.5 times the 10 of a hop

function Hop.isIntent(raw: any): boolean
	return raw == Hop.INTENT
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A hop's length in steps: `ticks` when it is a whole number of at least 1, else Hop.TICKS.
local function lengthOf(ticks: number?): number
	if finite(ticks) and (ticks :: number) >= 1 and ticks == math.floor(ticks :: number) then
		return ticks :: number
	end
	return Hop.TICKS
end

-- May a hop start at step `tick`, the last having started at `last` (nil: never)? A last that is nil or not
-- finite never blocks; a tick that is not finite never starts one.
function Hop.canStart(last: number?, tick: number, ticks: number?): boolean
	if not finite(tick) then
		return false
	end
	if last == nil or not finite(last) then
		return true
	end
	return tick >= last + lengthOf(ticks) + Hop.COOLDOWN
end

-- Studs above the standing eye at time `t` (in steps, fractional for a rendered frame): RISE * 4u(1 - u) for
-- u = (t - last) / TICKS strictly inside (0, 1), else 0; 0 when last is nil or either value is not finite.
function Hop.rise(last: number?, t: number, ticks: number?): number
	if last == nil or not finite(last) or not finite(t) then
		return 0
	end
	local u = (t - last) / lengthOf(ticks)
	if u <= 0 or u >= 1 then
		return 0
	end
	return Hop.RISE * 4 * u * (1 - u)
end

-- Studs above the standing eye at time `t` (in steps, fractional) while a run waits for play to start at step
-- `playAt` (f0234: the READY pause of a run, a life or a level): Hop.RISE, the top of a hop, until half a hop
-- before `playAt`, then the descent of a hop of Hop.TICKS that lands at `playAt` (Hop.rise of one that took off
-- Hop.TICKS before it), and 0 from `playAt` on; 0 when `playAt` is nil or either value is not finite.
function Hop.held(playAt: number?, t: number): number
	if playAt == nil or not finite(playAt) or not finite(t) then
		return 0
	end
	if playAt - t >= Hop.TICKS / 2 then
		return Hop.RISE
	end
	return Hop.rise(playAt - Hop.TICKS, t)
end

-- Whether the player is airborne during step `tick`: the eye is above the wall tops in the middle of the step.
-- Step N moves the world from tick N - 1 to tick N, and the camera shows it while the shown tick runs over that
-- span, so the rule samples the rise at N - 0.5 (steps 2 to 11 of a hop; off from the drawn eye by at most 0.19
-- of a step, always in the player's favour).
function Hop.airborne(last: number?, tick: number, ticks: number?): boolean
	return Hop.rise(last, tick - 0.5, ticks) > Hop.CLEARANCE
end

return Hop
