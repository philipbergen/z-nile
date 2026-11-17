--!strict
-- c0249 AC1, AC2, AC3, AC4, AC9: the pure rules of the rank (z-nile/engine/rank.luau). The grammar of the `rank:` line and
-- what the audit says about it; the order (a set rank before an unset one, the lower first, the ticket number as the
-- tiebreak, a raft before an issue, lost work and blocked items when asked); a raft's own rank over its members' best;
-- the move (a gap, or a renumbering from the top when there is none); and the pick `./zn next` prints.
local provenance = require("@znile/engine/provenance")
local rank = require("@znile/engine/rank")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function fact(id: string, over: { [string]: any }?): rank.Fact
	local f: rank.Fact = {
		id = id,
		kind = if string.sub(id, 1, 1) == "R" then "raft" else "issue",
		state = "backlog",
		status = "new",
		rank = nil,
		raft = nil,
		members = {},
		dependsOn = {},
		root = "z-nile/.tracker",
	}
	local extra: { [string]: any } = over or {}
	for k, v in extra do
		(f :: any)[k] = v
	end
	return f
end

local function ids(list: { rank.Fact }): string
	local out: { string } = {}
	for _, f in list do
		table.insert(out, f.id)
	end
	return table.concat(out, " ")
end

-- "c0003>20 c0001>nil", for the changes a move writes
local function shown(changes: { rank.Change }?): string
	local out: { string } = {}
	local list: { rank.Change } = changes or {}
	for _, c in list do
		table.insert(out, `{c.id}>{c.rank or "unset"}{if c.moved then "~" else ""}`) -- ~ marks a row written with moved=
	end
	return table.concat(out, " ")
end

local function plan(
	facts: { rank.Fact },
	kind: string,
	id: string,
	how: string,
	arg: (string | number)?
): string
	local changes, why = rank.plan(rank.stack(facts, kind), id, how, arg)
	return if changes then shown(changes) else `error: {why}`
end

local ROOTS = { "pickman/.tracker", "z-nile/.tracker" }

-- the facts after a move's changes are written, as the next read sees them
local function applied(facts: { rank.Fact }, changes: { rank.Change }?): { rank.Fact }
	local out: { rank.Fact } = {}
	local list: { rank.Change } = changes or {}
	for _, f in facts do
		local c = table.clone(f)
		for _, change in list do
			if change.id == f.id then
				c.rank = change.rank
				c.moved = change.rank ~= nil and change.moved == true
			end
		end
		table.insert(out, c)
	end
	return out
end

local function doc(front: string): string
	return `---\nid: c0001\ntitle: T\n{front}status: new-a-b-c\n---\n\n# c0001\n`
end

return t.spec("c0249 the rank's pure rules", function(it)
	it("AC1: a rank is a whole number from 1 to 999999, and an empty value is unset", function()
		t.expect((rank.parse("10"))).toBe(10)
		t.expect((rank.parse("1"))).toBe(1)
		t.expect((rank.parse("999999"))).toBe(999999)
		t.expect((rank.parse(nil))).toBe(nil)
		t.expect((rank.parse(""))).toBe(nil)
		local _, none = rank.parse("")
		t.expect(none).toBe(nil)
		-- the line is a bare integer, always: nothing is appended to a moved-written rank (who set it is in provenance.md)
		for _, bad in
			{
				"0",
				"-5",
				"010",
				"1.5",
				"1e3",
				"ten",
				"1000000",
				"+3",
				"5 5",
				"0x10",
				"30 auto",
				"30  auto",
				"auto",
				"30 AUTO",
			}
		do
			local n, why = rank.parse(bad)
			t.expect(n).toBe(nil)
			t.expect(why ~= nil and string.find(why, bad, 1, true) ~= nil).toBe(true)
		end
	end)

	it(
		"AC6: the audit's check names a malformed, repeated or oddly written rank line, and passes the rest",
		function()
			t.expect(rank.problem(doc(""))).toBe(nil)
			t.expect(rank.problem(doc("rank:\n"))).toBe(nil)
			t.expect(rank.problem(doc("rank: 20\n"))).toBe(nil)
			t.expect(rank.problem(doc("ranked: abc\n"))).toBe(nil) -- another key
			local zero = rank.problem(doc("rank: 0\n"))
			t.expect(zero ~= nil and string.find(zero, "rank: 0", 1, true) ~= nil).toBe(true)
			t.expect(rank.problem(doc("rank: abc\n")) ~= nil).toBe(true)
			t.expect(rank.problem(doc("rank: 1.5\n")) ~= nil).toBe(true)
			local twice = rank.problem(doc("rank: 10\nrank: 20\n"))
			t.expect(twice ~= nil and string.find(twice, "2 times", 1, true) ~= nil).toBe(true)
			-- shapes the readers would skip without a word are refused, not ignored
			t.expect(rank.problem(doc(" rank: 5\n")) ~= nil).toBe(true)
			t.expect(rank.problem(doc("rank : 5\n")) ~= nil).toBe(true)
			t.expect(rank.problem(doc("Rank: 5\n")) ~= nil).toBe(true)
			-- only the front block counts: the body may talk about rank freely, and a document with no block has none
			t.expect(rank.problem("---\nid: c0001\n---\n\nrank: abc\n") ~= nil).toBe(false)
			t.expect(rank.problem("# no front matter\nrank: abc\n")).toBe(nil)
		end
	)

	it("AC1: setting a rank writes one line right after id, unsetting removes every rank line", function()
		-- right after `id:`, the line no prep branch edits: a rank published while a prep is open merges cleanly
		local set = rank.withRank(doc(""), 30) :: string
		t.expect(set).toBe("---\nid: c0001\nrank: 30\ntitle: T\nstatus: new-a-b-c\n---\n\n# c0001\n")
		t.expect(rank.withRank(set, 40))
			.toBe("---\nid: c0001\nrank: 40\ntitle: T\nstatus: new-a-b-c\n---\n\n# c0001\n")
		t.expect(rank.withRank(set, nil)).toBe(doc(""))
		t.expect(rank.withRank(doc("rank: 1\nrank: 2\n"), nil)).toBe(doc(""))
		t.expect(rank.withRank(doc(""), nil)).toBe(doc(""))
		-- a rank elsewhere in the block moves to the one place; a body that mentions rank: is not touched
		t.expect(rank.withRank(doc("rank: 9\n"), 5))
			.toBe("---\nid: c0001\nrank: 5\ntitle: T\nstatus: new-a-b-c\n---\n\n# c0001\n")
		t.expect(rank.withRank("---\nid: c0001\n---\n\nrank: 9\n", 5))
			.toBe("---\nid: c0001\nrank: 5\n---\n\nrank: 9\n")
		-- with no id line the rank is the first line of the block
		t.expect(rank.withRank("---\ntitle: T\n---\n", 5)).toBe("---\nrank: 5\ntitle: T\n---\n")
		t.expect(rank.withRank("no front matter", 5)).toBe(nil)
	end)

	it(
		"AC1: a document path gives its state, id and root through the registry, and a done item is its id alone",
		function()
			local s, id, root = rank.where("pickman/.tracker/issues/c0010/c0010.md", ROOTS)
			t.expect(s).toBe("backlog")
			t.expect(id).toBe("c0010")
			t.expect(root).toBe("pickman/.tracker")
			t.expect((rank.where("z-nile/.tracker/issues/active/c0010/c0010.md", ROOTS))).toBe("active")
			t.expect((rank.where("z-nile/.tracker/issues/done/c0010/c0010.md", ROOTS))).toBe("done")
			t.expect((rank.where("z-nile/.tracker/rafts/retired/R0010/R0010.md", ROOTS))).toBe("retired")
			t.expect((rank.where("z-nile/.tracker/rafts/R0010/R0010.md", ROOTS))).toBe("backlog")
			t.expect((rank.where("z-nile/.tracker/rafts/active/R0010/R0010.md", ROOTS))).toBe("active")
			t.expect((rank.where("z-nile/.tracker/issues/c0010/spend.md", ROOTS))).toBe(nil)
			t.expect((rank.where("z-nile/.tracker/issues/c0010/c0011.md", ROOTS))).toBe(nil)
			t.expect((rank.where("z-nile/.tracker/rafts/c0010/c0010.md", ROOTS))).toBe(nil)
			t.expect((rank.where("z-nile/.tracker/rafts/retired/R0010/R0011.md", ROOTS))).toBe(nil)
			-- a root the registry does not list is no root: a folder that merely looks like one is not read
			t.expect((rank.where("gone/.tracker/issues/c0010/c0010.md", ROOTS))).toBe(nil)
			t.expect((rank.where("gone/.tracker/rafts/retired/R0010/R0010.md", ROOTS))).toBe(nil)
			t.expect((rank.where("z-nile/.tracker/issues/c0010/c0010.md", { "pickman/.tracker" }))).toBe(nil)
			local f = rank.factOf(
				"z-nile/.tracker/issues/c0010/c0010.md",
				{ rank = "7", status = "new-a-b-c", raft = "", depends_on = "[c0001, c0002]" },
				ROOTS
			)
			t.expect(
				f ~= nil and f.rank == 7 and #(f :: rank.Fact).dependsOn == 2 and (f :: rank.Fact).raft == nil
			)
				.toBe(true)
			t.expect(f ~= nil and (f :: rank.Fact).moved == false).toBe(true)
			-- who set the rank is read from the item's provenance.md, handed in as its text: a latest `ranked` row with
			-- `moved=` makes it a moved-written rank, and the line itself stays the bare number
			local function row(detail: string, when: string?): provenance.Row
				return {
					when = when or "2026-11-16 09:00",
					event = "ranked",
					actor = "human:Pat",
					detail = detail,
				}
			end
			local function record(rows: { provenance.Row }): string
				return provenance.render("c0010", rows)
			end
			local movedRecord = record({ row("rank=40; was=unset; moved=c0020") })
			local marked = rank.factOf(
				"z-nile/.tracker/issues/c0010/c0010.md",
				{ rank = "40", status = "new-a-b-c" },
				ROOTS,
				movedRecord
			)
			t.expect(
				marked ~= nil and (marked :: rank.Fact).rank == 40 and (marked :: rank.Fact).moved == true
			)
				.toBe(true)
			t.expect(rank.movedBy(movedRecord)).toBe(true)
			t.expect(rank.movedBy(record({ row("rank=40; was=unset") }))).toBe(false)
			-- the latest `ranked` row decides: a person re-ranking it after a move makes it the person's, and the reverse
			t.expect(rank.movedBy(record({
				row("rank=40; was=unset; moved=c0020", "2026-11-16 09:00"),
				row("rank=40; was=40", "2026-11-16 09:05"),
			}))).toBe(false)
			t.expect(rank.movedBy(record({
				row("rank=10; was=unset", "2026-11-16 09:00"),
				row("rank=20; was=10; moved=c0030", "2026-11-16 09:05"),
			}))).toBe(true)
			-- other events and other rows do not count; no record, an empty one or a hand edit with no row is a person's
			local approved: provenance.Row = {
				when = "2026-11-16 09:10",
				event = "confirmed",
				actor = "human:Pat",
				detail = "moved=c0030",
			}
			t.expect(rank.movedBy(record({ row("rank=10; was=unset"), approved }))).toBe(false)
			t.expect(rank.movedBy(record({ approved }))).toBe(false)
			t.expect(rank.movedBy(nil)).toBe(false)
			t.expect(rank.movedBy("")).toBe(false)
			t.expect(rank.movedBy("not a record")).toBe(false)
			-- the mark is read for an item that has a rank only
			local unranked = rank.factOf(
				"z-nile/.tracker/issues/c0010/c0010.md",
				{ rank = "", status = "new-a-b-c" },
				ROOTS,
				movedRecord
			)
			t.expect(unranked ~= nil and (unranked :: rank.Fact).moved == false).toBe(true)
			-- a rank on an item that is not in the backlog is not read (a rank orders work that is not started)
			local act = rank.factOf(
				"z-nile/.tracker/issues/active/c0010/c0010.md",
				{ rank = "7", status = "active-a-b-c" },
				ROOTS
			)
			t.expect(act ~= nil and (act :: rank.Fact).rank == nil and (act :: rank.Fact).status == "active")
				.toBe(true)
			-- a malformed rank is unset for ordering; the audit is what refuses it
			local junk = rank.factOf(
				"z-nile/.tracker/issues/c0010/c0010.md",
				{ rank = "abc", status = "new-a-b-c" },
				ROOTS
			)
			t.expect(junk ~= nil and (junk :: rank.Fact).rank == nil).toBe(true)
			-- blocked is the stored word, plain or stamped (c0250)
			local blocked =
				rank.factOf("z-nile/.tracker/issues/c0010/c0010.md", { status = "blocked-a-b-c" }, ROOTS)
			t.expect(blocked ~= nil and rank.isBlocked((blocked :: rank.Fact).status)).toBe(true)
			t.expect(rank.isBlocked("blocked")).toBe(true)
			t.expect(rank.isBlocked("blockedness")).toBe(false)
			t.expect(rank.isBlocked("new")).toBe(false)
		end
	)

	it("AC9: equal or unset ranks fall back to the ticket number, so the order is always stable", function()
		local facts = {
			fact("c0300"),
			fact("f0020"),
			fact("d0100"),
			fact("c0010", { rank = 5 }),
			fact("c0400", { rank = 5 }),
			fact("c0001", { rank = 9 }),
		}
		-- set ranks first (5 twice: the number breaks the tie), then the unset ones by number across f, d and c
		t.expect(ids(rank.order(facts))).toBe("c0010 c0400 c0001 f0020 d0100 c0300")
		-- the same facts in any input order give the same order
		local reversed = {}
		for i = #facts, 1, -1 do
			table.insert(reversed, facts[i])
		end
		t.expect(ids(rank.order(reversed))).toBe("c0010 c0400 c0001 f0020 d0100 c0300")
		-- one number in two kinds: the id breaks it, and a raft goes before an issue
		t.expect(ids(rank.order({ fact("f0420"), fact("c0420"), fact("R0420") }))).toBe("R0420 c0420 f0420")
		-- a rank of 1 beats an unset one with any number
		t.expect(ids(rank.order({ fact("c0001"), fact("c9999", { rank = 1 }) }))).toBe("c9999 c0001")
	end)

	it("AC1: only the backlog is ranked; an active or done item counts as unset", function()
		local order = rank.order({
			fact("c0010", { state = "active", rank = 1, status = "active" }),
			fact("c0020", { rank = 50 }),
			fact("c0030", { state = "done", rank = 2, status = "done" }),
		})
		t.expect(ids(order)).toBe("c0020 c0010 c0030")
	end)

	it("AC3: a raft's own rank overrides its members', and an unset one takes their best", function()
		local facts = {
			fact("c0010", { rank = 10, raft = "R0001" }),
			fact("c0011", { rank = 40, raft = "R0001" }),
			fact("c0020", { rank = 20, raft = "R0002" }),
			fact("R0001", { members = { "c0010", "c0011" } }), -- unset: the best member rank is 10
			fact("R0002", { members = { "c0020" }, rank = 50 }), -- own 50 wins over its member's 20
			fact("R0003", { members = {} }), -- no rank anywhere
			fact("R0004", { members = { "c0030" }, rank = 5 }),
			fact("c0030", { raft = "R0004" }), -- a member with no rank does not change the raft's own
		}
		local byId: { [string]: rank.Fact } = {}
		for _, f in facts do
			byId[f.id] = f
		end
		t.expect(rank.effective(byId.R0001, byId)).toBe(10)
		t.expect(rank.effective(byId.R0002, byId)).toBe(50)
		t.expect(rank.effective(byId.R0003, byId)).toBe(nil)
		t.expect(rank.effective(byId.R0004, byId)).toBe(5)
		t.expect(rank.effective(byId.c0020, byId)).toBe(20)
		local rafts = rank.order({ byId.R0001, byId.R0002, byId.R0003, byId.R0004 }, { world = facts })
		t.expect(ids(rafts)).toBe("R0004 R0001 R0002 R0003")
		-- a member of a raft that is no longer in the backlog adds nothing
		byId.c0010.state = "active"
		t.expect(rank.effective(byId.R0001, byId)).toBe(40)
	end)

	it("AC5: blocked items come first when asked, and lost work comes first whatever its rank", function()
		local facts = {
			fact("c0010", { rank = 1 }),
			fact("c0020", { rank = 9 }),
			fact("c0030", { status = "blocked-a-b-c" }),
			fact("c0040", { status = "blocked", rank = 99 }),
			fact("c0050", { state = "active", status = "active" }),
		}
		t.expect(ids(rank.order(facts))).toBe("c0010 c0020 c0040 c0030 c0050")
		t.expect(ids(rank.order(facts, { blockedFirst = true }))).toBe("c0040 c0030 c0010 c0020 c0050")
		-- c0050 is lost: it sits ahead of everything, c0020 (also lost, longer silent) ahead of it
		t.expect(ids(rank.order(facts, { lost = { "c0020", "c0050" } })))
			.toBe("c0020 c0050 c0010 c0040 c0030")
		-- blocked first still goes before lost when both are asked for
		t.expect(ids(rank.order(facts, { lost = { "c0050" }, blockedFirst = true })))
			.toBe("c0040 c0030 c0050 c0010 c0020")
	end)

	it("AC2: top, last, before and after put one item in a gap, so one move edits one file", function()
		local ranked = {
			fact("c0001", { rank = 10 }),
			fact("c0002", { rank = 20 }),
			fact("c0003", { rank = 30 }),
			fact("c0004"),
		}
		t.expect(plan(ranked, "issue", "c0003", "top")).toBe("c0003>5") -- no room for 10 - 10: half of 10
		t.expect(plan(ranked, "issue", "c0003", "after", "c0001")).toBe("c0003>15")
		t.expect(plan(ranked, "issue", "c0001", "after", "c0002")).toBe("c0001>25")
		t.expect(plan(ranked, "issue", "c0004", "before", "c0003")).toBe("c0004>25")
		-- last, below an unset item, unsets the moved item: it then sorts among the unset ones by number, and nothing
		-- is renumbered (F5 of the design review: the app's drop at the end of a column)
		t.expect(plan(ranked, "issue", "c0001", "last")).toBe("c0001>unset")
		local allRanked =
			{ fact("c0001", { rank = 10 }), fact("c0002", { rank = 20 }), fact("c0003", { rank = 30 }) }
		t.expect(plan(allRanked, "issue", "c0001", "last")).toBe("c0001>40")
		t.expect(plan(ranked, "issue", "c0004", "top")).toBe("c0004>5")
		local wide = { fact("c0001", { rank = 100 }), fact("c0002", { rank = 500 }), fact("c0003") }
		t.expect(plan(wide, "issue", "c0003", "top")).toBe("c0003>90")
		t.expect(plan(wide, "issue", "c0003", "after", "c0001")).toBe("c0003>110")
		t.expect(
			plan(
				{ fact("c0001", { rank = 100 }), fact("c0002", { rank = 105 }), fact("c0003") },
				"issue",
				"c0003",
				"after",
				"c0001"
			)
		).toBe("c0003>102")
	end)

	it("AC2: a move that lands where the item already is changes nothing", function()
		local ranked = { fact("c0001", { rank = 10 }), fact("c0002", { rank = 20 }), fact("c0003") }
		t.expect(plan(ranked, "issue", "c0002", "after", "c0001")).toBe("")
		t.expect(plan(ranked, "issue", "c0001", "top")).toBe("")
		t.expect(plan(ranked, "issue", "c0003", "last")).toBe("")
		t.expect(plan(ranked, "issue", "c0002", "before", "c0003")).toBe("")
		t.expect(plan(ranked, "issue", "c0002", "set", 20)).toBe("")
		t.expect(plan(ranked, "issue", "c0003", "unset")).toBe("")
	end)

	it(
		"AC2: with no gap, or among unset items, the items from the top through the moved one are renumbered 10, 20, 30",
		function()
			-- 10 and 11 leave no room: after c0001 renumbers the ranked ones in one change
			local tight = {
				fact("c0001", { rank = 10 }),
				fact("c0002", { rank = 11 }),
				fact("c0003", { rank = 12 }),
				fact("c0004"),
			}
			t.expect(plan(tight, "issue", "c0004", "after", "c0001")).toBe("c0004>20 c0002>30~ c0003>40~")
			-- equal ranks are a tie by number; an item cannot go between them
			local tie = { fact("c0001", { rank = 10 }), fact("c0002", { rank = 10 }), fact("c0003") }
			t.expect(plan(tie, "issue", "c0003", "after", "c0001")).toBe("c0003>20 c0002>30~")
			-- nothing is ranked: moving c0004 before c0002 ranks c0001 and c0004 and leaves the rest unset
			local bare = { fact("c0001"), fact("c0002"), fact("c0003"), fact("c0004") }
			t.expect(plan(bare, "issue", "c0004", "before", "c0002")).toBe("c0001>10~ c0004>20")
			t.expect(plan(bare, "issue", "c0003", "last")).toBe("")
			t.expect(plan(bare, "issue", "c0003", "top")).toBe("c0003>10")
			-- after an unset item: the unset items above it are ranked first (their rows carry moved=), in their place
			t.expect(plan(bare, "issue", "c0001", "after", "c0003")).toBe("c0002>10~ c0003>20~ c0001>30")
			-- no rank that exists changes: the new ranks start after the highest one
			local some = {
				fact("c0001", { rank = 40 }),
				fact("c0002", { rank = 50 }),
				fact("c0003"),
				fact("c0004"),
				fact("c0005"),
			}
			t.expect(plan(some, "issue", "c0005", "after", "c0003")).toBe("c0003>60~ c0005>70")
			t.expect(plan(some, "issue", "c0005", "before", "c0003")).toBe("c0005>60")
			-- every item a renumbering shifts gets a row with moved= (the moved item's row has none), whoever set its rank
			local marked = {
				fact("c0001", { rank = 10 }),
				fact("c0002", { rank = 11, moved = true }),
				fact("c0003", { rank = 12 }),
				fact("c0004"),
			}
			t.expect(plan(marked, "issue", "c0004", "after", "c0001")).toBe("c0004>20 c0002>30~ c0003>40~")
			-- rank 1 has no room above it
			local floor = { fact("c0001", { rank = 1 }), fact("c0002") }
			t.expect(plan(floor, "issue", "c0002", "top")).toBe("c0002>10 c0001>20~")
		end
	)

	it("AC2: set and unset change the one item; a bad number or anchor is refused naming it", function()
		local ranked = { fact("c0001", { rank = 10 }), fact("c0002") }
		t.expect(plan(ranked, "issue", "c0002", "set", 77)).toBe("c0002>77")
		t.expect(plan(ranked, "issue", "c0001", "unset")).toBe("c0001>unset")
		t.expect(plan(ranked, "issue", "c0002", "set", 0))
			.toBe("error: rank 0 is not a whole number from 1 to 999999")
		t.expect(plan(ranked, "issue", "c0002", "set", 1000000) ~= "").toBe(true)
		t.expect(string.find(plan(ranked, "issue", "c0002", "after", "c0009"), "c0009", 1, true) ~= nil)
			.toBe(true)
		t.expect(
			string.find(plan(ranked, "issue", "c0002", "after", "c0002"), "cannot go after itself", 1, true)
				~= nil
		).toBe(true)
		t.expect(string.find(plan(ranked, "issue", "c0009", "top"), "c0009", 1, true) ~= nil).toBe(true)
		-- an anchor that is active, done or of the other kind is not in the stack
		local mixed = {
			fact("c0001"),
			fact("c0002", { state = "active", status = "active" }),
			fact("c0003", { state = "done", status = "done" }),
			fact("R0001"),
		}
		for _, anchor in { "c0002", "c0003", "R0001" } do
			t.expect(
				string.find(
					plan(mixed, "issue", "c0001", "after", anchor),
					"is not in the backlog stack",
					1,
					true
				) ~= nil
			).toBe(true)
		end
		t.expect(string.find(plan(ranked, "issue", "c0002", "sideways"), "unknown move", 1, true) ~= nil)
			.toBe(true)
	end)

	it(
		"AC2: a move among rafts places a raft by its effective rank and gives it a rank of its own",
		function()
			local facts = {
				fact("c0010", { rank = 10, raft = "R0001" }),
				fact("R0001", { members = { "c0010" } }), -- effective 10, own unset
				fact("R0002", { rank = 30 }),
				fact("R0003"),
			}
			-- R0003 after R0001 goes between the effective 10 and 30
			t.expect(plan(facts, "raft", "R0003", "after", "R0001")).toBe("R0003>20")
			-- the issue is not in the raft stack
			t.expect(
				string.find(
					plan(facts, "raft", "R0003", "after", "c0010"),
					"is not in the backlog stack",
					1,
					true
				) ~= nil
			).toBe(true)
			-- R0002 to the top: the raft with only an effective 10 is renumbered with an own rank
			t.expect(plan(facts, "raft", "R0002", "top")).toBe("R0002>5")
			t.expect(plan(facts, "raft", "R0001", "set", 10)).toBe("R0001>10") -- explicit, though the effective rank is already 10
		end
	)

	local function pickOf(facts: { rank.Fact }, over: { [string]: any }?): string
		local o: { [string]: any } = over or {}
		local ctx: rank.Context = {
			lost = o.lost,
			claimable = function(f: rank.Fact): boolean
				return (o.claimable or {})[f.id] ~= false
			end,
			mayDraft = function(f: rank.Fact): boolean
				return (o.draft or {})[f.id] ~= false
			end,
			scope = o.scope,
		}
		local pick, why = rank.next(facts, ctx)
		return if pick then `{pick.id} {pick.kind} {pick.why}` else `none: {why}`
	end

	it("AC4: next takes lost work first, whatever its rank, in the order given", function()
		local facts = {
			fact("R0001", { status = "prepared", rank = 1 }),
			fact("c0050", { status = "preparing" }),
			fact("R0009", { status = "active", state = "active" }),
		}
		t.expect(pickOf(facts, { lost = { "R0009", "c0050" } })).toBe("R0009 lost its heartbeat is stale")
		t.expect(pickOf(facts, { lost = { "c0050", "R0009" } })).toBe("c0050 lost its heartbeat is stale")
		-- a lost id that is done, retired, gone or blocked is not picked; the next one is
		local done = {
			fact("c0050", { state = "done", status = "done" }),
			fact("R0001", { status = "prepared", rank = 1 }),
		}
		t.expect(pickOf(done, { lost = { "c0050", "c0099" } })).toBe("R0001 raft rank 1")
		t.expect(
			pickOf(
				{ fact("c0050", { status = "blocked-a-b-c" }), fact("R0001", { status = "prepared" }) },
				{ lost = { "c0050" } }
			)
		).toBe("R0001 raft rank unset")
	end)

	it(
		"AC4: next takes the claimable raft with the best rank, and an issue only when no raft is claimable",
		function()
			local facts = {
				fact("R0001", { status = "prepared" }), -- unset
				fact("R0002", { status = "prepared", rank = 40 }),
				fact("R0003", { status = "prepared", rank = 20 }),
				fact("c0001", { rank = 1 }), -- an issue, ranked best of all, still after any raft
			}
			t.expect(pickOf(facts)).toBe("R0003 raft rank 20")
			-- a raft that ready would refuse is not claimable; the next one is
			t.expect(pickOf(facts, { claimable = { R0003 = false } })).toBe("R0002 raft rank 40")
			t.expect(pickOf(facts, { claimable = { R0003 = false, R0002 = false } }))
				.toBe("R0001 raft rank unset")
			-- no raft is claimable: the issue to draft
			t.expect(pickOf(facts, { claimable = { R0003 = false, R0002 = false, R0001 = false } }))
				.toBe("c0001 draft rank 1")
			-- the issue must be one a worker may draft
			t.expect(pickOf({ fact("c0001", { rank = 1 }), fact("c0002") }, { draft = { c0001 = false } }))
				.toBe("c0002 draft rank unset")
			-- a raft with no rank of its own is placed by its members' best
			local viaMembers = {
				fact("R0001", { status = "prepared", members = { "c0010" } }),
				fact("c0010", { rank = 3, raft = "R0001", status = "prepared" }),
				fact("R0002", { status = "prepared", rank = 10 }),
			}
			t.expect(pickOf(viaMembers)).toBe("R0001 raft rank 3")
		end
	)

	it(
		"AC4: next skips an item that waits on undone work or is blocked, and its rank is left as it is",
		function()
			local facts = {
				fact("c0001", { status = "prepared", state = "backlog" }),
				fact("c0010", { rank = 1, dependsOn = { "c0099" } }), -- waits on c0099, which is not done
				fact("c0099", { status = "preparing" }),
				fact("c0011", { rank = 2, status = "blocked-a-b-c" }),
				fact("c0012", { rank = 3 }),
			}
			t.expect(pickOf(facts)).toBe("c0012 draft rank 3")
			-- the dependency lands: the same item is first again at its old rank
			facts[3] = fact("c0099", { status = "done", state = "done" })
			t.expect(pickOf(facts)).toBe("c0010 draft rank 1")
			-- a raft waits on a dependency of any member outside it, and not on one inside it
			local rafts = {
				fact("R0001", { status = "prepared", rank = 1, members = { "c0020", "c0021" } }),
				fact("c0020", { raft = "R0001", status = "prepared", dependsOn = { "c0021" } }),
				fact("c0021", { raft = "R0001", status = "prepared", dependsOn = { "c0098" } }),
				fact("c0098", { status = "prepared" }),
				fact("R0002", { status = "prepared", rank = 9 }),
			}
			t.expect(pickOf(rafts)).toBe("R0002 raft rank 9")
			rafts[4] = fact("c0098", { status = "done", state = "done" })
			t.expect(pickOf(rafts)).toBe("R0001 raft rank 1")
			-- a blocked raft is skipped
			rafts[1] = fact("R0001", { status = "blocked", rank = 1, members = { "c0020", "c0021" } })
			t.expect(pickOf(rafts)).toBe("R0002 raft rank 9")
		end
	)

	it(
		"AC4: next takes only items in the backlog that are not claimed, and says why when there is none",
		function()
			local none = pickOf({
				fact("R0001", { status = "active", state = "active" }),
				fact("R0002", { status = "preparing" }), -- claimed by a person, not prepared
				fact("c0001", { status = "preparing" }),
				fact("c0002", { status = "prepared" }),
				fact("c0003", { raft = "R0009" }), -- in a raft: the raft is what a worker takes
				fact("c0004", { state = "done", status = "done" }),
			})
			t.expect(none)
				.toBe("none: no lost work, no claimable raft, no approved issue to raft and no issue to draft")
			t.expect(pickOf({}))
				.toBe("none: no lost work, no claimable raft, no approved issue to raft and no issue to draft")
		end
	)

	it("AC4: next in a project's folder takes that project's items only", function()
		local facts = {
			fact("R0001", { status = "prepared", rank = 1, root = "pickman/.tracker" }),
			fact("R0002", { status = "prepared", rank = 2, root = "z-nile/.tracker" }),
			fact("c0050", { status = "preparing", root = "pickman/.tracker" }),
		}
		t.expect(pickOf(facts)).toBe("R0001 raft rank 1")
		t.expect(pickOf(facts, { scope = "z-nile/.tracker" })).toBe("R0002 raft rank 2")
		t.expect(pickOf(facts, { scope = "" })).toBe("R0001 raft rank 1")
		t.expect(pickOf(facts, { scope = "z-nile/.tracker", lost = { "c0050" } })).toBe("R0002 raft rank 2")
		t.expect(pickOf(facts, { scope = "pickman/.tracker", lost = { "c0050" } }))
			.toBe("c0050 lost its heartbeat is stale")
	end)
	it(
		"AC4: ./zn work next takes rafts in rank order too, an unset rank last and the number as the tiebreak",
		function()
			local function raft(id: string, ranked: number?): work.RaftFact
				return {
					id = id,
					title = "t",
					where = "backlog",
					status = "prepared",
					designReady = true,
					depsMet = true,
					questions = false,
					issues = { "c0010" },
					layers = {},
					holder = "",
					since = "",
					stacked = false,
					codeReview = "none",
					finalReview = "none",
					trace = false,
					traceOk = false,
					root = "",
					rank = ranked,
				}
			end
			local function first(rafts: { work.RaftFact }): string
				return work.decide({ rafts = rafts }).raft
			end
			t.expect(first({ raft("R0001"), raft("R0002", 40), raft("R0003", 20) })).toBe("R0003")
			t.expect(first({ raft("R0001"), raft("R0002") })).toBe("R0001")
			t.expect(first({ raft("R0009", 5), raft("R0002", 5) })).toBe("R0002")
			-- a raft ready would refuse is skipped whatever its rank
			local refused = raft("R0003", 1)
			refused.depsMet = false
			t.expect(first({ refused, raft("R0004", 90) })).toBe("R0004")
		end
	)
	it(
		"AC3: a rank a move wrote (moved= in its record) does not count towards a raft, so an unrelated move never reorders the rafts",
		function()
			-- the review's facts: c0050 is in R0002, c0100 in R0001, c0200 and c0300 are in no raft; nothing is ranked
			local facts = {
				fact("R0001", { status = "prepared", members = { "c0100" } }),
				fact("R0002", { status = "prepared", members = { "c0050" } }),
				fact("c0050", { raft = "R0002", status = "prepared" }),
				fact("c0100", { raft = "R0001", status = "prepared" }),
				fact("c0200"),
				fact("c0300"),
			}
			local function nextRaft(list: { rank.Fact }): string
				local pick = rank.next(list, {
					claimable = function(): boolean
						return true
					end,
					mayDraft = function(): boolean
						return false
					end,
				})
				return if pick then pick.id else "none"
			end
			t.expect(nextRaft(facts)).toBe("R0001")
			-- dragging c0300 before c0200 ranks c0050 and c0100 too (they sit above it), with moved= rows
			local changes = rank.plan(rank.stack(facts, "issue"), "c0300", "before", "c0200")
			t.expect(shown(changes)).toBe("c0050>10~ c0100>20~ c0300>30")
			local after = applied(facts, changes)
			t.expect(nextRaft(after)).toBe("R0001") -- today's code (every rank counts) picks R0002 here
			local byId: { [string]: rank.Fact } = {}
			for _, f in after do
				byId[f.id] = f
			end
			t.expect(rank.effective(byId.R0001, byId)).toBe(nil)
			t.expect(rank.effective(byId.R0002, byId)).toBe(nil)
			t.expect(rank.effective(byId.c0050, byId)).toBe(10) -- the issues themselves keep the ranks
			-- a move that does move a member (c0050 to the top: a person ranks it) does move its raft
			local topChanges = rank.plan(rank.stack(after, "issue"), "c0050", "top")
			local moved = applied(after, topChanges)
			t.expect(nextRaft(moved)).toBe("R0002")
			-- and a plain number set on a member counts, as before
			local setChanges = rank.plan(rank.stack(facts, "issue"), "c0050", "set", 3)
			local set = applied(facts, setChanges)
			t.expect(nextRaft(set)).toBe("R0002")
		end
	)

	it(
		"AC1: a move writes the rows of the unset items it ranks with moved=, and the moved item's without",
		function()
			local bare = { fact("c0001"), fact("c0002"), fact("c0003"), fact("c0004") }
			local changes = rank.plan(rank.stack(bare, "issue"), "c0003", "top")
			t.expect(shown(changes)).toBe("c0003>10")
			local some, _ = rank.plan(rank.stack(bare, "issue"), "c0004", "before", "c0003")
			t.expect(shown(some)).toBe("c0001>10~ c0002>20~ c0004>30")
			-- the third result of a drop below the unset items says what happened
			local ranked = { fact("c0001", { rank = 10 }), fact("c0002"), fact("c0003") }
			local last, why, note = rank.plan(rank.stack(ranked, "issue"), "c0001", "last")
			t.expect(shown(last)).toBe("c0001>unset")
			t.expect(why).toBe(nil)
			t.expect(note ~= nil and string.find(note, "dropped below the unset items", 1, true) ~= nil)
				.toBe(true)
			local _, _, plainNote = rank.plan(rank.stack(ranked, "issue"), "c0002", "after", "c0003")
			t.expect(plainNote).toBe(nil)
			-- with every item ranked, last goes after the last one and says nothing
			local allRanked = { fact("c0001", { rank = 10 }), fact("c0002", { rank = 20 }) }
			local end_, _, endNote = rank.plan(rank.stack(allRanked, "issue"), "c0001", "last")
			t.expect(shown(end_)).toBe("c0001>30")
			t.expect(endNote).toBe(nil)
		end
	)

	it(
		"AC4: next rafts an approved issue that is in no raft after the claimable rafts and before any draft",
		function()
			local approved =
				fact("c0070", { status = "prepared", design = "ready", approved = true, rank = 9 })
			local draft = fact("c0001", { rank = 1 })
			local raft = fact("R0001", { status = "prepared", rank = 50 })
			t.expect(pickOf({ draft, approved })).toBe("c0070 rafting approved, in no raft")
			-- a claimable raft comes first, whatever the ranks
			t.expect(pickOf({ draft, approved, raft })).toBe("R0001 raft rank 50")
			t.expect(pickOf({ draft, approved, raft }, { claimable = { R0001 = false } }))
				.toBe("c0070 rafting approved, in no raft")
			-- lost work comes before all of them
			t.expect(
				pickOf(
					{ draft, approved, raft, fact("c0099", { status = "preparing" }) },
					{ lost = { "c0099" } }
				)
			).toBe("c0099 lost its heartbeat is stale")
			-- the best-ranked one of several, the number as the tiebreak
			t.expect(pickOf({
				approved,
				fact("c0060", { status = "prepared", design = "ready", approved = true, rank = 4 }),
			})).toBe("c0060 rafting approved, in no raft")
			t.expect(pickOf({
				fact("c0090", { status = "prepared", design = "ready", approved = true }),
				fact("c0080", { status = "prepared", design = "ready", approved = true }),
			})).toBe("c0080 rafting approved, in no raft")
			-- what is not offered: no approval, a design not ready, already in a raft, a dependency not done, blocked, claimed
			local overs: { { [string]: any } } = {
				{ approved = false },
				{ design = "reviewed" },
				{ raft = "R0009" },
				{ dependsOn = { "c0500" } },
				{ status = "blocked-a-b-c" },
				{ status = "preparing" },
			}
			for _, over in overs do
				local item = fact("c0070", { status = "prepared", design = "ready", approved = true })
				for k, v in over do
					(item :: any)[k] = v
				end
				t.expect(pickOf({ item, fact("c0500", { status = "new" }) }, { draft = { c0500 = false } }))
					.toBe("none: no lost work, no claimable raft, no approved issue to raft and no issue to draft")
			end
		end
	)

	it(
		"AC5: list puts every blocked item first (rafts, then issues), then lost work, then the stack",
		function()
			-- c0250's fixture and the order its work-board spec pins: a blocked raft, two blocked issues, then the rest
			local facts = {
				fact("c0010"),
				fact("c0030"),
				fact("c0050"),
				fact("c0020", { status = "blocked-a-b-c" }),
				fact("c0040", { status = "blocked-a-b-c" }),
				fact("R0010", { status = "prepared" }),
				fact("R0020", { status = "blocked-a-b-c" }),
			}
			local function listed(lost: { string }?): string
				return ids(rank.listOrder(facts, lost, facts))
			end
			t.expect(listed(nil)).toBe("R0020 c0020 c0040 R0010 c0010 c0030 c0050")
			-- lost work goes after the blocked items and before the rest, in the heartbeat's order, whatever the kind or rank
			t.expect(listed({ "c0050", "R0010" })).toBe("R0020 c0020 c0040 c0050 R0010 c0010 c0030")
			t.expect(listed({ "R0010", "c0050" })).toBe("R0020 c0020 c0040 R0010 c0050 c0010 c0030")
			-- a lost id that is also blocked stays with the blocked; an id no fact has is ignored
			t.expect(listed({ "c0020", "c9999" })).toBe("R0020 c0020 c0040 R0010 c0010 c0030 c0050")
			-- a rank orders each group: a ranked issue before an unranked one, a ranked blocked issue before an unranked one
			facts[3] = fact("c0050", { rank = 5 })
			facts[5] = fact("c0040", { status = "blocked-a-b-c", rank = 7 })
			t.expect(listed(nil)).toBe("R0020 c0040 c0020 R0010 c0050 c0010 c0030")
			-- rafts come before issues even when an issue is ranked and the raft is not
			t.expect(listed({ "c0010" })).toBe("R0020 c0040 c0020 c0010 R0010 c0050 c0030")
		end
	)
end)
