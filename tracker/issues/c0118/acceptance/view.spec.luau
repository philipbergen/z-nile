--!strict
-- c0118: columns, ISO weeks, review counts, tokens by model, and the page, all on a plain table.
local status = require("@scripts/tracker/status")
local t = require("@tests/lib/t")

local function view(): any
	return require("@scripts/tracker/view")
end

local function swap(text: string, old: string, new: string): string
	local out = ""
	local rest = text
	while true do
		local at = string.find(rest, old, 1, true)
		if not at then
			return out .. rest
		end
		out ..= string.sub(rest, 1, at - 1) .. new
		rest = string.sub(rest, at + #old)
	end
end

local function cardColumn(views: { any }, id: string): string?
	for _, p in views do
		for _, card in p.cards do
			if card.id == id then
				return card.column
			end
		end
	end
	return nil
end

return t.spec("z-nile view", function(it)
	it("columns", function()
		local v = view()
		t.expect(v.column("new", false)).toBe("ticket")
		t.expect(v.column("preparing", false)).toBe("design")
		t.expect(v.column("prepared", false)).toBe("raft")
		t.expect(v.column("prepared", true)).toBe("rafted")
		t.expect(v.column("active", true)).toBe("run")
		t.expect(v.column("done", true)).toBe("done")
		local word = status.effective({ status = "preparing-raging-heron-sunny", raft = "" }, "backlog")
		t.expect(v.column(word, false)).toBe("design")
	end)

	it("weeks", function()
		local v = view()
		t.expect(v.week("2026-12-27T23:59:00Z")).toBe("2026-W52")
		t.expect(v.week("2026-12-28T00:00:00Z")).toBe("2026-W53")
		t.expect(v.week("2027-01-04T00:00:00Z")).toBe("2027-W01")
	end)

	it("landed reviews", function()
		local built = view().build({
			projects = { "alpha", "z-nile" },
			items = {
				{
					id = "R0001",
					project = "z-nile",
					status = "done",
					inRaft = false,
					doneAt = "2026-12-28T00:00:00Z",
				},
			},
			reviews = {
				{ raft = "R0001", kind = "design" },
				{ raft = "R0001", kind = "development" },
				{ raft = "R0002", kind = "design" },
			},
			rows = {},
			doneAtByRaft = { R0001 = "2026-12-28T00:00:00Z" },
		})
		t.expect(built[1].id).toBe("alpha")
		t.expect(built[1].weeks[1]).toBe(nil)
		t.expect(built[2].id).toBe("z-nile")
		local week = built[2].weeks[1]
		t.expect(week.week).toBe("2026-W53")
		t.expect(week.design).toBe(1)
		t.expect(week.development).toBe(1)
		t.expect(built[2].weeks[2]).toBe(nil)
	end)

	it("tokens", function()
		local built = view().build({
			projects = { "alpha", "beta" },
			items = {
				{ id = "c0001", project = "alpha", status = "new", inRaft = false },
				{
					id = "c0002",
					project = "beta",
					status = "done",
					inRaft = true,
					doneAt = "2026-12-28T00:00:00Z",
				},
			},
			reviews = {},
			rows = {
				{ project = "alpha", phase = "design-review", tokens = 10, model = nil },
				{ project = "alpha", phase = "code-review", tokens = 4, model = "grok-4.7" },
				{ project = "alpha", phase = "build", tokens = 99, model = "grok-4.7" },
				{ project = "beta", phase = "design-review", tokens = 7, model = "grok-4.7" },
			},
			doneAtByRaft = {},
		})
		t.expect(built[1].tokens.unrecorded).toBe(10)
		t.expect(built[1].tokens["grok-4.7"]).toBe(4)
		t.expect(built[2].tokens["grok-4.7"]).toBe(7)
		t.expect(cardColumn(built, "c0001")).toBe("ticket")
		t.expect(cardColumn(built, "c0002")).toBe("done")
		local betaHasAlpha = false
		for _, card in built[2].cards do
			if card.id == "c0001" then
				betaHasAlpha = true
			end
		end
		t.expect(betaHasAlpha).toBe(false)
		t.expect(built[2].cards[1].doneAt).toBe("2026-12-28T00:00:00Z")
	end)

	it("page", function()
		local built = view().build({
			projects = { "alpha", "beta" },
			items = {},
			reviews = {},
			rows = {},
			doneAtByRaft = {},
		})
		local html = view().render(built)
		local function tabs(id: string): number
			local needle = `data-project="{id}"`
			local n = 0
			local from = 1
			while true do
				local at = string.find(html, needle, from, true)
				if not at then
					return n
				end
				n += 1
				from = at + #needle
			end
		end
		t.expect(tabs("alpha")).toBe(1)
		t.expect(tabs("beta")).toBe(1)
		t.expect(tabs("gamma")).toBe(0)
		t.expect(string.find(html, 'data-done-hours="24"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, 'data-done-min="1"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, 'data-done-max="720"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, 'data-chart-days="90"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, "scripts/tracker.sh stop", 1, true) ~= nil).toBe(true)
		t.expect(string.find(html, "scripts/tracker.sh ready", 1, true) ~= nil).toBe(true)
	end)

	it("unknown project", function()
		local built = view().build({
			projects = { "alpha" },
			items = { { id = "c0009", project = "gamma", status = "new", inRaft = false } },
			reviews = {},
			rows = {},
			doneAtByRaft = {},
		})
		t.expect(built[1].id).toBe("alpha")
		t.expect(built[2].id).toBe("unknown")
		t.expect(built[3]).toBe(nil)
		t.expect(built[2].cards[1].id).toBe("c0009")
		t.expect(cardColumn(built, "c0009")).toBe("ticket")
	end)

	it("reader", function()
		local fs = require("@lune/fs")
		local fixture = require("@tests/lib/fixture")
		local serde = require("@lune/serde")
		local trackerfix = require("@tests/lib/trackerfix")
		local issue = table.concat({
			"---",
			"id: c0001",
			"type: chore",
			"title: tool",
			"slug: tool",
			"raft: R0001",
			"depends_on: []",
			"emergent: false",
			"design: ready",
			"created: 2026-01-01",
			"status: active-quiet-copper-falcon",
			"project: z-nile",
			"---",
			"",
			"# c0001",
			"",
		}, "\n")
		local plain = swap(swap(issue, "id: c0001", "id: c0002"), "project: z-nile", "project: pickman")
		plain = swap(plain, "raft: R0001", "raft: ")
		local raft = table.concat({
			"---",
			"id: R0001",
			"type: chore",
			"title: landed",
			"slug: landed",
			"single: false",
			"issues: [c0001]",
			"design: ready",
			"created: 2026-01-01",
			"status: active-quiet-copper-falcon",
			"---",
			"",
			"# R0001",
			"",
		}, "\n")
		local spend = table.concat({
			"# Spend: c0001 tool",
			"",
			"| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model |",
			"|---|---|---|---|---|---|---|---|---|---|",
			"| 1 | 2026-11-02 00:00 | abc | 0 | 0 | 1.0 | split | design-review | 12 | grok-4.7 |",
			"",
		}, "\n")
		local f = trackerfix.new("c0118-reader", {
			["z-nile/projects.toml"] = 'id = ["pickman", "z-nile"]\n',
			["tracker/issues/c0001/c0001.md"] = issue,
			["tracker/issues/c0001/spend.md"] = spend,
			["tracker/issues/c0002/c0002.md"] = plain,
			["tracker/rafts/R0001/R0001.md"] = raft,
			["tracker/rafts/R0001/design-review-001.md"] = "# Review 001\n",
			["tracker/rafts/R0001/review-001.md"] = "# Review 001\n",
		})
		local old = {
			GIT_AUTHOR_DATE = "2026-11-02T00:00:00Z",
			GIT_COMMITTER_DATE = "2026-11-02T00:00:00Z",
		}
		fixture.exec(f.main, "git", { "commit", "--amend", "--no-edit" }, { env = old })
		fixture.git(f.main, { "push", "--force", "origin", "HEAD:main" })
		fixture.git(f.main, { "mv", "tracker/rafts/R0001", "tracker/rafts/done/R0001" })
		fixture.exec(f.main, "git", { "commit", "-q", "-m", "done" }, {
			env = {
				GIT_AUTHOR_DATE = "2026-12-28T00:00:00Z",
				GIT_COMMITTER_DATE = "2026-12-28T00:00:00Z",
			},
		})
		fixture.git(f.main, { "push", "origin", "HEAD:main" })
		local out = `{f.base}/page.html`
		local r = trackerfix.tr(f, f.main, { "view", "--out", out, "-O" })
		t.expect(r.ok).toBe(true)
		local tag = '<script type="application/json" id="z-nile-view">'
		local html = fs.readFile(out)
		local start = string.find(html, tag, 1, true)
		t.expect(start ~= nil).toBe(true)
		local from = (start :: number) + #tag
		local stop = string.find(html, "</script>", from, true)
		t.expect(stop ~= nil).toBe(true)
		local built = serde.decode("json", string.sub(html, from, (stop :: number) - 1))
		local function byId(id: string): any
			for _, p in built do
				if p.id == id then
					return p
				end
			end
			return nil
		end
		local function hasCard(p: any, id: string): boolean
			for _, card in p.cards do
				if card.id == id then
					return true
				end
			end
			return false
		end
		local nile = byId("z-nile")
		local pick = byId("pickman")
		t.expect(nile ~= nil).toBe(true)
		t.expect(pick ~= nil).toBe(true)
		t.expect(hasCard(nile, "c0001")).toBe(true)
		t.expect(hasCard(pick, "c0001")).toBe(false)
		t.expect(hasCard(pick, "c0002")).toBe(true)
		t.expect(nile.weeks[1].week).toBe("2026-W53")
		t.expect(nile.weeks[1].design).toBe(1)
		t.expect(nile.weeks[1].development).toBe(1)
		t.expect(nile.weeks[2]).toBe(nil)
		t.expect(nile.tokens["grok-4.7"]).toBe(12)
		local pickWeeks = pick.weeks
		t.expect(pickWeeks == nil or pickWeeks[1] == nil).toBe(true)
		t.expect(pick.tokens["grok-4.7"]).toBe(nil)
	end)
end)
