--!strict
-- c0264: z-nile/README.md states the intent in its own "## Intent" section, the first `##` section, right before
-- "## How it should work". This spec: a plain aim, no sub-section and no state label. The section's exact text is check.sh's (AC4, sequestered), so the promoted
-- specs pin structure only. Reads the checkout's own README as text, never writes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local README = fs.readFile(`{ROOT}/z-nile/README.md`)

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

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

return t.spec("c0264 the README states the intent (AC3)", function(it)
	it("AC3: the section is a plain aim: no sub-section, no state label, and it says so", function()
		local s = intent()
		t.expect(has(s, "\n### ")).toBe(false)
		for _, label in { "*exists*", "*designed*", "*captured*" } do
			t.expect(has(s, label)).toBe(false)
		end
		t.expect(has(s, "This section is the aim and carries no status label.")).toBe(true)
	end)
end)
