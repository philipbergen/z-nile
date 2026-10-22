--!strict
-- Spend attribution must be exact (lines sum to the diff) and follow Touched modules.
local spend = require("../../../scripts/tracker/spend")
local t = require("@tests/lib/t")

local function item(id: string, slug: string): any
	return {
		id = id,
		kind = "issue",
		state = "backlog",
		dir = "tests/fixtures/spend",
		doc = `tests/fixtures/spend/{id}-{slug}.md`,
		slug = slug,
	}
end
local ADD, MUL = item("f9990", "add"), item("f9991", "mul")

return t.spec("spend", function(it)
	it("reads Touched modules, ignoring HTML comments", function()
		t.expect(spend.ownedPaths(ADD)).toEqual({ "src/shared/Logic/Add", "tests/unit/Add" })
	end)

	it("assigns files to their owners and splits unowned files", function()
		local shares = spend.attribute({ ADD, MUL }, {
			{ path = "src/shared/Logic/Add/init.luau", added = 10, removed = 2 },
			{ path = "src/shared/Logic/Mul/init.luau", added = 6, removed = 0 },
			{ path = "README.md", added = 3, removed = 1 },
		}, 20, "explicit")
		t.expect(shares[1].added + shares[2].added).toBe(19)
		t.expect(shares[1].removed + shares[2].removed).toBe(3)
		t.expect(shares[1].added >= 11 and shares[1].added <= 12).toBe(true)
		t.expect(shares[1].minutes + shares[2].minutes).toBeNear(20, 0.11)
	end)

	it("odd lines split evenly still sum exactly", function()
		local shares = spend.attribute({ ADD, MUL }, {
			{ path = "tests/unit/Mul/mul.spec.luau", added = 9, removed = 0 },
		}, 0, "raft")
		t.expect(shares[1].added + shares[2].added).toBe(9)
		t.expect(shares[1].how).toBe("raft+proportional")
	end)

	it("minutes follow lines added", function()
		local shares = spend.attribute({ ADD, MUL }, {
			{ path = "src/shared/Logic/Add/a.luau", added = 30, removed = 0 },
			{ path = "src/shared/Logic/Mul/m.luau", added = 10, removed = 0 },
		}, 40, "focus")
		t.expect(shares[1].minutes).toBeNear(30, 0.01)
		t.expect(shares[2].minutes).toBeNear(10, 0.01)
	end)
end)
