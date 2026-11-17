--!strict
-- c0402 AC1: the raft cap is 3,000 changed lines. raftplan.CAP is 3000 and the plan honours it at the
-- boundary with its default (an issue of 3,000 fits a raft, 3,001 is a raft by itself, a raft's sum may reach 3,000
-- and not 3,001).
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")

local ROOT = "z-nile/.tracker"
local function issue(id: string, size: number, solo: boolean?): raftplan.Issue
	return {
		id = id,
		type = "chore",
		root = ROOT,
		state = "backlog",
		status = "prepared",
		design = "ready",
		raft = "",
		size = size,
		solo = solo == true,
		touched = nil,
	}
end
-- the default-cap plan as one line per op: "new c0001,c0002", "new c0003 single"
local function lines(issues: { raftplan.Issue }): { string }
	local ops = raftplan.plan(issues, {})
	local out: { string } = {}
	for _, op in ops do
		table.insert(out, `new {table.concat(op.issues, ",")}{if op.single then " single" else ""}`)
	end
	return out
end

return t.spec("c0402 the plan's cap is 3,000 changed lines", function(it)
	it("raftplan.CAP is 3000 and is the default the plan uses", function()
		t.expect(raftplan.CAP).toBe(3000)
		-- 1,600 + 1,400 was two rafts under 1,500 and is one at 3,000
		t.expect(lines({ issue("c0001", 1600), issue("c0002", 1400) })).toEqual({ "new c0001,c0002" })
	end)

	it("a sum of exactly 3,000 fits one raft and 3,001 starts another", function()
		t.expect(lines({ issue("c0001", 1500), issue("c0002", 1500) })).toEqual({ "new c0001,c0002" })
		t.expect(lines({ issue("c0001", 1500), issue("c0002", 1501) })).toEqual({ "new c0001", "new c0002" })
	end)

	it("an issue of 3,000 is not over the cap, and one of 3,001 is a raft by itself", function()
		t.expect(lines({ issue("c0001", 3000) })).toEqual({ "new c0001" })
		t.expect(lines({ issue("c0001", 3001) })).toEqual({ "new c0001 single" })
		-- an issue of 2,000 shares a raft with 1,000 more (it was single under the old cap)
		t.expect(lines({ issue("c0001", 2000), issue("c0002", 1000) })).toEqual({ "new c0001,c0002" })
	end)
end)
