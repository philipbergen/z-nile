--!strict
-- R0270 review 001 F6: a remap whose merge of origin/main conflicts keeps its remap commit, and a second remap must
-- then refuse: the branch has no local compaction map yet, but its ids are already the new ones, and remapping again
-- would renumber them a second time. Fixture under .cache/remap-once.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
-- fixtures under this home's .cache (the working directory, c0120)
local base = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/remap-once`
-- c0178: no seed folder, and origin is only reached through the branch (trackerfix.new, in the setup case)
local main = `{base}/main`

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
		-- c0178: trackerfix.new makes the repositories (tooling, empty tracker roots, the checkout's .claude, .luaurc and
		-- .gitignore, and the files below as one commit "seed") that this setup built by hand (init, copy, add, commit, bare
		-- clone, clone, identities)
		trackerfix.new("remap-once", {
			["z-nile/next"] = "issue 41 a-b-c\nraft 31 a-b-c\n",
			["pickman/.tracker/issues/c0010/c0010.md"] = doc("c0010", "raft: R0030\n"),
			["pickman/.tracker/rafts/R0030/R0030.md"] = doc("R0030", "issues: [c0010]\n"),
		}, { copy = { ".claude", ".luaurc", ".gitignore" } })
		branch = worktree("prep-x")
		edit(`{branch}/pickman/.tracker/issues/c0010/c0010.md`, "line b", "line b, the branch's version")
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
		edit(`{wt}/pickman/.tracker/issues/c0001/c0001.md`, "line b", "line b, main's version")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "main edits line b" })
		git(wt, { "push", "-q", "origin", "HEAD:main" })
	end)

	it("the remap commits, then its merge of origin/main conflicts", function()
		-- R0026 review 001 F2: the remapped merge base is built outside .cache, so a link at the old fixed name there
		-- (a spec can swap one in) leads nowhere: its target stays empty
		local victim = `{base}/remap-victim`
		fs.writeDir(victim)
		fs.writeDir(`{branch}/.cache`)
		t.expect(process.exec("ln", { "-s", victim, `{branch}/.cache/tracker-remap-base` }).ok).toBe(true)
		local r = tr(branch, { "remap" })
		t.expect(#fs.readDir(victim)).toBe(0)
		process.exec("rm", { "-f", `{branch}/.cache/tracker-remap-base` })
		t.expect(r.ok).toBe(false)
		t.expect(git(branch, { "log", "-1", "--format=%s" })).toBe("tracker: remap ids")
		t.expect(fs.isFile(`{branch}/pickman/.tracker/issues/c0001/c0001.md`)).toBe(true)
	end)

	it("a second remap refuses and changes nothing", function()
		local head = git(branch, { "rev-parse", "HEAD" })
		local r = tr(branch, { "remap" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "already")).toBe(true)
		t.expect(has(r.stderr, "git merge origin/main")).toBe(true)
		t.expect(git(branch, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(branch, { "status", "--porcelain" })).toBe("")
		t.expect(fs.isFile(`{branch}/pickman/.tracker/issues/c0001/c0001.md`)).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
