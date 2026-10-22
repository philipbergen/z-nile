--!strict
-- A small deterministic model for harness specs and docs: a walker on a line 0..10, starting at 5.
-- Intents: "L", "R" or "S" (stop). Walking into an end emits a Bump event and stops the walker.
local sim = require("@tests/lib/sim")

local Walker: sim.Model<any> = {
	name = "walker",
	tickRate = 30,
	new = function(_seed: number): any
		return { x = 5, dir = 0 }
	end,
	step = function(s: any, intents: { any }, _tick: number): { sim.Event }?
		for _, intent in intents do
			s.dir = if intent == "L" then -1 elseif intent == "R" then 1 else 0
		end
		local nx = s.x + s.dir
		if nx < 0 or nx > 10 then
			s.dir = 0
			return { { kind = "Bump", at = s.x } }
		end
		s.x = nx
		return nil
	end,
	observe = function(s: any): any
		return { x = s.x, dir = s.dir }
	end,
}

return Walker
