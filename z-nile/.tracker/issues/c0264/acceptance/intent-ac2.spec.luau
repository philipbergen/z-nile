--!strict
-- c0264: z-nile/README.md states the intent in its own "## Intent" section, the first `##` section, right before
-- "## How it should work". This spec: the three bold lead-ins, in order. The section's exact text is check.sh's (AC4, sequestered), so the promoted
-- specs pin structure only. Reads the checkout's own README as text, never writes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local README = fs.readFile(`{ROOT}/z-nile/README.md`)

-- The text of "## Intent", up to the next "## " heading; errors when there is not exactly one.
local function intent(): string
	local from = string.find(README, "\n## Intent\n", 1, true)
	if from == nil then
		error("README has no '## Intent'", 0)
	end
	if string.find(README, "\n## Intent\n", from + 1, true) ~= nil then
		error("README has more than one '## Intent'", 0)
	end
	local rest = string.sub(README, from + 1)
	local to = string.find(rest, "\n## ", 4, true)
	return if to then string.sub(rest, 1, to) else rest
end

return t.spec("c0264 the README states the intent (AC2)", function(it)
	it("AC2: the section states the three halves of the intent, each as a bold lead-in, in order", function()
		local s = intent()
		local leads = {
			"- **Humans at the idea and the design.**",
			"- **Workers from the raft to the merge.**",
			"- **Cheap on the way, sharp at the end.**",
		}
		local last = 0
		for _, lead in leads do
			local p = string.find(s, lead, 1, true)
			t.expect(p ~= nil).toBe(true)
			t.expect((p :: number) > last).toBe(true) -- in this order
			last = p :: number
		end
	end)
end)
