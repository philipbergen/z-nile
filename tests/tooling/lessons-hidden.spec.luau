--!strict
-- c0111 (review 002 F1): `lessons.load` skips hidden files in a lessons/ folder (a Finder .DS_Store) but still reports
-- any other name that is not <slug>.md. Builds its own tree under .cache/lessons-hidden; reads nothing else.
local fs = require("@lune/fs")
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

local root = ".cache/lessons-hidden"

return t.spec("lessons.load and hidden files", function(it)
	it("skips a hidden file and reports a stray one", function()
		if fs.isDir(root) then
			fs.removeDir(root)
		end
		local folder = `{root}/.claude/skills/testing/lessons`
		fs.writeDir(folder)
		fs.writeFile(`{root}/.claude/skills/testing/SKILL.md`, "---\nname: testing\ndescription: x\n---\n")
		fs.writeFile(`{folder}/.DS_Store`, "binary")
		fs.writeFile(`{folder}/notes.txt`, "not a lesson")
		fs.writeFile(
			`{folder}/pin.md`,
			"---\ntitle: Pin\nwhen: build\ntags: [wiring]\ncheck: Pinned?\nfrom: test\n---\nPin them.\n"
		)
		local tree = lessons.load(root)
		t.expect(tree.lessons["testing/pin"] ~= nil).toBe(true)
		local joined = table.concat(tree.problems, "\n")
		t.expect(string.find(joined, "notes.txt: not a lesson file", 1, true) ~= nil).toBe(true)
		t.expect((string.find(joined, ".DS_Store", 1, true))).toBe(nil)
		fs.removeDir(root)
	end)
end)
