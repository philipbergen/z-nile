--!strict
-- R0270 review 001 F6: a remap whose merge of origin/main conflicts keeps its remap commit, and a second remap must
-- then refuse: the branch has no local compaction map yet, but its ids are already the new ones, and remapping again
-- would renumber them a second time. Fixture under .cache/remap-once.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/remap-once`
local seed, origin, main = `{base}/seed`, `{base}/origin.git`, `{base}/main`

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function tr(cwd: string, args: { string }): Result
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) })
end
local function trOk(cwd: string, args: { string }): string
	local r = tr(cwd, args)
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
	git(dir, { "config", "user.name", "remap-once" })
	git(dir, { "config", "user.email", "remap-once@example.invalid" })
end
local function doc(id: string, extra: string): string
	local lines = {}
	for i = 1, 30 do
		table.insert(lines, `Body line {i} of the document.`)
	end
	return `---\nid: {id}\ntype: chore\ntitle: T\nslug: s-{string.lower(id)}\n{extra}design: ready\ncreated: 2026-01-01\n---\n\n# {id}: T\n\nline a\nline b\nline c\n{table.concat(
		lines,
		"\n"
	)}\n`
end
local function worktree(name: string): string
	local wt = trOk(main, { "worktree", name })
	identity(wt)
	return wt
end
local function edit(path: string, from: string, to: string)
	fs.writeFile(path, (string.gsub(fs.readFile(path), from, to)))
end

local branch = ""

return t.spec("remap runs once, even after a conflicting merge", function(it)
	it("sets up an origin and a branch that edits a line main will edit too", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		identity(seed)
		for _, p in { "scripts", ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		fs.writeDir(`{seed}/tracker`)
		process.exec("cp", { "-R", `{root}/tracker/templates`, `{seed}/tracker/templates` })
		write(`{seed}/tracker/next`, "issue 41 a-b-c\nraft 31 a-b-c\n")
		write(`{seed}/tracker/issues/c0010/c0010.md`, doc("c0010", "raft: R0030\n"))
		write(`{seed}/tracker/rafts/R0030/R0030.md`, doc("R0030", "issues: [c0010]\n"))
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main }) -- raw: clone to a named path
		identity(main)
		branch = worktree("prep-x")
		edit(`{branch}/tracker/issues/c0010/c0010.md`, "line b", "line b, the branch's version")
		git(branch, { "add", "-A" })
		git(branch, { "commit", "-q", "-m", "branch work" })
		git(branch, { "push", "-q", "-u", "origin", "prep-x" })
	end)

	it("a forced compaction lands, then main edits the same line", function()
		local wt = worktree("compact-x")
		local r = tr(wt, { "compact", "--force" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		git(wt, { "push", "-q", "origin", "HEAD:main" })
		edit(`{wt}/tracker/issues/c0001/c0001.md`, "line b", "line b, main's version")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "main edits line b" })
		git(wt, { "push", "-q", "origin", "HEAD:main" })
	end)

	it("the remap commits, then its merge of origin/main conflicts", function()
		local r = tr(branch, { "remap" })
		t.expect(r.ok).toBe(false)
		t.expect(git(branch, { "log", "-1", "--format=%s" })).toBe("tracker: remap ids")
		t.expect(fs.isFile(`{branch}/tracker/issues/c0001/c0001.md`)).toBe(true)
	end)

	it("a second remap refuses and changes nothing", function()
		local head = git(branch, { "rev-parse", "HEAD" })
		local r = tr(branch, { "remap" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "already")).toBe(true)
		t.expect(has(r.stderr, "git merge origin/main")).toBe(true)
		t.expect(git(branch, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(branch, { "status", "--porcelain" })).toBe("")
		t.expect(fs.isFile(`{branch}/tracker/issues/c0001/c0001.md`)).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
