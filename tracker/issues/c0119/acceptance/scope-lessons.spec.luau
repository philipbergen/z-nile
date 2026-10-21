--!strict
-- c0119 AC2: the two scope lessons are valid design lessons, sourced from the user's R0042 correction.
-- Reads the real files; writes nothing.
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

return t.spec("c0119 scope lessons", function(it)
	it("the two scope lessons are valid design lessons sourced from the R0042 correction", function()
		local tree = lessons.load(".")
		local sources = lessons.sources(tree.items)
		for _, id in { "ticket-prep/never-narrow-captured-scope", "review/no-scope-cut-as-fix" } do
			local text = tree.lessons[id]
			t.expect(text ~= nil).toBe(true)
			local lesson, problem = lessons.parse(id, text :: string)
			t.expect(problem).toBe(nil)
			local l = lesson :: lessons.Lesson
			t.expect(l.when).toBe("design")
			t.expect(table.find(l.tags, "scope") ~= nil).toBe(true)
			local named = false
			for _, s in sources[id] or {} do
				if string.find(s, "R0042 note user correction 2026-10-20", 1, true) == 1 then
					named = true
				end
			end
			t.expect(named).toBe(true)
		end
		for _, p in lessons.check(tree) do
			t.expect(string.find(p, "scope", 1, true)).toBe(nil)
		end
	end)
end)
