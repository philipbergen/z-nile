--!strict
-- c0117 AC8: a spend row stores the model id beside its token count. spend.md keeps its nine columns until a row
-- records a model, then has ten; an empty model cell is no model; rows stay append-only, the model included.
-- `spend --model` and `commit --model` write it. Pure cases on ledger.luau, then the commands in fixtures under
-- .cache/c0117-ledger-spend (a published spend) and .cache/c0117-ledger-commit (an offline started raft).
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function row(model: string?, tokens: number?): ledger.Row
	return {
		when = "2026-10-21 10:00",
		subject = "s",
		added = 1,
		removed = 0,
		minutes = 1.5,
		how = "spend",
		phase = "prep",
		tokens = tokens,
		model = model,
	}
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "c0117-ledger",
	GIT_AUTHOR_EMAIL = "c0117-ledger@example.invalid",
	GIT_COMMITTER_NAME = "c0117-ledger",
	GIT_COMMITTER_EMAIL = "c0117-ledger@example.invalid",
}

return t.spec("c0117 the spend row's model cell", function(it)
	it("a file with no model row keeps the nine-column header", function()
		local text = ledger.render("c0010", "T", { row(nil, 5) })
		t.expect(has(text, ledger.HEADER)).toBe(true)
		t.expect(has(text, "| model |")).toBe(false)
		t.expect(has(text, "| 1 | 2026-10-21 10:00 | s | 1 | 0 | 1.5 | spend | prep | 5 |\n")).toBe(true)
	end)

	it("a row with a model makes ten columns; earlier rows parse back with no model", function()
		local text = ledger.append(ledger.render("c0010", "T", { row(nil, 5) }), "c0010", "T", row("grok-4.7-xhigh", 9))
		t.expect(has(text, ledger.HEADER_MODEL)).toBe(true)
		t.expect(has(text, "| 1 | 2026-10-21 10:00 | s | 1 | 0 | 1.5 | spend | prep | 5 |  |\n")).toBe(true)
		t.expect(has(text, "| prep | 9 | grok-4.7-xhigh |\n")).toBe(true)
		local l = ledger.parse(text) :: ledger.Ledger
		t.expect(l.rows[1].model).toBe(nil)
		t.expect(l.rows[2].model).toBe("grok-4.7-xhigh")
		t.expect(l.rows[2].tokens).toBe(9)
		-- its own form round-trips
		t.expect(ledger.render("c0010", "T", l.rows)).toBe(text)
	end)

	it("nine-cell and seven-cell rows still parse; a bad model cell does not", function()
		local nine = ledger.render("c0010", "T", { row(nil, nil) })
		t.expect((ledger.parse(nine) :: ledger.Ledger).rows[1].model).toBe(nil)
		local bad = string.gsub(ledger.append(nil, "c0010", "T", row("m", 1)), "| m |", "| a b |")
		local l, err = ledger.parse(bad)
		t.expect(l).toBe(nil)
		t.expect(has(err or "", "model")).toBe(true)
		t.expect((pcall(ledger.append, nil, "c0010", "T", row("a|b", 1)))).toBe(false)
	end)

	it("a published row's model may not change", function()
		local old = ledger.append(nil, "c0010", "T", row("claude-opus-5-5", 9))
		local changed = string.gsub(old, "claude%-opus%-5%-5", "grok-4.7")
		local appended = ledger.append(changed, "c0010", "T", row(nil, 1))
		t.expect(ledger.appendOnly(old, appended, "c0010"))
			.toBe("row 1 differs from origin/main: rows are only appended")
		t.expect(ledger.appendOnly(old, ledger.append(old, "c0010", "T", row(nil, 1)), "c0010")).toBe(nil)
	end)

	it("spend --model records the model on the published row", function()
		local f = trackerfix.new("c0117-ledger-spend", {
			["tracker/issues/c0010/c0010.md"] = trackerfix.stub("c0010", "thing", "new-quiet-copper-falcon"),
		})
		local w = trackerfix.trOk(f, f.main, { "worktree", "zn-dispatch" })
		trackerfix.trOk(f, w, {
			"spend",
			"c0010",
			"--phase",
			"capture",
			"--time",
			"1",
			"--tokens",
			"123",
			"--model",
			"claude-opus-5-5-high",
		})
		local text = fixture.git(f.origin, { "show", "main:tracker/issues/c0010/spend.md" }) .. "\n"
		local l = ledger.parse(text) :: ledger.Ledger
		t.expect(l.rows[#l.rows].model).toBe("claude-opus-5-5-high")
		t.expect(l.rows[#l.rows].tokens).toBe(123)
		local r = trackerfix.tr(f, w, { "spend", "c0010", "--phase", "capture", "--time", "1", "--model", "has space" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "--model takes one model id")).toBe(true)
		-- without --model the cell stays empty
		trackerfix.trOk(f, w, { "spend", "c0010", "--phase", "capture", "--time", "1", "--tokens", "4" })
		local again =
			ledger.parse(fixture.git(f.origin, { "show", "main:tracker/issues/c0010/spend.md" }) .. "\n") :: ledger.Ledger
		t.expect(again.rows[#again.rows].model).toBe(nil)
	end)

	it("commit --model records the model on the raft's rows", function()
		local root = fixture.physical(".") :: string
		local dir = `{root}/.cache/c0117-ledger-commit`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/tracker`)
		process.exec("git", { "init", "-q", "-b", "main", dir })
		for _, p in { ".luaurc", ".gitignore", "rokit.toml" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{dir}/{p}` })
		end
		engine.copy(root, dir)
		local function run(args: { string }): fixture.Result
			return fixture.exec(dir, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = ID })
		end
		local function must(args: { string }): string
			local r = run(args)
			if not r.ok then
				error(`{table.concat(args, " ")}: {r.stderr}{r.stdout}`, 2)
			end
			return trim(r.stdout)
		end
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			fs.writeDir(`{dir}/tracker/{d}`)
			fs.writeFile(`{dir}/tracker/{d}/.gitkeep`, "")
		end
		fixture.exec(dir, "git", { "add", "-A" }, { env = ID })
		fixture.exec(dir, "git", { "commit", "-q", "-m", "seed" }, { env = ID })
		local a = string.match(must({ "new", "issue", "c", "alpha" }), "(c%d%d%d%d)") :: string
		local raft = string.match(must({ "new", "raft", "chore", "demo", a }), "(R%d%d%d%d)") :: string
		for _, doc in { `tracker/issues/{a}/{a}.md`, `tracker/rafts/{raft}/{raft}.md` } do
			local p = `{dir}/{doc}`
			fs.writeFile(p, (string.gsub(fs.readFile(p), "design: draft", "design: ready")))
		end
		fixture.exec(dir, "git", { "add", "-A" }, { env = ID })
		fixture.exec(dir, "git", { "commit", "-q", "-m", "ready" }, { env = ID })
		must({ "start", raft })
		fs.writeFile(`{dir}/review-001.md`, "review\n")
		must({
			"commit",
			"-m",
			"review",
			"--phase",
			"code-review",
			"--time",
			"2",
			"--tokens",
			"77",
			"--model",
			"claude-opus-5-5",
		})
		local l = ledger.parse(fs.readFile(`{dir}/tracker/issues/active/{a}/spend.md`)) :: ledger.Ledger
		t.expect(l.rows[#l.rows].model).toBe("claude-opus-5-5")
		t.expect(l.rows[#l.rows].tokens).toBe(77)
		local bad = run({ "commit", "-m", "x", "--model", "a|b" })
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stderr, "--model takes one model id")).toBe(true)
	end)
end)
