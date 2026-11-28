--!strict
-- c0458 AC4 (pure): the publisher's raise exception covers the stop of a raft of several tickets that is not light, and
-- still refuses everything else. Texts in, a boolean out.
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")

local function ticket(id: string, over: { [string]: string }?, body: string?): string
	local f: { [string]: string } = {
		id = id,
		title = `{id} title`,
		risk = "normal",
		design = "ready",
		raft = "R0306",
		status = "active-a-b-c",
	}
	for k, v in (over or {}) :: { [string]: string } do
		f[k] = v
	end
	local lines = { "---" }
	for _, k in { "id", "title", "risk", "design", "raft", "status" } do
		table.insert(lines, `{k}: {f[k]}`)
	end
	table.insert(lines, "---")
	return table.concat(lines, "\n") .. `\n\n# {id}\n\n{body or "Body.\n"}`
end

local function raftDoc(issues: string, light: string?): string
	return `---\nid: R0306\n{if light then `light: {light}\n` else ""}issues: {issues}\nstatus: active-a-b-c\n---\n\n# R0306\n`
end

return t.spec("c0458: the raise exception covers a raft of several tickets", function(it)
	it(
		"AC4: one ticket raised, two released, in a raft that is not light, are accepted as one raise",
		function()
			local raise =
				{ raft = "R0306", raised = { c0011 = "risky" }, released = { "c0010", "c0012" } } :: any
			local raisedNew =
				ticket("c0011", { risk = "risky", design = "draft", raft = "", status = "new-a-b-c" })
			t.expect(publish.raiseEdit("c0011", ticket("c0011"), raisedNew, raise)).toBe(true)
			for _, id in { "c0010", "c0012" } do
				t.expect(
					publish.raiseEdit(
						id,
						ticket(id),
						ticket(id, { raft = "", status = "prepared-a-b-c" }),
						raise
					)
				).toBe(true)
			end
			t.expect(publish.raiseEdit("R0306", raftDoc("[c0010, c0011, c0012]"), raftDoc("[]"), raise))
				.toBe(true)
			-- two raised tickets
			local two = {
				raft = "R0306",
				raised = { c0011 = "risky", c0012 = "normal" },
				released = { "c0010" },
			} :: any
			t.expect(
				publish.raiseEdit(
					"c0012",
					ticket("c0012", { risk = "easy" }),
					ticket("c0012", { risk = "normal", design = "draft", raft = "" }),
					two
				)
			).toBe(true)
		end
	)

	it("AC4: the exception refuses what stop does not write, one rule at a time", function()
		local raise = { raft = "R0306", raised = { c0011 = "risky" }, released = { "c0010", "c0012" } } :: any
		local ok = ticket("c0011", { risk = "risky", design = "draft", raft = "", status = "new-a-b-c" })
		t.expect(publish.raiseEdit("c0011", ticket("c0011"), ok, raise)).toBe(true) -- control: the accepted document
		local function refuses(old: string, new: string, r: any?)
			t.expect(publish.raiseEdit("c0011", old, new, r or raise)).toBe(false)
		end
		-- the raised ticket: one difference from the accepted document each
		refuses(
			ticket("c0011", { risk = "risky" }),
			ticket("c0011", { risk = "normal", design = "draft", raft = "" }),
			{ raft = "R0306", raised = { c0011 = "normal" }, released = {} } :: any
		) -- lowered below its own level
		refuses(ticket("c0011"), ticket("c0011", { risk = "normal", design = "draft", raft = "" })) -- not the raised level
		refuses(ticket("c0011"), ticket("c0011", { risk = "risky", design = "ready", raft = "" })) -- design not draft
		refuses(ticket("c0011", { raft = "R7777" }), ok) -- came from another raft
		refuses(ticket("c0011"), ticket("c0011", { risk = "risky", design = "draft" })) -- keeps its raft
		refuses(ticket("c0011"), ticket("c0011", { risk = "risky", design = "draft", raft = "R9999" })) -- another raft
		refuses(
			ticket("c0011", { risk = "easy" }),
			ticket("c0011", { risk = "easy", design = "draft", raft = "" }),
			{ raft = "R0306", raised = { c0011 = "easy" }, released = {} } :: any
		) -- a raise to easy
		refuses(
			ticket("c0011"),
			ticket("c0011", { risk = "risky", design = "draft", raft = "" }, "Other body.\n")
		) -- a body edit
		t.expect(
			publish.raiseEdit(
				"c0011",
				ticket("c0011", { risk = "normal" }),
				ticket("c0011", { risk = "normal", design = "draft", raft = "" }),
				{ raft = "R0306", raised = { c0011 = "normal" }, released = {} } :: any
			)
		).toBe(true) -- already at the raised level
		-- a released member changes only raft: and status:
		t.expect(
			publish.raiseEdit("c0010", ticket("c0010"), ticket("c0010", { raft = "", risk = "risky" }), raise)
		)
			.toBe(false)
		t.expect(
			publish.raiseEdit(
				"c0010",
				ticket("c0010"),
				ticket("c0010", { raft = "", design = "draft" }),
				raise
			)
		)
			.toBe(false)
		t.expect(publish.raiseEdit("c0010", ticket("c0010"), ticket("c0010", { raft = "R9999" }), raise))
			.toBe(false)
		t.expect(
			publish.raiseEdit(
				"c0010",
				ticket("c0010", { raft = "R7777" }),
				ticket("c0010", { raft = "" }),
				raise
			)
		).toBe(false)
		-- a document that is no member of the raise
		t.expect(publish.raiseEdit("c0099", ticket("c0099"), ticket("c0099", { raft = "" }), raise))
			.toBe(false)
		-- the raft: its list is exactly the raised and released ids, and becomes empty
		t.expect(publish.raiseEdit("R0306", raftDoc("[c0010, c0011, c0012]"), raftDoc("[]"), raise))
			.toBe(true) -- control
		t.expect(publish.raiseEdit("R0306", raftDoc("[c0010, c0011]"), raftDoc("[]"), raise)).toBe(false)
		t.expect(publish.raiseEdit("R0306", raftDoc("[c0010, c0011, c0012, c0013]"), raftDoc("[]"), raise))
			.toBe(false)
		t.expect(publish.raiseEdit("R0306", raftDoc("[c0010, c0011, c0012]"), raftDoc("[c0010]"), raise))
			.toBe(false)
		t.expect(
			publish.raiseEdit(
				"R0306",
				raftDoc("[c0010, c0011, c0012]"),
				raftDoc("[c0010, c0011, c0012]"),
				raise
			)
		).toBe(false)
		t.expect(publish.raiseEdit("R0999", raftDoc("[c0010, c0011, c0012]"), raftDoc("[]"), raise))
			.toBe(false)
	end)

	it(
		"AC4: a raise that raises no ticket is refused for every document, so a plain stop never dissolves the raft",
		function()
			local empty = { raft = "R0306", raised = {}, released = { "c0010", "c0011", "c0012" } } :: any
			t.expect(publish.raiseEdit("R0306", raftDoc("[c0010, c0011, c0012]"), raftDoc("[]"), empty))
				.toBe(false)
			t.expect(publish.raiseEdit("c0010", ticket("c0010"), ticket("c0010", { raft = "" }), empty))
				.toBe(false)
		end
	)

	it(
		"AC4: the raft and every raised and released member move together, each judged a raise, or none does",
		function()
			t.expect(type((publish :: any).raiseWhole)).toBe("function")
			local raise =
				{ raft = "R0306", raised = { c0011 = "risky" }, released = { "c0010", "c0012" } } :: any
			local whole = (publish :: any).raiseWhole
			t.expect(whole(raise, { R0306 = true, c0011 = true, c0010 = true, c0012 = true })).toBe(nil)
			t.expect(whole(raise, {})).toBe(nil)
			t.expect(whole(raise, { R0306 = true, c0011 = true, c0010 = true }) ~= nil).toBe(true) -- a released member missing
			t.expect(whole(raise, { c0011 = true, c0010 = true, c0012 = true }) ~= nil).toBe(true) -- the raft missing
			t.expect(whole(raise, { R0306 = true, c0010 = true, c0012 = true }) ~= nil).toBe(true) -- the raised ticket missing
			t.expect(whole(raise, { c0010 = true }) ~= nil).toBe(true) -- a released member alone
		end
	)
end)
