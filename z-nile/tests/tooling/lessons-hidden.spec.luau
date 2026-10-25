--!strict
-- c0111 (review 002 F1): `lessons.load` skips hidden files in a lessons/ folder (a Finder .DS_Store) but still reports
-- any other name that is not <slug>.md. Builds its own tree under .cache/lessons-hidden; reads nothing else.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

local root = ".cache/lessons-hidden"

return t.spec("lessons.load and hidden files", function(it)
	it("skips a hidden file and reports a stray one", function()
		if fs.isDir(root) then
			fs.removeDir(root)
		end
		local folder = `{root}/z-nile/skills/zz-test/lessons`
		fs.writeDir(folder)
		fs.writeFile(`{root}/z-nile/skills/zz-test/SKILL.md`, "---\nname: zz-test\ndescription: x\n---\n")
		fs.writeFile(`{folder}/.DS_Store`, "binary")
		fs.writeDir(`{root}/z-nile`) -- c0114: a tree without the registry refuses
		fs.writeFile(`{root}/z-nile/projects.toml`, fs.readFile(`{engine.TOP}/z-nile/projects.toml`)) -- c0120: specs run in z-nile/
		fs.writeFile(`{folder}/notes.txt`, "not a lesson")
		fs.writeFile(
			`{folder}/pin.md`,
			"---\ntitle: Pin\nwhen: build\ntags: [wiring]\ncheck: Pinned?\nfrom: test\n---\nPin them.\n"
		)
		local tree = lessons.load(root)
		t.expect(tree.lessons["zz-test/pin"] ~= nil).toBe(true)
		local joined = table.concat(tree.problems, "\n")
		t.expect(string.find(joined, "notes.txt: not a lesson file", 1, true) ~= nil).toBe(true)
		t.expect((string.find(joined, ".DS_Store", 1, true))).toBe(nil)
		fs.removeDir(root)
	end)
end)
