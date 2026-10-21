--!strict
-- c0780: `tracker.sh land` lands a capture without a pull request: merge origin/main, run the gate, check that only
-- backlog issue documents change, push one commit on top of origin/main, retry a lost race. Fixture under
-- .cache/c0780-land: a seed with this tree's tooling, a bare origin, a main clone, a second clone and capture
-- worktrees. The gate is PICKMAN_LAND_GATE (a command), so no case runs the real gate.
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
local base = `{root}/.cache/c0780-land`
local seed, origin, main, other = `{base}/seed`, `{base}/origin.git`, `{base}/main`, `{base}/other`

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function tr(cwd: string, args: { string }, gate: string?): Result
	local env = { PICKMAN_LAND_GATE = gate or "true" }
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function trOk(cwd: string, args: { string }, gate: string?): string
	local r = tr(cwd, args, gate)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return git(origin, { "rev-parse", "main" })
end
local function write(path: string, text: string, exec: boolean?)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
	if exec then
		process.exec("chmod", { "+x", path })
	end
end
local function identity(dir: string)
	git(dir, { "config", "user.name", "land" })
	git(dir, { "config", "user.email", "land@example.invalid" })
end
-- a capture worktree with one new issue, its Problem filled in and committed
local function capture(name: string, slug: string): (string, string)
	local wt = trOk(main, { "worktree", name })
	identity(wt)
	local made = trOk(wt, { "new", "issue", "c", slug, "--desc", `First line of {slug}.` })
	local id = string.match(made, "(c%d%d%d%d)") :: string
	local doc = `{wt}/tracker/issues/{id}/{id}.md`
	fs.writeFile(doc, fs.readFile(doc) .. `\nMore about {slug}.\n`)
	git(wt, { "add", "tracker" })
	git(wt, { "commit", "-q", "-m", `tracker: new {id} {slug}` })
	return wt, id
end

return t.spec("tracker land", function(it)
	it("sets up a bare origin, a main checkout and a second clone", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		identity(seed)
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		fs.writeDir(`{seed}/tracker`)
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			write(`{seed}/tracker/{d}/.gitkeep`, "")
		end
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		for _, c in { main, other } do
			process.exec("git", { "clone", "-q", origin, c })
			identity(c)
		end
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
	end)

	it(
		"land pushes one commit with the capture's issue edits on top of origin/main, and the branch equals main",
		function()
			local wt, id = capture("capture-a", "alpha")
			local before = tip() -- the stub is already on origin (new issue published it)
			local out = trOk(wt, { "land" })
			t.expect(has(out, "gate overridden")).toBe(true) -- PICKMAN_LAND_GATE is never silent
			t.expect(git(origin, { "rev-parse", "main^" })).toBe(before)
			t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
			t.expect(git(origin, { "diff", "--name-only", before, "main" }))
				.toBe(`tracker/issues/{id}/{id}.md`)
			t.expect(has(git(origin, { "show", `main:tracker/issues/{id}/{id}.md` }), "More about alpha."))
				.toBe(true)
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(tip())
			t.expect(git(origin, { "log", "-1", "--format=%s", "main" })).toBe(`tracker: new {id} alpha`)
		end
	)

	it("land brings the main checkout up to origin/main", function()
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("land merges what others pushed meanwhile, and the result is linear (one parent)", function()
		local wt, id = capture("capture-b", "beta")
		git(other, { "pull", "-q", "origin", "main" })
		write(
			`{other}/tracker/issues/f0500/f0500.md`,
			"---\nid: f0500\ntype: feature\ntitle: Elsewhere\nslug: elsewhere\n---\n"
		)
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "other f0500" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		local before = tip()
		trOk(wt, { "land" })
		t.expect(git(origin, { "rev-parse", "main^" })).toBe(before)
		t.expect(git(origin, { "rev-list", "--count", "--merges", `{before}..main` })).toBe("0")
		t.expect(git(origin, { "diff", "--name-only", before, "main" })).toBe(`tracker/issues/{id}/{id}.md`)
	end)

	it("land refuses a change outside the capture's issue documents, and pushes nothing", function()
		local wt = capture("capture-c", "gamma")
		write(`{wt}/scripts/extra.txt`, "not a capture\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "sneak a script change" })
		local before = tip()
		local r = tr(wt, { "land" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "scripts/extra.txt")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it("land refuses anything but edits to draft issue documents", function()
		-- a ready issue on origin, as a merged prep would have left it
		git(other, { "pull", "-q", "origin", "main" })
		write(
			`{other}/tracker/issues/f0600/f0600.md`,
			"---\nid: f0600\ntype: feature\ntitle: Ready\nslug: ready\ndesign: ready\nstatus: prepared-a-b-c\n---\n"
		)
		-- a draft raft document: draft frontmatter, but not an issue document
		write(
			`{other}/tracker/rafts/R0900/R0900.md`,
			"---\nid: R0900\ntype: chore\ntitle: Draft raft\nslug: draft-raft\ndesign: draft\n---\n"
		)
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "prep f0600" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		local wt, id = capture("capture-h", "eta")
		git(wt, { "merge", "-q", "--no-edit", "origin/main" })
		local function refused(change: () -> (), path: string)
			change()
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-q", "-m", "attempt" })
			local before = tip()
			local r = tr(wt, { "land" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, path)).toBe(true)
			t.expect(tip()).toBe(before)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		end
		local alpha =
			string.match(git(origin, { "log", "--format=%s", "main" }), "tracker: new (c%d+) alpha") :: string
		refused(function() -- a deletion
			fs.removeFile(`{wt}/tracker/issues/{alpha}/{alpha}.md`)
		end, `tracker/issues/{alpha}/{alpha}.md`)
		refused(function() -- an acceptance file
			write(`{wt}/tracker/issues/{id}/acceptance/x.spec.luau`, "return nil\n")
		end, `tracker/issues/{id}/acceptance/x.spec.luau`)
		refused(function() -- a done item
			write(`{wt}/tracker/issues/done/c0990/c0990.md`, "---\nid: c0990\n---\n")
		end, "tracker/issues/done/c0990/c0990.md")
		refused(function() -- an existing check.sh (sequestered once written)
			local p = `{wt}/tracker/issues/{id}/check.sh`
			fs.writeFile(p, fs.readFile(p) .. "# edited\n")
		end, `tracker/issues/{id}/check.sh`)
		refused(function() -- an issue whose design is past draft
			local p = `{wt}/tracker/issues/f0600/f0600.md`
			fs.writeFile(p, fs.readFile(p) .. "\nEdited after prep.\n")
		end, "tracker/issues/f0600/f0600.md")
		refused(function() -- demoting a prepared issue to draft, then rewriting it (status untouched)
			local p = `{wt}/tracker/issues/f0600/f0600.md`
			fs.writeFile(
				p,
				(string.gsub(fs.readFile(p), "design: ready", "design: draft")) .. "\nRewritten.\n"
			)
		end, "tracker/issues/f0600/f0600.md")
		refused(function() -- an edit to a draft raft document (the path decides, not the frontmatter)
			local p = `{wt}/tracker/rafts/R0900/R0900.md`
			fs.writeFile(p, fs.readFile(p) .. "\nEdited.\n")
		end, "tracker/rafts/R0900/R0900.md")
		refused(function() -- an edit to the issue template, which carries `design: draft` too
			local p = `{wt}/z-nile/templates/issue/doc.md`
			fs.writeFile(p, fs.readFile(p) .. "\n<!-- edited -->\n")
		end, "z-nile/templates/issue/doc.md")
		refused(function() -- a capture promoting its own issue past draft, with no prep
			local p = `{wt}/tracker/issues/{id}/{id}.md`
			fs.writeFile(p, (string.gsub(fs.readFile(p), "design: draft", "design: ready")))
		end, `tracker/issues/{id}/{id}.md`)
		refused(function() -- a capture changing its own status line
			local p = `{wt}/tracker/issues/{id}/{id}.md`
			fs.writeFile(p, (string.gsub(fs.readFile(p), "status: [^\n]*", "status: prepared-a-b-c")))
		end, `tracker/issues/{id}/{id}.md`)
		refused(function() -- an issue added locally instead of published by new issue
			write(`{wt}/tracker/issues/c0980/c0980.md`, "---\nid: c0980\ntype: chore\ndesign: draft\n---\n")
			write(`{wt}/tracker/issues/c0980/check.sh`, "#!/bin/sh\n", true)
		end, "tracker/issues/c0980/c0980.md")
	end)

	it("land refuses when the gate fails, and pushes nothing", function()
		local wt = capture("capture-d", "delta")
		local before = tip()
		local r = tr(wt, { "land" }, "false")
		t.expect(r.ok).toBe(false)
		t.expect(tip()).toBe(before)
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
	end)

	it("land refuses outside a capture worktree, on a dirty tree, and with nothing to land", function()
		local named = trOk(main, { "worktree", "edit-skills" })
		identity(named)
		local r = tr(named, { "land" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "capture")).toBe(true)
		local wt = capture("capture-e", "epsilon") -- publishes its stub: count from here
		local before = tip()
		fs.writeFile(`{wt}/stray.txt`, "x")
		local dirty = tr(wt, { "land" })
		fs.removeFile(`{wt}/stray.txt`)
		t.expect(dirty.ok).toBe(false)
		local empty = trOk(main, { "worktree", "capture-f" })
		identity(empty)
		local nothing = tr(empty, { "land" })
		t.expect(nothing.ok).toBe(false)
		t.expect(tip()).toBe(before)
	end)

	it("land retries a lost race", function()
		local wt, id = capture("capture-g", "zeta")
		-- the gate runs between land's fetch and its push: on its first run it pushes from another clone, so the
		-- first push is rejected and land must sync, gate again and push again. Reviewed exception to the fixture
		-- rule: this gate script runs raw git, only in `other`, a fixture clone under this spec's .cache directory.
		local marker = `{base}/raced`
		local gate = `{base}/racing-gate`
		write(
			gate,
			`#!/bin/bash\n[ -e "{marker}" ] && exit 0\ntouch "{marker}"\ncd "{other}" || exit 1\n`
				.. "git pull -q origin main && echo raced > tracker/raced.txt && git add -A && "
				.. "git commit -qm 'race' && git push -q origin HEAD:main\n",
			true
		)
		local r = tr(wt, { "land" }, gate)
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(marker)).toBe(true)
		t.expect(git(origin, { "log", "-1", "--format=%s", "main" })).toBe(`tracker: new {id} zeta`)
		t.expect(git(origin, { "log", "-1", "--format=%s", "main^" })).toBe("race")
		t.expect(git(origin, { "rev-list", "--count", "--merges", "main~2..main" })).toBe("0")
	end)
end)
