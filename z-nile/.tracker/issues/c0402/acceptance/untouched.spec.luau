--!strict
-- c0402 AC4: the cap changes nothing else. A solo issue is still alone whatever the cap, and an explicit smaller
-- cap still wins over the default.
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

return t.spec("c0402 the rules the cap does not touch", function(it)
	it("a solo issue is alone, a smaller explicit cap still wins", function()
		t.expect(lines({ issue("c0001", 100, true), issue("c0002", 100) }))
			.toEqual({ "new c0001 single", "new c0002" })
		local ops = raftplan.plan({ issue("c0001", 300), issue("c0002", 300) }, {}, 500)
		t.expect(#ops).toBe(2)
	end)
end)
