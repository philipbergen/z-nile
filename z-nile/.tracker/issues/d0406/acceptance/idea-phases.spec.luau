--!strict
-- d0406: `./zn idea` writes spend rows whose phase is `idea` or `idea-challenge`. `./zn metrics` crashed on them
-- ("attempt to index nil with 'chore'"), because its phase tables held only the phases ledger listed. Here: ledger
-- lists the two phases, metrics finishes and reports them under their own names, a phase nothing lists is shown
-- rather than crashing, and the other readers of spend rows (the board, the raft summary's readers, the lessons and
-- rounds tables of metrics) finish on the same tracker. Fixtures under .cache/d0406-idea and .cache/d0406-plain
-- (tests/lib/trackerfix); every command only reads them.
local costrow = require("@znile/engine/costrow")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- the part of `text` from the line that holds `from` up to the next empty line
local function tableAt(text: string, from: string): string
	local s = string.find(text, from, 1, true)
	if not s then
		error(`no "{from}" in:\n{text}`, 2)
	end
	local e = string.find(text, "\n\n", s :: number, true)
	return string.sub(text, s :: number, if e then e else #text)
end

local function issue(id: string, ty: string, raft: string): string
	return `---\nid: {id}\ntype: {ty}\ntitle: T\nslug: t\nraft: {raft}\ndepends_on: []\nemergent: false\n`
		.. `design: ready\ncreated: 2026-01-01\nstatus: done\n---\n\n# {id}\n`
end
local RAFT = "---\nid: R0010\ntype: chore\ntitle: T\nslug: t\nsingle: false\nissues: [c0010]\ndesign: ready\n"
	.. "created: 2026-01-01\nstatus: done\n---\n\n# R0010\n"

local TSV = "when\tsubject\tadded\tremoved\tphase\ttokens\tmodel\twall\tcpu\tai\ttest\tunmeasured\n"
local function tsv(rows: { string }): string
	return TSV .. table.concat(rows, "\n") .. "\n"
end
-- an old-format spend.md: typed minutes, a phase and tokens
local function md(id: string, rows: { string }): string
	return `# Spend: {id} T\n\n`
		.. "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n"
		.. "|---|---|---|---|---|---|---|---|---|\n"
		.. table.concat(rows, "\n")
		.. "\n"
end

local DONE = "pickman/.tracker/issues/done"
local SEED: { [string]: string } = {
	["pickman/.tracker/rafts/done/R0010/R0010.md"] = RAFT,
	-- c0010, a chore in R0010: typed minutes for capture (4.0) and idea (2.5), and measured idea rows
	[`{DONE}/c0010/c0010.md`] = issue("c0010", "chore", "R0010"),
	[`{DONE}/c0010/spend.md`] = md("c0010", {
		"| 1 | 2026-01-01 10:00 | capture | 0 | 0 | 4.0 | explicit | capture | 0 |",
		"| 2 | 2026-01-01 10:05 | idea typed | 0 | 0 | 2.5 | explicit | idea | 11 |",
	}),
	[`{DONE}/c0010/spend.d/host-00000001.tsv`] = tsv({
		"2026-01-01 10:01\tc0010 ok\t0\t0\tidea\t100\tm-a\t6.000\t1.000\t\t\t",
		"2026-01-01 10:02\tc0010 ok\t0\t0\tidea-challenge\t300\tm-b\t20.000\t2.000\t\t\t",
		"2026-01-01 10:03\tc0010 ok\t0\t0\tidea\t250\tm-a\t7.000\t1.000\t\t\t",
	}),
	-- a second writer's file for c0010: a row whose phase nothing lists, inside a raft
	[`{DONE}/c0010/spend.d/host-00000002.tsv`] = tsv({
		"2026-01-01 10:04\tc0010 ok\t0\t0\tmystery\t5\tm-a\t1.000\t1.000\t\t\t",
	}),
	-- d0020, a defect in no raft: one row whose phase nothing lists
	[`{DONE}/d0020/d0020.md`] = issue("d0020", "defect", ""),
	[`{DONE}/d0020/spend.d/host-00000001.tsv`] = tsv({
		"2026-01-01 11:00\td0020 ok\t0\t0\tmystery\t7\tm-a\t1.000\t1.000\t\t\t",
	}),
}

return t.spec("d0406 idea spend rows", function(it)
	it("ledger lists idea and idea-challenge, and still rejects any other phase", function()
		t.expect(ledger.isPhase("idea")).toBe(true)
		t.expect(ledger.isPhase("idea-challenge")).toBe(true)
		t.expect(ledger.isPhase("mystery")).toBe(false)
		local parsed =
			ledger.parse(md("c0010", { "| 1 | 2026-01-01 10:05 | x | 0 | 0 | 2.5 | explicit | idea | 11 |" }))
		t.expect(parsed ~= nil).toBe(true)
		t.expect((parsed :: ledger.Ledger).rows[1].phase).toBe("idea")
		local bad, err = ledger.parse(
			md("c0010", { "| 1 | 2026-01-01 10:05 | x | 0 | 0 | 2.5 | explicit | mystery | 11 |" })
		)
		t.expect(bad).toBe(nil)
		t.expect(has(err or "", "unknown phase mystery")).toBe(true)
		local row: ledger.Row = (parsed :: ledger.Ledger).rows[1]
		local wrong = table.clone(row)
		wrong.phase = "mystery"
		local okAppend, why = pcall(ledger.append, nil, "c0010", "T", wrong)
		t.expect(okAppend).toBe(false)
		t.expect(has(tostring(why), "unknown phase mystery")).toBe(true)
		local good = table.clone(row)
		good.phase = "idea-challenge"
		t.expect(has(ledger.append(nil, "c0010", "T", good), "| idea-challenge |")).toBe(true)
	end)

	local f: trackerfix.Fixture? = nil
	local out = ""
	it("metrics finishes on a tracker that holds idea rows", function()
		f = trackerfix.new("d0406-idea", SEED)
		local fx = f :: trackerfix.Fixture
		local r = trackerfix.tr(fx, fx.main, { "metrics" })
		out = r.stdout
		t.expect(has(r.stderr .. r.stdout, "attempt to index nil")).toBe(false)
		t.expect(r.code).toBe(0)
	end)

	it("the phase table reports the idea rows' minutes and tokens under their own phases", function()
		local phases = tableAt(out, "| phase | feature | defect | chore | all | tokens |")
		-- c0010 is a chore: 2.5 typed idea minutes; tokens 11 + 100 + 250, and 300 for the challenge
		t.expect(has(phases, "| idea | 0.0 | 0.0 | 2.5 | 2.5 | 361 |")).toBe(true)
		t.expect(has(phases, "| idea-challenge | 0.0 | 0.0 | 0.0 | 0.0 | 300 |")).toBe(true)
		t.expect(has(phases, "| capture | 0.0 | 0.0 | 4.0 | 4.0 | 0 |")).toBe(true)
		-- the lifecycle phases keep their order, and the idea phases follow them
		local capture = string.find(phases, "| capture |", 1, true) :: number
		local deliver = string.find(phases, "| deliver |", 1, true) :: number
		local idea = string.find(phases, "| idea |", 1, true) :: number
		local challenge = string.find(phases, "| idea-challenge |", 1, true) :: number
		t.expect(capture < deliver and deliver < idea and idea < challenge).toBe(true)
	end)

	it("a phase nothing lists is shown under its own name, after the listed ones", function()
		local phases = tableAt(out, "| phase | feature | defect | chore | all | tokens |")
		t.expect(has(phases, "| mystery | 0.0 | 0.0 | 0.0 | 0.0 | 12 |")).toBe(true)
		local challenge = string.find(phases, "| idea-challenge |", 1, true) :: number
		local mystery = string.find(phases, "| mystery |", 1, true) :: number
		t.expect(challenge < mystery).toBe(true)
	end)

	it("the raft's row counts the idea minutes and tokens in its totals", function()
		local rafts = tableAt(
			out,
			"| raft | type | capture | prep | design-review | build | code-review | deliver | all | tokens |"
		)
		-- capture 4.0, nothing in the other lifecycle columns, all 6.5 (4.0 + 2.5 idea), tokens 666 (the unlisted row included)
		t.expect(has(rafts, "| R0010 | chore | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 6.5 | 666 |")).toBe(true)
	end)

	it("the rounds and lessons tables after the phase table are printed", function()
		t.expect(has(out, "| raft | design rounds | code rounds | format |")).toBe(true)
		t.expect(has(out, "| R0010 | 0 | 0 |")).toBe(true)
		t.expect(has(out, "| tag | findings | items |")).toBe(true)
	end)

	it("metrics <issue> and metrics <raft> list the idea stages", function()
		local fx = f :: trackerfix.Fixture
		for _, id in { "c0010", "R0010" } do
			local r = trackerfix.tr(fx, fx.main, { "metrics", id })
			t.expect(r.code).toBe(0)
			local stages = tableAt(r.stdout, `Stages for {id}.`)
			-- reported minutes, wall, cpu, tokens, ai, test, n
			t.expect(has(stages, "| idea | 2.5 | 13.000 | 2.000 | 361 |")).toBe(true)
			t.expect(has(stages, "| idea-challenge | 0.0 | 20.000 | 2.000 | 300 |")).toBe(true)
		end
		local r = trackerfix.tr(fx, fx.main, { "metrics", "d0020" })
		t.expect(r.code).toBe(0)
	end)

	it("the board is written from the same tracker", function()
		local fx = f :: trackerfix.Fixture
		local r = trackerfix.tr(fx, fx.main, { "board", "--out", ".cache/board-d0406.html", "-O" })
		t.expect(r.code).toBe(0)
		local page = fs.readFile(`{fx.main}/.cache/board-d0406.html`)
		t.expect(has(page, "c0010")).toBe(true)
		t.expect(has(page, "R0010")).toBe(true)
	end)

	it("the readers a raft's spend summary uses return and total the idea rows", function()
		local fx = f :: trackerfix.Fixture
		local rows = costrow.readMeasured(`{fx.main}/{DONE}/c0010`)
		t.expect(#rows).toBe(4)
		local by = ledger.byPhase(rows)
		t.expect(by.idea.records).toBe(2)
		t.expect(by.idea.tokens).toBe(350)
		t.expect(by["idea-challenge"].tokens).toBe(300)
		t.expect(by.capture.records).toBe(0)
		t.expect(ledger.sum(rows).tokens).toBe(655)
	end)

	it("a tracker with no idea row prints no idea line in the phase table", function()
		local plain = trackerfix.new("d0406-plain", {
			[`{DONE}/c0010/c0010.md`] = issue("c0010", "chore", ""),
			[`{DONE}/c0010/spend.md`] = md("c0010", {
				"| 1 | 2026-01-01 10:00 | capture | 0 | 0 | 4.0 | explicit | capture | 0 |",
			}),
		})
		local r = trackerfix.tr(plain, plain.main, { "metrics" })
		t.expect(r.code).toBe(0)
		local phases = tableAt(r.stdout, "| phase | feature | defect | chore | all | tokens |")
		t.expect(has(phases, "| capture | 0.0 | 0.0 | 4.0 | 4.0 | 0 |")).toBe(true)
		t.expect(has(phases, "| deliver | 0.0 | 0.0 | 0.0 | 0.0 | 0 |")).toBe(true)
		t.expect(has(phases, "| idea")).toBe(false)
		t.expect(has(phases, "| test |")).toBe(false)
	end)
end)
