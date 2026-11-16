--!strict
-- c0394 AC1: added.luau (pure) places added issues in a raft's order and plans what lands, what blocks and what is above
-- the blocker, and refuses an unknown `waits:` value and a `before:` that names no unlanded member.
-- Waiting is `waits: approval`, not approved, not done. `members` is the raft's unlanded members.
local added = require("@znile/engine/added")
local t = require("@tests/lib/t")

local function fact(id: string, over: { [string]: any }?): added.Fact
	local f: { [string]: any } =
		{ id = id, state = "active", waits = nil, before = nil, approved = false, finished = false }
	local overrides: { [string]: any } = over or {}
	for k, v in overrides do
		f[k] = v
	end
	return f :: any
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("c0394 added: place and plan a raft's order", function(it)
	it("a waits value other than approval is a problem", function()
		local members = { "c0010", "c0200" }
		t.expect(added.problem(fact("c0200", { waits = "approval" }), members)).toBe(nil)
		t.expect(added.problem(fact("c0010"), members)).toBe(nil)
		for _, bad in { "later", "Approval", "approve", "yes" } do
			local why = added.problem(fact("c0200", { waits = bad }), members)
			t.expect(why ~= nil).toBe(true)
			-- the refusal names the item and the rule
			t.expect(has(why :: string, "c0200")).toBe(true)
			t.expect(has(why :: string, "waits")).toBe(true)
			t.expect(has(why :: string, "approval")).toBe(true)
		end
		-- an unknown value never counts as waiting
		t.expect(added.isWaiting(fact("c0200", { waits = "later" }))).toBe(false)
		t.expect(added.isWaiting(fact("c0200"))).toBe(false)
		t.expect(added.isWaiting(fact("c0200", { waits = "approval" }))).toBe(true)
	end)

	it("a before naming a landed member or no member is a problem", function()
		-- c0010 has landed, so it is not among the unlanded members
		local unlanded = { "c0020", "c0200" }
		local ok = added.problem(fact("c0200", { waits = "approval", before = "c0020" }), unlanded)
		t.expect(ok).toBe(nil)
		for _, named in { "c0010", "c9999" } do
			local why = added.problem(fact("c0200", { waits = "approval", before = named }), unlanded)
			t.expect(why ~= nil).toBe(true)
			t.expect(has(why :: string, "c0200")).toBe(true)
			t.expect(has(why :: string, named)).toBe(true)
			t.expect(has(why :: string, "before")).toBe(true)
		end
	end)

	it("place puts an added issue before the member it names, else last, lowest id first", function()
		local facts = {
			fact("c0010"),
			fact("c0200", { waits = "approval", before = "c0010" }),
			fact("c0120", { waits = "approval", before = "c0010" }),
			fact("c0201", { waits = "approval" }),
			fact("c0150", { waits = "approval" }),
		}
		-- the user's example: T2 in front of T1, T3 last
		t.expect(added.place({ "c0010" }, { facts[1], facts[2], facts[4] }))
			.toEqual({ "c0200", "c0010", "c0201" })
		-- several in front of the same member and several last go by lowest id first
		t.expect(added.place({ "c0010" }, facts)).toEqual({ "c0120", "c0200", "c0010", "c0150", "c0201" })
		-- in front of the middle member of a longer base
		local two = { fact("c0010"), fact("c0020"), fact("c0200", { waits = "approval", before = "c0020" }) }
		t.expect(added.place({ "c0010", "c0020" }, two)).toEqual({ "c0010", "c0200", "c0020" })
	end)

	it("place leaves a raft with no added issue in stack.order's order", function()
		-- not sorted by id: the order given is the order kept
		t.expect(added.place({ "c0030", "c0010", "c0020" }, { fact("c0030"), fact("c0010"), fact("c0020") }))
			.toEqual({ "c0030", "c0010", "c0020" })
		t.expect(added.place({}, {})).toEqual({})
	end)

	it("plan lands the finished members below the first waiting one", function()
		local facts = {
			fact("c0001", { state = "done" }),
			fact("c0002", { finished = true }),
			fact("c0003", { finished = true }),
			fact("c0004", { waits = "approval" }),
			fact("c0005", { finished = true }),
			fact("c0006", { waits = "approval" }),
		}
		local plan = added.plan({ "c0001", "c0002", "c0003", "c0004", "c0005", "c0006" }, facts)
		t.expect(plan.order).toEqual({ "c0001", "c0002", "c0003", "c0004", "c0005", "c0006" })
		t.expect(plan.landed).toEqual({ "c0001" })
		t.expect(plan.lands).toEqual({ "c0002", "c0003" })
		t.expect(plan.blocker).toBe("c0004")
		t.expect(plan.unfinished).toBe(nil)
		t.expect(plan.above).toEqual({ "c0005", "c0006" })
		-- a blocker first: nothing lands, everything else is above it
		local front = added.plan({ "c0004", "c0002", "c0003" }, { facts[4], facts[2], facts[3] })
		t.expect(#front.lands).toBe(0)
		t.expect(front.blocker).toBe("c0004")
		t.expect(front.above).toEqual({ "c0002", "c0003" })
	end)

	it("an approved added issue is not a blocker", function()
		t.expect(added.isWaiting(fact("c0004", { waits = "approval", approved = true }))).toBe(false)
		t.expect(added.isWaiting(fact("c0004", { waits = "approval", state = "done" }))).toBe(false)
		local facts = {
			fact("c0002", { finished = true }),
			fact("c0004", { waits = "approval", approved = true, finished = true }),
			fact("c0005", { finished = true }),
		}
		local plan = added.plan({ "c0002", "c0004", "c0005" }, facts)
		t.expect(plan.blocker).toBe(nil)
		t.expect(plan.unfinished).toBe(nil)
		t.expect(plan.lands).toEqual({ "c0002", "c0004", "c0005" })
		t.expect(#plan.above).toBe(0)
	end)

	it("plan names the first unfinished member below the blocker", function()
		local facts = {
			fact("c0001", { state = "done" }),
			fact("c0002"),
			fact("c0003", { finished = true }),
			fact("c0004", { waits = "approval" }),
			fact("c0005"),
		}
		local plan = added.plan({ "c0001", "c0002", "c0003", "c0004", "c0005" }, facts)
		-- c0005 is above the blocker: it is not asked for
		t.expect(plan.unfinished).toBe("c0002")
		t.expect(plan.blocker).toBe("c0004")
		t.expect(plan.landed).toEqual({ "c0001" })
		-- with nothing unfinished below the blocker there is none to name
		facts[2] = fact("c0002", { finished = true })
		t.expect(added.plan({ "c0001", "c0002", "c0003", "c0004", "c0005" }, facts).unfinished).toBe(nil)
	end)
end)
