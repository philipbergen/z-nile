--!strict
-- c0260: `./zn land` lets a capture add or edit the files of its issue's capture/ folder (ask.md, idea-review-NNN.md,
-- idea-refute-NNN.md) beside the issue document, and nothing else in that folder or for another issue. Fixture under
-- .cache/c0260-land (c0072's: a seed with this tree's tooling, a bare origin, a main clone and capture worktrees; the
-- gate is PICKMAN_LAND_GATE, so no case runs the real gate).
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
-- c0120 override: fixtures live under the home's .cache (the jail refuses the checkout top's)
local here = fixture.physical(".") or "."
local base = `{here}/.cache/c0260-land`
local seed, origin, main = `{base}/seed`, `{base}/origin.git`, `{base}/main`

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
-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
local function capture(name: string, slug: string): (string, string)
	local wt = trOk(main, { "worktree", name })
	identity(wt)
	local made = trOk(wt, { "new", "issue", "c", slug, "--desc", `First line of {slug}.`, "--project", "pickman" })
	local id = string.match(made, "(c%d%d%d%d)") :: string
	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	local doc = `{wt}/pickman/.tracker/issues/{id}/{id}.md`
	fs.writeFile(doc, fs.readFile(doc) .. `\nMore about {slug}.\n`)
	-- c0120 override: pickman's files live in pickman/ (its home)
	git(wt, { "add", "pickman/.tracker" })
	git(wt, { "commit", "-q", "-m", `tracker: new {id} {slug}` })
	return wt, id
end

local CAPTURE = "pickman/.tracker/issues"
local ASK_V1 = "# Ask for it\n\n## Verbatim ask\nmake the ghosts scarrier, thx\n\n## Interview\nNone: complete\n\n## Confirmation\n"
	.. 'Confirmed (user, 2026-11-07) after idea-review-001: "yes"\n'
local function addCapture(wt: string, id: string, files: { string })
	for _, name in files do
		write(`{wt}/{CAPTURE}/{id}/capture/{name}`, if name == "ask.md" then ASK_V1 else `{name} of {id}\n`)
	end
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-q", "-m", "capture files" })
end
local function refusedWith(wt: string, path: string)
	local before = tip()
	local r = tr(wt, { "land" })
	t.expect(r.ok).toBe(false)
	t.expect(has(r.stderr, path)).toBe(true)
	t.expect(tip()).toBe(before)
end

return t.spec("c0260 a capture lands its capture folder", function(it)
	it("sets up a bare origin and a main checkout", function()
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
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main })
		identity(main)
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
	end)

	it("AC6: land pushes the issue document with its ask, idea reviews and refutes in one commit", function()
		local wt, id = capture("capture-a", "alpha")
		addCapture(wt, id, { "ask.md", "idea-review-001.md", "idea-refute-001.md" })
		local before = tip()
		local out = trOk(wt, { "land" })
		t.expect(has(out, "landed")).toBe(true)
		t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		local changed = git(origin, { "diff", "--name-only", before, "main" })
		for _, name in { "ask.md", "idea-review-001.md", "idea-refute-001.md" } do
			t.expect(has(changed, `{CAPTURE}/{id}/capture/{name}`)).toBe(true)
		end
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(tip())
	end)

	it(
		"AC6: a second land appends to ask.md; it refuses a changed Verbatim ask, an edited landed review and a deletion",
		function()
			local first =
				string.match(git(origin, { "log", "--format=%s", "main" }), "tracker: new (c%d+) alpha") :: string
			local dir = `{CAPTURE}/{first}/capture`
			local wt = trOk(main, { "worktree", "capture-b" })
			identity(wt)
			git(wt, { "pull", "-q", "origin", "main" })
			local function commit()
				git(wt, { "add", "-A" })
				git(wt, { "commit", "-q", "-m", "tracker: new edit" })
			end
			write(`{wt}/{dir}/ask.md`, (string.gsub(ASK_V1, "scarrier", "scary"))) -- the Verbatim ask rewritten: refused
			commit()
			refusedWith(wt, `{dir}/ask.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			write(`{wt}/{dir}/idea-review-001.md`, "rewritten\n") -- a landed review edited: refused
			commit()
			refusedWith(wt, `{dir}/idea-review-001.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			fs.removeFile(`{wt}/{dir}/idea-refute-001.md`) -- a deletion: refused
			commit()
			refusedWith(wt, `{dir}/idea-refute-001.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			write(`{wt}/{dir}/ask.md`, ASK_V1 .. "### Q9\nQuestion: more?\nOptions: no\nAnswer: no\n") -- appended: lands
			commit()
			trOk(wt, { "land" })
			t.expect(has(git(origin, { "show", `main:{dir}/ask.md` }), "### Q9")).toBe(true)
		end
	)

	it(
		"AC6: land refuses any other file in capture/, a file for no draft issue, a nested path and a symlink",
		function()
			local wt, id = capture("capture-c", "gamma")
			addCapture(wt, id, { "notes.md" })
			refusedWith(wt, `{CAPTURE}/{id}/capture/notes.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			addCapture(wt, id, { "sub/ask.md" })
			refusedWith(wt, `{CAPTURE}/{id}/capture/sub/ask.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			addCapture(wt, "c0999", { "ask.md" }) -- no such issue on origin/main
			refusedWith(wt, `{CAPTURE}/c0999/capture/ask.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			fs.writeDir(`{wt}/{CAPTURE}/{id}/capture`)
			process.exec("ln", { "-s", "/etc/passwd", `{wt}/{CAPTURE}/{id}/capture/ask.md` }) -- a link to a file outside
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-q", "-m", "link" })
			refusedWith(wt, `{CAPTURE}/{id}/capture/ask.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		end
	)

	it("AC6: land still refuses a capture file for an issue that is no longer a draft", function()
		local ready = "---\nid: c0888\ntype: chore\ntitle: R\nslug: r\ndesign: ready\nstatus: prepared-a-b-c\n---\n"
		local tmp = `{base}/other`
		process.exec("git", { "clone", "-q", origin, tmp }) -- raw: clone to a named path
		identity(tmp)
		write(`{tmp}/{CAPTURE}/c0888/c0888.md`, ready)
		git(tmp, { "add", "-A" })
		git(tmp, { "commit", "-q", "-m", "prep c0888" })
		git(tmp, { "push", "-q", "origin", "HEAD:main" })
		local wt = capture("capture-d", "delta")
		git(wt, { "merge", "-q", "--no-edit", "origin/main" })
		addCapture(wt, "c0888", { "ask.md" })
		refusedWith(wt, `{CAPTURE}/c0888/capture/ask.md`)
	end)

	it("AC6: land refuses capture files for an issue another terminal has already claimed", function()
		local wt, id = capture("capture-e", "epsilon")
		local tmp = `{base}/claimer`
		process.exec("git", { "clone", "-q", origin, tmp }) -- raw: clone to a named path
		identity(tmp)
		local doc = `{tmp}/{CAPTURE}/{id}/{id}.md`
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "status: new%-", "status: preparing-")))
		git(tmp, { "add", "-A" })
		git(tmp, { "commit", "-q", "-m", `tracker: {id} preparing` })
		git(tmp, { "push", "-q", "origin", "HEAD:main" })
		git(wt, { "merge", "-q", "--no-edit", "origin/main" })
		addCapture(wt, id, { "ask.md" })
		refusedWith(wt, `{CAPTURE}/{id}/capture/ask.md`)
		fs.removeDir(base)
	end)
end)
