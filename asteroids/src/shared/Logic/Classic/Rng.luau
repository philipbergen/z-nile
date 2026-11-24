--!strict
-- A small deterministic generator (Park-Miller, multiplier 16807): the state is one number, so a run stays
-- plain data, and every product stays below 2^53.
local Rng = {}

local MODULUS = 2147483647

-- A state in 1..MODULUS-1 from any seed; a seed that is not a finite number counts as 0.
function Rng.seed(seed: number): number
	local s = if type(seed) == "number" then math.floor(seed) else 0
	if s ~= s or math.abs(s) == math.huge then
		s = 0
	end
	return s % (MODULUS - 1) + 1
end

-- The next state and a whole number in 1..n.
function Rng.next(state: number, n: number): (number, number)
	local nextState = (state * 16807) % MODULUS
	return nextState, nextState % n + 1
end

return Rng
