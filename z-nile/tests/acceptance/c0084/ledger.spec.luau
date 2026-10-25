--!strict
-- c0084: the spend ledger is the one format of an issue's spend.md. Rows carry a phase and optional tokens; rows
-- written before it (seven cells, possibly spanning lines) read as build; a published change may only append rows.
local ledger = require("@scripts/tracker/ledger")
local t = require("@tests/lib/t")

local OLD = "# Spend: c0910 Old item\n\n"
	.. "| # | when | commit | +lines | -lines | minutes | attribution |\n|---|---|---|---|---|---|---|\n"
	.. "| 1 | 2026-09-29 03:16 | c0910: first | 66 | 9 | 20.0 | focus |\n"
	.. "| 2 | 2026-09-29 03:30 | R0910: a message\n\nwith a body | 4 | 0 | 10.0 | raft+proportional |\n"
	.. "\n**Total:** +70 / -9 lines, 30.0 agent-minutes over 2 commits\n"
	.. "<!-- totals: added=70 removed=9 minutes=30.0 commits=2 -->\n"

-- the shape c0073's board fixtures use: a bare title, integer minutes, no totals line
local BARE = "# Spend\n\n| # | when | commit | +lines | -lines | minutes | attribution |\n|---|---|---|---|---|---|---|\n"
	.. "| 1 | 2025-06-11 09:30 | abc1234 | 100 | 20 | 30 | explicit |\n"

local function row(phase: string, minutes: number, tokens: number?, added: number?): any
	return {
		when = "2026-10-05 12:00",
		subject = `{phase} work`,
		added = added or 0,
		removed = 0,
		minutes = minutes,
		how = "spend",
		phase = phase,
		tokens = tokens,
	}
end

local function parsed(text: string): any
	local l, err = ledger.parse(text)
	if not l then
		error(`does not parse: {err}`, 2)
	end
	return l
end

return t.spec("spend ledger", function(it)
	it("lists the six phases in lifecycle order", function()
		t.expect(ledger.PHASES)
			.toEqual({ "capture", "prep", "design-review", "build", "code-review", "deliver" })
		t.expect(ledger.isPhase("design-review")).toBe(true)
		t.expect(ledger.isPhase("review")).toBe(false)
	end)

	it("reads seven-cell rows as build with no tokens, joining a row that spans lines", function()
		local l = parsed(OLD)
		t.expect(l.id).toBe("c0910")
		t.expect(l.title).toBe("Old item")
		t.expect(#l.rows).toBe(2)
		t.expect(l.rows[1].phase).toBe("build")
		t.expect(l.rows[1].tokens).toBe(nil)
		t.expect(l.rows[1].added).toBe(66)
		t.expect(l.rows[2].added).toBe(4)
		t.expect(l.rows[2].minutes).toBe(10)
		t.expect(l.rows[2].how).toBe("raft+proportional")
	end)

	it("reads c0073's fixture shape: a bare title, integer minutes, no totals", function()
		local l = parsed(BARE)
		t.expect(#l.rows).toBe(1)
		t.expect(l.rows[1].minutes).toBe(30)
		t.expect(l.rows[1].when).toBe("2025-06-11 09:30")
		t.expect(l.rows[1].phase).toBe("build")
	end)

	it("reads nine-cell rows with their phase and tokens", function()
		local text =
			ledger.render("c0920", "New", { row("design-review", 6, 1200), row("capture", 1.5, nil) })
		local l = parsed(text)
		t.expect(l.rows[1].phase).toBe("design-review")
		t.expect(l.rows[1].tokens).toBe(1200)
		t.expect(l.rows[2].phase).toBe("capture")
		t.expect(l.rows[2].tokens).toBe(nil)
		t.expect(l.rows[2].minutes).toBe(1.5)
	end)

	it("refuses malformed rows, naming the line", function()
		local head = "# Spend: c0920 X\n\n" .. ledger.HEADER
		for _, bad in
			{
				"| 1 | 2026-10-05 12:00 | s | 1 | 0 | 1.0 | spend | review | |", -- unknown phase
				"| 1 | 2026-10-05 12:00 | s | 1 | 0 | 1.0 | spend | build |", -- eight cells
				"| 1 | 2026-10-05 12:00 | s | -1 | 0 | 1.0 | spend | build | |", -- negative lines
				"| 1 | 2026-10-05 12:00 | s | 1 | 0 | 1.0 | spend | build | 1.5 |", -- fractional tokens
				"| 1 | 2026-10-05 12:00 | s | 1 | 0 | soon | spend | build | |", -- minutes not a number
				"| 1 | yesterday | s | 1 | 0 | 1.0 | spend | build | |", -- no date
				"| 1 | 2026-10-05 12:00 | never ends", -- unterminated
			}
		do
			local l, err = ledger.parse(head .. bad .. "\n")
			t.expect(l).toBe(nil)
			t.expect(string.find(err or "", string.sub(bad, 1, 12), 1, true) ~= nil).toBe(true)
		end
	end)

	it("renders nine cells per row and totals that sum every row, tokens included", function()
		local text = ledger.render("c0920", "Sum", {
			row("prep", 0.1, nil, 7),
			row("prep", 0.2, 5, 3),
			row("build", 10, 100, 1),
		})
		local l = parsed(text)
		t.expect(#l.rows).toBe(3)
		local totals = ledger.sum(l.rows)
		t.expect(totals.added).toBe(11)
		t.expect(totals.minutes).toBe(10.3)
		t.expect(totals.tokens).toBe(105)
		t.expect(totals.records).toBe(3)
		t.expect(
			string.find(
				text,
				"| 2 | 2026-10-05 12:00 | prep work | 3 | 0 | 0.2 | spend | prep | 5 |",
				1,
				true
			) ~= nil
		).toBe(true)
		t.expect(
			string.find(text, "| 1 | 2026-10-05 12:00 | prep work | 7 | 0 | 0.1 | spend | prep |  |", 1, true)
				~= nil
		).toBe(true)
		-- the patterns c0001's promoted lifecycle spec reads
		t.expect(string.match(text, "totals: added=(%d+)")).toBe("11")
		t.expect(string.match(text, "minutes=([%d%.]+)")).toBe("10.3")
		t.expect(string.match(text, "tokens=(%d+)")).toBe("105")
	end)

	it("never lets a cell break the table: pipes and newlines in a subject are replaced", function()
		local r = row("build", 1)
		r.subject = "a | b\nc"
		local text = ledger.render("c0920", "X", { r, row("build", 2) })
		t.expect(string.find(text, "| 1 | 2026-10-05 12:00 | a / b c | 0 |", 1, true) ~= nil).toBe(true)
		local l = parsed(text)
		t.expect(#l.rows).toBe(2)
		t.expect(l.rows[1].subject).toBe("a / b c")
	end)

	it("sums by phase", function()
		local by = ledger.byPhase({ row("prep", 3, 10, 4), row("prep", 2, nil, 1), row("deliver", 1) })
		t.expect(by.prep.minutes).toBe(5)
		t.expect(by.prep.added).toBe(5)
		t.expect(by.prep.tokens).toBe(10)
		t.expect(by.deliver.records).toBe(1)
		t.expect(by.capture.records).toBe(0)
	end)

	it(
		"appends a numbered row, keeps the existing title and rows, and rewrites old rows as nine cells",
		function()
			local text = ledger.append(OLD, "c0910", "Renamed since", row("deliver", 4, 50))
			local l = parsed(text)
			t.expect(l.title).toBe("Old item")
			t.expect(#l.rows).toBe(3)
			t.expect(l.rows[3].phase).toBe("deliver")
			t.expect(l.rows[1].phase).toBe("build")
			t.expect(string.find(text, "| 3 | 2026-10-05 12:00 | deliver work |", 1, true) ~= nil).toBe(true)
			t.expect(string.find(text, "| 20.0 | focus | build |  |", 1, true) ~= nil).toBe(true)
			t.expect(ledger.sum(l.rows).minutes).toBe(34)
			local fresh = parsed(ledger.append(nil, "c0930", "Fresh", row("capture", 2)))
			t.expect(fresh.id).toBe("c0930")
			t.expect(fresh.title).toBe("Fresh")
			t.expect(#fresh.rows).toBe(1)
		end
	)

	it("accepts only appended rows in the ledger's own form", function()
		local one = ledger.append(OLD, "c0910", "", row("capture", 1))
		t.expect(ledger.appendOnly(OLD, one, "c0910")).toBe(nil)
		t.expect(ledger.appendOnly(nil, ledger.append(nil, "c0930", "F", row("prep", 1)), "c0930")).toBe(nil)
		local base = parsed(OLD)
		local function refused(new: string, why: string)
			local reason = ledger.appendOnly(OLD, new, "c0910")
			if reason == nil then
				error(`accepted: {why}`, 2)
			end
		end
		refused(OLD, "no new row")
		refused(ledger.render("c0910", "Old item", base.rows), "old rows re-rendered, nothing added")
		local edited = table.clone(base.rows)
		edited[1] = table.clone(edited[1])
		edited[1].minutes = 2
		table.insert(edited, row("capture", 1))
		refused(ledger.render("c0910", "Old item", edited), "an old row's minutes changed")
		refused(ledger.render("c0910", "Old item", { base.rows[2], row("capture", 1) }), "an old row removed")
		refused(
			ledger.render("c0910", "Old item", { base.rows[2], base.rows[1], row("capture", 1) }),
			"reordered"
		)
		refused(
			ledger.render("c0911", "Old item", { base.rows[1], base.rows[2], row("capture", 1) }),
			"another id"
		)
		refused(
			ledger.render("c0910", "New title", { base.rows[1], base.rows[2], row("capture", 1) }),
			"retitled"
		)
		refused(string.gsub(one, "minutes=[%d%.]+", "minutes=3.0") :: string, "totals edited by hand")
		refused(string.gsub(one, "| 3 |", "| 9 |") :: string, "rows renumbered")
		refused(one .. "\nextra\n", "text after the totals")
		refused(string.gsub(one, "| capture |", "| review |") :: string, "an unknown phase")
		-- every field of an old row is history: each change below appends a row too, so only the field rule refuses it
		local tokened = ledger.append(OLD, "c0910", "", row("capture", 1, 0))
		local function rewritten(field: string, value: any, from: string?, at: number?): string
			local l = parsed(from or OLD)
			local rs = table.clone(l.rows)
			local i = at or 1
			rs[i] = table.clone(rs[i]);
			(rs[i] :: any)[field] = value
			table.insert(rs, row("capture", 1))
			return ledger.render("c0910", "Old item", rs)
		end
		refused(rewritten("when", "2026-09-30 03:16"), "an old row's date changed")
		refused(rewritten("subject", "c0910: other"), "an old row's subject changed")
		refused(rewritten("how", "explicit"), "an old row's attribution changed")
		refused(rewritten("phase", "capture"), "an old row's phase changed")
		refused(rewritten("removed", 8), "an old row's removed lines changed")
		refused(rewritten("added", 65), "an old row's added lines changed")
		refused(rewritten("tokens", 0), "an old row's empty tokens became 0")
		local reason = ledger.appendOnly(tokened, rewritten("tokens", 5, tokened, 3), "c0910")
		t.expect(reason ~= nil).toBe(true) -- a recorded 0 tokens became 5
		local reason2 = ledger.appendOnly(tokened, rewritten("tokens", nil, tokened, 3), "c0910")
		t.expect(reason2 ~= nil).toBe(true) -- a recorded 0 tokens became empty
		t.expect(ledger.appendOnly(nil, "# Spend: c0930 F\n\nnot a ledger\n", "c0930") ~= nil).toBe(true)
		-- a new ledger is held to the same form: every case below has a valid row, so only the named rule refuses it
		local fresh = ledger.append(nil, "c0930", "F", row("prep", 1))
		local function refusedNew(new: string, why: string)
			if ledger.appendOnly(nil, new, "c0930") == nil then
				error(`accepted for a new ledger: {why}`, 2)
			end
		end
		t.expect(ledger.appendOnly(nil, fresh, "c0930")).toBe(nil)
		refusedNew(string.gsub(fresh, "minutes=1%.0", "minutes=9.0") :: string, "totals edited by hand")
		refusedNew(fresh .. "trailing text\n", "text after the totals")
		refusedNew(string.gsub(fresh, "\n| 1 |", "\n| 2 |") :: string, "its row renumbered")
		refusedNew(ledger.render("c0930", "F", {}), "no rows at all")
		-- a new ledger must name the item it is published for
		t.expect(ledger.appendOnly(nil, ledger.append(nil, "c0931", "F", row("prep", 1)), "c0930") ~= nil)
			.toBe(true)
	end)
end)
