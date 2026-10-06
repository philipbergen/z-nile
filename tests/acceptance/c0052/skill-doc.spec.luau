--!strict
-- The tracker skill's Conflicts bullet must describe the new `renumber` (c0500): no hand-computed
-- multiple of 10, but the tool picks one above the highest number across the local tree and origin/main.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function conflicts(): string
	for line in string.gmatch(fs.readFile(".claude/skills/tracker/SKILL.md"), "[^\n]+") do
		if string.sub(line, 1, 15) == "- **Conflicts**" then
			return line
		end
	end
	error("no Conflicts bullet in the tracker skill", 0)
end

local function says(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("tracker skill: Conflicts bullet", function(it)
	it("renumber is called with just the id", function()
		local line = conflicts()
		t.expect(says(line, "tracker.sh renumber <ID>")).toBe(true)
		t.expect(says(line, "<next free>")).toBe(false)
	end)

	it("says the number is one above the highest, across your tree and origin/main", function()
		local line = conflicts()
		t.expect(says(line, "one above the highest")).toBe(true)
		t.expect(says(line, "origin/main")).toBe(true)
	end)

	it("no longer tells the reader to work out a multiple of 10", function()
		t.expect(says(conflicts(), "multiple of 10")).toBe(false)
	end)

	it(
		"still tells the reader to fetch origin/main first and that a content conflict is not a renumber",
		function()
			local line = conflicts()
			t.expect(says(line, "git fetch origin main")).toBe(true)
			t.expect(says(line, "never renumber")).toBe(true)
		end
	)

	it("the Numbering bullet says new takes its number from tracker/next (c0870)", function()
		local text = fs.readFile(".claude/skills/tracker/SKILL.md")
		t.expect(says(text, "`tracker/next` holds the next number")).toBe(true)
	end)
end)
