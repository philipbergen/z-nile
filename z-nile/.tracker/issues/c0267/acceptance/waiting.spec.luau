--!strict
-- c0267 AC5, AC6: readycheck.waiting names the issues whose approval is all `./zn ready` would refuse a raft for, in
-- the layer order given, and approval.stateOf is the one reading of an approval's text (reasonOf keeps its words).
-- Pure: texts in.
local approval = require("@znile/engine/approval")
local contract = require("@znile/engine/contract")
local raftplan = require("@znile/engine/raftplan")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")

local CHECK = 'check "AC1: holds" true\n'

local function docOf(id: string, design: string?): string
	return table.concat({
		"---",
		`id: {id}`,
		"design: ready",
		"---",
		"",
		`# {id}`,
		"",
		"## Problem",
		"P",
		"",
		"## Solution",
		"S",
		"",
		"## Design",
		design or "D",
		"",
		"## Acceptance criteria",
		"A",
		"",
		"## Test plan",
		"T",
		"",
	}, "\n")
end

local function approvalOf(doc: string): string
	local built = contract.build(doc, CHECK, {}) :: contract.Parts
	return contract.render({
		{
			when = "2026-11-15T00:00:00Z",
			who = "Ada",
			hash = contract.hash(built),
			parts = contract.partHashes(built),
		},
	})
end

-- a member whose approval is `kind`: "holds", "none", "bad", or "changed" (approved, then its Design edited)
local function member(id: string, kind: string, deps: { readycheck.Dep }?): readycheck.Member
	local doc = docOf(id)
	local text: string? = nil
	if kind == "holds" then
		text = approvalOf(doc)
	elseif kind == "bad" then
		text = "not an approval\n"
	elseif kind == "changed" then
		text = approvalOf(doc)
		doc = docOf(id, "changed after approval")
	end
	local files: { [string]: string } = { [`{id}.md`] = doc, ["check.sh"] = CHECK, ["harvest.md"] = "kept\n" }
	if text then
		files["approval.md"] = text
	end
	return {
		id = id,
		design = "ready",
		doc = doc,
		deps = deps or {},
		files = files,
		specs = {},
		approval = text,
		approvalFile = `z-nile/.tracker/issues/{id}/approval.md`,
	}
end

local function raftOf(members: { readycheck.Member }, over: { [string]: any }?): readycheck.Raft
	local ids: { string } = {}
	local map: { [string]: string } = {}
	for _, m in members do
		table.insert(ids, m.id)
		map[m.id] = raftplan.recordHash(m.id, m.files)
	end
	local grouped = raftplan.renderGrouped(map)
	local files: { [string]: string } = { ["check.sh"] = CHECK }
	if #members > 1 then
		files["design-review-001.md"] = `Grouped: {grouped}\n`
	end
	local r: readycheck.Raft = {
		id = "R0050",
		where = "backlog",
		status = "prepared",
		dir = "z-nile/.tracker/rafts/R0050",
		design = "ready",
		doc = "---\ndesign: ready\n---\n",
		grouped = grouped,
		questions = false,
		listed = ids,
		members = members,
		files = files,
		loaded = true,
	}
	local extra: { [string]: any } = over or {}
	for k, v in extra do
		(r :: any)[k] = v
	end
	return r
end

local function ids(list: { readycheck.Unapproved }?): string
	if not list then
		return "nil"
	end
	local out: { string } = {}
	for _, u in list do
		table.insert(out, `{u.id}:{u.state}`)
	end
	return table.concat(out, ",")
end

return t.spec("c0267: which issues wait for a person's approval", function(it)
	it("AC5: every approval holds: an empty list, and ready accepts", function()
		local r = raftOf({ member("c0001", "holds"), member("c0002", "holds") })
		t.expect((readycheck.reason(r))).toBe(nil)
		t.expect(ids(readycheck.waiting(r, { "c0001", "c0002" }))).toBe("")
	end)

	it("AC5: a missing, an unreadable and a changed approval are each named, in the order given", function()
		local r = raftOf({
			member("c0001", "holds"),
			member("c0002", "none"),
			member("c0003", "bad"),
			member("c0004", "changed"),
		})
		t.expect(ids(readycheck.waiting(r, { "c0004", "c0003", "c0002", "c0001" })))
			.toBe("c0004:changed,c0003:bad,c0002:none")
		-- a member the order leaves out comes after, by id
		t.expect(ids(readycheck.waiting(r, { "c0003" }))).toBe("c0003:bad,c0002:none,c0004:changed")
		local list = readycheck.waiting(r, { "c0004" }) :: { readycheck.Unapproved }
		t.expect(list[1].id).toBe("c0004")
		t.expect(table.concat(list[1].changed, ",")).toBe("design")
		t.expect(#list[2].changed + #list[3].changed).toBe(0)
		-- an unreadable approval carries why, and every entry its file
		t.expect(list[2].id).toBe("c0002")
		t.expect(list[2].why).toBe(nil)
		t.expect(list[3].id).toBe("c0003")
		t.expect(list[3].why ~= nil and list[3].why ~= "").toBe(true)
		for _, u in list do
			t.expect(u.file).toBe(`z-nile/.tracker/issues/{u.id}/approval.md`)
		end
		-- ready itself still refuses the raft, with its own words
		t.expect(string.find(readycheck.reason(r) or "", "approve", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC5: anything else ready refuses for comes first: nil, so the chain lets z-ready refuse it",
		function()
			local dep = { { id = "c0099", state = "backlog" } }
			t.expect(readycheck.waiting(raftOf({ member("c0001", "none", dep) }), { "c0001" })).toBe(nil)
			-- a member whose check.sh has no check line (a refusal c0250's ready keeps as it is)
			local unchecked = member("c0001", "none")
			unchecked.files["check.sh"] = "true\n"
			t.expect(readycheck.waiting(raftOf({ unchecked }), { "c0001" })).toBe(nil)
			t.expect(
				readycheck.waiting(raftOf({ member("c0001", "none") }, { design = "draft" }), { "c0001" })
			)
				.toBe(nil)
			local draft = member("c0002", "none")
			draft.design = "draft"
			t.expect(readycheck.waiting(raftOf({ member("c0001", "none"), draft }), {})).toBe(nil)
			-- not loaded: the design files were never read, so nothing is judged
			t.expect(readycheck.waiting(raftOf({ member("c0001", "none") }, { loaded = false }), {}))
				.toBe(nil)
			-- the grouping record: a member redesigned since z-raft grouped it
			local r = raftOf({ member("c0001", "none"), member("c0002", "none") })
			r.members[2].files["harvest.md"] = "rewritten\n"
			t.expect(readycheck.waiting(r, {})).toBe(nil)
		end
	)

	it("AC6: approval.stateOf is the one reading, and reasonOf keeps its answers' heads", function()
		local doc = docOf("c0001")
		local parts = contract.build(doc, CHECK, {}) :: contract.Parts
		local state, changed, err = approval.stateOf(parts, nil)
		t.expect(state).toBe("none")
		t.expect(#changed).toBe(0)
		t.expect(err).toBe(nil)
		t.expect((approval.stateOf(parts, approvalOf(doc)))).toBe("holds")
		local bad, _, why = approval.stateOf(parts, "not an approval\n")
		t.expect(bad).toBe("bad")
		t.expect(why ~= nil).toBe(true)
		local moved = contract.build(docOf("c0001", "changed"), CHECK, {}) :: contract.Parts
		local was, parts2 = approval.stateOf(moved, approvalOf(doc))
		t.expect(was).toBe("changed")
		t.expect(#parts2 > 0).toBe(true)
		local file = "z-nile/.tracker/issues/c0001/approval.md"
		t.expect(approval.reasonOf("c0001", file, parts, nil, false)).toBe(nil)
		-- each answer's head names its state and the way through; a later item may reword what follows it
		local function head(text: string?, start: string): boolean
			return text ~= nil and string.sub(text :: string, 1, #start) == start
		end
		local none = approval.reasonOf("c0001", file, parts, nil, true)
		-- c0369's one command, from anywhere (re-prep of 2026-11-17)
		t.expect(
			head(
				none,
				"c0001 has no approval: run ./zn approve c0001 in a terminal, from anywhere in the checkout"
			)
		).toBe(true)
		t.expect(string.find(none or "", "--publish", 1, true) == nil).toBe(true)
		-- the dispatched path drafts, merges and rafts before approval: no "one-time step" for a legacy item
		t.expect(string.find(none or "", "one-time step", 1, true) == nil).toBe(true)
		t.expect(approval.reasonOf("c0001", file, parts, approvalOf(doc), true)).toBe(nil)
		t.expect(
			head(
				approval.reasonOf("c0001", file, parts, "not an approval\n", true),
				`c0001: {file} does not parse: {why}`
			)
		).toBe(true)
		t.expect(
			head(
				approval.reasonOf("c0001", file, moved, approvalOf(doc), true),
				`c0001's contract changed since approval: {table.concat(parts2, ", ")}.`
			)
		).toBe(true)
	end)
end)
