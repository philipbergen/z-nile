--!strict
-- c0283 AC1: the pure half. `provenance.approved` writes the approved row of a design approval (the human, and the first
-- 12 hex of approval.md's hash as `design=`), and `provenance.hint` reads the one list of agent markers.
local contract = require("@znile/engine/contract")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")

local HASH = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
local OTHER = "f123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

-- an approval.md of these hashes, oldest first, each by `who`
local function approvals(rows: { { who: string, hash: string } }): string
	local out: { contract.Row } = {}
	for i, r in rows do
		table.insert(out, {
			when = `2026-11-1{i}T09:00:00Z`,
			who = r.who,
			hash = r.hash,
			parts = { design = r.hash, ["check.sh"] = r.hash },
		})
	end
	return contract.render(out)
end
local function record(rows: { { event: string, actor: string, detail: string } }): string
	local out: { provenance.Row } = {}
	for _, r in rows do
		table.insert(out, { when = "2026-11-12 09:00", event = r.event, actor = r.actor, detail = r.detail })
	end
	return provenance.render("c0010", out)
end

return t.spec("c0283 the approved row", function(it)
	it("is one row: the human, the first 12 hex of the hash, and the record it joins", function()
		local text = provenance.approved(nil, "c0010", "Ann Lee", HASH, "2026-11-12 09:00") :: string
		local rows = provenance.parse(text) :: { provenance.Row }
		t.expect(#rows).toBe(1)
		t.expect(rows[1]).toEqual({
			when = "2026-11-12 09:00",
			event = "approved",
			actor = "human:Ann Lee",
			detail = "design=0123456789ab",
		})
		-- a later approval appends: the old row is kept as it was
		local again = provenance.approved(
			text,
			"c0010",
			"Bob",
			"f" .. string.sub(HASH, 2),
			"2026-11-12 10:00"
		) :: string
		local both = provenance.parse(again) :: { provenance.Row }
		t.expect(#both).toBe(2)
		t.expect(both[1]).toEqual(rows[1])
		t.expect(both[2].detail).toBe("design=f123456789ab")
		t.expect(provenance.appendOnly(text, again, "c0010")).toBe(nil)
	end)

	it("refuses a name the record cannot hold and a record that does not parse, writing nothing", function()
		for _, name in { "Ann | Lee", "Ann\nLee", "" } do
			local text, why = provenance.approved(nil, "c0010", name, HASH, "2026-11-12 09:00")
			t.expect(text).toBe(nil)
			t.expect(why ~= nil).toBe(true)
		end
		local text, why = provenance.approved("not a record\n", "c0010", "Ann", HASH, "2026-11-12 09:00")
		t.expect(text).toBe(nil)
		t.expect(why ~= nil).toBe(true)
	end)

	it("takes each agent marker as an agent session, and none of them as a human one", function()
		t.expect(provenance.AGENT_VARS)
			.toEqual({ "CLAUDECODE", "AI_AGENT", "CURSOR_AGENT", "GROK_SESSION_ID", "ZN_DISPATCH" })
		for _, name in provenance.AGENT_VARS do
			t.expect(provenance.hint({ [name] = "1" }).agent).toBe(true)
			t.expect(provenance.hint({ [name] = "" }).agent).toBe(false)
		end
		t.expect(provenance.hint({ CLAUDE_EFFORT = "high", ZN_ACTOR = "human:Ann" }).agent).toBe(false)
	end)

	it("publishes one approved row only beside the one approval.md row it matches", function()
		local after = approvals({ { who = "Ann Lee", hash = HASH } })
		local row = { event = "approved", actor = "human:Ann Lee", detail = "design=0123456789ab" }
		local function problem(old: string?, new: string, was: string?, now: string): string?
			return provenance.approvedPublishProblem(old, new, "c0010", was, now)
		end
		t.expect(problem(nil, record({ row }), nil, after)).toBe(nil)
		-- a second approval: old rows kept in both files, one row appended to each
		local again = approvals({ { who = "Ann Lee", hash = HASH }, { who = "Bob", hash = OTHER } })
		local rowTwo = { event = "approved", actor = "human:Bob", detail = "design=f123456789ab" }
		t.expect(problem(record({ row }), record({ row, rowTwo }), after, again)).toBe(nil)
		-- an existing record with a published row in it
		local ranked = { event = "ranked", actor = "human:Cy", detail = "rank=3" }
		t.expect(problem(record({ ranked }), record({ ranked, row }), nil, after)).toBe(nil)

		local function refused(why: string, got: string?)
			if not got then
				error(`{why}: not refused`, 2)
			end
		end
		-- the human or the hash does not match the approval
		refused(
			"another human",
			problem(
				nil,
				record({ { event = "approved", actor = "human:Eve", detail = row.detail } }),
				nil,
				after
			)
		)
		refused(
			"another hash",
			problem(
				nil,
				record({ { event = "approved", actor = row.actor, detail = "design=aaaaaaaaaaaa" } }),
				nil,
				after
			)
		)
		refused(
			"a longer design",
			problem(
				nil,
				record({ { event = "approved", actor = row.actor, detail = "design=0123456789abc" } }),
				nil,
				after
			)
		)
		refused(
			"an agent",
			problem(
				nil,
				record({ { event = "approved", actor = "agent:x effort high", detail = row.detail } }),
				nil,
				after
			)
		)
		-- two approved rows in one commit
		refused("two rows", problem(nil, record({ row, row }), nil, after))
		refused("two rows, the second matching", problem(nil, record({ rowTwo, row }), nil, after))
		-- another event beside it, or instead of it
		refused("a ranked row beside", problem(nil, record({ row, ranked }), nil, after))
		refused(
			"a confirmed row",
			problem(nil, record({ { event = "confirmed", actor = row.actor, detail = "" } }), nil, after)
		)
		-- approval.md: no new row, two new rows, an old row changed, or a text that does not parse
		refused("no approval row added", problem(nil, record({ row }), after, after))
		refused("two approval rows added", problem(nil, record({ rowTwo }), nil, again))
		refused(
			"an old approval row changed",
			problem(
				record({ row }),
				record({ row, rowTwo }),
				approvals({ { who = "Eve", hash = HASH } }),
				again
			)
		)
		refused("approval.md does not parse", problem(nil, record({ row }), nil, "not an approval\n"))
		-- the record: an old row edited, or nothing appended
		refused(
			"an old row edited",
			problem(
				record({ ranked }),
				record({ { event = "ranked", actor = "human:Cy", detail = "rank=4" }, row }),
				nil,
				after
			)
		)
		refused("nothing appended", problem(record({ row }), record({ row }), nil, after))
		-- PUBLISHED is not widened: `./zn provenance record` still cannot publish an approval
		t.expect(table.find(provenance.PUBLISHED, "approved")).toBe(nil)
	end)
end)
