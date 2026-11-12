--!strict
-- c0261: `./zn metrics` prints the cost per model: a "by model" table of tokens, minutes and rows per model id over
-- every issue's spend.md and spend.d, rows that record no model under none, after every other table (c0084's tables keep their
-- shape). A sandbox copy of the tooling with its own small tree (metrics only reads), under .cache/c0261-metrics.
local buffer = require("@znile/engine/buffer")
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local SB = ".cache/c0261-metrics"

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]*$") :: string)
	fs.writeFile(path, text)
end
local function row(subject: string, model: string?, tokens: number, minutes: number): ledger.Row
	return {
		when = "2026-11-08 10:00",
		subject = subject,
		added = 0,
		removed = 0,
		minutes = minutes,
		how = "x",
		phase = "design-review",
		tokens = tokens,
		model = model,
	}
end
local function has(text: string, line: string): boolean
	return string.find("\n" .. text .. "\n", "\n" .. line .. "\n", 1, true) ~= nil
end

return t.spec("c0261 metrics shows the cost per model", function(it)
	it(
		"prints a by-model table: tokens, minutes and rows per model id, none for a row that records no model",
		function()
			if fs.isDir(SB) then
				fs.removeDir(SB)
			end
			fs.writeDir(SB)
			engine.copy(".", SB)
			fs.copy(`{engine.TOP}/.luaurc`, `{SB}/.luaurc`)
			fs.copy(`{engine.TOP}/rokit.toml`, `{SB}/rokit.toml`)
			local tr = `{SB}/pickman/.tracker`
			write(
				`{tr}/issues/c0960/c0960.md`,
				"---\nid: c0960\ntype: chore\ntitle: c0960\nslug: c0960\nraft: \n---\n\n# c0960\n"
			)
			write(
				`{tr}/issues/c0960/spend.md`,
				ledger.render("c0960", "c0960", {
					row("design-review-001", "claude-sonnet-5-5-high", 100, 1),
					row("design-review-002", "claude-opus-5-5", 50, 2),
					row("design-review-003", nil, 7, 3),
				})
			)
			-- a measured row lives in spend.d/<writer>.tsv, beside an older spend.md
			write(
				`{tr}/issues/c0960/spend.d/w1.tsv`,
				buffer.appendTsv(nil, { row("design-review-004", "claude-opus-5-5", 5, 0) })
			)
			write(
				`{tr}/issues/c0961/c0961.md`,
				"---\nid: c0961\ntype: chore\ntitle: c0961\nslug: c0961\nraft: \n---\n\n# c0961\n"
			)
			write(
				`{tr}/issues/c0961/spend.md`,
				ledger.render(
					"c0961",
					"c0961",
					{ row("design-review-001", "claude-sonnet-5-5-high", 20, 1.5) }
				)
			)
			local r = process.exec("scripts/tracker.sh", { "metrics" }, { cwd = SB })
			local out = r.stdout
			local ok = r.ok
			if fs.isDir(SB) then
				fs.removeDir(SB)
			end
			if not ok then
				error(r.stderr .. out)
			end
			t.expect(has(out, "| model | tokens | minutes | rows |")).toBe(true)
			t.expect(has(out, "| claude-sonnet-5-5-high | 120 | 2.5 | 2 |")).toBe(true)
			t.expect(has(out, "| claude-opus-5-5 | 55 | 2.0 | 2 |")).toBe(true)
			t.expect(has(out, "| none | 7 | 3.0 | 1 |")).toBe(true)
			-- last: after the rework lines, so no earlier table changes shape
			local at = string.find(out, "| model | tokens | minutes | rows |", 1, true) :: number
			local rework = string.find(out, "by agent time:", 1, true) :: number
			t.expect(at > rework).toBe(true)
		end
	)
end)
