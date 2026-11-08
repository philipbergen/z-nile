--!strict
-- c0260 AC10: which issues must carry a capture record is a mark stored in the issue (`capture: required`, written by
-- `./zn new` when the base holds the landing's marker file), never a date or a read of history. capturecut over texts.
local capturecheck = require("@znile/engine/capturecheck")
local capturecut = require("@znile/engine/capturecut")
local t = require("@tests/lib/t")

local DOC =
	"---\nid: c0900\ntype: chore\nslug: c\ndesign: draft\ncreated: 2026-11-08\nstatus: new-a-b-c\n---\n\n# c0900\n\n## Problem\nP\n"

return t.spec("c0260 the cut-over is a mark in the issue", function(it)
	it("AC10: the mark is written once, after the design line, and read back", function()
		local marked = capturecut.mark(DOC)
		t.expect(string.find(marked, "design: draft\ncapture: required\ncreated:", 1, true) ~= nil).toBe(true)
		t.expect(capturecut.mark(marked)).toBe(marked) -- idempotent
		t.expect(capturecut.required({ capture = "required" })).toBe(true)
		t.expect(capturecut.required({})).toBe(false)
		t.expect(capturecut.required({ capture = "optional" })).toBe(false)
	end)

	it("AC10: an unmarked issue is never judged: it is older, or made where the rule was not in force", function()
		t.expect(capturecheck.kind(DOC)).toBe("none")
		t.expect(capturecut.required(require("@znile/engine/audit").front(DOC))).toBe(false)
	end)

	it("AC10: the mark survives a renumbering (the id is not what is read) and a copy to another folder", function()
		local renumbered = (string.gsub(capturecut.mark(DOC), "c0900", "c0123"))
		t.expect(capturecut.required(require("@znile/engine/audit").front(renumbered))).toBe(true)
	end)

	it("AC10: the marker file the landing adds is z-nile/.tracker/capture-since", function()
		t.expect(capturecut.MARKER).toBe("z-nile/.tracker/capture-since")
	end)
end)
