--!strict
-- c0118 AC3: board.collect over a checkout with two projects: the tabs in registry order, each issue in its project's
-- column (ready or run by its raft's branch), raft bands, done times from history (or, across a compaction, from the
-- newest spend row), the done age, a raft's rounds with its members' and its retired rafts', each project's two charts,
-- the card facts (model, spend, branch, worktree, dispatcher state), problems named, and board.readFacts on a repository.
-- Fixture under .cache/c0118-model, a repository of its own; git runs through @tests/lib/fixture.
local board = require("@znile/engine/board")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local stats = require("@znile/engine/stats")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
-- fixtures live under the home's .cache, where the spec runs (the jail refuses the checkout top's when they differ)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local repo = `{here}/.cache/c0118-model`

local REGISTRY = [==[
[[project]]
name = "game"
root = "game/.tracker"

[[project]]
name = "tool"
root = "tool/.tracker"
]==]

local function write(path: string, text: string)
	local full = `{repo}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function item(path: string, front: { string })
	local id = string.match(path, "([^/]+)$") :: string
	write(
		`{path}/{id}.md`,
		"---\nid: " .. id .. "\n" .. table.concat(front, "\n") .. "\n---\n\n# " .. id .. "\n"
	)
end
local HEADER = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model |\n"
	.. "|---|---|---|---|---|---|---|---|---|---|\n"
local function spend(dir: string, id: string, rows: { string })
	write(`{dir}/spend.md`, `# Spend: {id} t\n\n` .. HEADER .. table.concat(rows, "\n") .. "\n")
end
local function commit(at: string, message: string)
	local env = { GIT_AUTHOR_DATE = at, GIT_COMMITTER_DATE = at }
	fixture.git(repo, { "add", "-A" }, { env = env })
	fixture.git(repo, { "commit", "-q", "-m", message }, { env = env })
end
local function move(from: string, to: string)
	fs.writeDir(string.match(`{repo}/{to}`, "^(.*)/[^/]+$") :: string)
	fixture.git(repo, { "mv", from, to })
end

local G, T = "game/.tracker", "tool/.tracker"
-- the fixture's own dispatcher folder, spelled in two parts: c0049 counts a literal .cache/<dir> as a fixture name
local DISPATCH = "." .. "cache/dispatch"
local AS_OF = stats.seconds("2026-10-21T10:00:00Z")
local LANDED = stats.seconds("2026-10-20T10:00:00Z")
local FACTS = {
	asOf = AS_OF,
	refs = {
		{ name = "main", at = AS_OF },
		{ name = "origin/R0020-alpha", at = stats.seconds("2026-10-02T10:00:00Z") }, -- after R0020's ready
		{ name = "R00300-x", at = AS_OF },
		{ name = "feature/R0030-x", at = AS_OF },
		{ name = "xR0030-y", at = AS_OF },
		{ name = "R0030-left", at = stats.seconds("2026-09-30T10:00:00Z") }, -- left from before R0030's ready
		{ name = "origin/main", at = AS_OF },
	},
	worktrees = { { path = "/w/R0020", branch = "R0020-alpha" }, { path = "/w/main", branch = "main" } },
	dispatch = { f0021 = { step = "z-run", outcome = "running", model = "grok-y", questions = true } },
}

local m: any = nil
local function byId(list: { any }): { [string]: any }
	local out = {}
	for _, x in list do
		out[x.id] = x
	end
	return out
end
local function bandsOf(project: string, column: string): { any }
	return m.columns[project][column]
end
local function band(raft: string?, ids: { string }): any
	return { raft = raft, ids = ids }
end
local function idsIn(project: string): { [string]: boolean }
	local out = {}
	for _, bands in m.columns[project] do
		for _, b in bands do
			for _, id in b.ids do
				out[id] = true
			end
		end
	end
	return out
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0118 board model", function(it)
	it("sets up a two-project repository with landed, running, readied, prepared and new work", function()
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(repo)
		process.exec("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
		fixture.git(repo, { "config", "user.name", "c0118-model" })
		fixture.git(repo, { "config", "user.email", "c0118-model@example.invalid" })
		write("z-nile/projects.toml", REGISTRY)
		-- game: R0010 lands with c0011; reviews on the raft, on its member, and on two rafts retired into it
		item(
			`{G}/rafts/active/R0010`,
			{ "type: chore", "title: Landed", "design: ready", "status: active-a-b-c" }
		)
		item(
			`{G}/issues/active/c0011`,
			{ "type: chore", "title: Member", "raft: R0010", "status: active-a-b-c" }
		)
		write(`{G}/rafts/active/R0010/design-review-001.md`, "# Review 001\n")
		write(`{G}/rafts/active/R0010/design-refute-001.md`, "# Refute 001\n")
		write(`{G}/rafts/active/R0010/review-001.md`, "# Review 001\n")
		write(`{G}/issues/active/c0011/design-review-001.md`, "# Review 001\n")
		write(`{G}/issues/active/c0011/design-review-002.md`, "# Review 002\n")
		item(`{G}/rafts/retired/R0019`, { "type: chore", "title: Retired", "retired: R0010" })
		write(`{G}/rafts/retired/R0019/design-review-001.md`, "# Review 001\n")
		item(`{G}/rafts/retired/R0018`, { "type: chore", "title: Retired earlier", "retired: R0019" })
		write(`{G}/rafts/retired/R0018/design-review-001.md`, "# Review 001\n")
		spend(`{G}/issues/active/c0011`, "c0011", {
			"| 1 | 2026-10-19 10:00 | s | 0 | 0 | 2.0 | spend | design-review | 1000 | opus-x |",
			"| 2 | 2026-10-20 09:00 | s | 0 | 0 | 1.0 | spend | code-review | 500 |  |",
			"| 3 | 2026-10-20 09:30 | s | 10 | 2 | 5.0 | raft | build | 99999 | build-model |",
		})
		-- running: R0020 has a branch on origin and a worktree; readied: R0030 has only look-alike branches
		item(
			`{G}/rafts/active/R0020`,
			{ "type: feature", "title: Running", "design: ready", "status: active-d-e-f" }
		)
		item(
			`{G}/issues/active/f0021`,
			{ "type: feature", "title: Runs", "raft: R0020", "status: active-d-e-f" }
		)
		spend(
			`{G}/issues/active/f0021`,
			"f0021",
			{ "| 1 | 2026-10-20 11:00 | s | 0 | 0 | 3.0 | spend | code-review | 300 | grok-y |" }
		)
		item(
			`{G}/rafts/active/R0030`,
			{ "type: feature", "title: Readied", "design: ready", "status: active-g-h-i" }
		)
		item(
			`{G}/issues/active/f0031`,
			{ "type: feature", "title: Waits", "raft: R0030", "status: active-g-h-i" }
		)
		-- prepared: one in a backlog raft, one with no raft yet; preparing; new
		item(
			`{G}/rafts/R0040`,
			{ "type: feature", "title: Prepared", "design: ready", "status: prepared-j-k-l" }
		)
		item(
			`{G}/issues/f0041`,
			{ "type: feature", "title: Rafted", "raft: R0040", "status: prepared-j-k-l" }
		)
		item(
			`{G}/issues/f0042`,
			{ "type: feature", "title: Unrafted", "raft:", "design: ready", "status: prepared-m-n-o" }
		)
		item(`{G}/issues/f0050`, { "type: feature", "title: Designing", "raft:", "status: preparing-p-q-r" })
		write(`{G}/issues/f0050/spend.md`, "# Spend: f0050 t\n\n| 1 | 2026-10-20 10:00 | unterminated\n")
		item(`{G}/issues/f0060`, { "type: feature", "title: Captured", "raft:", "design: draft" })
		-- tool: R0110 landed two weeks earlier
		item(
			`{T}/rafts/active/R0110`,
			{ "type: chore", "title: Tool raft", "design: ready", "status: active-s-t-u" }
		)
		item(
			`{T}/issues/active/c0111`,
			{ "type: chore", "title: Tool member", "raft: R0110", "status: active-s-t-u" }
		)
		write(`{T}/issues/active/c0111/design-review-001.md`, "# Review 001\n")
		spend(
			`{T}/issues/active/c0111`,
			"c0111",
			{ "| 1 | 2026-10-05 10:00 | s | 0 | 0 | 2.0 | spend | design-review | 7000 | tool-model |" }
		)
		item(`{T}/issues/c0120`, { "type: chore", "title: Tool ticket", "raft:" })
		commit("2026-10-01T10:00:00Z", "the trackers")
		move(`{T}/rafts/active/R0110`, `{T}/rafts/done/R0110`)
		move(`{T}/issues/active/c0111`, `{T}/issues/done/c0111`)
		commit("2026-10-06T10:00:00Z", "R0110: land")
		move(`{G}/rafts/active/R0010`, `{G}/rafts/done/R0010`)
		move(`{G}/issues/active/c0011`, `{G}/issues/done/c0011`)
		commit("2026-10-20T10:00:00Z", "R0010: land")
		-- a compaction re-adds c0070 in done/ under its new id: no landing time from history
		item(`{G}/issues/done/c0070`, { "type: chore", "title: Compacted", "raft:", "status: active-v-w-x" })
		spend(`{G}/issues/done/c0070`, "c0070", {
			"| 1 | 2026-10-14 08:00 | s | 1 | 0 | 2.0 | focus | build |  |  |",
			"| 2 | 2026-10-15 08:00 | s | 0 | 0 | 1.0 | raft | deliver |  |  |",
		})
		write("z-nile/compaction.txt", "# map\nc0700 c0070\n")
		-- the compaction keeps c0011 and rewrites its document in place: board.collect's history keeps its landing
		item(
			`{G}/issues/done/c0011`,
			{ "type: chore", "title: Member", "raft: R0010", "status: active-a-b-c", "after: c0070" }
		)
		commit("2026-10-21T09:00:00Z", "tracker: compact ids")
		m = board.collect(nil, repo, FACTS)
		t.expect(m ~= nil).toBe(true)
	end)

	it("has one tab per project, in registry order, and tags every item with its project", function()
		t.expect(m.projects).toEqual({ { name = "game", root = G }, { name = "tool", root = T } })
		local issues, rafts = byId(m.issues), byId(m.rafts)
		t.expect(issues.c0011.project).toBe("game")
		t.expect(issues.c0111.project).toBe("tool")
		t.expect(rafts.R0110.project).toBe("tool")
		t.expect(idsIn("tool")).toEqual({ c0111 = true, c0120 = true })
		local game = idsIn("game")
		t.expect(game.c0111).toBe(nil)
		t.expect(game.f0021).toBe(true)
	end)

	it("puts each issue in its column, with each raft a band and the raftless cards last", function()
		t.expect(bandsOf("game", "ticket")).toEqual({ band(nil, { "f0060" }) })
		t.expect(bandsOf("game", "design")).toEqual({ band(nil, { "f0050" }) })
		t.expect(bandsOf("game", "raft")).toEqual({ band("R0040", { "f0041" }), band(nil, { "f0042" }) })
		t.expect(bandsOf("game", "ready")).toEqual({ band("R0030", { "f0031" }) })
		t.expect(bandsOf("game", "run")).toEqual({ band("R0020", { "f0021" }) })
		t.expect(bandsOf("game", "done")).toEqual({ band("R0010", { "c0011" }), band(nil, { "c0070" }) })
		t.expect(bandsOf("tool", "ticket")).toEqual({ band(nil, { "c0120" }) })
		t.expect(byId(m.issues).f0021.column).toBe("run")
	end)

	it(
		"a raft runs when a branch <R-id>-…, local or on origin, has a commit after its latest ready; look-alikes and a branch left from before do not count",
		function()
			local rafts = byId(m.rafts)
			t.expect(rafts.R0020.launched).toBe(true)
			t.expect(rafts.R0020.branch).toBe("R0020-alpha")
			t.expect(rafts.R0020.worktree).toBe("/w/R0020")
			t.expect(rafts.R0030.launched).toBe(false)
			t.expect(rafts.R0030.branch).toBe(nil)
			local local_ = board.collect(nil, repo, {
				asOf = AS_OF,
				refs = { { name = "R0030-left", at = stats.seconds("2026-10-01T10:00:01Z") } }, -- one second after the ready
				worktrees = {},
				dispatch = {},
			})
			t.expect(byId(local_.rafts).R0030.launched).toBe(true)
			t.expect(byId(local_.issues).f0031.column).toBe("run")
			local same = board.collect(nil, repo, {
				asOf = AS_OF,
				refs = { { name = "R0030-left", at = stats.seconds("2026-10-01T10:00:00Z") } }, -- the ready's own second
				worktrees = {},
				dispatch = {},
			})
			t.expect(byId(same.rafts).R0030.launched).toBe(false)
		end
	)

	it("dates landings from history, and an arrival under a compaction from the newest spend row", function()
		local issues, rafts = byId(m.issues), byId(m.rafts)
		t.expect(rafts.R0010.doneAt).toBe(LANDED)
		t.expect(rafts.R0010.doneFrom).toBe("history")
		t.expect(issues.c0011.doneAt).toBe(LANDED)
		t.expect(issues.c0011.doneFrom).toBe("history") -- kept by the compaction, whose map history.read reads
		t.expect(issues.c0011.age).toBe(AS_OF - LANDED)
		t.expect(issues.c0070.doneAt).toBe(stats.seconds("2026-10-15T08:00:00Z"))
		t.expect(issues.c0070.doneFrom).toBe("spend")
		t.expect(issues.f0021.doneAt).toBe(nil)
		t.expect(issues.f0021.age).toBe(nil)
	end)

	it(
		"counts a raft's rounds over its folder, its members' and its retired rafts' (followed through), once each",
		function()
			local rafts = byId(m.rafts)
			t.expect(rafts.R0010.rounds).toEqual({ design = 5, code = 1 })
			t.expect(rafts.R0110.rounds).toEqual({ design = 1, code = 0 })
			t.expect(rafts.R0020.rounds).toEqual({ design = 0, code = 0 })
		end
	)

	it("draws each project's rounds chart for every range from that project's landed rafts only", function()
		for _, r in m.ranges do
			t.expect(type(m.charts.game.rounds[r.key])).toBe("string")
			t.expect(type(m.charts.game.tokens[r.key])).toBe("string")
		end
		local game, tool = m.charts.game.rounds.all, m.charts.tool.rounds.all
		t.expect(has(game, "Design reviews, Oct 19: 5 rounds")).toBe(true)
		t.expect(has(game, "Code reviews, Oct 19: 1 rounds")).toBe(true)
		t.expect(has(game, "Oct 5")).toBe(false)
		t.expect(has(tool, "Design reviews, Oct 5: 1 rounds")).toBe(true)
		t.expect(has(m.charts.tool.rounds["90d"], "Design reviews, Oct 5: 1 rounds")).toBe(true)
		t.expect(has(m.charts.tool.rounds["30d"], "Design reviews, Oct 5: 1 rounds")).toBe(true)
	end)

	it(
		"draws the tokens chart from review rows by model, the unrecorded series included, build rows not",
		function()
			local svg = m.charts.game.tokens["90d"]
			t.expect(has(svg, "opus-x, Oct 19: 1000 tokens")).toBe(true)
			t.expect(has(svg, "grok-y, Oct 19: 300 tokens")).toBe(true)
			t.expect(has(svg, "unrecorded model, Oct 19: 500 tokens")).toBe(true)
			t.expect(has(svg, "build-model")).toBe(false)
			t.expect(has(svg, "tool-model")).toBe(false)
			t.expect(has(m.charts.tool.tokens["90d"], "tool-model, Oct 5: 7000 tokens")).toBe(true)
		end
	)

	it("gives each card its spend, models and dispatcher state", function()
		local issues = byId(m.issues)
		t.expect(issues.c0011.spend).toEqual({
			minutes = 8,
			tokens = 101499,
			added = 10,
			removed = 2,
			models = { "build-model", "opus-x" },
		})
		t.expect(issues.f0021.dispatch)
			.toEqual({ step = "z-run", outcome = "running", model = "grok-y", questions = true })
		t.expect(issues.c0011.dispatch).toBe(nil)
	end)

	it("names a spend.md that does not parse, and still builds", function()
		t.expect(#m.problems).toBe(1)
		t.expect(has(m.problems[1], "game/.tracker/issues/f0050/spend.md")).toBe(true)
		t.expect(byId(m.issues).f0050.spend.tokens).toBe(0)
	end)

	it(
		"opens on the Board with a 24-hour done window and a 90-day chart range, and keeps the old views",
		function()
			t.expect(m.initialView).toBe("board")
			t.expect(m.window).toBe(86400)
			t.expect(m.range).toBe("90d")
			t.expect(m.asOf).toBe(AS_OF)
			t.expect(table.find(m.views.rafts.done, "R0010") ~= nil).toBe(true)
			t.expect(table.find(m.views.rafts.done, "R0110") ~= nil).toBe(true)
			t.expect(m.views.issues ~= nil).toBe(true)
		end
	)

	it("without an as-of time there are no done ages and no charts", function()
		local bare = board.collect(nil, repo, { asOf = nil, refs = {}, worktrees = {}, dispatch = {} })
		t.expect(byId(bare.issues).c0011.age).toBe(nil)
		t.expect((next(bare.charts.game.rounds))).toBe(nil)
	end)

	it(
		"readFacts reads HEAD's time, the branches, the worktrees and the dispatcher's state, writing nothing",
		function()
			fixture.git(repo, { "branch", "R0020-alpha" })
			write(
				DISPATCH .. "/f0021/state.json",
				'{"id":"f0021","step":"z-run","outcome":"failed","model":"grok-y"}'
			)
			write(DISPATCH .. "/f0021/questions.md", "# questions\n")
			write(DISPATCH .. "/notanid/state.json", '{"step":"x"}')
			local before = fixture.git(repo, { "status", "--porcelain", "--ignored" })
			local facts = board.readFacts(repo)
			t.expect(facts.asOf).toBe(stats.seconds("2026-10-21T09:00:00Z"))
			local at: { [string]: number } = {}
			for _, ref in facts.refs do
				at[ref.name] = ref.at
			end
			t.expect(at["R0020-alpha"]).toBe(stats.seconds("2026-10-21T09:00:00Z"))
			t.expect(at.main).toBe(stats.seconds("2026-10-21T09:00:00Z"))
			t.expect(#facts.worktrees).toBe(1)
			t.expect(facts.worktrees[1].branch).toBe("main")
			t.expect(facts.dispatch.f0021)
				.toEqual({ step = "z-run", outcome = "failed", model = "grok-y", questions = true })
			t.expect(facts.dispatch.notanid).toBe(nil)
			t.expect(fixture.git(repo, { "status", "--porcelain", "--ignored" })).toBe(before)
			local real = board.collect(nil, repo)
			t.expect(byId(real.rafts).R0020.launched).toBe(true)
			t.expect(byId(real.issues).f0021.dispatch.outcome).toBe("failed")
		end
	)

	it(
		"without git history every done item is dated by its newest spend row, and the model says so",
		function()
			local bare = `{repo}-nogit`
			if fs.isDir(bare) then
				fs.removeDir(bare)
			end
			fs.writeDir(`{bare}/z-nile`)
			fs.writeFile(`{bare}/z-nile/projects.toml`, REGISTRY)
			local function put(path: string, text: string)
				fs.writeDir(string.match(`{bare}/{path}`, "^(.*)/[^/]+$") :: string)
				fs.writeFile(`{bare}/{path}`, text)
			end
			put(`{G}/issues/done/c0011/c0011.md`, "---\nid: c0011\ntype: chore\ntitle: x\nraft: R0010\n---\n")
			put(`{G}/rafts/done/R0010/R0010.md`, "---\nid: R0010\ntype: chore\ntitle: r\n---\n")
			put(
				`{G}/issues/done/c0011/spend.md`,
				"# Spend: c0011 x\n\n"
					.. HEADER
					.. "| 1 | 2026-10-20 07:00 | s | 0 | 0 | 1.0 | raft | deliver |  |  |\n"
			)
			local nogit = board.collect(nil, bare, FACTS)
			fs.removeDir(bare)
			t.expect(nogit.history).toBe(false)
			t.expect(m.history).toBe(true)
			local issue, raft = byId(nogit.issues).c0011, byId(nogit.rafts).R0010
			t.expect(issue.doneFrom).toBe("spend")
			t.expect(issue.doneAt).toBe(stats.seconds("2026-10-20T07:00:00Z"))
			t.expect(raft.doneFrom).toBe("spend") -- a raft from its members' newest row
			t.expect(raft.doneAt).toBe(stats.seconds("2026-10-20T07:00:00Z"))
		end
	)

	it("reserves pr and checks for the served page: nil in every model c0118 builds", function()
		for _, list in { m.rafts, m.issues } do
			for _, x in list do
				t.expect(x.pr).toBe(nil)
				t.expect(x.checks).toBe(nil)
			end
		end
	end)

	it("cleans up", function()
		fs.removeDir(repo)
	end)
end)
