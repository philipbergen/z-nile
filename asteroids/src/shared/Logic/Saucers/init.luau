--!strict
-- Saucers: the large saucer (200), which fires at random, and the small one (1,000), which aims at the ship,
-- more closely as the score rises, and comes more often in later waves. A saucer crosses the field edge to
-- edge, wrapping only up and down, and changes its course now and then.
local Field = require("./Field")

export type Kind = "large" | "small"
export type KindConfig = { radius: number, points: number, speed: number, fireTicks: number, aimed: boolean }
export type Config = {
	large: KindConfig,
	small: KindConfig,
	firstWait: number, -- ticks without a saucer before one appears, in wave 1
	waitStep: number, -- how much shorter the wait is each later wave
	minWait: number,
	smallEighths: { number }, -- by wave (the last entry for every wave after): the small saucer's share, in eighths
	turnTicks: number, -- ticks between course changes
	shotSpeed: number,
	shotLife: number,
	spread: { { score: number, spread: number } }, -- the small saucer's aim error, in headings, from a score up
}
export type Saucer = {
	kind: Kind,
	x: number,
	y: number,
	vx: number,
	vy: number,
	travelled: number,
	fireElapsed: number,
	turnElapsed: number,
}
export type Draw = (n: number) -> number -- a whole number in 1..n

local Saucers = {}

Saucers.CLASSIC = table.freeze({
	large = table.freeze(
		{ radius = 20, points = 200, speed = 2, fireTicks = 60, aimed = false } :: KindConfig
	),
	small = table.freeze(
		{ radius = 10, points = 1000, speed = 3, fireTicks = 40, aimed = true } :: KindConfig
	),
	firstWait = 900,
	waitStep = 120,
	minWait = 360,
	smallEighths = table.freeze({ 1, 2, 3, 4, 5, 6, 7 }),
	turnTicks = 60,
	shotSpeed = 6,
	shotLife = 60,
	spread = table.freeze({
		table.freeze({ score = 0, spread = 16 }),
		table.freeze({ score = 10000, spread = 8 }),
		table.freeze({ score = 20000, spread = 4 }),
		table.freeze({ score = 40000, spread = 0 }),
	}),
} :: Config)

-- the ticks without a saucer before the next one appears, in this wave
function Saucers.wait(c: Config, wave: number): number
	return math.max(c.minWait, c.firstWait - c.waitStep * (wave - 1))
end

-- the small saucer's share of appearances in this wave, in eighths
function Saucers.smallShare(c: Config, wave: number): number
	return c.smallEighths[math.min(wave, #c.smallEighths)]
end

-- the small saucer's aim error at this score: the last row whose score the score has reached
function Saucers.spread(c: Config, score: number): number
	local s = c.spread[1].spread
	for _, row in c.spread do
		if score >= row.score then
			s = row.spread
		end
	end
	return s
end

-- A new saucer: its kind (small when draw(8) is at most the small share), its side (draw(2): 1 from the left
-- edge heading right, 2 from the right heading left), then its height (draw(height) - 1). Both sides start on
-- the x = 0 edge, which is also the field's right edge.
function Saucers.appear(c: Config, f: Field.Field, wave: number, draw: Draw): Saucer
	local kind: Kind = if draw(8) <= Saucers.smallShare(c, wave) then "small" else "large"
	local dir = if draw(2) == 1 then 1 else -1
	local y = draw(f.height) - 1
	return {
		kind = kind,
		x = 0,
		y = y,
		vx = dir * c[kind].speed,
		vy = 0,
		travelled = 0,
		fireElapsed = 0,
		turnElapsed = 0,
	}
end

-- One tick: a course change when due (draw(3): down, level or up at 45 degrees), then the move. True once it
-- has crossed the whole width, when it leaves.
function Saucers.move(s: Saucer, c: Config, f: Field.Field, draw: Draw): boolean
	local speed = c[s.kind].speed
	s.turnElapsed += 1
	if s.turnElapsed >= c.turnTicks then
		s.turnElapsed = 0
		s.vy = (draw(3) - 2) * speed
	end
	s.x, s.y = Field.wrap(f, s.x + s.vx, s.y + s.vy)
	s.travelled += math.abs(s.vx)
	return s.travelled >= f.width
end

-- The heading of its next shot: a large saucer's is drawn (draw(256) - 1); a small one's points at the target
-- across the wrap, off by a drawn error of up to the spread either way (draw(2 * spread + 1) - 1 - spread).
function Saucers.aim(
	s: Saucer,
	c: Config,
	f: Field.Field,
	score: number,
	tx: number,
	ty: number,
	draw: Draw
): number
	if not c[s.kind].aimed then
		return draw(Field.HEADINGS) - 1
	end
	local dx, dy = Field.delta(f, s.x, s.y, tx, ty)
	local spread = Saucers.spread(c, score)
	local err = draw(2 * spread + 1) - 1 - spread
	return (Field.heading(dx, dy) + err) % Field.HEADINGS
end

return Saucers
