--!strict
-- c0460: `./zn finish` refuses a layer whose ticket carries `Mutants: mutants.md` until mutants.md holds only
-- killed rows, with its exemptions (risk easy, a layer of only .md and *.spec.luau files, a ticket without the
-- line), and writing mutants.md leaves the approval hash alone. Driven through ./zn in a fixture; this spec
-- requires only @tests/lib/* and @lune/* (the rule it pins).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NEXT = "issue 1 fixture\nraft 1 fixture\n"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local SPEC = "--!strict\nreturn {}\n"
local SRC = "pickman/src/shared/Logic/Maze/init.luau"
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local TABLE_HEAD = "| rule | spec :: case | mutant | result |\n|---|---|---|---|\n"

type Case = {
	template: boolean, -- the fixture renders the checkout's real issue template (which carries the line)
	typed: string?, -- a line typed into the Test plan after the document is made (the near-miss cases)
	risk: string?, -- nil keeps the template's normal
	failing: boolean?, -- the issue's own check.sh fails (the refusal must come before it runs)
	mutants: string?, -- the text of mutants.md, nil for none
	changes: { string }, -- paths the layer writes (each gets text by its extension)
}

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function zn(f: trackerfix.Fixture, args: { string })
	return trackerfix.tr(f, f.main, args)
end

-- Builds one raft of one issue, applies `c`, commits the layer, and returns the result of `./zn finish` and
-- the number of approvals sealed (the fixture is approved, so finish checks the hash).
local function finish(name: string, c: Case): (fixture.Result, number)
	local stamped = 0
	local f = trackerfix.new(name, { ["z-nile/next"] = NEXT })
	fixture.git(f.main, { "remote", "remove", "origin" })
	-- fixtures render a template without the line (so the finish-driving specs of other tickets stay as they were):
	-- an armed case puts the checkout's real template back
	local tpl = `{f.main}/z-nile/templates/issue/doc.md`
	if c.template then
		fs.writeFile(tpl, fs.readFile(`{TOP}/z-nile/templates/issue/doc.md`))
	else
		fs.writeFile(tpl, (string.gsub(fs.readFile(tpl), "\nMutants: mutants%.md\n", "\n")))
	end
	local made = zn(f, { "new", "issue", "c", "mut", "--project", "pickman" })
	local id = string.match(made.stdout, "(c%d%d%d%d)") :: string
	local rmade = zn(f, { "new", "raft", "chore", "mut", id, "--single", "--project", "pickman" })
	local raft = string.match(rmade.stdout, "(R%d%d%d%d)") :: string
	local root = "pickman/.tracker"
	local doc = `{root}/issues/{id}/{id}.md`
	for _, p in { doc, `{root}/rafts/{raft}/{raft}.md` } do
		fs.writeFile(
			`{f.main}/{p}`,
			(string.gsub(fs.readFile(`{f.main}/{p}`), "design: draft", "design: ready"))
		)
	end
	local text = fs.readFile(`{f.main}/{doc}`)
	if c.typed then
		text = string.gsub(text, "(## Test plan\n)", "%1" .. c.typed .. "\n", 1)
	end
	if c.risk then
		text = string.gsub(text, "risk: %a+", `risk: {c.risk}`, 1)
	end
	fs.writeFile(`{f.main}/{doc}`, text)
	write(f.main, `{root}/issues/{id}/acceptance/mut.spec.luau`, SPEC)
	write(
		f.main,
		`{root}/issues/{id}/check.sh`,
		if c.failing then (string.gsub(CHECK, "true", "false")) else CHECK
	)
	write(f.main, `{root}/rafts/{raft}/check.sh`, CHECK)
	seal.prep(f.main)
	stamped = seal.stamp(f.main)
	fixture.git(f.main, { "add", "-A" })
	fixture.git(f.main, { "commit", "-qm", "prep" })
	zn(f, { "start", raft })
	for _, raw in c.changes do
		local path = string.gsub(raw, "%%ID%%", id)
		write(
			f.main,
			path,
			if string.find(path, ".spec.luau", 1, true) then SPEC else "return { maze = true }\n"
		)
	end
	if c.mutants then
		write(f.main, `{root}/issues/active/{id}/mutants.md`, c.mutants)
	end
	zn(f, { "commit", "-m", "the layer", "--issue", id })
	return zn(f, { "finish", id }), stamped
end

local function row(result: string): string
	return `| the rule | a.spec.luau :: case | drop the rule | {result} |\n`
end

local function said(r: fixture.Result, word: string): boolean
	return not r.ok and string.find(r.stdout .. r.stderr, word, 1, true) ~= nil
end

local function refused(r: fixture.Result): boolean
	return said(r, "mutants.md")
end

local NOTES = "pickman/.tracker/issues/active/%ID%/notes.txt"

return t.spec("finish and mutants.md (c0460)", function(it)
	it(
		"the real issue template alone arms the rule: a source change with no mutants.md is refused",
		function()
			local r = finish("mut-missing", { template = true, changes = { SRC } })
			t.expect(refused(r)).toBe(true)
		end
	)

	it("the refusal comes before the ticket's own check.sh runs", function()
		local r = finish("mut-first", { template = true, failing = true, changes = { SRC } })
		t.expect(refused(r)).toBe(true)
		t.expect(said(r, "check.sh failed")).toBe(false)
	end)

	it("a header-only mutants.md is refused", function()
		local r = finish("mut-empty", { template = true, mutants = TABLE_HEAD, changes = { SRC } })
		t.expect(refused(r)).toBe(true)
	end)

	it("one survived row among killed rows is refused", function()
		local m = TABLE_HEAD .. row("killed") .. row("survived")
		local r = finish("mut-survived", { template = true, mutants = m, changes = { SRC } })
		t.expect(refused(r)).toBe(true)
	end)

	it("a row whose cell holds a pipe is refused with the escape hint, not as a survivor", function()
		local m = TABLE_HEAD .. "| the rule | a.spec.luau :: case | a | b | killed |\n"
		local r = finish("mut-pipe", { template = true, mutants = m, changes = { SRC } })
		t.expect(said(r, "escape")).toBe(true)
	end)

	it("every row killed finishes on an approved ticket: mutants.md moves no hash", function()
		local m = TABLE_HEAD .. row("killed") .. row("killed")
		local r, sealed = finish("mut-killed", { template = true, mutants = m, changes = { SRC } })
		t.expect(sealed >= 1).toBe(true) -- the fixture ticket is approved, so finish compares the hash
		t.expect(r.ok).toBe(true)
		t.expect((string.find(r.stdout .. r.stderr, "not approved", 1, true))).toBe(nil)
	end)

	it("a ticket without the line is never refused for mutants.md", function()
		local r = finish("mut-noline", { template = false, changes = { SRC } })
		t.expect(r.ok).toBe(true)
	end)

	for i, typed in { "`Mutants: mutants.md`", "**Mutants:** mutants.md", "Mutants: mutants.txt" } do
		it(`a near-miss line ({typed}) is refused as not exactly the line`, function()
			local r = finish(`mut-near-{i}`, { template = false, typed = typed, changes = { SRC } })
			t.expect(said(r, "exactly")).toBe(true)
		end)
	end

	it("an easy ticket with the line and no mutants.md finishes", function()
		local r = finish("mut-easy", { template = true, risk = "easy", changes = { SRC } })
		t.expect(r.ok).toBe(true)
	end)

	it("a layer of .md, spec and issue-folder bookkeeping files is not refused", function()
		local r = finish("mut-docs-only", {
			template = true,
			changes = { "pickman/docs/note.md", "pickman/tests/unit/x.spec.luau", NOTES },
		})
		t.expect(r.ok).toBe(true)
	end)

	it("a layer of one issue-folder .txt file and nothing else is not refused", function()
		local r = finish("mut-bookkeeping", { template = true, changes = { NOTES } })
		t.expect(r.ok).toBe(true)
	end)

	it("a layer that changes a source and an .md file is still refused", function()
		local r = finish("mut-mixed", { template = true, changes = { SRC, "pickman/docs/note.md" } })
		t.expect(refused(r)).toBe(true)
	end)

	it("a layer that changes a source and a spec file is still refused", function()
		local r = finish("mut-spec", { template = true, changes = { SRC, "pickman/tests/unit/x.spec.luau" } })
		t.expect(refused(r)).toBe(true)
	end)
end)
