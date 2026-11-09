--!strict
-- c0260 AC10/AC11: the claim gate (`./zn status <id> preparing`, and `new raft` for each member) refuses an issue marked
-- `capture: required` (made after the marker file landed) unless it carries the record or the agent-filed marker, never
-- touches an unmarked (older) one, and reads no history (a shallow clone judges it the same); `./zn new issue --filed-by`
-- writes the exemption marker. Fixture under
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

local ISSUES = "pickman/.tracker/issues"
local REVIEW_FILE = "# Review 001\n\n### F1 [low] a claim\n"
-- a full user record (the claim needs all five sections; the audit judges their content, c0260 AC3/AC4)
local RECORD = "\n## Ask (verbatim)\n### Message 2026-11-08\n```\nmore ghosts\n```\n\n## Interview\n### Q1\nQuestion: restate?\nOptions: approve | correct\nAnswer: approve\n\n"
	.. '## Idea\nMore ghosts.\n\n## Idea review\n### Round 1\n- F1: fixed: done\n\n## Confirmation\nConfirmed (user, 2026-11-08) after round 1: "yes"\n'

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

	it("AC10: an issue made before the landing (no mark) is claimed as before", function()
		local wt = trOk(main, { "worktree", "prep-old" })
		identity(wt)
		trOk(wt, { "status", "c0777", "preparing" })
		t.expect(has(git(origin, { "show", `main:{ISSUES}/c0777/c0777.md` }), "status: preparing")).toBe(true)
	end)

	it(
		"AC10: an issue made after the landing without the record is refused, and its claim is not published",
		function()
			local wt = trOk(main, { "worktree", "prep-new" })
			identity(wt)
			local made = trOk(
				wt,
				{ "new", "issue", "c", "after-landing", "--desc", "A bare stub.", "--project", "pickman" }
			)
			local id = string.match(made, "(c%d%d%d%d)") :: string
			local before = tip()
			local r = tr(wt, { "status", id, "preparing" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "made after the capture record landed")).toBe(true)
			t.expect(tip()).toBe(before)
		end
	)

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
			for _, bad in { "", "make the ghosts scarier", "lesson:no-slash", "agent:no-item" } do
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

	it("AC10: an issue made after the landing is marked, so a shallow clone judges it the same", function()
		local shallow = `{base}/shallow`
		process.exec("git", { "clone", "-q", "--depth", "1", `file://{origin}`, shallow }) -- raw: clone to a named path
		identity(shallow)
		local wt = trOk(shallow, { "worktree", "prep-shallow" })
		identity(wt)
		local id = string.match(
			git(origin, { "log", "--format=%s", "main" }),
			"tracker: new (c%d+) after%-landing"
		) :: string
		t.expect(has(git(origin, { "show", `main:{ISSUES}/{id}/{id}.md` }), "capture: required")).toBe(true)
		local r = tr(wt, { "status", id, "preparing" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "made after the capture record landed")).toBe(true)
		-- an old issue carries no mark
		t.expect(has(git(origin, { "show", `main:{ISSUES}/c0777/c0777.md` }), "capture:")).toBe(false)
	end)

	it(
		"AC10: `new raft` claims its members through the same gate: a marked stub without a record is refused and stays new",
		function()
			local wt = trOk(main, { "worktree", "raft-direct" })
			identity(wt)
			local made = trOk(
				wt,
				{ "new", "issue", "c", "direct-member", "--desc", "A bare stub.", "--project", "pickman" }
			)
			local id = string.match(made, "(c%d%d%d%d)") :: string
			local before = tip()
			local r = tr(wt, { "new", "raft", "chore", "direct-raft", id, "--project", "pickman" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "made after the capture record landed")).toBe(true)
			t.expect(has(git(origin, { "show", `main:{ISSUES}/{id}/{id}.md` }), "status: new-")).toBe(true)
			t.expect(tip()).toBe(before)
		end
	)

	it("AC11: an agent: source is accepted, and the ticket it files is claimed", function()
		local wt = trOk(main, { "worktree", "prep-agent" })
		identity(wt)
		local made = trOk(wt, {
			"new",
			"issue",
			"c",
			"graph-miss-found",
			"--desc",
			"A graph miss.",
			"--project",
			"pickman",
			"--filed-by",
			"agent:c0260/graph-miss",
		})
		local id = string.match(made, "(c%d%d%d%d)") :: string
		t.expect(has(git(origin, { "show", `main:{ISSUES}/{id}/{id}.md` }), "Source: agent:c0260/graph-miss"))
			.toBe(true)
		trOk(wt, { "status", id, "preparing" })
	end)

	it(
		"AC10: a marked ticket with a full user record is claimed by status and by new raft; the gate refuses only what lacks it",
		function()
			local wt = trOk(main, { "worktree", "prep-record" })
			identity(wt)
			local id = string.match(
				trOk(wt, {
					"new",
					"issue",
					"c",
					"with-record",
					"--desc",
					"A captured idea.",
					"--project",
					"pickman",
				}),
				"(c%d%d%d%d)"
			) :: string
			local rec = trOk(main, { "worktree", "prep-record2" })
			identity(rec)
			git(rec, { "fetch", "-q", "origin" })
			git(rec, { "reset", "-q", "--hard", "origin/main" })
			local doc = `{rec}/{ISSUES}/{id}/{id}.md`
			local text = fs.readFile(doc)
			text = (string.gsub(text, "\n## Design", RECORD .. "\n## Design", 1))
			fs.writeFile(doc, text)
			write(`{rec}/{ISSUES}/{id}/capture/idea-review-001.md`, REVIEW_FILE)
			git(rec, { "add", "-A" })
			git(rec, { "commit", "-q", "-m", `tracker: new {id} record` })
			git(rec, { "push", "-q", "origin", "HEAD:main" })
			trOk(wt, { "status", id, "preparing" }) -- claimed: the record is there
			local id2 = string.match(
				trOk(
					wt,
					{ "new", "issue", "c", "second-record", "--desc", "Another.", "--project", "pickman" }
				),
				"(c%d%d%d%d)"
			) :: string
			git(rec, { "fetch", "-q", "origin" })
			git(rec, { "reset", "-q", "--hard", "origin/main" })
			local doc2 = `{rec}/{ISSUES}/{id2}/{id2}.md`
			fs.writeFile(doc2, (string.gsub(fs.readFile(doc2), "\n## Design", RECORD .. "\n## Design", 1)))
			write(`{rec}/{ISSUES}/{id2}/capture/idea-review-001.md`, REVIEW_FILE)
			git(rec, { "add", "-A" })
			git(rec, { "commit", "-q", "-m", `tracker: new {id2} record` })
			git(rec, { "push", "-q", "origin", "HEAD:main" })
			git(wt, { "fetch", "-q", "origin" })
			git(wt, { "reset", "-q", "--hard", "origin/main" })
			trOk(wt, { "new", "raft", "chore", "recorded-raft", id2, "--project", "pickman" }) -- a raft claims a recorded member
			-- the same record with no raw review beside it is refused: the claim calls the record check
			local id3 = string.match(
				trOk(
					wt,
					{ "new", "issue", "c", "no-review", "--desc", "Unreviewed.", "--project", "pickman" }
				),
				"(c%d%d%d%d)"
			) :: string
			git(rec, { "fetch", "-q", "origin" })
			git(rec, { "reset", "-q", "--hard", "origin/main" })
			local doc3 = `{rec}/{ISSUES}/{id3}/{id3}.md`
			fs.writeFile(doc3, (string.gsub(fs.readFile(doc3), "\n## Design", RECORD .. "\n## Design", 1)))
			git(rec, { "add", "-A" })
			git(rec, { "commit", "-q", "-m", `tracker: new {id3} record without a review` })
			git(rec, { "push", "-q", "origin", "HEAD:main" })
			local refused = tr(wt, { "status", id3, "preparing" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "made after the capture record landed")).toBe(true)
			fs.removeDir(base)
		end
	)
end)
