--!strict
-- The pure shape of a stacked raft: names, order, what is finished, the binding message.
local stack = require("@znile/engine/stack")
local t = require("@tests/lib/t")

local function member(id: string, depends: { string }?): stack.Member
	return { id = id, dependsOn = depends or {} }
end

return t.spec("a raft stack's shape", function(it)
	it("reads the raft, the position and the issue from a layer branch", function()
		local layer = stack.parse("R0010/1/c0010")
		t.expect(layer ~= nil).toBe(true)
		local found = layer :: stack.Layer
		t.expect(found.raft).toBe("R0010")
		t.expect(found.position).toBe(1)
		t.expect(found.issue).toBe("c0010")
		t.expect(found.name).toBe("R0010/1/c0010")
		t.expect(stack.parse("origin/R0010/12/d0030") ~= nil).toBe(true)
		t.expect((stack.parse("origin/R0010/12/d0030") :: stack.Layer).position).toBe(12)
		t.expect(stack.parse("R0010-kept")).toBe(nil)
		t.expect(stack.parse("R0010/01/c0010")).toBe(nil)
		t.expect(stack.owns("origin/R0010/2/c0020", "R0010")).toBe(true)
		t.expect(stack.owns("main", "R0010")).toBe(false)
		t.expect(stack.branch("R0010", 2, "c0020")).toBe("R0010/2/c0020")
	end)

	it("orders named ids first, then the rest by depends_on and id", function()
		local ids = stack.order("R0010", "c0020 then c0010", {
			member("c0010"),
			member("c0030", { "c0010" }),
			member("c0020"),
		})
		t.expect(ids).toEqual({ "c0020", "c0010", "c0030" })
		local fallback = stack.order("R0010", "By id.", {
			member("c0030", { "c0010" }),
			member("c0010"),
			member("c0020"),
		})
		t.expect(fallback).toEqual({ "c0010", "c0020", "c0030" })
	end)

	it("refuses a duplicate, a non-member, a backwards dependency and a cycle", function()
		local _, twice = stack.order("R0010", "c0010 c0010", { member("c0010") })
		t.expect(twice).toBe("c0010 is listed twice in R0010's Order")
		local _, stranger = stack.order("R0010", "c0090", { member("c0010") })
		t.expect(stranger).toBe("c0090 is in R0010's Order and is not a member")
		local _, backwards = stack.order("R0010", "c0020 c0010", {
			member("c0010"),
			member("c0020", { "c0010" }),
		})
		t.expect(backwards).toBe("c0020 is listed before c0010, which it depends on")
		local _, cycle = stack.order("R0010", "By id.", {
			member("c0010", { "c0020" }),
			member("c0020", { "c0010" }),
		})
		t.expect(cycle).toBe("dependency cycle among: c0010, c0020")
	end)

	it("a layer is finished only as one commit on its base, titled with the issue", function()
		t.expect(stack.finishSubject("c0010", "a\tb\nc")).toBe("c0010: a b c")
		t.expect(stack.finished(1, "c0010: alpha", "base", "base", "c0010", "alpha")).toBe(true)
		t.expect(stack.finished(2, "c0010: alpha", "base", "base", "c0010", "alpha")).toBe(false)
		t.expect(stack.finished(1, "tracker: start R0010", "base", "base", "c0010", "alpha")).toBe(false)
		t.expect(stack.finished(1, "c0010: alpha", "other", "base", "c0010", "alpha")).toBe(false)
		t.expect(stack.alreadyStacked(true)).toBe(true)
		t.expect(stack.alreadyStacked(false)).toBe(false)
	end)

	it("a rewritten lower layer rebases only this layer's own commits", function()
		t.expect(stack.rebaseUpstream("c0020", "R0010", "c0020: beta", "old", false, {})).toBe("old")
		t.expect(stack.rebaseUpstream("c0020", "R0010", "c0020: beta", "old", true, {})).toBe(nil)
		t.expect(stack.rebaseUpstream("c0020", "R0010", "still working", "tip", false, {
			{ subject = "c0010: alpha", parent = "main" },
			{ subject = "tracker: start R0010 Stack", parent = "lower" },
		})).toBe("lower")
	end)

	it("the binding message names the raft, the tickets and the verdict", function()
		t.expect(stack.bindMessage("R0010", { "c0010", "c0020" }, "approve"))
			.toBe("R0010: bind c0010, c0020\n\nVerdict: approve\n")
		t.expect(stack.oldShapeMessage("R0010", "R0010-kept")).toBe(
			"R0010 is an active raft in the old single-branch shape (R0010-kept) and is not migrated. It is being stopped separately."
		)
		t.expect(stack.render("R0010", {
			{ position = 1, name = "R0010/1/c0010", issue = "c0010", state = "finished", sha = "abc" },
			{ position = 2, name = "R0010/2/c0020", issue = "c0020", state = "missing", sha = "-" },
		})).toBe("R0010\n1 R0010/1/c0010 c0010 finished abc\n2 R0010/2/c0020 c0020 missing -")
	end)
end)
