--!strict
-- c0267 AC11: the fail-safes where the dispatcher feeds the chain (design review 001 F4). dispatcher.approvalFacts
-- reads approvals only for a prepared backlog raft and turns a read that answers nothing, or errors, into
-- `unreadable`; workread.unapprovedFrom turns a failed collect or a raft collect did not see into nil and why, never
-- an empty list (which would let the chain run z-ready). Pure: a stub ctx and collect's answers.
local dispatcher = require("@znile/engine/dispatcher")
local t = require("@tests/lib/t")
local workread = require("@znile/engine/workread")

local LIST =
	{ { id = "c0010", state = "none", changed = {}, file = "z-nile/.tracker/issues/c0010/approval.md" } }

-- a ctx whose only member is `approvals`, counting its calls
local function ctxWith(answer: (string) -> (any, any)): (any, () -> number)
	local calls = 0
	local ctx = {
		approvals = function(id: string): (any, any)
			calls += 1
			return answer(id)
		end,
	}
	return ctx, function(): number
		return calls
	end
end

return t.spec("c0267: the approvals read where the dispatcher acts", function(it)
	it("AC11: a prepared backlog raft's answer is passed through as it is", function()
		local ctx, calls = ctxWith(function(_id: string): (any, any)
			return LIST, nil
		end)
		local list, why = dispatcher.approvalFacts(ctx, "raft", "backlog", "prepared", "R0050")
		t.expect(list).toBe(LIST)
		t.expect(why).toBe(nil)
		t.expect(calls()).toBe(1)
		local empty = ctxWith(function(_id: string): (any, any)
			return {}, nil
		end)
		local none, noWhy = dispatcher.approvalFacts(empty, "raft", "backlog", "prepared", "R0050")
		t.expect(#(none :: { any })).toBe(0)
		t.expect(noWhy).toBe(nil)
	end)

	it("AC11: no answer, an error or a why is unreadable, never an empty list", function()
		local silent = ctxWith(function(_id: string): (any, any)
			return nil, nil
		end)
		local a, aWhy = dispatcher.approvalFacts(silent, "raft", "backlog", "prepared", "R0050")
		t.expect(a).toBe(nil)
		t.expect(aWhy).toBe("no answer")
		local said = ctxWith(function(_id: string): (any, any)
			return nil, "git ls-tree failed"
		end)
		local b, bWhy = dispatcher.approvalFacts(said, "raft", "backlog", "prepared", "R0050")
		t.expect(b).toBe(nil)
		t.expect(bWhy).toBe("git ls-tree failed")
		local thrown = ctxWith(function(_id: string): (any, any)
			error("the reader broke", 0)
		end)
		local c, cWhy = dispatcher.approvalFacts(thrown, "raft", "backlog", "prepared", "R0050")
		t.expect(c).toBe(nil)
		t.expect(string.find(cWhy or "", "the reader broke", 1, true) ~= nil).toBe(true)
	end)

	it("AC11: nothing else is read: an issue, an active raft, a raft not prepared, a done raft", function()
		local ctx, calls = ctxWith(function(_id: string): (any, any)
			error("must not be called", 0)
		end)
		for _, case in
			{
				{ "issue", "backlog", "prepared" },
				{ "raft", "active", "active" },
				{ "raft", "backlog", "preparing" },
				{ "raft", "done", "done" },
				{ "none", "none", "none" },
			}
		do
			local list, why = dispatcher.approvalFacts(ctx, case[1], case[2], case[3], "R0050")
			t.expect(list).toBe(nil)
			t.expect(why).toBe(nil)
		end
		t.expect(calls()).toBe(0)
	end)

	it("AC11: collect's answer: the raft's list, an empty list, or nil and why", function()
		local function raft(id: string, unapproved: any): any
			return { id = id, unapproved = unapproved }
		end
		local seen, none = workread.unapprovedFrom(true, { rafts = { raft("R0050", LIST) } }, "R0050")
		t.expect(seen).toBe(LIST)
		t.expect(none).toBe(nil)
		-- another refusal first, or ready would accept: the reader left the field nil, which is an empty list
		local other = workread.unapprovedFrom(true, { rafts = { raft("R0050", nil) } }, "R0050")
		t.expect(#(other :: { any })).toBe(0)
		-- a failed collect, a missing raft and an answer with no rafts are nil and why
		local failed, fWhy = workread.unapprovedFrom(false, "git ls-tree failed", "R0050")
		t.expect(failed).toBe(nil)
		t.expect(fWhy).toBe("git ls-tree failed")
		local missing, mWhy = workread.unapprovedFrom(true, { rafts = { raft("R0051", LIST) } }, "R0050")
		t.expect(missing).toBe(nil)
		t.expect(string.find(mWhy or "", "R0050", 1, true) ~= nil).toBe(true)
		local shapeless, sWhy = workread.unapprovedFrom(true, {}, "R0050")
		t.expect(shapeless).toBe(nil)
		t.expect(sWhy ~= nil).toBe(true)
	end)
end)
