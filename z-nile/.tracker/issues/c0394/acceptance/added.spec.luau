--!strict
-- c0394 AC1: added.luau (pure) splits a raft's members into landed, due and waiting, and refuses an unknown
-- `waits:` value. Waiting is `waits: approval`, not yet approved, not done. The split keeps the order given.
local added = require("@znile/engine/added")
local t = require("@tests/lib/t")

local function fact(id: string, state: string, waits: string?, approved: boolean): added.Fact
	return { id = id, state = state :: any, waits = waits, approved = approved }
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("c0394 added: landed, due and waiting", function(it)
	it("a waits value other than approval is a problem", function()
		t.expect(added.problem("c0010", nil)).toBe(nil)
		t.expect(added.problem("c0010", "approval")).toBe(nil)
		for _, bad in { "later", "Approval", "approve", "yes" } do
			local why = added.problem("c0010", bad)
			t.expect(why ~= nil).toBe(true)
			-- the refusal names the item and the rule
			t.expect(has(why :: string, "c0010")).toBe(true)
			t.expect(has(why :: string, "waits")).toBe(true)
			t.expect(has(why :: string, "approval")).toBe(true)
		end
		-- an unknown value never counts as waiting
		t.expect(added.isWaiting(fact("c0010", "active", "later", false))).toBe(false)
		t.expect(added.isWaiting(fact("c0010", "active", nil, false))).toBe(false)
		t.expect(added.isWaiting(fact("c0010", "active", "approval", false))).toBe(true)
	end)

	it("split keeps order: landed, due, waiting", function()
		local split = added.split({
			fact("c0050", "active", "approval", false),
			fact("c0010", "done", nil, false),
			fact("c0040", "active", nil, false),
			fact("c0020", "active", "approval", false),
			fact("c0030", "backlog", nil, false),
			fact("c0060", "done", nil, false),
		})
		t.expect(split.landed).toEqual({ "c0010", "c0060" })
		t.expect(split.due).toEqual({ "c0040", "c0030" })
		t.expect(split.waiting).toEqual({ "c0050", "c0020" })
		-- no members at all
		local none = added.split({})
		t.expect(#none.landed + #none.due + #none.waiting).toBe(0)
		-- a done member that once waited is landed, never waiting
		local was = added.split({ fact("c0070", "done", "approval", false) })
		t.expect(was.landed).toEqual({ "c0070" })
		t.expect(#was.waiting).toBe(0)
	end)

	it("an approved added issue is due", function()
		t.expect(added.isWaiting(fact("c0010", "active", "approval", true))).toBe(false)
		t.expect(added.isWaiting(fact("c0010", "done", "approval", false))).toBe(false)
		local split = added.split({
			fact("c0010", "active", nil, false),
			fact("c0020", "active", "approval", true),
			fact("c0030", "active", "approval", false),
		})
		t.expect(split.due).toEqual({ "c0010", "c0020" })
		t.expect(split.waiting).toEqual({ "c0030" })
		t.expect(#split.landed).toBe(0)
	end)
end)
