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
-- c0120 override: fixtures live under the home's .cache (the jail refuses the checkout top's)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local tree = `{here}/.cache/c0790-board`

local function write(path: string, text: string)
	local full = `{tree}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function issue(id: string, kind: string, created: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: {created}\n---\n\n# {id}\n`
end
-- c0120 override: the spec runs from z-nile/, so the vendored marked (a checkout-relative path) is read from the top
local MARKED = `{root}/{board.MARKED_PATH}`
-- c0120 override: render reads its template by a checkout-relative path, so point it at the checkout's top
if string.sub(board.TEMPLATE_PATH, 1, 1) ~= "/" then
	board.TEMPLATE_PATH = `{root}/{board.TEMPLATE_PATH}`
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
		t.expect(assert(s.periods).week.closed.all).toBe(0) -- no history: close days are unknown
	end)

	it("the page has the Stats button and section, beside Rafts and Issues", function()
		-- c0120 override: the spec runs from its project's home after the move
		local html = board.render(m, fs.readFile(MARKED))
		for _, id in { "stats-toggle", "stats", "tab-rafts", "tab-issues", "search", "board-data" } do
			t.expect(string.find(html, `id="{id}"`, 1, true) ~= nil).toBe(true)
		end
		for _, id in { "tab-active", "tab-waiting", "tab-done" } do
			t.expect((string.find(html, `id="{id}"`, 1, true))).toBe(nil)
		end
		local nav = string.match(html, "<nav>.-</nav>") or ""
		t.expect(string.find(nav, "stats", 1, true) == nil).toBe(true)
		t.expect(string.find(html, "history unavailable", 1, true) ~= nil).toBe(true)
	end)

	it("builds of one tree are identical", function()
		-- c0120 override: the spec runs from its project's home after the move
		local marked = fs.readFile(MARKED)
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
		t.expect(u.stats.periods).toBe(nil)
		-- c0120 override: the spec runs from its project's home after the move
		local html = board.render(u, fs.readFile(MARKED))
		t.expect(string.find(html, "no dated data", 1, true) ~= nil).toBe(true)
		fs.removeDir(bare)
	end)

	it("the real tracker's board has history and non-empty views", function()
		-- c0120 override: the spec runs from z-nile/, so the real tracker is collected from the checkout's top
		local real = board.collect(nil, root)
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

	it("the page has every chart for every view and type filter, with themed series colors", function()
		-- c0120 override: the spec runs from its project's home after the move
		local html = board.render(m, fs.readFile(MARKED))
		local section = string.match(html, '<section id="stats".-</section>') or ""
		local figures: { [string]: string } = {}
		for tag, id in
			string.gmatch(
				section,
				'(<figure class="chart%-fig"[^>]*>)%s*<svg class="chart" data%-chart="([^"]+)"'
			)
		do
			figures[id :: string] = tag :: string
		end
		local function visible(id: string): boolean
			return string.find(figures[id], " hidden", 1, true) == nil
		end
		local shown = 0
		for _, v in { "month", "quarter", "year" } do
			for _, ty in { "all", "feature", "defect", "chore" } do
				for _, metric in { "opened", "closed", "net", "minutes", "lines" } do
					local id = `{v}/{ty}/{metric}`
					t.expect(figures[id] ~= nil).toBe(true)
					t.expect(string.find(figures[id], `data-view="{v}"`, 1, true) ~= nil).toBe(true)
					t.expect(string.find(figures[id], `data-type="{ty}"`, 1, true) ~= nil).toBe(true)
					if visible(id) then
						shown += 1
						t.expect(v == "month" and ty == "all").toBe(true) -- only month/all starts visible
					end
				end
			end
			for _, r in { "ratios-count", "ratios-time" } do
				local id = `{v}/{r}`
				t.expect(figures[id] ~= nil).toBe(true)
				local at = string.find(section, `data-chart="{v}/{r}"`, 1, true) or 1 -- plain find: ids hold hyphens
				local stop = string.find(section, "</svg>", at, true) or at
				local svg = string.sub(section, at, stop)
				t.expect(
					string.find(svg, "ser-defect", 1, true) ~= nil
						and string.find(svg, "ser-chore", 1, true) ~= nil
				).toBe(true) -- defect % and chore % are two distinct series
				if visible(id) then
					shown += 1
				end
			end
		end
		t.expect(figures.durations ~= nil).toBe(true)
		if visible("durations") then
			shown += 1
		end
		t.expect(shown).toBe(8) -- month/all's five, month's two ratio charts and the durations
		for _, id in { "stats-view", "stats-type", "stats-table-toggle", "stats-tables" } do
			t.expect(string.find(section, `id="{id}"`, 1, true) ~= nil).toBe(true)
		end
		-- series tokens: light in :root, dark in the dark media block, different, and every class painted from them
		local light = string.match(html, ":root%s*{[^}]*}") or ""
		local dark = string.match(html, "@media %(prefers%-color%-scheme: dark%)%s*{%s*:root%s*{[^}]*}") or ""
		for _, key in { "feature", "defect", "chore", "net" } do
			local lv = string.match(light, `%-%-ser%-{key}:%s*([^;]+);`)
			local dv = string.match(dark, `%-%-ser%-{key}:%s*([^;]+);`)
			t.expect(lv ~= nil and dv ~= nil and lv ~= dv).toBe(true)
			t.expect(string.find(html, `.ser-{key}`, 1, true) ~= nil).toBe(true)
			t.expect(string.find(html, `var(--ser-{key})`, 1, true) ~= nil).toBe(true)
		end
	end)

	it(
		"the Table view has one table per view, the periods and the time in state, with units in the headers",
		function()
			-- c0120 override: the spec runs from its project's home after the move
			local html = board.render(m, fs.readFile(MARKED))
			local tables = string.match(html, '<div id="stats%-tables".-</div>') or ""
			local _, n = string.gsub(tables, "<table", "")
			t.expect(n >= 5).toBe(true) -- month, quarter, year, the periods, time in state
			for _, unit in { "minutes", "+lines", "−lines", "days", "%" } do
				t.expect(string.find(tables, unit, 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("the Stats section stays under 450 KB for a busy year", function()
		local busy = `{tree}-busy`
		if fs.isDir(busy) then
			fs.removeDir(busy)
		end
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			fs.writeDir(`{busy}/tracker/{d}`)
		end
		local kinds = { "feature", "defect", "chore" }
		for i = 1, 240 do
			local id = string.format("%s%04d", string.sub(kinds[(i % 3) + 1], 1, 1), i)
			local month = (i % 12) + 1
			local day = (i % 27) + 1
			local created = string.format("2025-%02d-%02d", month, day)
			local dir = `{busy}/tracker/issues/{id}`
			fs.writeDir(dir)
			fs.writeFile(`{dir}/{id}.md`, issue(id, kinds[(i % 3) + 1], created))
			fs.writeFile(
				`{dir}/spend.md`,
				SPEND_HEAD .. `| 1 | {created} 10:00 | abc1234 | {i * 3} | {i} | {i % 50 + 5} | explicit |\n`
			)
		end
		-- c0120 override: the spec runs from its project's home after the move
		local html = board.render(board.collect(`{busy}/tracker`), fs.readFile(MARKED))
		local section = string.match(html, '<section id="stats".-</section>') or ""
		t.expect(#section > 0).toBe(true)
		t.expect(#section < 450 * 1024).toBe(true)
		fs.removeDir(busy)
	end)

	it("the board workflow checks out full history", function()
		-- c0120 override: the spec runs from z-nile/, so the workflow is read from the checkout's top
		local wf = serde.decode("yaml", fs.readFile(`{root}/.github/workflows/board.yml`))
		local steps = wf.jobs.board.steps
		t.expect(steps[1].uses).toBe("actions/checkout@v4")
		t.expect(steps[1].with["fetch-depth"]).toBe(0)
		fs.removeDir(tree)
	end)
end)
