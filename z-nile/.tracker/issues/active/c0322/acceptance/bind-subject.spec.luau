--!strict
-- c0322: the spend rows and the trailers a tool commit records, as the pure functions that build them. Every row's
-- subject is the commit's first line and nothing else. `./zn done` hands the commit the session's reading: its
-- tokens, AI seconds and model go on the first row only (the reading is the commit's, not each member's), and its
-- note, which names what each CLI measured, is kept as the commit's last trailer, `Session: <note>`. Before c0322
-- the note was appended to the bind row's subject ("R0010: bind f0010, f0020 claude unmeasured; grok unmeasured; …"),
-- and c0084's slow-tier commit-phase.spec, which expects the plain subject, had been red on main with no gate to
-- show it. This spec is the fast guard; wiring.spec.luau pins the CLI's one call of each function.
local ledger = require("@znile/engine/ledger")
local t = require("@tests/lib/t")

local NOTE = "claude unmeasured; grok unmeasured; agent unmeasured; kimi unmeasured"
local WHEN = "2026-11-15 20:00"
local BARE = "tokens,wall,cpu,ai"
local MEASURED: ledger.Reading = { tokens = 2361, ai = 12.5, model = "m-9" }
local function share(
	id: string,
	added: number,
	removed: number,
	minutes: number,
	tokens: number?
): ledger.Share
	return { id = id, added = added, removed = removed, minutes = minutes, how = "raft", tokens = tokens }
end
local ONE = { share("f0010", 3, 1, 0) }
local TWO = { share("f0010", 7, 2, 0), share("f0020", 1, 0, 1.5, 40) }

return t.spec("c0322 a commit's rows keep the session note out of their subject", function(it)
	it("every row's subject is the commit's first line, with or without a reading", function()
		local rows =
			ledger.commitRows("R0010: bind f0010, f0020", WHEN, "deliver", TWO, nil, MEASURED, "wall,cpu")
		t.expect(#rows).toBe(2)
		t.expect(rows[1].subject).toBe("R0010: bind f0010, f0020")
		t.expect(rows[2].subject).toBe("R0010: bind f0010, f0020")
		-- only the first line of a message with a body and trailers
		local long = "R0010: bind f0010\n\nVerdict: approve\nTrace: x/trace.md\n"
		t.expect(ledger.commitRows(long, WHEN, "deliver", ONE, nil, MEASURED, "wall,cpu")[1].subject)
			.toBe("R0010: bind f0010")
		t.expect(ledger.commitRows("layer b", WHEN, "build", ONE, nil, nil, "")[1].subject).toBe("layer b")
		-- a reading that measured nothing changes no subject either
		local none: ledger.Reading = {}
		t.expect(
			ledger.commitRows("R0010: bind f0010", WHEN, "deliver", ONE, nil, none, "wall,cpu,tokens,ai")[1].subject
		).toBe("R0010: bind f0010")
	end)

	it("the reading goes on the first row only, and every other row is bare", function()
		local rows =
			ledger.commitRows("R0010: bind f0010, f0020", WHEN, "deliver", TWO, nil, MEASURED, "wall,cpu")
		t.expect(rows[1].tokens).toBe(2361)
		t.expect(rows[1].ai).toBe(12.5)
		t.expect(rows[1].model).toBe("m-9")
		t.expect(rows[1].unmeasured).toBe("wall,cpu")
		t.expect(rows[2].tokens).toBe(nil)
		t.expect(rows[2].ai).toBe(nil)
		t.expect(rows[2].model).toBe(nil)
		t.expect(rows[2].unmeasured).toBe(BARE)
		-- each row has its own share's lines, and the cells every measured row has
		t.expect(rows[1].added).toBe(7)
		t.expect(rows[1].removed).toBe(2)
		t.expect(rows[2].added).toBe(1)
		t.expect(rows[2].removed).toBe(0)
		for _, row in rows do
			t.expect(row.when).toBe(WHEN)
			t.expect(row.phase).toBe("deliver")
			t.expect(row.minutes).toBe(0)
			t.expect(row.how).toBe("measured")
		end
		-- no reading: every row is bare, whatever flags the caller passed for a reading
		local bare = ledger.commitRows("x", WHEN, "build", TWO, nil, nil, "wall,cpu")
		t.expect(bare[1].tokens).toBe(nil)
		t.expect(bare[1].ai).toBe(nil)
		t.expect(bare[1].model).toBe(nil)
		t.expect(bare[1].unmeasured).toBe(BARE)
		t.expect(bare[2].unmeasured).toBe(BARE)
		t.expect(#ledger.commitRows("x", WHEN, "build", {}, nil, MEASURED, "wall,cpu")).toBe(0)
	end)

	it("a model the caller names wins over the reading's, on every row", function()
		local rows = ledger.commitRows("x", WHEN, "code-review", TWO, "named", MEASURED, "wall,cpu")
		t.expect(rows[1].model).toBe("named")
		t.expect(rows[2].model).toBe("named")
		t.expect(rows[1].tokens).toBe(2361)
		t.expect(ledger.commitRows("x", WHEN, "build", ONE, "named", nil, "")[1].model).toBe("named")
	end)

	it("the trailers are one Issue line per row, then the session's note as its own last line", function()
		local shares = TWO
		local rows =
			ledger.commitRows("R0010: bind f0010, f0020", WHEN, "deliver", shares, nil, MEASURED, "wall,cpu")
		t.expect(ledger.commitTrailers("deliver", shares, rows, NOTE)).toEqual({
			"Issue: f0010 +7/-2 0.0m deliver 2361 tokens m-9",
			"Issue: f0020 +1/-0 1.5m deliver 40 tokens",
			`Session: {NOTE}`,
		})
		-- no reading, or a reading with nothing to say: no Session line
		local plain = ledger.commitRows("layer b", WHEN, "build", shares, "named", nil, "")
		t.expect(ledger.commitTrailers("build", shares, plain, nil)).toEqual({
			"Issue: f0010 +7/-2 0.0m named",
			"Issue: f0020 +1/-0 1.5m 40 tokens named",
		})
		t.expect(#ledger.commitTrailers("build", shares, plain, "")).toBe(2)
		t.expect(ledger.commitTrailers("deliver", {}, {}, NOTE)).toEqual({ `Session: {NOTE}` })
	end)
end)
