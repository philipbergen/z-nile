--!strict
-- Pilot: one player's ship and its life on the field: on the field, away in hyperspace, or lost and waiting to
-- come back; its protection, its shots, its lives and its score. The rules that are the same for every ship
-- live here, so a run with one ship (Classic) or two steps each pilot through the same functions. A pilot is
-- any table with these fields: a run that is itself a pilot passes itself.
local Field = require("./Field")
local Ship = require("./Ship")

export type State = "alive" | "hyperspace" | "dead"
export type Cause = "rock" | "saucer" | "saucershot" | "hyperspace" | "shot" -- shot: the other player's, with friendly fire
export type Shot = { x: number, y: number, vx: number, vy: number, life: number }
export type Controls = { turn: number, thrust: boolean, fire: boolean, hyperspace: boolean }
export type Config = {
	field: Field.Field,
	ship: Ship.Config,
	lives: number,
	extraLifeEvery: number,
	shotLimit: number,
	shotSpeed: number,
	shotLife: number,
	hyperspaceTicks: number,
	hyperspaceOdds: number,
	respawnTicks: number,
	protectTicks: number,
}
export type Home = { x: number, y: number }
export type Pilot = {
	ship: Ship.Ship,
	shipState: State,
	timer: number, -- ticks left away in hyperspace, or before a lost ship may come back
	protect: number, -- protected ticks left
	shots: { Shot },
	lives: number,
	score: number,
	nextExtra: number, -- the score that earns the next life
	home: Home?, -- where the ship is lost to and comes back at; nil is the field's centre
}
export type Event = { kind: string, lives: number?, cause: Cause?, x: number?, y: number? }
export type Draw = (n: number) -> number -- a whole number in 1..n

local Pilot = {}

-- where the pilot's ship waits when lost and comes back: its home, or the field's centre
function Pilot.home(p: Pilot, c: Config): (number, number)
	local h = p.home
	if h then
		return h.x, h.y
	end
	return c.field.width / 2, c.field.height / 2
end

-- a pilot at (x, y), on the field at rest, with the run's lives and no score
function Pilot.new(c: Config, x: number, y: number): Pilot
	return {
		ship = Ship.new(c.ship, x, y),
		shipState = "alive",
		timer = 0,
		protect = 0,
		shots = {},
		lives = c.lives,
		score = 0,
		nextExtra = c.extraLifeEvery,
	}
end

-- What an input asks for: a turn only of exactly 1 or -1, the rest only when exactly true. Anything else,
-- or no table at all, asks for nothing.
function Pilot.controls(input: any): Controls
	if type(input) ~= "table" then
		return { turn = 0, thrust = false, fire = false, hyperspace = false }
	end
	local turn = if input.turn == 1 then 1 elseif input.turn == -1 then -1 else 0
	return {
		turn = turn,
		thrust = input.thrust == true,
		fire = input.fire == true,
		hyperspace = input.hyperspace == true,
	}
end

-- on the field and not protected: what rocks, saucers and their shots can hit
function Pilot.exposed(p: Pilot): boolean
	return p.shipState == "alive" and p.protect == 0
end

-- Points won, and a life each time the score reaches another extraLifeEvery (after the event of the hit).
function Pilot.award(p: Pilot, c: Config, points: number, emit: (Event) -> ())
	p.score += points
	while c.extraLifeEvery > 0 and p.score >= p.nextExtra do
		p.lives += 1
		p.nextExtra += c.extraLifeEvery
		emit({ kind = "ExtraLife", lives = p.lives })
	end
end

-- The ship is lost where it is: a life, and it waits at its home (the centre), unseen, for its respawn. Its
-- shots fly on. True when that was its last life (the run decides what that ends).
function Pilot.lose(p: Pilot, c: Config, cause: Cause, emit: (Event) -> ()): boolean
	p.lives -= 1
	emit({ kind = "ShipDestroyed", cause = cause, lives = p.lives, x = p.ship.x, y = p.ship.y })
	local hx, hy = Pilot.home(p, c)
	p.ship = Ship.new(c.ship, hx, hy)
	p.shipState = "dead"
	p.timer = c.respawnTicks
	p.protect = 0
	return p.lives <= 0
end

-- One tick of the ship's clocks, first in the tick. Protection runs down while the ship is not lost (on the
-- field or away). Away, it comes back when its time is up, unless draw(hyperspaceOdds) is 1, which loses it
-- there, protected or not. Lost, it waits out its time, then comes back at its home, protected, on the
-- first tick clear() says the home is clear. True when the ship was lost on its last life.
function Pilot.clock(p: Pilot, c: Config, draw: Draw, clear: () -> boolean, emit: (Event) -> ()): boolean
	if p.shipState ~= "dead" and p.protect > 0 then
		p.protect -= 1
	end
	if p.shipState == "hyperspace" then
		p.timer -= 1
		if p.timer <= 0 then
			p.timer = 0
			if draw(c.hyperspaceOdds) == 1 then
				return Pilot.lose(p, c, "hyperspace", emit)
			end
			p.shipState = "alive"
			emit({ kind = "HyperspaceEnd" })
		end
	elseif p.shipState == "dead" then
		if p.timer > 0 then
			p.timer -= 1
		end
		if p.timer == 0 and clear() then
			local hx, hy = Pilot.home(p, c)
			p.ship = Ship.new(c.ship, hx, hy)
			p.shipState = "alive"
			p.protect = c.protectTicks
			emit({ kind = "Respawn", lives = p.lives })
		end
	end
	return false
end

-- One tick of the player's controls, only while the ship is on the field: a hyperspace jump (to a drawn spot,
-- x then y, at rest, its heading kept) and nothing else, or the flight, then a fire with fewer than shotLimit
-- shots out (from the nose, at shotSpeed plus the ship's own velocity).
function Pilot.control(p: Pilot, c: Config, controls: Controls, draw: Draw, emit: (Event) -> ())
	if p.shipState ~= "alive" then
		return
	end
	local f = c.field
	if controls.hyperspace then
		local x = draw(f.width) - 1
		local y = draw(f.height) - 1
		p.ship.x, p.ship.y, p.ship.vx, p.ship.vy = x, y, 0, 0
		p.shipState = "hyperspace"
		p.timer = c.hyperspaceTicks
		emit({ kind = "Hyperspace", x = x, y = y })
		return
	end
	Ship.fly(p.ship, c.ship, f, controls.turn, controls.thrust)
	if controls.fire and #p.shots < c.shotLimit then
		local x, y = Ship.nose(p.ship, c.ship, f)
		local ux, uy = Field.unit(p.ship.heading)
		table.insert(p.shots, {
			x = x,
			y = y,
			vx = ux * c.shotSpeed + p.ship.vx,
			vy = uy * c.shotSpeed + p.ship.vy,
			life = c.shotLife,
		})
		emit({ kind = "Fire" })
	end
end

return Pilot
