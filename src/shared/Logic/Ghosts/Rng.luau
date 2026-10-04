--!strict
-- A small deterministic generator (Park-Miller, multiplier 16807): the state is one number, so a Ghosts set
-- stays plain data, and every product stays below 2^53 on every platform.
local Rng = {}

local MODULUS = 2147483647

-- a state in 1..MODULUS-1 from any whole seed
function Rng.seed(seed: number): number
	local s = math.floor(seed) % (MODULUS - 1)
	return s + 1
end

-- The next state and a whole number in 1..n.
function Rng.next(state: number, n: number): (number, number)
	local nextState = (state * 16807) % MODULUS
	return nextState, nextState % n + 1
end

return Rng
