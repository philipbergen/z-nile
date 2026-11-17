--!strict
-- c0278 E5: a stamp drawn by status.stamp("closed", pick) is one closing.guard accepts and status.parse reads as closed.
local closing = require("../../../../../engine/closing")
local status = require("../../../../../engine/status")
local n = 0
for seed = 1, 200 do
	math.randomseed(seed)
	local stamp = status.stamp("closed", function(k: number): number
		return math.random(k)
	end)
	local before = "---\nid: c0510\nstatus: new-amber-otter-lynx\n---\n\n# c0510\n"
	local after = closing.edit(before, "moot", stamp) :: string
	assert(status.parse(stamp) == "closed", `parse {stamp}`)
	assert(closing.guard(before, after) == nil, `guard {stamp}: {closing.guard(before, after)}`)
	n += 1
end
print(`E5 pass: {n} stamps parse as closed and pass the guard`)
