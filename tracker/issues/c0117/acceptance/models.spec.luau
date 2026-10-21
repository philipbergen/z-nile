--!strict
-- c0117: .models.toml stacks, the stronger spec wins whole, dry-run prints the plan, spend keeps nine columns until a model is set.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@scripts/tracker/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
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

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)

local function models(): any
	return require("@scripts/tracker/models")
end

local function dispatch(): any
	return require("@scripts/tracker/dispatch")
end

local function row(phase: string, model: string?): any
	return {
		when = "2026-01-01 00:00",
		subject = "abc",
		added = 0,
		removed = 0,
		minutes = 1,
		how = "split",
		phase = phase,
		tokens = 12,
		model = model,
	}
end

return t.spec("z-nile models", function(it)
	it("closer key wins", function()
		local base = `{root}/.cache/c0117-stack`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/game`)
		fs.writeFile(
			`{base}/.models.toml`,
			'[z-run]\nmodel = "grok-4.7"\nrank = 2\nruntime = "grok-cli"\nmax_tokens = 300000\n'
		)
		fs.writeFile(`{base}/game/.models.toml`, "[z-run]\nmax_tokens = 1000\n")
		local spec = models().resolve(base, `{base}/game`, "z-run")
		t.expect(spec.model).toBe("grok-4.7")
		t.expect(spec.rank).toBe(2)
		t.expect(spec.runtime).toBe("grok-cli")
		t.expect(spec.maxTokens).toBe(1000)
	end)

	it("higher rank wins whole", function()
		local won = models().strongest({
			{ model = "composer-2.5", rank = 1, runtime = "cursor-cli", maxTokens = 900000 },
			{ model = "claude-opus-5-5-medium", rank = 3, runtime = "claude-cli", maxTokens = 1000 },
		})
		t.expect(won.model).toBe("claude-opus-5-5-medium")
		t.expect(won.maxTokens).toBe(1000)
		t.expect(won.runtime).toBe("claude-cli")
	end)

	it("equal rank uses the larger cap", function()
		local won = models().strongest({
			{ model = "a", rank = 2, runtime = "grok-cli", maxTokens = 10 },
			{ model = "b", rank = 2, runtime = "cursor-cli", maxTokens = 50 },
		})
		t.expect(won.model).toBe("b")
		t.expect(won.runtime).toBe("cursor-cli")
		t.expect(won.maxTokens).toBe(50)
	end)

	it("plan kinds", function()
		local spec = { model = "grok-4.7", rank = 2, runtime = "grok-cli", maxTokens = 10 }
		local d = dispatch()
		for _, skill in { "z-ready", "z-stop", "spend", "recombine" } do
			local step = d.plan(skill, spec)
			t.expect(step.kind).toBe("script")
			t.expect(step.spec).toBe(nil)
		end
		local modelStep = d.plan("z-design", spec)
		t.expect(modelStep.kind).toBe("model")
		t.expect(modelStep.spec.model).toBe("grok-4.7")
		t.expect(modelStep.spec.maxTokens).toBe(10)
	end)

	it("model cell", function()
		local nine = ledger.render("c0001", "T", { row("build", nil) })
		t.expect(string.find(nine, "| model |", 1, true) ~= nil).toBe(false)
		local parsed = ledger.parse(nine)
		t.expect(parsed ~= nil).toBe(true)
		t.expect(((parsed :: any).rows[1]).model).toBe(nil)
		local ten = ledger.append(nine, "c0001", "T", row("design-review", "grok-4.7"))
		t.expect(string.find(ten, "| model |", 1, true) ~= nil).toBe(true)
		local again = ledger.parse(ten)
		t.expect(again ~= nil).toBe(true)
		t.expect(((again :: any).rows[1]).model).toBe(nil)
		t.expect(((again :: any).rows[2]).model).toBe("grok-4.7")
		local blank = swap(ten, "grok-4.7", "")
		local blankRow = ledger.parse(blank)
		t.expect(blankRow ~= nil).toBe(true)
		t.expect(((blankRow :: any).rows[2]).model).toBe(nil)
		local changed = swap(ten, "grok-4.7", "other-model")
		t.expect(ledger.appendOnly(ten, changed, "c0001") ~= nil).toBe(true)
		t.expect(ledger.appendOnly(nine, nine, "c0001")).toBe(nil)
	end)

	it("bad specs", function()
		local base = `{root}/.cache/c0117-bad`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		fs.writeFile(
			base .. "/.models.toml",
			'[z-run]\nmodel = "grok-4.7"\nruntime = "grok-cli"\nmax_tokens = 10\n'
		)
		t.expect(pcall(models().resolve, base, base, "z-run")).toBe(false)
		fs.writeFile(
			base .. "/.models.toml",
			'[z-run]\nmodel = "grok-4.7"\nrank = 1\nruntime = "nope"\nmax_tokens = 10\n'
		)
		t.expect(pcall(models().resolve, base, base, "z-run")).toBe(false)
		fs.writeFile(
			base .. "/.models.toml",
			'[z-run]\nmodel = "grok-4.7"\nrank = 1\nruntime = "grok-cli"\nmax_tokens = 10\n'
		)
		local ok, err = pcall(models().resolve, base, base, "no-such")
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "no-such", 1, true) ~= nil).toBe(true)
		t.expect(pcall(models().strongest, {})).toBe(false)
	end)

	it("root file names every model skill", function()
		local m = models()
		local review = m.resolve(root, root, "zz-review")
		local run = m.resolve(root, root, "z-run")
		t.expect(review.rank > run.rank).toBe(true)
		for _, skill in { "z-ticket", "z-design", "z-raft", "z-run", "zz-review" } do
			local spec = m.resolve(root, root, skill)
			t.expect(spec.model ~= "").toBe(true)
			t.expect(spec.rank > 0).toBe(true)
		end
	end)

	it("dry run and model flag", function()
		local issue = table.concat({
			"---",
			"id: c0001",
			"type: chore",
			"title: cap",
			"slug: cap",
			"raft: ",
			"depends_on: []",
			"emergent: false",
			"design: draft",
			"created: 2026-01-01",
			"status: new-quiet-copper-falcon",
			"project: pickman",
			"---",
			"",
			"# c0001",
			"",
			"### Touched modules",
			"- `game/x.luau`",
			"- `tracker/issues/c0001/acceptance/a.spec.luau`",
			"",
		}, "\n")
		local active = swap(issue, "status: new-quiet-copper-falcon", "status: active-quiet-copper-falcon")
		active = swap(active, "raft: ", "raft: R0001")
		local raft = table.concat({
			"---",
			"id: R0001",
			"type: chore",
			"title: demo",
			"slug: demo",
			"single: false",
			"issues: [c0001, c0002]",
			"design: ready",
			"created: 2026-01-01",
			"status: active-quiet-copper-falcon",
			"---",
			"",
			"# R0001",
			"",
		}, "\n")
		local onlyGame = swap(raft, "id: R0001", "id: R0002")
		onlyGame = swap(onlyGame, "issues: [c0001, c0002]", "issues: [c0001]")
		onlyGame = swap(onlyGame, "# R0001", "# R0002")
		local seed: { [string]: string } = {
			[".models.toml"] = '[z-run]\nmodel = "grok-4.7"\nrank = 2\nruntime = "grok-cli"\nmax_tokens = 300000\n',
			["game/.models.toml"] = "[z-run]\nmax_tokens = 1000\n",
			["game/x.luau"] = "-- touched\n",
			["tracker/next"] = "issue 2 seed-phrase\nraft 2 seed-phrase\n",
			["other/y.luau"] = "-- outside\n",
			["tracker/issues/active/c0002/c0002.md"] = swap(
				swap(active, "id: c0001", "id: c0002"),
				"- `game/x.luau`",
				"- `game/x.luau`\n- `other/y.luau`"
			),
			["tracker/issues/active/c0002/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/issues/active/c0001/c0001.md"] = active,
			["tracker/issues/active/c0001/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/issues/c0003/c0003.md"] = swap(issue, "id: c0001", "id: c0003"),
			["tracker/issues/c0003/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/rafts/active/R0001/R0001.md"] = raft,
			["tracker/rafts/active/R0001/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/rafts/active/R0002/R0002.md"] = onlyGame,
			["tracker/rafts/active/R0002/check.sh"] = 'check "AC1: ok" true\n',
		}
		local f = trackerfix.new("c0117-dispatch", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-dispatch" })
		local dry = trackerfix.tr(f, wt, { "dispatch", "z-run", "c0001", "--dry-run" })
		local said = dry.stdout .. dry.stderr
		t.expect(dry.ok).toBe(true)
		t.expect(string.find(said, "usage: scripts/tracker.sh", 1, true) ~= nil).toBe(false)
		t.expect(string.find(said, "kind=model", 1, true) ~= nil).toBe(true)
		t.expect(string.find(said, "max_tokens=1000", 1, true) ~= nil).toBe(true)
		local mixed = trackerfix.tr(f, wt, { "dispatch", "z-run", "c0002", "--dry-run" })
		t.expect(mixed.ok).toBe(true)
		t.expect(string.find(mixed.stdout, "max_tokens=300000", 1, true) ~= nil).toBe(true)
		local raftRun = trackerfix.tr(f, wt, { "dispatch", "z-run", "R0001", "--dry-run" })
		t.expect(raftRun.ok).toBe(true)
		t.expect(string.find(raftRun.stdout, "max_tokens=300000", 1, true) ~= nil).toBe(true)
		local gameRaft = trackerfix.tr(f, wt, { "dispatch", "z-run", "R0002", "--dry-run" })
		t.expect(gameRaft.ok).toBe(true)
		t.expect(string.find(gameRaft.stdout, "max_tokens=1000", 1, true) ~= nil).toBe(true)
		local scripted = trackerfix.tr(f, wt, { "dispatch", "spend", "c0001", "--dry-run" })
		t.expect(scripted.ok).toBe(true)
		t.expect(string.find(scripted.stdout, "kind=script", 1, true) ~= nil).toBe(true)
		t.expect(string.find(scripted.stdout, "model=", 1, true) ~= nil).toBe(false)
		local refused = trackerfix.tr(f, wt, {
			"spend",
			"c0001",
			"--phase",
			"capture",
			"--time",
			"1",
			"--model",
			"grok-4.7",
			"--tokens",
			"12",
		})
		t.expect(refused.ok).toBe(false)
		t.expect(string.find(refused.stdout .. refused.stderr, "commit --phase", 1, true) ~= nil).toBe(true)
		local spent = trackerfix.tr(f, wt, {
			"spend",
			"c0003",
			"--phase",
			"design-review",
			"--time",
			"1",
			"--model",
			"grok-4.7",
			"--tokens",
			"12",
		})
		t.expect(spent.ok).toBe(true)
		local spendText = fixture.git(wt, { "show", "origin/main:tracker/issues/c0003/spend.md" })
		t.expect(string.find(spendText, "grok-4.7", 1, true) ~= nil).toBe(true)
		fixture.git(f.main, { "worktree", "add", "-b", "R0001-demo", `{f.base}/commit-wt`, "main" })
		local cwd = `{f.base}/commit-wt`
		fs.writeFile(`{cwd}/game/y.luau`, "-- changed\n")
		local committed = trackerfix.tr(f, cwd, {
			"commit",
			"-m",
			"record the model",
			"--issue",
			"c0001",
			"--time",
			"1",
			"--phase",
			"code-review",
			"--model",
			"grok-4.7",
			"--tokens",
			"12",
		})
		t.expect(committed.ok).toBe(true)
		local commitSpend = fs.readFile(`{cwd}/tracker/issues/active/c0001/spend.md`)
		t.expect(string.find(commitSpend, "grok-4.7", 1, true) ~= nil).toBe(true)
	end)
end)
