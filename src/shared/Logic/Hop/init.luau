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

function Hop.isIntent(raw: any): boolean
	return raw == Hop.INTENT
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- May a hop start at step `tick`, the last having started at `last` (nil: never)? A last that is nil or not
-- finite never blocks; a tick that is not finite never starts one.
function Hop.canStart(last: number?, tick: number): boolean
	if not finite(tick) then
		return false
	end
	if last == nil or not finite(last) then
		return true
	end
	return tick >= last + Hop.TICKS + Hop.COOLDOWN
end

-- Studs above the standing eye at time `t` (in steps, fractional for a rendered frame): RISE * 4u(1 - u) for
-- u = (t - last) / TICKS strictly inside (0, 1), else 0; 0 when last is nil or either value is not finite.
function Hop.rise(last: number?, t: number): number
	if last == nil or not finite(last) or not finite(t) then
		return 0
	end
	local u = (t - last) / Hop.TICKS
	if u <= 0 or u >= 1 then
		return 0
	end
	return Hop.RISE * 4 * u * (1 - u)
end

-- Whether the player is airborne during step `tick`: the eye is above the wall tops in the middle of the step.
-- Step N moves the world from tick N - 1 to tick N, and the camera shows it while the shown tick runs over that
-- span, so the rule samples the rise at N - 0.5 (steps 2 to 11 of a hop; off from the drawn eye by at most 0.19
-- of a step, always in the player's favour).
function Hop.airborne(last: number?, tick: number): boolean
	return Hop.rise(last, tick - 0.5) > Hop.CLEARANCE
end

return Hop
