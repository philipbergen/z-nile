--!strict
-- c0139 AC1: a whole merge conflict is a line starting `<<<<<<< ` followed later by a line starting `>>>>>>> `;
-- markers quoted inline, indented, a lone opener or a closer before the opener are no conflict.
local conflicts = require("@znile/engine/conflicts")
local t = require("@tests/lib/t")

return t.spec("c0139 a whole conflict at line starts, and nothing else", function(it)
	it("finds a whole conflict at line starts, and nothing else", function()
		t.expect(conflicts.markerLine("a\n<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> b\n")).toBe(2)
		t.expect(conflicts.markerLine("<<<<<<< HEAD\nno close\n")).toBe(nil)
		t.expect(conflicts.markerLine("quoted `<<<<<<< ` and `>>>>>>> ` inline\n")).toBe(nil)
		t.expect(conflicts.markerLine(">>>>>>> b\n<<<<<<< a\n")).toBe(nil)
		t.expect(conflicts.markerLine("x\n  <<<<<<< indented\n  >>>>>>> indented\n")).toBe(nil)
	end)
end)
