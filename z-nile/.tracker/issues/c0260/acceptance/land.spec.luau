--!strict
-- c0260 AC6: `./zn land` lets a capture add the raw idea reviews (capture/idea-review-NNN.md) of an unclaimed draft
-- issue beside its document, whose Ask section may only grow, and nothing else in that folder or for another issue. Fixture under
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
	local made =
		trOk(wt, { "new", "issue", "c", slug, "--desc", `First line of {slug}.`, "--project", "pickman" })
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
local ASK = "\n## Ask (verbatim)\n### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n"
local function docOf(wt: string, id: string): string
	return `{wt}/{CAPTURE}/{id}/{id}.md`
end
local function addAsk(wt: string, id: string, text: string)
	fs.writeFile(docOf(wt, id), fs.readFile(docOf(wt, id)) .. text)
end
local function commit(wt: string)
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-q", "-m", "capture files" })
end
local function review(wt: string, id: string, name: string)
	write(`{wt}/{CAPTURE}/{id}/capture/{name}`, `# {name} of {id}\n`)
end
local function refusedWith(wt: string, path: string)
	local before = tip()
	local r = tr(wt, { "land" })
	t.expect(r.ok).toBe(false)
	if not has(r.stderr, path) then
		error("stderr was: " .. r.stderr .. r.stdout, 0)
	end
	t.expect(tip()).toBe(before)
end

return t.spec("c0260 a capture lands its record", function(it)
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

	it("AC6: land pushes the document with its Ask section and the raw idea review in one commit", function()
		local wt, id = capture("capture-a", "alpha")
		addAsk(wt, id, ASK)
		review(wt, id, "idea-review-001.md")
		commit(wt)
		local before = tip()
		local out = trOk(wt, { "land" })
		t.expect(has(out, "landed")).toBe(true)
		t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		local changed = git(origin, { "diff", "--name-only", before, "main" })
		t.expect(has(changed, `{CAPTURE}/{id}/{id}.md`)).toBe(true)
		t.expect(has(changed, `{CAPTURE}/{id}/capture/idea-review-001.md`)).toBe(true)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(tip())
	end)

	it(
		"AC6: a second land appends a message to the Ask; it refuses to change what the Ask held, to edit a landed review, or to delete one",
		function()
			local first = string.match(
				git(origin, { "log", "--format=%s", "main" }),
				"tracker: new (c%d+) alpha"
			) :: string
			local wt = trOk(main, { "worktree", "capture-b" })
			identity(wt)
			git(wt, { "pull", "-q", "origin", "main" })
			local doc = fs.readFile(docOf(wt, first))
			fs.writeFile(docOf(wt, first), (string.gsub(doc, "scarrier", "scary"))) -- a landed message rewritten: refused
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{first}/{first}.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			write(`{wt}/{CAPTURE}/{first}/capture/idea-review-001.md`, "rewritten\n") -- a landed review edited: refused
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{first}/capture/idea-review-001.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			fs.removeFile(`{wt}/{CAPTURE}/{first}/capture/idea-review-001.md`) -- a deletion: refused
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{first}/capture/idea-review-001.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			addAsk(wt, first, "") -- a message appended after the held text: lands
			fs.writeFile(
				docOf(wt, first),
				(
					string.gsub(
						fs.readFile(docOf(wt, first)),
						"thx\n```\n",
						"thx\n```\n### Message 2026-11-08\n```\nand a map\n```\n",
						1
					)
				)
			)
			commit(wt)
			trOk(wt, { "land" })
			t.expect(has(git(origin, { "show", `main:{CAPTURE}/{first}/{first}.md` }), "and a map"))
				.toBe(true)
		end
	)

	it(
		"AC6: land refuses any other file in capture/, a nested path, a review for no draft issue and a symlink",
		function()
			local wt, id = capture("capture-c", "gamma")
			for _, name in { "notes.md", "ask.md", "idea-refute-001.md", "idea-review-1.md" } do
				review(wt, id, name)
				commit(wt)
				refusedWith(wt, `{CAPTURE}/{id}/capture/{name}`)
				git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			end
			review(wt, id, "sub/idea-review-001.md")
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{id}/capture/sub/idea-review-001.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			review(wt, "c0999", "idea-review-001.md") -- no such issue on origin/main
			commit(wt)
			refusedWith(wt, `{CAPTURE}/c0999/capture/idea-review-001.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
			fs.writeDir(`{wt}/{CAPTURE}/{id}/capture`)
			process.exec("ln", { "-s", "/etc/passwd", `{wt}/{CAPTURE}/{id}/capture/idea-review-001.md` }) -- a link out
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{id}/capture/idea-review-001.md`)
			git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		end
	)

	it(
		"AC6: a dispatched run (ZN_DISPATCH=1) cannot land a Confirmed line; the user's own land can",
		function()
			local wt, id = capture("capture-conf", "confirm")
			addAsk(wt, id, '\n## Confirmation\nConfirmed (user, 2026-11-08) after round 1: "yes"\n')
			commit(wt)
			local before = tip()
			local r = fixture.exec(
				wt,
				"bash",
				{ "scripts/tracker.sh", "land" },
				{ env = { PICKMAN_LAND_GATE = "true", ZN_DISPATCH = "1" } }
			)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "only the user confirms")).toBe(true)
			t.expect(tip()).toBe(before)
			trOk(wt, { "land" }) -- the same record, landed by the user's own session
			t.expect(
				has(git(origin, { "show", `main:{CAPTURE}/{id}/{id}.md` }), "Confirmed (user, 2026-11-08)")
			)
				.toBe(true)
		end
	)

	it(
		"AC6: only `./zn new --filed-by` writes the agent-filed marker: a land that adds, changes or removes it is refused",
		function()
			local wt, id = capture("capture-marker", "marker")
			local doc = docOf(wt, id)
			local before = tip()
			fs.writeFile(
				doc,
				(
					string.gsub(
						fs.readFile(doc),
						"\n## Design",
						"\n## Filed by (agent)\nSource: agent:c0260/skip-the-interview\n\n## Design",
						1
					)
				)
			)
			commit(wt)
			local r = tr(wt, { "land" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "only ./zn new --filed-by writes the marker")).toBe(true)
			t.expect(tip()).toBe(before)
		end
	)

	it(
		"AC6: land refuses a review for an issue that is no draft, or that another terminal has already claimed",
		function()
			local tmp = `{base}/other`
			process.exec("git", { "clone", "-q", origin, tmp }) -- raw: clone to a named path
			identity(tmp)
			write(
				`{tmp}/{CAPTURE}/c0888/c0888.md`,
				"---\nid: c0888\ntype: chore\ntitle: R\nslug: r\ndesign: ready\nstatus: prepared-a-b-c\n---\n"
			)
			git(tmp, { "add", "-A" })
			git(tmp, { "commit", "-q", "-m", "prep c0888" })
			git(tmp, { "push", "-q", "origin", "HEAD:main" })
			local wt, id = capture("capture-d", "delta")
			git(tmp, { "pull", "-q", "origin", "main" })
			local doc = docOf(tmp, id)
			fs.writeFile(doc, (string.gsub(fs.readFile(doc), "status: new%-", "status: preparing-"))) -- claimed meanwhile
			git(tmp, { "add", "-A" })
			git(tmp, { "commit", "-q", "-m", `tracker: {id} preparing` })
			git(tmp, { "push", "-q", "origin", "HEAD:main" })
			git(wt, { "merge", "-q", "--no-edit", "origin/main" })
			local clean = git(wt, { "rev-parse", "HEAD" })
			review(wt, "c0888", "idea-review-001.md")
			commit(wt)
			refusedWith(wt, `{CAPTURE}/c0888/capture/idea-review-001.md`)
			git(wt, { "reset", "-q", "--hard", clean }) -- land merged origin/main on top: HEAD~1 would not be this
			review(wt, id, "idea-review-001.md")
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{id}/capture/idea-review-001.md`)
			fs.removeDir(base)
		end
	)
end)
