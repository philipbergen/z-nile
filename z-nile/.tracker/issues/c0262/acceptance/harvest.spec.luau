--!strict
-- c0262 AC4: a final review's findings are harvested like any review's, and its files are not item documents.
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

return t.spec("c0262 AC4 a final review's findings are harvested", function(it)
	it("AC4: a final review's findings are harvested and its files are not item documents", function()
		local entries, problems = lessons.parseHarvest("R0099", "- final-review-c0010-001 F1: one-off: wording\n")
		t.expect(#problems).toBe(0)
		t.expect(#entries).toBe(1)
		t.expect(entries[1].review).toBe("final-review-c0010-001")
		local _, bad = lessons.parseHarvest("R0099", "- final-review-x-001 F1: one-off: wording\n")
		t.expect(#bad).toBe(1)
		t.expect(trail.isDoc("final-review-c0010-001.md")).toBe(false)
		t.expect(trail.isDoc("final-refute-c0010-001.md")).toBe(false)
		t.expect(trail.isDoc("R0099.md")).toBe(true)
	end)
end)
