--!strict
-- c0402 AC2: z-raft's and z-design's skills, and the lesson that restates the cap, say about 3,000; none says about 1,500. Reads the real tree as text with plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0402 the skills say about 3,000", function(it)
	it("z-raft, z-design and the size lesson say about 3,000, and none of them says about 1,500", function()
		local raft = read("z-nile/skills/z-raft/SKILL.md")
		t.expect(
			has(
				raft,
				"a raft that would pass about 3,000 changed lines (the sum of its members' `size:`) starts another"
			)
		).toBe(true)
		t.expect(has(raft, "an issue estimated over that is a raft by itself and is never split")).toBe(true)
		local design = read("z-nile/skills/z-design/SKILL.md")
		t.expect(has(design, "z-raft sums them against its cap of about 3,000 lines")).toBe(true)
		local lesson = read("z-nile/skills/z-design/lessons/size-is-re-estimated-when-scope-grows.md")
		t.expect(has(lesson, "its cap of about 3,000 lines")).toBe(true)
		t.expect(has(lesson, "raft cap of about 3,000 changed lines")).toBe(true)
		for _, text in { raft, design, lesson } do
			t.expect(has(text, "about 1,500")).toBe(false)
		end
	end)
end)
