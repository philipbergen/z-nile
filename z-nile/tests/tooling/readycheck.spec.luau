--!strict
-- readycheck.reason is the check `./zn ready` and `./zn work next` both call.
local contract = require("@znile/engine/contract")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")

local DOC = table.concat({
	"---",
	"id: c0001",
	"design: ready",
	"---",
	"",
	"# c0001",
	"",
	"## Problem",
	"P",
	"",
	"## Solution",
	"S",
	"",
	"## Design",
	"D",
	"",
	"## Acceptance criteria",
	"A",
	"",
	"## Test plan",
	"T",
	"",
}, "\n")

local CHECK = 'check "AC1: holds" true\n'

local function member(approval: string?): readycheck.Member
	return {
		id = "c0001",
		design = "ready",
		doc = DOC,
		deps = {},
		files = { ["c0001.md"] = DOC, ["check.sh"] = CHECK, ["approval.md"] = approval or "" },
		specs = {},
		approval = approval,
		approvalFile = "z-nile/.tracker/issues/c0001/approval.md",
	}
end

local function raft(over: { [string]: any }): readycheck.Raft
	local r: readycheck.Raft = {
		id = "R0001",
		where = "backlog",
		status = "prepared",
		dir = "z-nile/.tracker/rafts/R0001",
		design = "ready",
		doc = "---\ndesign: ready\n---\n",
		grouped = nil,
		questions = false,
		listed = { "c0001" },
		members = { member(nil) },
		files = { ["check.sh"] = CHECK },
		loaded = true,
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

return t.spec("ready would accept it", function(it)
	it("refuses questions, a held raft, and a missing approval", function()
		local asked = raft({ questions = true })
		local why = readycheck.reason(asked)
		t.expect(string.find(why or "", "questions.md", 1, true) ~= nil).toBe(true)
		local held = raft({ where = "active", status = "active" })
		t.expect(string.find(readycheck.reason(held) or "", "only a prepared raft", 1, true) ~= nil)
			.toBe(true)
		local bare = readycheck.reason(raft({}))
		t.expect(string.find(bare or "", "./zn approve c0001 --publish", 1, true) ~= nil).toBe(true)
	end)

	it("accepts a member whose approval still holds", function()
		local parts = contract.build(DOC, CHECK, {})
		t.expect(parts ~= nil).toBe(true)
		local built = parts :: contract.Parts
		local text = contract.render({
			{
				when = "2026-11-13T00:00:00Z",
				who = "Ada",
				hash = contract.hash(built),
				parts = contract.partHashes(built),
			},
		})
		local why = readycheck.reason(raft({ members = { member(text) } }))
		t.expect(why).toBe(nil)
	end)
end)
