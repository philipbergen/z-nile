--!strict
-- c0790: the board carries statistics. A tracker tree under .cache/c0790-board with no repository of its own (so no
-- history), and the real tracker (with history). Dates are in 2025, so a "today" taken from the clock would show.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local tree = `{root}/.cache/c0790-board`

local function write(path: string, text: string)
	local full = `{tree}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function issue(id: string, kind: string, created: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: {created}\n---\n\n# {id}\n`
end
local SPEND_HEAD =
	"# Spend\n\n| # | when | commit | +lines | -lines | minutes | attribution |\n|---|---|---|---|---|---|---|\n"

local m: any = nil

return t.spec("tracker board statistics", function(it)
	it("the model carries stats from created dates and spend rows, without history", function()
		if fs.isDir(tree) then
			fs.removeDir(tree)
		end
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			fs.writeDir(`{tree}/tracker/{d}`)
		end
		write("tracker/issues/f0010/f0010.md", issue("f0010", "feature", "2025-06-10"))
		write(
			"tracker/issues/f0010/spend.md",
			SPEND_HEAD .. "| 1 | 2025-06-11 09:30 | abc1234 | 100 | 20 | 30 | explicit |\n"
		)
		write("tracker/issues/done/d0020/d0020.md", issue("d0020", "defect", "2025-06-11"))
		write(
			"tracker/issues/done/d0020/spend.md",
			SPEND_HEAD .. "| 1 | 2025-06-12 10:00 | def5678 | 10 | 5 | 10 | explicit |\n"
		)
		m = board.collect(tree .. "/tracker") -- collect takes the tracker directory
		local s = m.stats
		t.expect(s ~= nil).toBe(true)
		t.expect(s.history).toBe(false)
		t.expect(s.today).toBe("2025-06-12") -- the latest date in the data, not the clock
		t.expect(#s.views.month).toBe(32) -- 2025-05-12 through 2025-06-12
		local byStart: { [string]: any } = {}
		for _, row in s.views.month do
			byStart[row.bucket.start] = row
		end
		t.expect(byStart["2025-06-10"].opened.feature).toBe(1)
		t.expect(byStart["2025-06-11"].opened.defect).toBe(1)
		t.expect(byStart["2025-06-11"].minutes.all).toBe(30)
		t.expect(byStart["2025-06-12"].netLines.defect).toBe(5)
		t.expect(s.periods.week.closed.all).toBe(0) -- no history: close days are unknown
	end)

	it("the page has the Stats button and section, and keeps the three tabs", function()
		local html = board.render(m, fs.readFile(board.MARKED_PATH))
		for _, id in
			{ "stats-toggle", "stats", "tab-active", "tab-waiting", "tab-done", "search", "board-data" }
		do
			t.expect(string.find(html, `id="{id}"`, 1, true) ~= nil).toBe(true)
		end
		local nav = string.match(html, "<nav>.-</nav>") or ""
		t.expect(string.find(nav, "stats", 1, true) == nil).toBe(true) -- not a fourth tab
		t.expect(string.find(html, "history unavailable", 1, true) ~= nil).toBe(true)
	end)

	it("builds of one tree are identical", function()
		local marked = fs.readFile(board.MARKED_PATH)
		t.expect(
			board.render(board.collect(tree .. "/tracker"), marked)
				== board.render(board.collect(tree .. "/tracker"), marked)
		).toBe(true)
	end)

	it("an undated tree collects without error and shows no dated data", function()
		local bare = `{tree}-undated`
		if fs.isDir(bare) then
			fs.removeDir(bare)
		end
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			fs.writeDir(`{bare}/tracker/{d}`)
		end
		fs.writeDir(`{bare}/tracker/issues/c0010`)
		fs.writeFile(`{bare}/tracker/issues/c0010/c0010.md`, "---\nid: c0010\ntype: chore\ntitle: x\n---\n")
		local u = board.collect(`{bare}/tracker`)
		t.expect(u.stats.today).toBe("")
		t.expect(#u.stats.views.month).toBe(0)
		local html = board.render(u, fs.readFile(board.MARKED_PATH))
		t.expect(string.find(html, "no dated data", 1, true) ~= nil).toBe(true)
		fs.removeDir(bare)
	end)

	it("the real tracker's board has history and non-empty views", function()
		local real = board.collect()
		t.expect(real.stats.history).toBe(true)
		t.expect(#real.stats.views.year).toBe(13)
		local opened = 0
		for _, row in real.stats.views.year do
			opened += row.opened.all
		end
		t.expect(opened > 0).toBe(true)
		local closed = 0
		for _, row in real.stats.views.year do
			closed += row.closed.all
		end
		t.expect(closed > 0).toBe(true)
	end)

	it("the board workflow checks out full history", function()
		local wf = serde.decode("yaml", fs.readFile(".github/workflows/board.yml"))
		local steps = wf.jobs.board.steps
		t.expect(steps[1].uses).toBe("actions/checkout@v4")
		t.expect(steps[1].with["fetch-depth"]).toBe(0)
		fs.removeDir(tree)
	end)
end)
