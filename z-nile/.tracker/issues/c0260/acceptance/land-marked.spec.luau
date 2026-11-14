--!strict
-- c0260 AC6: `./zn land` runs the record checker for a marked ticket (one malformed capture would turn the real-tree
-- audit, and so every gate, red), binds a Confirmed line to the record and the idea its round saw, keeps the Confirmation
-- lines, refuses an idea file by any other name or a move of the `idea:` line other than to challenged, and leaves an
-- older (unmarked) hand-recorded draft judged by the Ask rule only. Fixture under .cache/c0260-landmarked.
local capturecheck = require("@znile/engine/capturecheck")
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
local base = `{here}/.cache/c0260-landmarked`
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
local function docOf(wt: string, id: string): string
	return `{wt}/{CAPTURE}/{id}/{id}.md`
end
local function commit(wt: string)
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-q", "-m", "capture files" })
end
local function review(wt: string, id: string, name: string)
	write(`{wt}/{CAPTURE}/{id}/{name}`, `# {name} of {id}\n`)
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

local LEGACY =
	'---\nid: c0778\ntype: chore\ntitle: Old\nslug: old\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-01\nstatus: new-a-b-c\n---\n\n# c0778: Old\n\n## Problem\nOld.\n\n## Ask (verbatim)\n### Message 2026-11-11\n```\nhello\n```\n\n## Interview\nfree prose\n\n## Idea\nI.\n\n## Confirmation\nConfirmed (Phil, 2026-11-11) after round 3: "ok"\n\n## Design\n'
local RECORD =
	"\n## Ask (verbatim)\n### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n\n## Interview\n### Q1\nQuestion: restate?\nAnswer: approve\n"

local function setText(wt: string, id: string, f: (string) -> string)
	fs.writeFile(docOf(wt, id), f(fs.readFile(docOf(wt, id))))
end
local function withRecord(text: string): string
	return (string.gsub(text, "\n## Design", RECORD .. "\n## Design", 1))
end
local function refusedSaying(wt: string, needle: string)
	local before = tip()
	local r = tr(wt, { "land" })
	t.expect(r.ok).toBe(false)
	if not has(r.stderr, needle) then
		error("stderr was: " .. r.stderr .. r.stdout, 0)
	end
	t.expect(tip()).toBe(before)
end

return t.spec("c0260 land judges a marked record", function(it)
	it("sets up a seed with the marker file, an unmarked hand-recorded draft and a bare origin", function()
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
		write(`{seed}/z-nile/.tracker/capture-since`, "marker\n")
		write(`{seed}/{CAPTURE}/c0778/c0778.md`, LEGACY)
		write(`{seed}/{CAPTURE}/c0778/check.sh`, "#!/usr/bin/env bash\n", true)
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main })
		identity(main)
	end)

	it(
		"AC6: a marked ticket's malformed record is refused naming the problem: a gap, a stray heading, an unclosed fence",
		function()
			local wt, id = capture("capture-bad", "bad")
			t.expect(has(fs.readFile(docOf(wt, id)), "capture: required")).toBe(true)
			local clean = git(wt, { "rev-parse", "HEAD" })
			local function attempt(text: (string) -> string, needle: string)
				setText(wt, id, text)
				commit(wt)
				refusedSaying(wt, needle)
				git(wt, { "reset", "-q", "--hard", clean })
			end
			attempt(function(d)
				return (
					string.gsub(withRecord(d), "Answer: approve\n", "Answer: approve\n### Q3\nQuestion: q\nAnswer: a\n")
				)
			end, "found Q3 where Q2 belongs")
			attempt(function(d)
				return (string.gsub(withRecord(d), "\n## Interview", "\n## Notes\nmine\n\n## Interview", 1))
			end, '"## Notes" sits inside the capture record')
			attempt(function(d)
				return (string.gsub(withRecord(d), "thx\n```", "thx\n", 1))
			end, "never closed")
		end
	)

	it(
		"AC6: a marked ticket's growing record lands; a Confirmed line lands only with the review of the round it names and the state that round saw",
		function()
			local wt, id = capture("capture-good", "good")
			setText(wt, id, withRecord)
			commit(wt)
			trOk(wt, { "land" }) -- a record still growing: Ask and Interview, no Confirmation
			-- the idea is written, the round's review names the state it saw, the user confirms
			local text = fs.readFile(docOf(wt, id))
			text = (string.gsub(text, "idea: unchallenged", "idea: challenged", 1))
			text = capturecheck.addConfirmation(text, 'Confirmed (user, 2026-11-08) after round 1: "yes"')
			fs.writeFile(docOf(wt, id), text)
			write(
				`{wt}/{CAPTURE}/{id}/idea-review-001.md`,
				`# Idea review 001\n\nRound: {capturecheck.roundState(text)}\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n`
			)
			commit(wt)
			trOk(wt, { "land" })
			t.expect(has(git(origin, { "show", `main:{CAPTURE}/{id}/{id}.md` }), 'after round 1: "yes"')).toBe(true)
			-- the Problem changed by hand afterwards: the line no longer stands for it
			local second = trOk(main, { "worktree", "capture-drift" })
			identity(second)
			git(second, { "pull", "-q", "origin", "main" })
			setText(second, id, function(d)
				return (string.gsub(d, "\n## Problem\n", "\n## Problem\nAnd a new wish.\n", 1))
			end)
			commit(second)
			refusedSaying(second, "changed since that round")
			git(second, { "reset", "-q", "--hard", "HEAD~1" })
			-- the confirmation's words rewritten, or the line dropped without a new round of the document
			setText(second, id, function(d)
				return (string.gsub(d, 'after round 1: "yes"', 'after round 1: "no"', 1))
			end)
			commit(second)
			refusedSaying(second, "only appended")
		end
	)

	it(
		"AC6: an older (unmarked) hand-recorded draft still lands what the Ask rule allows, and nothing it forbids",
		function()
			local wt = trOk(main, { "worktree", "capture-legacy" })
			identity(wt)
			git(wt, { "pull", "-q", "origin", "main" })
			fs.writeFile(docOf(wt, "c0778"), fs.readFile(docOf(wt, "c0778")) .. "\nA later note.\n")
			commit(wt)
			trOk(wt, { "land" }) -- not judged by the record checker (its shape is its own)
			git(wt, { "pull", "-q", "origin", "main" })
			setText(wt, "c0778", function(d)
				return (string.gsub(d, "hello", "goodbye", 1))
			end)
			commit(wt)
			refusedSaying(wt, `{CAPTURE}/c0778/c0778.md`) -- its landed words still only grow
		end
	)

	it(
		"AC6: only idea-review-NNN.md and idea-refute-NNN.md land beside a document, and the idea line moves only to challenged",
		function()
			local wt, id = capture("capture-names", "names")
			setText(wt, id, function(d)
				return (string.gsub(d, "idea: unchallenged", "idea: challenged", 1))
			end)
			commit(wt)
			local clean = git(wt, { "rev-parse", "HEAD" })
			for _, name in { "idea-rebuttal-001.md", "idea-resume-001.md", "idea-refute-1.md" } do
				review(wt, id, name)
				commit(wt)
				refusedWith(wt, `{CAPTURE}/{id}/{name}`)
				git(wt, { "reset", "-q", "--hard", clean })
			end
			-- the key removed, or moved back
			setText(wt, id, function(d)
				return (string.gsub(d, "idea: challenged\n", "", 1))
			end)
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{id}/{id}.md`)
			git(wt, { "reset", "-q", "--hard", clean })
			trOk(wt, { "land" }) -- unchallenged -> challenged is the one move
			git(wt, { "pull", "-q", "origin", "main" })
			setText(wt, id, function(d)
				return (string.gsub(d, "idea: challenged", "idea: unchallenged", 1))
			end)
			commit(wt)
			refusedWith(wt, `{CAPTURE}/{id}/{id}.md`)
			fs.removeDir(base)
		end
	)
end)
