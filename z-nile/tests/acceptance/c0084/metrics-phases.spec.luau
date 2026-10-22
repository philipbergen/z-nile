--!strict
-- c0084: `tracker.sh metrics` reports spend by phase and type, per raft by phase, and the design-review cost per
-- round, and says that rework counts every phase. A sandbox copy of the tooling with its own small tracker tree
-- (metrics only reads), under .cache/c0084-metrics. Ids are fixture ids no real item uses.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local SB = ".cache/c0084-metrics"

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]*$") :: string)
	fs.writeFile(path, text)
end

local function doc(id: string, kind: string, raft: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {id}\nraft: {raft}\n---\n\n# {id}\n`
end
local function raftDoc(id: string, kind: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {id}\n---\n\n# {id}\n`
end

local NEW_HEAD = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n"
	.. "|---|---|---|---|---|---|---|---|---|\n"
local OLD_HEAD =
	"| # | when | commit | +lines | -lines | minutes | attribution |\n|---|---|---|---|---|---|---|\n"
-- { phase, added, minutes, tokens or "" }
local function ledgerOf(id: string, rows: { { any } }): string
	local out = `# Spend: {id} {id}\n\n{NEW_HEAD}`
	for i, r in rows do
		out ..= `| {i} | 2026-10-01 10:00 | s | {r[2]} | 0 | {r[3]} | spend | {r[1]} | {r[4]} |\n`
	end
	return out
end

local REVIEW = "# Review 001\n\n### F1 [low] x\nWhere: a\nEvidence: b\nFix: c\n\nVerdict: approve\n"

local function build()
	if fs.isDir(SB) then
		fs.removeDir(SB)
	end
	fs.writeDir(SB)
	engine.copy(".", SB) -- c0114 override: ./zn, scripts/ and z-nile/
	-- c0120 override: the spec runs from z-nile/; the root's .luaurc and rokit.toml are at the checkout's top
	fs.copy(`{engine.TOP}/.luaurc`, `{SB}/.luaurc`)
	fs.copy(`{engine.TOP}/rokit.toml`, `{SB}/rokit.toml`)
	-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
	local tr = `{SB}/pickman/.tracker`
	-- R0910: a done feature raft, two design rounds, every phase on f0910 and an old seven-cell ledger on f0911
	write(`{tr}/rafts/done/R0910/R0910.md`, raftDoc("R0910", "feature"))
	write(`{tr}/rafts/done/R0910/design-review-001.md`, REVIEW)
	write(`{tr}/rafts/done/R0910/design-review-002.md`, REVIEW)
	write(`{tr}/issues/done/f0910/f0910.md`, doc("f0910", "feature", "R0910"))
	write(
		`{tr}/issues/done/f0910/spend.md`,
		ledgerOf("f0910", {
			{ "capture", 0, "2.0", "" },
			{ "prep", 40, "10.0", "" },
			{ "design-review", 0, "6.0", "1000" },
			{ "build", 100, "30.0", "" },
			{ "code-review", 0, "8.0", "500" },
			{ "deliver", 0, "4.0", "" },
		})
	)
	write(`{tr}/issues/done/f0911/f0911.md`, doc("f0911", "feature", "R0910"))
	write(
		`{tr}/issues/done/f0911/spend.md`,
		`# Spend: f0911 f0911\n\n{OLD_HEAD}| 1 | 2026-09-29 03:16 | old | 10 | 0 | 20.0 | focus |\n`
	)
	-- R0920: a done defect raft without design rounds
	write(`{tr}/rafts/done/R0920/R0920.md`, raftDoc("R0920", "defect"))
	write(`{tr}/issues/done/d0920/d0920.md`, doc("d0920", "defect", "R0920"))
	write(`{tr}/issues/done/d0920/spend.md`, ledgerOf("d0920", { { "build", 5, "10.0", "" } }))
	-- a done chore in no raft
	write(`{tr}/issues/done/c0930/c0930.md`, doc("c0930", "chore", ""))
	write(`{tr}/issues/done/c0930/spend.md`, ledgerOf("c0930", { { "build", 1, "5.0", "" } }))
	-- R0940: a raft still in prep, two design rounds; its member is not done, so it counts only per round
	write(`{tr}/rafts/R0940/R0940.md`, raftDoc("R0940", "chore"))
	write(`{tr}/rafts/R0940/design-review-001.md`, REVIEW)
	write(`{tr}/rafts/R0940/design-review-002.md`, REVIEW)
	write(`{tr}/issues/c0940/c0940.md`, doc("c0940", "chore", "R0940"))
	write(
		`{tr}/issues/c0940/spend.md`,
		ledgerOf("c0940", { { "design-review", 0, "4.0", "300" }, { "design-review", 0, "6.0", "100" } })
	)
end

local function metrics(): string
	local r = process.exec("scripts/tracker.sh", { "metrics" }, { cwd = SB })
	if not r.ok then
		error(r.stderr .. r.stdout)
	end
	return r.stdout
end

local function has(text: string, line: string): boolean
	return string.find("\n" .. text .. "\n", "\n" .. line .. "\n", 1, true) ~= nil
end

-- the text from a table's header line up to the next blank line
local function tableAt(text: string, header: string): string
	local s = string.find(text, header, 1, true)
	if not s then
		error(`no table headed {header}:\n{text}`, 2)
	end
	return string.match(string.sub(text, s :: number), "^(.-)\n\n") or string.sub(text, s :: number)
end

return t.spec("metrics by phase", function(it)
	local out = ""
	local ok, err = pcall(function()
		build()
		out = metrics()
	end)
	if fs.isDir(SB) then
		fs.removeDir(SB)
	end
	if not ok then
		error(err, 0)
	end

	it("lists every counted issue with its tokens, old seven-cell ledgers included", function()
		local tbl = tableAt(out, "| issue | type | raft | +lines | -lines | agent-minutes | tokens |")
		t.expect(has(tbl, "| f0910 | feature | R0910 | 140 | 0 | 60.0 | 1500 |")).toBe(true)
		t.expect(has(tbl, "| f0911 | feature | R0910 | 10 | 0 | 20.0 | 0 |")).toBe(true)
		t.expect((string.find(tbl, "c0940", 1, true))).toBe(nil) -- not done
	end)

	it("sums agent-minutes by phase and type, in lifecycle order, with tokens", function()
		local tbl = tableAt(out, "| phase | feature | defect | chore | all | tokens |")
		local want = {
			"| capture | 2.0 | 0.0 | 0.0 | 2.0 | 0 |",
			"| prep | 10.0 | 0.0 | 0.0 | 10.0 | 0 |",
			"| design-review | 6.0 | 0.0 | 0.0 | 6.0 | 1000 |",
			"| build | 50.0 | 10.0 | 5.0 | 65.0 | 0 |",
			"| code-review | 8.0 | 0.0 | 0.0 | 8.0 | 500 |",
			"| deliver | 4.0 | 0.0 | 0.0 | 4.0 | 0 |",
		}
		local rows: { string } = {}
		for line in string.gmatch(tbl, "[^\n]+") do
			if string.match(line, "^| [%l%-]+ | %d") then
				table.insert(rows, line)
			end
		end
		t.expect(rows).toEqual(want)
	end)

	it("gives each raft with counted issues its minutes by phase", function()
		local tbl = tableAt(
			out,
			"| raft | type | capture | prep | design-review | build | code-review | deliver | all | tokens |"
		)
		t.expect(has(tbl, "| R0910 | feature | 2.0 | 10.0 | 6.0 | 50.0 | 8.0 | 4.0 | 80.0 | 1500 |"))
			.toBe(true)
		t.expect(has(tbl, "| R0920 | defect | 0.0 | 0.0 | 0.0 | 10.0 | 0.0 | 0.0 | 10.0 | 0 |")).toBe(true)
		t.expect((string.find(tbl, "R0940", 1, true))).toBe(nil)
	end)

	it("prices a design round for every raft that has one, in any state", function()
		local tbl =
			tableAt(out, "| raft | design rounds | design-review minutes | minutes/round | tokens/round |")
		t.expect(has(tbl, "| R0910 | 2 | 6.0 | 3.0 | 500 |")).toBe(true)
		t.expect(has(tbl, "| R0940 | 2 | 10.0 | 5.0 | 200 |")).toBe(true)
		t.expect((string.find(tbl, "R0920", 1, true))).toBe(nil) -- no design rounds
	end)

	it("keeps the review-rounds table, and comes before it", function()
		t.expect(has(out, "| raft | design rounds | code rounds | format |")).toBe(true)
		t.expect(has(out, "| R0910 | 2 | 0 | classic |")).toBe(true)
		t.expect(has(out, "| R0920 | 0 | 0 | none |")).toBe(true)
		local rounds = string.find(out, "| raft | design rounds | code rounds | format |", 1, true) :: number
		local per = string.find(out, "| raft | design rounds | design-review minutes", 1, true) :: number
		t.expect(per < rounds).toBe(true)
	end)

	it("counts every phase in rework, and says so", function()
		t.expect(string.find(out, "Rework counts every phase, capture to deliver.", 1, true) ~= nil)
			.toBe(true)
		t.expect(string.find(out, "by agent time:   11.1%", 1, true) ~= nil).toBe(true) -- 10 / (10 + 80)
		t.expect(string.find(out, "by lines added:  3.2%", 1, true) ~= nil).toBe(true) -- 5 / (5 + 150)
	end)
end)
