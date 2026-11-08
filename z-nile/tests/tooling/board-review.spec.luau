--!strict
-- c0118, code review 001 (R0083): what the first review found that the sequestered acceptance specs do not pin.
--   F1: a chart's caption carries the unit its axis was scaled to and, for one series, that series (the chart draws a
--       legend from two); the board's charts are sized in #charts, not by Stats' 320 px.
--   F2: the page shows model.problems (a spend.md that does not parse).
--   F3: the board keeps no round-file pattern of its own (boardview.rounds is the one rule, shared with metrics).
-- Fixture under .cache/c0118-review (a tracker folder, no git): the done dates come from spend rows.
local board = require("@znile/engine/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local here = trim(process.exec("pwd", { "-P" }).stdout)
local dir = `{here}/.cache/c0118-review`
local TRACKER = `{dir}/game/.tracker`
local AS_OF = stats.seconds("2026-10-21T10:00:00Z")
local FACTS = { asOf = AS_OF, refs = {}, worktrees = {}, dispatch = {} }
local HEADER = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model |\n"
	.. "|---|---|---|---|---|---|---|---|---|---|\n"

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function item(path: string, id: string, front: string)
	write(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n`)
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end
local function readSource(path: string): string
	return fs.readFile(`{here}/{path}`)
end

-- the code of a Luau file with its line comments removed (board.luau writes none as a long comment)
local function code(src: string): string
	local lines = {}
	for line in string.gmatch(src, "[^\n]*") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

return t.spec("c0118 code review 001", function(it)
	it("sets up a done raft whose only review spend is one model's 12 million tokens", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		write(`{here}/.cache/c0118-review/z-nile-marker`, "fixture\n")
		item(`{TRACKER}/rafts/done/R0010`, "R0010", "type: chore\ntitle: Landed\ndesign: ready\nstatus: done")
		item(`{TRACKER}/issues/done/c0011`, "c0011", "type: chore\ntitle: Member\nraft: R0010\nstatus: done")
		write(
			`{TRACKER}/issues/done/c0011/spend.md`,
			"# Spend: c0011 t\n\n"
				.. HEADER
				.. "| 1 | 2026-10-19 10:00 | s | 0 | 0 | 2.0 | spend | design-review | 12000000 | opus-x |\n"
		)
		write(`{TRACKER}/issues/done/c0011/design-review-001.md`, "# Review 001\n")
	end)

	it(
		"F1: the tokens caption names the scaled unit and the lone series; the rounds caption stays plain",
		function()
			local m = board.collect(TRACKER, nil, FACTS)
			local game = m.charts.game
			t.expect(game ~= nil).toBe(true)
			for _, range in m.ranges do
				t.expect(has(game.captions.tokens[range.key], "M tokens")).toBe(true)
				t.expect(has(game.captions.tokens[range.key], "opus-x")).toBe(true)
				t.expect(game.captions.rounds[range.key]).toBe("")
			end
		end
	)

	it("F1: the page puts the caption in the figure and sizes the board's charts apart from Stats", function()
		local html = board.build(TRACKER, nil, FACTS)
		t.expect(has(html, "ch.captions.tokens[range]")).toBe(true)
		t.expect(has(html, "#charts .chart { width: 100%; max-width: 640px; }")).toBe(true)
		t.expect(has(html, ".chart { width: 320px; height: auto; }")).toBe(true) -- Stats keeps its own size
	end)

	it(
		"F2: a spend.md that does not parse is named in the model and the page shows the model's problems",
		function()
			write(
				`{TRACKER}/issues/done/c0012/c0012.md`,
				"---\nid: c0012\ntype: chore\ntitle: Bad\nstatus: done\n---\n\n# c0012\n"
			)
			write(
				`{TRACKER}/issues/done/c0012/spend.md`,
				"# Spend: c0012 t\n\n| 1 | 2026-10-20 10:00 | unterminated\n"
			)
			local m = board.collect(TRACKER, nil, FACTS)
			t.expect(#m.problems >= 1).toBe(true)
			local named = false
			for _, p in m.problems do
				if has(p, "c0012/spend.md") then
					named = true
				end
			end
			t.expect(named).toBe(true)
			local html = board.build(TRACKER, nil, FACTS)
			t.expect(has(html, 'id="problems"')).toBe(true)
			t.expect(has(html, "problemsEl.innerHTML")).toBe(true)
			t.expect(has(html, "files could not be read")).toBe(true)
			t.expect(has(html, "c0012/spend.md")).toBe(true) -- in the embedded model
		end
	)

	it("F3: board.luau keeps no round-file pattern of its own: boardview.rounds counts the files", function()
		local src = code(readSource("engine/board.luau"))
		t.expect(has(src, "review%-")).toBe(false)
		t.expect(has(src, "boardview.rounds(")).toBe(true)
	end)
end)
