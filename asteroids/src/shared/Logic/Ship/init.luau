--!strict
-- Ship: one ship's flight on the field. It turns at a fixed rate and thrusts with inertia and slight drag,
-- up to a top speed.
local Field = require("./Field")

export type Config = {
	radius: number,
	turnRate: number, -- headings a tick
	thrust: number, -- units a tick, added each thrusting tick
	drag: number, -- the share of the velocity lost each tick
	maxSpeed: number, -- units a tick
	startHeading: number,
}
export type Ship = { x: number, y: number, vx: number, vy: number, heading: number }

local Ship = {}

Ship.CLASSIC = table.freeze({
	radius = 12,
	turnRate = 3,
	thrust = 0.1,
	drag = 0.01,
	maxSpeed = 6,
	startHeading = 64,
} :: Config)

-- at rest at (x, y), pointing along the start heading
function Ship.new(c: Config, x: number, y: number): Ship
	return { x = x, y = y, vx = 0, vy = 0, heading = c.startHeading }
end

-- One tick: turn (1 to the left, -1 to the right), then thrust along the new heading, then drag, then the
-- top speed, then move and wrap.
function Ship.fly(s: Ship, c: Config, f: Field.Field, turn: number, thrust: boolean)
	s.heading = (s.heading + turn * c.turnRate) % Field.HEADINGS
	if thrust then
		local ux, uy = Field.unit(s.heading)
		s.vx += ux * c.thrust
		s.vy += uy * c.thrust
	end
	s.vx *= 1 - c.drag
	s.vy *= 1 - c.drag
	local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
	if speed > c.maxSpeed then
		s.vx = s.vx * c.maxSpeed / speed
		s.vy = s.vy * c.maxSpeed / speed
	end
	s.x, s.y = Field.wrap(f, s.x + s.vx, s.y + s.vy)
end

-- the tip of the ship, where its shots start
function Ship.nose(s: Ship, c: Config, f: Field.Field): (number, number)
	local ux, uy = Field.unit(s.heading)
	return Field.wrap(f, s.x + ux * c.radius, s.y + uy * c.radius)
end

return Ship
