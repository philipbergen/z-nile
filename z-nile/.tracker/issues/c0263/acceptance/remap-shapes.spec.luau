--!strict
-- c0263: `./zn remap` settles every item record by id (design-review-011 F2, F3), on the c0081 remap fixture: three
-- branches in flight during a compaction. A: both sides appended to an item's record and main readied the item and wrote
-- a near-identical record for another item (git pairs our row with that record), so the row must stay with its own
-- item and the union sits at the item's new place. C: our branch edited a row of the shared record, so remap stops.
-- D: a document and a record both conflict, so remap stops with no conflict markers in the tree.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0263-remap-shapes`
local seed, origin, main = `{base}/seed`, `{base}/origin.git`, `{base}/main`
local ISSUES = "pickman/.tracker/issues"

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function tr(cwd: string, args: { string }, env: { [string]: string }?): Result
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function trOk(cwd: string, args: { string }, env: { [string]: string }?): string
	local r = tr(cwd, args, env)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function identity(dir: string)
	git(dir, { "config", "user.name", "remap" })
	git(dir, { "config", "user.email", "remap@example.invalid" })
end
-- a document long enough for git to see a rewritten copy as a rename
local function doc(id: string): string
	local lines = {}
	for i = 1, 30 do
		table.insert(lines, `Body line {i} of the document.`)
	end
	return `---\nid: {id}\ntype: chore\ntitle: T\nslug: s-{string.lower(id)}\ndesign: ready\ncreated: 2026-01-01\n---\n\n# {id}: T\n\nline a\nline b\nline c\n{table.concat(
		lines,
		"\n"
	)}\n`
end
local function rec(id: string, ...: string): string
	local out = `# Provenance: {id}\n\n| when | event | actor | detail |\n|---|---|---|---|\n`
	for _, who in { ... } do
		out ..= `| 2026-11-08 10:00 | ranked | human:{who} | rank=1 |\n`
	end
	return out
end
local function worktree(name: string): string
	local wt = trOk(main, { "worktree", name })
	identity(wt)
	return wt
end
local function appendRow(wt: string, id: string, who: string)
	local path = `{wt}/{ISSUES}/{id}/provenance.md`
	fs.writeFile(path, fs.readFile(path) .. `| 2026-11-08 11:00 | ranked | human:{who} | rank=2 |\n`)
end
local function whoOrder(text: string): { string }
	local order: { string } = {}
	for who in string.gmatch(text, "| (human:%w+) |") do
		table.insert(order, who)
	end
	return order
end

local a, c, d = "", "", ""

return t.spec("c0263 remap settles records by id", function(it)
	it("sets up an origin, three branches in flight, main's own changes and a compaction", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		identity(seed)
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		engine.copy(root, seed)
		engine.roots(seed)
		write(`{seed}/z-nile/next`, "issue 41 a-b-c\nraft 31 a-b-c\n")
		for _, id in { "c0010", "c0011", "c0012", "f0020" } do
			write(`{seed}/{ISSUES}/{id}/{id}.md`, doc(id))
		end
		for _, id in { "c0010", "c0011", "c0012" } do
			write(`{seed}/{ISSUES}/{id}/provenance.md`, rec(id, "Base"))
		end
		write(`{seed}/pickman/tests/acceptance/c0010/a.spec.luau`, "return 1\n")
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main }) -- raw: clone to a named path
		identity(main)
		a, c, d = worktree("shape-a"), worktree("shape-c"), worktree("shape-d")
		-- the branches' own work
		appendRow(a, "c0010", "Ours")
		local edited = (
			string.gsub(fs.readFile(`{c}/{ISSUES}/c0011/provenance.md`), "human:Base", "human:Eve")
		)
		fs.writeFile(`{c}/{ISSUES}/c0011/provenance.md`, edited)
		appendRow(c, "c0011", "Ours")
		appendRow(d, "c0012", "Ours")
		local dd = `{d}/{ISSUES}/c0012/c0012.md`
		fs.writeFile(dd, (string.gsub(fs.readFile(dd), "line b", "line B, edited on the branch")))
		for _, wt in { a, c, d } do
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-q", "-m", "branch work" })
			git(wt, { "push", "-q", "-u", "origin", (git(wt, { "branch", "--show-current" })) })
		end
		-- main's work before the compaction: rows, the same document edit as D's, a near-identical record for f0020,
		-- c0010 readied (moved to active/)
		local wm = worktree("main-work")
		local dm = `{wm}/{ISSUES}/c0012/c0012.md`
		fs.writeFile(dm, (string.gsub(fs.readFile(dm), "line b", "line B, edited on main")))
		git(wm, { "add", "-A" })
		git(wm, { "commit", "-q", "-m", "main edit" })
		git(wm, { "push", "-q", "origin", "HEAD:main" })
		for _, who in { "M1", "M2", "M3" } do
			trOk(wm, { "record", "c0010", "ranked", "--actor", `human:{who}` })
		end
		trOk(wm, { "record", "c0011", "ranked", "--actor", "human:Main" })
		trOk(wm, { "record", "c0012", "ranked", "--actor", "human:Main" })
		write(`{wm}/{ISSUES}/f0020/provenance.md`, rec("f0020", "Base"))
		git(wm, { "add", "-A" })
		git(wm, { "commit", "-q", "-m", "a record for f0020" })
		git(wm, { "mv", `{ISSUES}/c0010`, `{ISSUES}/active/c0010` })
		git(wm, { "commit", "-q", "-m", "tracker: ready c0010" })
		git(wm, { "push", "-q", "origin", "HEAD:main" })
		local wc = worktree("compact-z")
		local r = tr(wc, { "compact", "--force" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		git(wc, { "push", "-q", "origin", "HEAD:main" })
	end)

	it(
		"A: the row stays with its own item, the union sits at the item's new place, the other record is main's",
		function()
			local out = trOk(a, { "remap" })
			t.expect(has(out, "c0010 -> c0001")).toBe(true)
			local united = fs.readFile(`{a}/{ISSUES}/active/c0001/provenance.md`)
			t.expect(has(united, "# Provenance: c0001")).toBe(true)
			t.expect(whoOrder(united))
				.toEqual({ "human:Base", "human:M1", "human:M2", "human:M3", "human:Ours" })
			t.expect(fs.readFile(`{a}/{ISSUES}/f0004/provenance.md`)).toBe(rec("f0004", "Base"))
			t.expect(fs.isDir(`{a}/{ISSUES}/c0010`)).toBe(false)
			t.expect(fs.isDir(`{a}/{ISSUES}/c0001`)).toBe(false)
			t.expect(git(a, { "status", "--porcelain" })).toBe("")
			trOk(a, { "audit" }) -- the remapped tree audits clean (trOk raises otherwise)
		end
	)

	it("C: our branch edited a row of the shared record, so remap stops after its own commit", function()
		local r = tr(c, { "remap" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "remap committed, but merging origin/main conflicts")).toBe(true)
		t.expect(git(c, { "log", "-1", "--format=%s" })).toBe("tracker: remap ids")
		t.expect(git(c, { "status", "--porcelain" })).toBe("")
	end)

	it("D: a document and a record both conflict, so remap stops and leaves no conflict markers", function()
		local r = tr(d, { "remap" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "remap committed, but merging origin/main conflicts")).toBe(true)
		t.expect(git(d, { "log", "-1", "--format=%s" })).toBe("tracker: remap ids")
		t.expect(git(d, { "status", "--porcelain" })).toBe("")
		t.expect(fixture.exec(d, "git", { "grep", "-q", "<<<<<<<", "--", ISSUES }).ok).toBe(false)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
