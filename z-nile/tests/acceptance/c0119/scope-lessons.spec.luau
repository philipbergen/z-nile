--!strict
-- c0119 AC2: the two scope lessons are valid design lessons, sourced from the user's R0042 correction.
-- Reads the real files; writes nothing.
local lessons = require("@scripts/tracker/lessons")
-- c0120 override: the spec runs from its project's home after the move
local process = require("@lune/process")
local t = require("@tests/lib/t")
-- c0120 override: specs run from their project's home; the repository files live at the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0119 scope lessons", function(it)
	it("the two scope lessons are valid design lessons sourced from the R0042 correction", function()
		-- c0120 override: the spec runs from its home: the checkout's files are read from the top
		local tree = lessons.load(TOP)
		local sources = lessons.sources(tree.items)
		for _, id in { "z-design/never-narrow-captured-scope", "zz-review/no-scope-cut-as-fix" } do
			local text = tree.lessons[id]
			t.expect(text ~= nil).toBe(true)
			local lesson, problem = lessons.parse(id, text :: string)
			t.expect(problem).toBe(nil)
			local l = lesson :: lessons.Lesson
			t.expect(l.when).toBe("design")
			t.expect(table.find(l.tags, "scope") ~= nil).toBe(true)
			local named = false
			local list: { string } = sources[id] or {}
			for _, s in list do
				if string.find(s, "R0042 note user correction 2026-10-20", 1, true) == 1 then
					named = true
				end
			end
			t.expect(named).toBe(true)
		end
		for _, p in lessons.check(tree) do
			t.expect((string.find(p, "scope", 1, true))).toBe(nil)
		end
	end)
end)
