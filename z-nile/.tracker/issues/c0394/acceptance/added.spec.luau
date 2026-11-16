--!strict
-- c0394 AC1: added.luau (pure) places added issues in a raft's order, names the first waiting member and the member
-- below it, and refuses an unknown `waits:` value and a `before:` that names an added issue or no member.
-- Waiting is `waits: approval`, not approved, not landed. A landed issue is never judged.
local added = require("@znile/engine/added")
local t = require("@tests/lib/t")

local function fact(id: string, over: { [string]: any }?): added.Fact
	local f: { [string]: any } = { id = id, landed = false, waits = nil, before = nil, approved = false }
	local overrides: { [string]: any } = over or {}
	for k, v in overrides do
		f[k] = v
	end
	return f :: any
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("c0394 added: place and blocker over a raft's order", function(it)
	it("a waits value other than approval is a problem", function()
		local ok = fact("c0200", { waits = "approval" })
		t.expect(added.problem(ok, { fact("c0010"), ok })).toBe(nil)
		t.expect(added.problem(fact("c0010"), { fact("c0010") })).toBe(nil)
		for _, bad in { "later", "Approval", "approve", "yes" } do
			local odd = fact("c0200", { waits = bad })
			local why = added.problem(odd, { fact("c0010"), odd })
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

	it(
		"a before naming an added issue or no member is a problem, and a landed issue is not judged",
		function()
			local t1 = fact("c0010")
			local front = fact("c0200", { waits = "approval", before = "c0010" })
			local second = fact("c0201", { waits = "approval", before = "c0200" }) -- names an added issue
			local nowhere = fact("c0202", { waits = "approval", before = "c9999" }) -- names no member
			local facts = { t1, front, second, nowhere }
			t.expect(added.problem(front, facts)).toBe(nil)
			for _, bad in { second, nowhere } do
				local why = added.problem(bad, facts)
				t.expect(why ~= nil).toBe(true)
				t.expect(has(why :: string, bad.id)).toBe(true)
				t.expect(has(why :: string, "before")).toBe(true)
				t.expect(has(why :: string, bad.before :: string)).toBe(true)
			end
			-- after the first landing T2 is in done/ and its `before: c0010` names a landed member: not judged
			local landed = fact("c0203", { landed = true, waits = "approval", before = "c9999" })
			t.expect(added.problem(landed, { landed, t1 })).toBe(nil)
		end
	)

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

	it("blocker is the first waiting member and names the member below it", function()
		local facts = {
			fact("c0001", { landed = true }),
			fact("c0002"),
			fact("c0003"),
			fact("c0004", { waits = "approval" }),
			fact("c0005"),
			fact("c0006", { waits = "approval" }),
		}
		local order = { "c0001", "c0002", "c0003", "c0004", "c0005", "c0006" }
		local blocker, below = added.blocker(order, facts)
		t.expect(blocker).toBe("c0004")
		t.expect(below).toBe("c0003") -- what `done` lands through
		-- a blocker first: there is nothing below it
		local first, none = added.blocker({ "c0004", "c0002" }, { facts[4], facts[2] })
		t.expect(first).toBe("c0004")
		t.expect(none).toBe(nil)
		-- everything below it has landed: nothing to land through
		local landedBelow, nothing = added.blocker(
			{ "c0001", "c0004", "c0005" },
			{ facts[1], facts[4], facts[5] }
		)
		t.expect(landedBelow).toBe("c0004")
		t.expect(nothing).toBe(nil)
		-- no waiting member: no blocker, and the raft lands as c0248 lands it
		local clear, empty = added.blocker({ "c0001", "c0002" }, { facts[1], facts[2] })
		t.expect(clear).toBe(nil)
		t.expect(empty).toBe(nil)
	end)

	it("an approved added issue is not a blocker", function()
		t.expect(added.isWaiting(fact("c0004", { waits = "approval", approved = true }))).toBe(false)
		t.expect(added.isWaiting(fact("c0004", { waits = "approval", landed = true }))).toBe(false)
		local facts = {
			fact("c0002"),
			fact("c0004", { waits = "approval", approved = true }),
			fact("c0005", { waits = "approval" }),
		}
		local blocker, below = added.blocker({ "c0002", "c0004", "c0005" }, facts)
		t.expect(blocker).toBe("c0005")
		t.expect(below).toBe("c0004")
	end)
end)
