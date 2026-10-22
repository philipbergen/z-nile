--!strict
-- c0870: `tracker.sh remap` brings a branch that was in flight during a compaction onto the new ids: it applies
-- origin/main's z-nile/compaction.txt to the branch, numbers the branch's own unmapped items from origin's counter,
-- commits, then merges origin/main itself against the remapped merge base. Fixture under .cache/c0870-remap.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ids = require("@scripts/tracker/ids")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- c0120 override: fixtures live under the spec's home's .cache (the jail refuses the checkout top's)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0870-remap`
local seed, origin, main = `{base}/seed`, `{base}/origin.git`, `{base}/main`

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
local function doc(id: string, extra: string): string
	local lines = {}
	for i = 1, 30 do
		table.insert(lines, `Body line {i} of the document.`)
	end
	return `---\nid: {id}\ntype: chore\ntitle: T\nslug: s-{string.lower(id)}\n{extra}design: ready\ncreated: 2026-01-01\n---\n\n# {id}: T\n\nSee c0010 and f0020.\nline a\nline b\nline c\n{table.concat(
		lines,
		"\n"
	)}\n`
end
local function worktree(name: string): string
	local wt = trOk(main, { "worktree", name })
	identity(wt)
	return wt
end

local branch = ""

return t.spec("c0870 remap", function(it)
	it("sets up an origin and a branch with its own edits and an item of its own", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		identity(seed)
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		-- c0120 override: the spec runs from its project's home after the move
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		engine.roots(seed) -- c0120 override: the fixture is on the final layout (engine.roots lays out every root)
		write(`{seed}/z-nile/next`, "issue 41 a-b-c\nraft 31 a-b-c\n")
		write(`{seed}/pickman/.tracker/issues/c0010/c0010.md`, doc("c0010", "raft: R0030\n"))
		write(`{seed}/pickman/.tracker/issues/f0020/f0020.md`, doc("f0020", "raft: R0030\n"))
		write(`{seed}/pickman/.tracker/rafts/R0030/R0030.md`, doc("R0030", "issues: [c0010, f0020]\n"))
		-- c0120 override: pickman's promoted specs live in its home, pickman/tests/acceptance
		write(`{seed}/pickman/tests/acceptance/c0010/a.spec.luau`, "return 1\n")
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main }) -- raw: clone to a named path
		identity(main)
		branch = worktree("prep-y")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local c10 = `{branch}/pickman/.tracker/issues/c0010/c0010.md`
		fs.writeFile(c10, (string.gsub(fs.readFile(c10), "line b", "line B, edited on the branch (c0010)")))
		fs.writeFile(
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			`{branch}/pickman/.tracker/issues/f0020/f0020.md`,
			fs.readFile(`{branch}/pickman/.tracker/issues/f0020/f0020.md`)
				.. "Appended on the branch for f0020.\n"
		)
		t.expect(
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			trOk(branch, { "new", "issue", "c", "mine", "--project", "pickman" }, { PICKMAN_PUBLISH = "0" })
		).toBe("pickman/.tracker/issues/c0041/c0041.md")
		t.expect(
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			trOk(branch, { "new", "issue", "c", "also", "--project", "pickman" }, { PICKMAN_PUBLISH = "0" })
		).toBe("pickman/.tracker/issues/c0042/c0042.md")
		git(branch, { "add", "-A" })
		git(branch, { "commit", "-q", "-m", "branch work" })
		git(branch, { "push", "-q", "-u", "origin", "prep-y" })
	end)

	it("refuses while origin/main has no compaction map", function()
		local head = git(branch, { "rev-parse", "HEAD" })
		local r = tr(branch, { "remap" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, ids.MAP_FILE)).toBe(true)
		t.expect(git(branch, { "rev-parse", "HEAD" })).toBe(head)
	end)

	it("a forced compaction lands on main", function()
		local wt = worktree("compact-z")
		local r = tr(wt, { "compact", "--force" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout .. r.stderr, "prep-y")).toBe(true)
		git(wt, { "push", "-q", "origin", "HEAD:main" }) -- stands in for the merged pull request
		local c = ids.parse(git(origin, { "show", "main:z-nile/next" }) .. "\n") :: ids.Counters
		t.expect(c.issue).toBe(3)
	end)

	it("a branch from before the compaction cannot allocate until it remaps", function()
		local before = git(origin, { "rev-parse", "main" })
		local r = tr(branch, { "new", "issue", "c", "stale", "--project", "pickman" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "a branch that changed tracker/ runs ./zn remap")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		t.expect(git(branch, { "status", "--porcelain" })).toBe("")
		-- nor publish a status stamp: old ids name other items on origin now
		local st = tr(branch, { "status", "c0010", "preparing" })
		t.expect(st.ok).toBe(false)
		t.expect(has(st.stderr, "a branch that changed tracker/ runs ./zn remap")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
	end)

	it("remap renames the branch's items, numbers its own from origin's counter and commits", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local head = git(branch, { "rev-parse", "HEAD" })
		local out = trOk(branch, { "remap" })
		-- the branch's own items in plan order (number, then prefix), one reservation past the last
		t.expect(has(out, "c0041 -> c0003")).toBe(true)
		t.expect(has(out, "c0042 -> c0004")).toBe(true)
		-- the remap commit, then a merge of origin/main against the remapped merge base
		t.expect(git(branch, { "rev-parse", "HEAD^1^" })).toBe(head)
		t.expect(git(branch, { "log", "-1", "--format=%s", "HEAD^1" })).toBe("tracker: remap ids")
		t.expect(git(branch, { "rev-parse", "HEAD^2" })).toBe(git(branch, { "rev-parse", "origin/main" }))
		t.expect(git(branch, { "status", "--porcelain" })).toBe("")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{branch}/pickman/.tracker/issues/c0001/c0001.md`)).toBe(true)
		t.expect(fs.isFile(`{branch}/pickman/.tracker/issues/f0002/f0002.md`)).toBe(true)
		t.expect(fs.isFile(`{branch}/pickman/.tracker/issues/c0003/c0003.md`)).toBe(true)
		t.expect(fs.isFile(`{branch}/pickman/.tracker/issues/c0004/c0004.md`)).toBe(true)
		t.expect(fs.isDir(`{branch}/pickman/.tracker/issues/c0042`)).toBe(false)
		t.expect(fs.isDir(`{branch}/pickman/.tracker/issues/c0041`)).toBe(false)
		t.expect(fs.isFile(`{branch}/pickman/tests/acceptance/c0001/a.spec.luau`)).toBe(true)
		t.expect(has(fs.readFile(`{branch}/pickman/.tracker/rafts/R0001/R0001.md`), "issues: [c0001, f0002]"))
			.toBe(true)
		-- the number is reserved on origin
		local c = ids.parse(git(origin, { "show", "main:z-nile/next" }) .. "\n") :: ids.Counters
		t.expect(c.issue).toBe(5)
	end)

	it("the branch then holds origin/main, with the branch's edits kept", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local r = fixture.exec(branch, "git", { "merge-base", "--is-ancestor", "origin/main", "HEAD" })
		t.expect(r.ok).toBe(true)
		t.expect(git(branch, { "status", "--porcelain" })).toBe("")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local c1 = fs.readFile(`{branch}/pickman/.tracker/issues/c0001/c0001.md`)
		t.expect(has(c1, "line B, edited on the branch (c0001)")).toBe(true)
		t.expect(has(c1, "See c0001 and f0002.")).toBe(true)
		t.expect(
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			has(
				fs.readFile(`{branch}/pickman/.tracker/issues/f0002/f0002.md`),
				"Appended on the branch for f0002."
			)
		).toBe(true)
		t.expect(fs.isDir(`{branch}/pickman/.tracker/issues/c0010`)).toBe(false)
		t.expect(fs.isDir(`{branch}/pickman/.tracker/rafts/R0030`)).toBe(false)
		t.expect(fs.isFile(`{branch}/{ids.MAP_FILE}`)).toBe(true)
		t.expect(trOk(branch, { "audit" }) ~= nil).toBe(true)
	end)

	it("a second remap refuses: the branch already has the compaction", function()
		local head = git(branch, { "rev-parse", "HEAD" })
		local r = tr(branch, { "remap" })
		t.expect(r.ok).toBe(false)
		t.expect(git(branch, { "rev-parse", "HEAD" })).toBe(head)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
