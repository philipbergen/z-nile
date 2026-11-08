--!strict
-- c0260 AC10/AC11: the claim gate (`./zn status <id> preparing`) refuses an issue made after the capture record landed unless it
-- carries the record or the agent-filed marker, never touches an older one, and fails closed on a history it cannot
-- read; `./zn new issue --filed-by` writes the marker. Fixture under
-- .cache/c0260-claim (c0072's: a seed with this tree's tooling, a bare origin, a main clone and capture worktrees; the
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
local base = `{here}/.cache/c0260-claim`
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

local ISSUES = "pickman/.tracker/issues"

return t.spec("c0260 the claim gate", function(it)
	it("sets up an origin whose history holds an old issue, then the marker's landing", function()
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
		write(
			`{seed}/{ISSUES}/c0777/c0777.md`,
			"---\nid: c0777\ntype: chore\ntitle: Old\nslug: old\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-01\nstatus: new-a-b-c\n---\n\n# c0777: Old\n\n## Problem\nOld.\n\n## Design\n"
		)
		write(`{seed}/{ISSUES}/c0777/check.sh`, "#!/usr/bin/env bash\n", true)
		-- the first commit is the history before the landing; the second adds the marker file that puts the rule in force
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "before the landing" })
		write(
			`{seed}/z-nile/.tracker/capture-since`,
			"Issues made after the commit that added this file carry a capture record (c0260).\n"
		)
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "the landing" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main })
		identity(main)
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
	end)

	it("AC10: an issue made before the landing is claimed as before", function()
		local wt = trOk(main, { "worktree", "prep-old" })
		identity(wt)
		trOk(wt, { "status", "c0777", "preparing" })
		t.expect(has(git(origin, { "show", `main:{ISSUES}/c0777/c0777.md` }), "status: preparing")).toBe(true)
	end)

	it("AC10: an issue made after the landing without the record is refused, and its claim is not published", function()
		local wt = trOk(main, { "worktree", "prep-new" })
		identity(wt)
		local made =
			trOk(wt, { "new", "issue", "c", "after-landing", "--desc", "A bare stub.", "--project", "pickman" })
		local id = string.match(made, "(c%d%d%d%d)") :: string
		local before = tip()
		local r = tr(wt, { "status", id, "preparing" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "made after the capture record landed")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it(
		"AC11: --filed-by writes the marker with its source and the Scope decision, and that ticket is claimed",
		function()
			local wt = trOk(main, { "worktree", "prep-filed" })
			identity(wt)
			local made = trOk(wt, {
				"new",
				"issue",
				"c",
				"from-a-lesson",
				"--desc",
				"A lesson.",
				"--project",
				"pickman",
				"--filed-by",
				"review:c0260/design-review-003 F4",
			})
			local id = string.match(made, "(c%d%d%d%d)") :: string
			local doc = git(origin, { "show", `main:{ISSUES}/{id}/{id}.md` })
			t.expect(has(doc, "## Filed by (agent)\nSource: review:c0260/design-review-003 F4")).toBe(true)
			t.expect(has(doc, "Scope decision (user, 2026-11-08): agent-filed tickets are exempt")).toBe(true)
			trOk(wt, { "status", id, "preparing" })
		end
	)

	it(
		"AC11: --filed-by refuses an empty source, the user's words and a bare lesson name, and creates nothing",
		function()
			local wt = trOk(main, { "worktree", "prep-bad" })
			identity(wt)
			local before = tip()
			for _, bad in { "", "make the ghosts scarier", "lesson:no-slash" } do
				local r = tr(wt, {
					"new",
					"issue",
					"c",
					"bad-source",
					"--desc",
					"x",
					"--project",
					"pickman",
					"--filed-by",
					bad,
				})
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "--filed-by takes")).toBe(true)
			end
			t.expect(tip()).toBe(before)
		end
	)

	it(
		"AC10: a history the gate cannot read (a shallow clone) refuses the claim of an issue it cannot place",
		function()
			local shallow = `{base}/shallow`
			process.exec("git", { "clone", "-q", "--depth", "1", `file://{origin}`, shallow }) -- raw: clone to a named path
			identity(shallow)
			local wt = trOk(shallow, { "worktree", "prep-shallow" })
			identity(wt)
			local r = tr(wt, { "status", "c0777", "preparing" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "cannot tell whether")).toBe(true)
			fs.removeDir(base)
		end
	)
end)
