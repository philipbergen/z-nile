--!strict
-- c0262 AC4: a final review's findings are harvested like any review's, and its files are not item documents.
local fs = require("@lune/fs")
local process = require("@lune/process")
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0262 AC4 a final review's findings are harvested; one leaf module owns the names", function(it)
	it("AC4: harvest entries and item documents", function()
		local entries, problems = lessons.parseHarvest("R0099", "- final-review-c0010-001 F1: one-off: wording\n")
		t.expect(#problems).toBe(0)
		t.expect(#entries).toBe(1)
		t.expect(entries[1].review).toBe("final-review-c0010-001")
		local _, bad = lessons.parseHarvest("R0099", "- final-review-x-001 F1: one-off: wording\n")
		t.expect(#bad).toBe(1)
		t.expect(trail.isDoc("final-review-c0010-001.md")).toBe(false)
		t.expect(trail.isDoc("final-review-c0010-002.md")).toBe(false)
		t.expect(trail.isDoc("final-refute-c0010-001.md")).toBe(false)
		t.expect(trail.isDoc("R0099.md")).toBe(true)
		t.expect(trail.isDoc("stream-review-c0010-001.md")).toBe(false)
	end)

	it("AC4: finalreview is a leaf (it requires nothing) and lessons and trail use its name test", function()
		local src = fs.readFile(`{TOP}/z-nile/engine/finalreview.luau`)
		t.expect((string.find(src, "require(", 1, true))).toBe(nil)
		for _, f in { "lessons", "trail" } do
			local text = fs.readFile(`{TOP}/z-nile/engine/{f}.luau`)
			t.expect(string.find(text, 'require("./finalreview")', 1, true) ~= nil).toBe(true)
		end
	end)
end)
