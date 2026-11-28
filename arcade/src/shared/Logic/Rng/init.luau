--!strict
-- Rng: a seeded generator (Park-Miller), engine-free. The state is one whole number in 1..MODULUS-1 held in a plain
-- table, so a generator is plain data; a stream's multiplier, mix and offset pick its sequence from a seed.
export type Stream = { multiplier: number, mix: number, offset: number }
export type Generator = { state: number, multiplier: number }
export type Draw = (n: number) -> number

local MODULUS = 2147483647
local MAX_MULTIPLIER = 2 ^ 21 -- state * multiplier stays below 2^52, exact in a double
local MAX_MIX = 2 ^ 21

local Rng = {}
Rng.MODULUS = MODULUS
Rng.STREAM = table.freeze({ multiplier = 48271, mix = 1, offset = 0 } :: Stream)

local function whole(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) ~= math.huge and v == math.floor(v)
end

function Rng.new(seed: number, stream: Stream?): Generator
	local st = stream or Rng.STREAM
	if not whole(st.multiplier) then
		error("Rng.new: the stream's multiplier must be a whole number")
	end
	if st.multiplier < 2 or st.multiplier >= MAX_MULTIPLIER then
		error("Rng.new: the stream's multiplier must be in 2..2^21-1")
	end
	if not whole(st.mix) then
		error("Rng.new: the stream's mix must be a whole number")
	end
	if st.mix < 1 or st.mix >= MAX_MIX then
		error("Rng.new: the stream's mix must be in 1..2^21-1")
	end
	if not whole(st.offset) then
		error("Rng.new: the stream's offset must be a whole number")
	end
	if math.abs(st.offset) >= MODULUS then
		error("Rng.new: the stream's offset must be below the modulus in size")
	end
	local s = if type(seed) == "number"
			and seed == seed
			and math.abs(seed) ~= math.huge
		then math.floor(seed)
		else 0
	s = s % (MODULUS - 1)
	return { state = (s * st.mix + st.offset) % (MODULUS - 1) + 1, multiplier = st.multiplier }
end

function Rng.int(g: Generator, n: number): number
	if not whole(n) then
		error("Rng.int: n must be a whole number")
	end
	if n < 1 then
		error("Rng.int: n must be at least 1")
	end
	g.state = (g.state * g.multiplier) % MODULUS
	return g.state % n + 1
end

function Rng.float(g: Generator): number
	g.state = (g.state * g.multiplier) % MODULUS
	return (g.state - 1) / (MODULUS - 1)
end

function Rng.draw(g: Generator): Draw
	return function(n: number): number
		return Rng.int(g, n)
	end
end

return Rng
