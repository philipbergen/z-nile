--!strict
-- d0295 AC1: the Order every reader cuts. stack.orderSection is the text after `## Order & dependencies` up to the
-- next `## ` heading, so a `## Cross-raft waits` section after it is never read as layers, and stack.order on that
-- cut accepts R0090's order once its cross-raft ids are moved there. stack.orderProblem is the part of stack.order's
-- refusals that is the Order text's own fault.
local stack = require("@znile/engine/stack")
local t = require("@tests/lib/t")

local function member(id: string, deps: { string }?): stack.Member
	return { id = id, dependsOn = deps or {} }
end

-- R0090's Order as it was refused (2026-11-12, PR #303): its own member, then two other rafts' issues
local REFUSED = table.concat({
	"## Theme",
	"T.",
	"",
	"## Order & dependencies",
	"One member, c0261. R0090 merges before the rafts of c0264 and c0260.",
	"",
	"## Risks & rollback",
	"",
}, "\n")

local MOVED = table.concat({
	"## Theme",
	"T.",
	"",
	"## Order & dependencies",
	"One member, c0261. R0062 is unrelated.",
	"",
	"### Why",
	"It stands alone.",
	"",
	"## Cross-raft waits",
	"R0090 merges before the rafts of c0264 and c0260.",
	"",
	"## Risks & rollback",
	"c0999 is mentioned here too.",
	"",
}, "\n")

return t.spec("d0295 the Order section start reads", function(it)
	it("reproduces R0090: an Order naming other rafts' issues is refused as non-members", function()
		local ids, err = stack.order("R0090", stack.orderSection(REFUSED), { member("c0261") })
		t.expect(ids).toBe(nil)
		t.expect(err).toBe("c0264 is in R0090's Order and is not a member")
	end)

	it("cuts at the next level-two heading: Cross-raft waits and later sections are not the Order", function()
		local cut = stack.orderSection(MOVED)
		t.expect(cut).toBe("One member, c0261. R0062 is unrelated.\n\n### Why\nIt stands alone.")
		local ids, err = stack.order("R0090", cut, { member("c0261") })
		t.expect(err).toBe(nil)
		t.expect(ids).toEqual({ "c0261" })
	end)

	it("is empty for a document with no Order, and the fallback order applies", function()
		t.expect(stack.orderSection("## Theme\nT.\n")).toBe("")
		local ids = stack.order("R0001", stack.orderSection("## Theme\nT.\n"), {
			member("c0002", { "c0001" }),
			member("c0001"),
		})
		t.expect(ids).toEqual({ "c0001", "c0002" })
	end)

	it(
		"orderProblem is the Order text's faults: a cycle among members the Order does not name is not one",
		function()
			local cyclic = { member("c0070", { "c0080" }), member("c0080", { "c0070" }) }
			t.expect(stack.orderProblem("R0060", "By id.", cyclic)).toBe(nil)
			local _, err = stack.order("R0060", "By id.", cyclic)
			t.expect(err).toBe("dependency cycle among: c0070, c0080")
			t.expect(stack.orderProblem("R0090", stack.orderSection(REFUSED), { member("c0261") }))
				.toBe("c0264 is in R0090's Order and is not a member")
			t.expect(stack.orderProblem("R0001", "c0001 and c0001.", { member("c0001") }))
				.toBe("c0001 is listed twice in R0001's Order")
			t.expect(
				stack.orderProblem(
					"R0001",
					"c0001, then c0002.",
					{ member("c0001", { "c0002" }), member("c0002") }
				)
			).toBe("c0001 is listed before c0002, which it depends on")
		end
	)

	it("reads an Order that is the document's last section to its end", function()
		t.expect(stack.orderSection("## Order & dependencies\nc0001, then c0002.\n"))
			.toBe("c0001, then c0002.")
	end)
end)
