--!strict
-- E1: os.clock resolution/monotonicity in Lune; E2: @lune/serde JSON round trip incl. nested arrays, integer ticks, strings.
local serde = require("@lune/serde")
local a = os.clock()
local x = 0
for i = 1, 1e6 do
	x += i
end
local b = os.clock()
print("E1 os.clock delta for 1e6 adds:", b - a, "monotonic:", b >= a, "x", x)
local minStep = math.huge
local prev = os.clock()
for _ = 1, 1e5 do
	local c = os.clock()
	if c > prev then
		minStep = math.min(minStep, c - prev)
	end
	prev = c
end
print("E1 smallest observed os.clock step:", minStep)
local doc = {
	seed = 7,
	ticks = 120,
	script = { { at = 0, intent = "Left" }, { at = 12, intent = { kind = "Turn", dir = "Right" } } },
}
local s = serde.encode("json", doc, true)
local back = serde.decode("json", s)
print(
	"E2 json roundtrip:",
	back.seed == 7 and back.script[2].intent.dir == "Right" and back.script[2].at == 12,
	typeof(back.script[2].at)
)
