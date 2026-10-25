--!strict
-- c0870: the tracker skill describes numbering from tracker/next, the legacy rule for a tree without it, and the
-- compact and remap commands.
local fs = require("@lune/fs")
-- c0120 override: the spec runs from its project's home after the move
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: specs run from z-nile's home, so the skills are read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function skill(): string
	-- c0120 override: the spec runs from its home: the checkout's files are read from the top
	return fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
end
local function bullet(prefix: string): string
	for line in string.gmatch(skill(), "[^\n]+") do
		if string.sub(line, 1, #prefix) == prefix then
			return line
		end
	end
	error(`no line starting {prefix} in the tracker skill`, 0)
end
local function says(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0870 tracker skill", function(it)
	it("Numbering: ids come from tracker/next, counting by one, raised with a lease push", function()
		local line = bullet("- **Numbering**")
		t.expect(says(line, "`z-nile/next`")).toBe(true)
		t.expect(says(line, "by one")).toBe(true)
		t.expect(says(line, "lease")).toBe(true)
		t.expect(says(line, "**next multiple of 10**")).toBe(false)
	end)

	it("Numbering: a tree without tracker/next keeps the old rule", function()
		local line = bullet("- **Numbering**")
		t.expect(says(line, "without `z-nile/next`")).toBe(true)
		t.expect(says(line, "multiple of 10")).toBe(true)
	end)

	it("a Compaction bullet says how to run it and when, and that in-flight branches remap", function()
		local line = bullet("- **Compaction**")
		t.expect(says(line, "./zn compact")).toBe(true)
		t.expect(says(line, "--force")).toBe(true)
		t.expect(says(line, "./zn remap")).toBe(true)
		t.expect(says(line, "z-nile/compaction.txt")).toBe(true) -- c0114 override: the map moved
		-- a busy branch remaps before it merges, and the compaction lands only on the main it was made from
		t.expect(says(line, "before merging `origin/main`")).toBe(true)
		t.expect(says(line, "still equals")).toBe(true)
		t.expect(says(line, "ORIG_HEAD")).toBe(true) -- the way back from a plain merge
	end)

	it("the testing skill tells spec writers how to survive a compaction", function()
		local testing = fs.readFile(`{TOP}/z-nile/skills/zz-test/SKILL.md`) -- c0120 override: see TOP
		t.expect(says(testing, "tests/lib/renamed")).toBe(true)
		t.expect(says(testing, "in two parts")).toBe(true)
	end)

	it("the direct-push exception names tracker/next, which may only go up", function()
		local line = bullet("- **The direct-push exception.**")
		t.expect(says(line, "`z-nile/next`")).toBe(true)
		t.expect(says(line, "only go up")).toBe(true)
	end)

	it("Other commands lists compact and remap", function()
		local text = skill()
		local other = string.match(text, "## Other commands\n(.-)\n## ") :: string
		t.expect(other ~= nil).toBe(true)
		for _, c in { "./zn compact", "./zn remap" } do
			t.expect(says(other, c)).toBe(true)
		end
	end)
end)
