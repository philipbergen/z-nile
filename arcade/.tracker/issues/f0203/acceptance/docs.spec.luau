--!strict
-- f0203 AC8: the rule the game issues read (f0213, f0218, f0222, c0204) is in the library's architecture: its section
-- comes before the deps block and holds the every-input rule, the no-Logic-require rule, the cells each game's design
-- leaves open, and the differences from pickman's copies. Only these sentences are pinned, not the section's prose.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local HEADING = "## Input and look cores (f0203)"

local function section(): string?
	local text = fs.readFile(".tracker/architecture.md")
	local s = string.find(text, "\n" .. HEADING .. "\n", 1, true)
	if s == nil then
		return nil
	end
	local rest = string.sub(text, s + 1)
	local stop = string.find(rest, "\n## ", 2, true)
	return if stop then string.sub(rest, 1, stop) else rest
end

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

return t.spec("f0203 docs", function(it)
	it("the section exists and comes before the deps block", function()
		local text = fs.readFile(".tracker/architecture.md")
		local at = string.find(text, "\n" .. HEADING .. "\n", 1, true)
		local deps = string.find(text, "\n## Allowed dependencies\n", 1, true)
		t.expect(at ~= nil).toBe(true)
		t.expect(deps ~= nil).toBe(true)
		t.expect((at or math.huge) < (deps or 0)).toBe(true)
	end)

	it(
		"it says every game builds its input from the cores, with a key, a gamepad input and a touch control",
		function()
			local s = section()
			t.expect(has(s, "Every game builds its input from these cores")).toBe(true)
			t.expect(has(s, "every action it has gets a key, a gamepad input and a touch control")).toBe(true)
			t.expect(has(s, "The cores hold no key map")).toBe(true)
		end
	)

	it("it says game Logic never requires them", function()
		t.expect(has(section(), "Game Logic never requires them")).toBe(true)
	end)

	it("it lists the cells the games' designs leave open, with the issue that decides each", function()
		local s = section()
		t.expect(has(s, "Open per game")).toBe(true)
		t.expect(has(s, "snake's look on a gamepad and on touch (f0213)")).toBe(true)
		t.expect(has(s, "asteroids' look on touch (f0222)")).toBe(true)
	end)

	it("it lists the differences from pickman's copies for c0204", function()
		local s = section()
		t.expect(has(s, "Differences from pickman's copies (c0204)")).toBe(true)
		for _, core in { "Rng", "Pad", "Touch", "Look" } do
			t.expect(has(s, `- {core}:`)).toBe(true)
		end
	end)
end)
