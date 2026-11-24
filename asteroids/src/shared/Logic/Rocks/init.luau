--!strict
-- Rocks: the three sizes, their points and speeds, and how a hit one splits. A rock drifts in a straight
-- line and wraps; a large one splits into 2 medium, a medium into 2 small, and a small one is destroyed.
local Field = require("./Field")

export type SizeName = "large" | "medium" | "small"
export type Size = {
	radius: number,
	points: number,
	speedMin: number,
	speedMax: number,
	splitsInto: SizeName?,
	pieces: number,
}
export type Rock = { id: number, size: SizeName, x: number, y: number, vx: number, vy: number }
export type Draw = (n: number) -> number -- a whole number in 1..n

local Rocks = {}

Rocks.SIZES = table.freeze({
	large = table.freeze(
		{ radius = 40, points = 20, speedMin = 0.75, speedMax = 1.5, splitsInto = "medium", pieces = 2 } :: Size
	),
	medium = table.freeze(
		{ radius = 20, points = 50, speedMin = 1, speedMax = 2.25, splitsInto = "small", pieces = 2 } :: Size
	),
	small = table.freeze(
		{ radius = 10, points = 100, speedMin = 1.25, speedMax = 3, splitsInto = nil, pieces = 0 } :: Size
	),
})
Rocks.SPEED_STEPS = 8

-- the speed of a size's step (1..SPEED_STEPS), from its slowest to its fastest
function Rocks.speed(size: SizeName, step: number): number
	local s = Rocks.SIZES[size]
	return s.speedMin + (s.speedMax - s.speedMin) * (step - 1) / (Rocks.SPEED_STEPS - 1)
end

-- a rock at (x, y) with a drawn heading, then a drawn speed step
function Rocks.launch(id: number, size: SizeName, x: number, y: number, draw: Draw): Rock
	local heading = draw(Field.HEADINGS) - 1
	local speed = Rocks.speed(size, draw(Rocks.SPEED_STEPS))
	local ux, uy = Field.unit(heading)
	return { id = id, size = size, x = x, y = y, vx = ux * speed, vy = uy * speed }
end

-- the pieces a hit rock leaves, at its centre, numbered from firstId
function Rocks.split(r: Rock, firstId: number, draw: Draw): { Rock }
	local s = Rocks.SIZES[r.size]
	local out = {}
	local into = s.splitsInto
	if into then
		for i = 1, s.pieces do
			table.insert(out, Rocks.launch(firstId + i - 1, into, r.x, r.y, draw))
		end
	end
	return out
end

function Rocks.move(r: Rock, f: Field.Field)
	r.x, r.y = Field.wrap(f, r.x + r.vx, r.y + r.vy)
end

return Rocks
