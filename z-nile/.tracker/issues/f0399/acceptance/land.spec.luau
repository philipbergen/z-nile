--!strict
-- f0399 AC8 to AC12, AC16 to AC18: guesses.md written by `./zn guess` and read by `./zn guesses`; a raft readied with a
-- `Lands: approved` trailer in its ready commit, finished with a note, refused by `done` until every approval holds,
-- still finished after `./zn approve` on the top layer, and landed with approval.md and guesses.md in done/; a raft whose
-- ready commit has no trailer lands by today's rule; Guessed bullets; the picks of work next for an issue and the carriers
-- file. Real git in fixtures under .cache (a bare origin whose path contains github.com, a `gh` stub). Approving is the
-- person's command: it runs under `script`, which gives it a terminal (as approve.spec does).
--   Fixture A carries the walked cases: R0010 (c0010 approved, c0020 not, c0025 approved) is readied, built, refused,
--   approved and landed; R0020 (c0030, no approval) is readied outside and inside the dispatcher and carried by a session;
--   R0050 (two approved members) shows what ready accepts; R0040 is made as a raft readied before trailers existed
--   (readied under ZN_DISPATCH, which writes no trailer, then one approval is removed from origin/main as for the six old
--   rafts) and passes on today's engine. Fixture B holds the Guessed bullets, fixture C the issue picks of work next.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local NEW = "new-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local TODAY = os.date("!%Y-%m-%d") :: string

local CAPTURED = table.concat({
	"## Problem",
	"The marker is missing.",
	"",
	"## Solution",
	"Store the marker.",
	"",
	"## Acceptance criteria",
	"- AC1: the marker is stored",
	"",
}, "\n")

local function issue(id: string, raft: string, body: string, extra: string?): string
	local text = if body == "" then CAPTURED else `{body}\n{CAPTURED}`
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\n{extra or ""}status: {PREPARED}\n---\n\n# {id}\n\n{text}`
end

local function raftDoc(id: string, issues: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{string.gsub(
		issues,
		", ",
		"\n"
	)}\n{extra or ""}`
end

local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
case "$1 $2" in
  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;
  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;
  "pr edit") exit 0 ;;
  "pr view") echo body; exit 0 ;;
esac
exit 0
]=]

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local function lines(s: string): { string }
	local out = {}
	for line in string.gmatch((string.gsub(s, "\r", "")), "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function commitAll(dir: string, message: string)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
end

-- A tracker fixture with a `gh` stub that logs its calls; returns it with its log and the environment to use.
local function build(
	name: string,
	seed: { [string]: string }
): (trackerfix.Fixture, string, { [string]: string })
	local fx = trackerfix.new(name, seed)
	local bin, log = `{fx.base}/bin`, `{fx.base}/gh.log`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/gh`, (string.gsub(GH, "@LOG@", log)))
	process.exec("chmod", { "+x", `{bin}/gh` })
	return fx, log, { PATH = `{bin}:{process.env.PATH or ""}` }
end

local function seedBase(): { [string]: string }
	return {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
	}
end

local function itemFiles(seed: { [string]: string }, id: string, doc: string)
	seed[`{ROOT}/issues/{id}/{id}.md`] = doc
	seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
end

-- an f0399 command: not built yet, so a failure is the assertion that it works
local function expectOk(r: fixture.Result, what: string): string
	if not r.ok then
		error(`expected ./zn {what} to succeed ({r.code}): {say(r)}`, 2)
	end
	return r.stdout
end

local function guessArgs(id: string, step: string, open: string, why: string): { string }
	return { "guess", id, "--step", step, "--open", open, "--chose", "Two.", "--why", why }
end

-- Fixture A -----------------------------------------------------------------------------------------------------------
local f: trackerfix.Fixture = nil :: any
local setUpA = false
local env: { [string]: string } = {}
local wtPrep, wt, wt20 = "", "", ""
local readied, built, refused, approvedAll = false, false, false, false
local waitLine = ""
local DOC10 = raftDoc("R0010", "c0010, c0020, c0025")

local function tr(dir: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local merged = table.clone(env)
	if extra then
		for k, v in extra do
			merged[k] = v
		end
	end
	return trackerfix.tr(f, dir, args, merged)
end

-- a setup command: today's engine runs it, so a failure is a broken fixture
local function zn(dir: string, args: { string }, extra: { [string]: string }?): string
	local r = tr(dir, args, extra)
	if not r.ok then
		error(`fixture step ./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function human(dir: string, args: { string }): fixture.Result
	local merged: { [string]: string } = { PATH = env.PATH, HOME = process.env.HOME or "" }
	local argv = { "-q", "/dev/null", "./zn" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "script", argv, { env = merged })
end

local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

-- the body of the newest ready commit of `raft` on origin/main
local function readyBody(raft: string): string
	return git(f.origin, { "log", "-1", "--format=%B", `--grep=^tracker: ready {raft} `, "main" })
end

local function withoutStatus(doc: string): string
	return (string.gsub(doc, "\nstatus: [^\n]*", ""))
end

local function setupA()
	if setUpA then
		return
	end
	setUpA = true
	local seed = seedBase()
	seed[`{ROOT}/rafts/R0010/R0010.md`] = DOC10
	seed[`{ROOT}/rafts/R0020/R0020.md`] = raftDoc("R0020", "c0030")
	seed[`{ROOT}/rafts/R0040/R0040.md`] = raftDoc("R0040", "c0060, c0070")
	seed[`{ROOT}/rafts/R0050/R0050.md`] = raftDoc("R0050", "c0040, c0045")
	for _, id in { "R0010", "R0020", "R0040", "R0050" } do
		seed[`{ROOT}/rafts/{id}/check.sh`] = CHECK
	end
	itemFiles(seed, "c0010", issue("c0010", "R0010", "## Design\none\n"))
	itemFiles(seed, "c0020", issue("c0020", "R0010", ""))
	itemFiles(seed, "c0025", issue("c0025", "R0010", "## Design\none\n"))
	itemFiles(seed, "c0030", issue("c0030", "R0020", ""))
	itemFiles(seed, "c0040", issue("c0040", "R0050", "## Design\none\n"))
	itemFiles(seed, "c0045", issue("c0045", "R0050", ""))
	itemFiles(seed, "c0050", issue("c0050", "", ""))
	itemFiles(seed, "c0060", issue("c0060", "R0040", ""))
	itemFiles(seed, "c0070", issue("c0070", "R0040", "## Design\none\n"))
	local made, _ignored, madeEnv = build("f0399-land-github.com", seed)
	f, env = made, madeEnv
	-- the seed stamps every design-ready issue; these are the ones with no approval
	for _, id in { "c0020", "c0030", "c0050" } do
		fs.removeFile(`{f.main}/{ROOT}/issues/{id}/approval.md`)
	end
	commitAll(f.main, "no approval for c0020, c0030 and c0050")
	git(f.main, { "push", "-q", "origin", "HEAD:main" })
	wtPrep = `{f.base}/prep`
	git(f.main, { "worktree", "add", "-q", "-b", "prep-f0399", wtPrep, "HEAD" })
end

local function layerWork(dir: string, file: string, id: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	commitAll(dir, `{id} work`)
end

-- another terminal pushes a commit that edits origin/main's tree through `edit`, which gets the clone's folder
local function elsewhere(message: string, edit: (string) -> ())
	git(f.other, { "pull", "-q", "origin", "main" })
	edit(f.other)
	git(f.other, { "add", "-A" })
	git(f.other, { "commit", "-qm", message })
	git(f.other, { "push", "-q", "origin", "HEAD:main" })
	git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
end

return t.spec("f0399: guesses, approval at the landing, and the picks for an issue", function(it)
	it(
		"guess writes guesses.md, numbers the next one, commits nothing, and refuses the main checkout, a bad step and an empty field",
		function()
			setupA()
			local dir = `{wtPrep}/{ROOT}/issues/c0050`
			local head = git(wtPrep, { "rev-parse", "HEAD" })
			local one = tr(wtPrep, guessArgs("c0050", "design", "Which file holds it.", "One list."))
			t.expect(
				has(
					expectOk(one, "guess c0050 --step design"),
					"G1 recorded for c0050: commit it with your work"
				)
			).toBe(true)
			t.expect(fs.readFile(`{dir}/guesses.md`))
				.toBe(`# guesses\n- G1 (design, {TODAY}): Which file holds it. Chose: Two. Why: One list.\n`)
			local two = tr(wtPrep, guessArgs("c0050", "build", "Second open.", "Because."))
			t.expect(
				has(
					expectOk(two, "guess c0050 --step build"),
					"G2 recorded for c0050: commit it with your work"
				)
			).toBe(true)
			t.expect(fs.readFile(`{dir}/guesses.md`)).toBe(
				`# guesses\n- G1 (design, {TODAY}): Which file holds it. Chose: Two. Why: One list.\n`
					.. `- G2 (build, {TODAY}): Second open. Chose: Two. Why: Because.\n`
			)
			t.expect(has(git(wtPrep, { "status", "--porcelain" }), `{ROOT}/issues/c0050/guesses.md`))
				.toBe(true)
			t.expect(git(wtPrep, { "rev-parse", "HEAD" })).toBe(head)

			local text = fs.readFile(`{dir}/guesses.md`)
			local main = tr(f.main, guessArgs("c0050", "design", "Elsewhere.", "Never."))
			t.expect(main.ok).toBe(false)
			t.expect(has(say(main), "must run inside a worktree")).toBe(true)
			local review = tr(wtPrep, guessArgs("c0050", "review", "Bad step.", "Never."))
			t.expect(review.ok).toBe(false)
			t.expect(has(say(review), "guess: ")).toBe(true)
			local empty = tr(wtPrep, guessArgs("c0050", "design", "Empty why.", ""))
			t.expect(empty.ok).toBe(false)
			t.expect(has(say(empty), "guess: ")).toBe(true)
			t.expect(fs.readFile(`{dir}/guesses.md`)).toBe(text)
		end
	)

	it(
		"guesses prints each member's guesses with its approval state, and --check fails on a malformed file",
		function()
			setupA()
			if git(wtPrep, { "status", "--porcelain" }) ~= "" then
				commitAll(wtPrep, "c0050 guesses")
			end
			local one = `- G1 (design, {TODAY}): Which file holds it. Chose: Two. Why: One list.`
			local two = `- G2 (build, {TODAY}): Second open. Chose: Two. Why: Because.`
			local before = expectOk(tr(wtPrep, { "guesses", "c0050" }), "guesses c0050")
			t.expect(lines(before)).toEqual({ "c0050: 2 guesses, not approved", one, two })

			local made = human(wtPrep, { "approve", "c0050" })
			if not made.ok then
				error(`fixture step ./zn approve c0050 failed: {say(made)}`)
			end
			local after = expectOk(tr(wtPrep, { "guesses", "c0050" }), "guesses c0050")
			t.expect(lines(after)).toEqual({ "c0050: 2 guesses, approved", one, two })

			local raft = lines(expectOk(tr(wtPrep, { "guesses", "R0010" }), "guesses R0010"))
			t.expect(raft).toEqual({
				"c0010: 0 guesses, approved",
				"c0020: 0 guesses, not approved",
				"c0025: 0 guesses, approved",
			})

			local clean = tr(wtPrep, { "guesses", "c0050", "--check" })
			t.expect(clean.ok).toBe(true)
			t.expect(clean.stdout).toBe("")
			local bad = `{wtPrep}/{ROOT}/issues/c0020/guesses.md`
			fs.writeFile(bad, `# guesses\n- G2 (design, {TODAY}): Skips G1. Chose: x. Why: y.\n`)
			local broken = tr(wtPrep, { "guesses", "c0020", "--check" })
			fs.removeFile(bad)
			t.expect(broken.code).toBe(1)
			t.expect(broken.stdout).toBe("")
			t.expect(has(broken.stderr, `{ROOT}/issues/c0020/guesses.md: `)).toBe(true)
		end
	)

	it("approve --publish publishes an approval of a backlog issue that has guesses", function()
		setupA()
		-- the guesses are on origin/main (merged), the approval is only in the worktree
		t.expect(fs.isFile(`{wtPrep}/{ROOT}/issues/c0050/guesses.md`)).toBe(true)
		git(wtPrep, { "push", "-q", "origin", "HEAD~1:main" })
		local published = human(wtPrep, { "approve", "c0050", "--publish" })
		t.expect(has(expectOk(published, "approve c0050 --publish"), "published c0050")).toBe(true)
		local file = onOrigin(`{ROOT}/issues/c0050/approval.md`) or ""
		t.expect(file ~= "").toBe(true)
		t.expect(has(file, "guesses=")).toBe(true)
		t.expect(has(onOrigin(`{ROOT}/issues/c0050/guesses.md`) or "", "- G2 (build,")).toBe(true)
	end)

	it(
		"ready accepts a raft with an unapproved member and records Lands: approved in its ready commit, leaving the raft document as it was",
		function()
			setupA()
			local r = tr(f.main, { "ready", "R0010" })
			readied = r.ok
			t.expect(has(expectOk(r, "ready R0010 (c0020 has no approval)"), "readied R0010")).toBe(true)
			t.expect(has(readyBody("R0010"), "Lands: approved")).toBe(true)
			t.expect(has(readyBody("R0010"), "On:")).toBe(false)
			local doc = onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) or ""
			t.expect(withoutStatus(doc)).toBe(withoutStatus(DOC10))
			t.expect(onOrigin(`{ROOT}/issues/active/c0020/c0020.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/active/c0020/approval.md`)).toBe(nil)
			t.expect(onOrigin(`{ROOT}/issues/active/c0010/approval.md`) ~= nil).toBe(true)
		end
	)

	it("ready under ZN_DISPATCH refuses a member with no approval and records nothing", function()
		setupA()
		local before = git(f.origin, { "rev-parse", "main" })
		local r = tr(f.main, { "ready", "R0020" }, { ZN_DISPATCH = "1" })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "c0030 has no approval")).toBe(true)
		t.expect(git(f.origin, { "rev-parse", "main" })).toBe(before)
		t.expect(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`)).toBe(nil)
		-- the same raft outside the dispatcher is accepted, and only then is a trailer recorded
		expectOk(tr(f.main, { "ready", "R0020" }), "ready R0020 (outside the dispatcher)")
		t.expect(has(readyBody("R0020"), "Lands: approved")).toBe(true)
	end)

	it(
		"ready refuses an approved member whose design changed and accepts one whose guesses alone changed",
		function()
			setupA()
			local doc = `{ROOT}/issues/c0040/c0040.md`
			local original = fs.readFile(`{f.main}/{doc}`)
			elsewhere("the design of c0040 edited", function(dir)
				fs.writeFile(`{dir}/{doc}`, (string.gsub(original, "\none\n", "\ntwo\n")))
			end)
			local refusal = tr(f.main, { "ready", "R0050" })
			t.expect(refusal.ok).toBe(false)
			t.expect(has(say(refusal), "contract changed since approval")).toBe(true)
			t.expect(onOrigin(`{ROOT}/rafts/active/R0050/R0050.md`)).toBe(nil)

			elsewhere("c0040 as approved, a guess for c0045", function(dir)
				fs.writeFile(`{dir}/{doc}`, original)
				write(
					dir,
					`{ROOT}/issues/c0045/guesses.md`,
					`# guesses\n- G1 (design, {TODAY}): Open. Chose: Two. Why: Because.\n`
				)
			end)
			local r = tr(f.main, { "ready", "R0050" })
			t.expect(has(expectOk(r, "ready R0050 (guesses alone changed)"), "readied R0050")).toBe(true)
			t.expect(has(readyBody("R0050"), "Lands: approved")).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/active/c0045/guesses.md`) ~= nil).toBe(true)
		end
	)

	it("finish on a lands raft goes on and names the unapproved member", function()
		setupA()
		t.expect(readied).toBe(true)
		wt = zn(f.main, { "worktree", "R0010" })
		zn(wt, { "start", "R0010" })
		write(wt, `{ROOT}/rafts/active/R0010/final-review-001.md`, "# Final Review 001\n\nVerdict: approve\n")
		write(wt, `{ROOT}/rafts/active/R0010/review-001.md`, "# Review 001\n\nVerdict: approve\n")
		layerWork(wt, "alpha", "c0010")
		local first = tr(wt, { "finish", "c0010" })
		t.expect(first.ok).toBe(true)
		t.expect(has(say(first), "note: c0010")).toBe(false)
		zn(wt, { "start", "R0010" })
		layerWork(wt, "beta", "c0020")
		local second = tr(wt, { "finish", "c0020" })
		built = second.ok
		expectOk(second, "finish c0020")
		local out = say(second)
		t.expect(has(out, "note: c0020 is not approved (no approval)")).toBe(true)
		t.expect(has(out, "will wait for ./zn approve c0020")).toBe(true)
		t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0020: c0020 title")
		-- the third member's design is edited on its layer before it is finished
		zn(wt, { "start", "R0010" })
		local doc = `{wt}/{ROOT}/issues/active/c0025/c0025.md`
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "\none\n", "\ntwo\n")))
		layerWork(wt, "gamma", "c0025")
		local third = tr(wt, { "finish", "c0025" })
		built = built and third.ok
		t.expect(has(say(third), "note: c0025 is not approved (changed: design)")).toBe(true)
	end)

	it("done on a lands raft lands nothing and names every member whose approval does not hold", function()
		setupA()
		t.expect(built).toBe(true)
		-- the approved member drifts: a guess recorded for it on the top layer, committed
		expectOk(tr(wt, guessArgs("c0010", "build", "Retry count.", "A real second attempt.")), "guess c0010")
		commitAll(wt, "c0010: a guess")
		seal.trace(wt, "R0010")
		local tipBefore = git(f.origin, { "rev-parse", "main" })
		waitLine = say(tr(f.main, { "work", "next", "R0010" }))
		local r = tr(wt, { "done", "R0010" })
		refused = not r.ok
		t.expect(r.ok).toBe(false)
		local err = say(r)
		t.expect(has(err, "R0010 waits for approval:")).toBe(true)
		t.expect(has(err, "c0020 (no approval)")).toBe(true)
		t.expect(has(err, "c0010 (changed: guesses)")).toBe(true)
		t.expect(has(err, "./zn guesses R0010")).toBe(true)
		t.expect(git(f.origin, { "rev-parse", "main" })).toBe(tipBefore)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
	end)

	it("a design edited on the layer after its approval makes done wait, naming design", function()
		setupA()
		t.expect(refused).toBe(true)
		local r = tr(wt, { "done", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "c0025 (changed: design)")).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
	end)

	it("a pushed guess that is removed is refused by finish and done", function()
		setupA()
		t.expect(refused).toBe(true)
		expectOk(tr(wt, guessArgs("c0025", "build", "Naming.", "Matches the file.")), "guess c0025")
		commitAll(wt, "c0025: a guess")
		git(wt, { "push", "-q" })
		local branch = git(wt, { "branch", "--show-current" })
		local file = `{wt}/{ROOT}/issues/active/c0025/guesses.md`
		fs.writeFile(file, "# guesses\n")
		commitAll(wt, "c0025: the guess dropped")
		local note = "guesses.md no longer holds G1 as it was pushed: a guess is never removed or changed"
		local finished = tr(wt, { "finish", "c0025" })
		t.expect(finished.ok).toBe(false)
		t.expect(has(say(finished), note)).toBe(true)
		local landed = tr(wt, { "done", "R0010" })
		t.expect(landed.ok).toBe(false)
		t.expect(has(say(landed), note)).toBe(true)
		git(wt, { "fetch", "-q", "origin" })
		git(wt, { "reset", "-q", "--hard", `origin/{branch}` })
		t.expect(has(fs.readFile(file), "- G1 (build,")).toBe(true)
	end)

	it(
		"approve for an active issue runs only on the top layer and pushes it, the layer is still finished, and a later guess makes done wait again, naming guesses",
		function()
			setupA()
			t.expect(refused).toBe(true)
			local top = git(wt, { "branch", "--show-current" })
			t.expect(top).toBe("R0010/3/c0025")
			git(wt, { "switch", "-q", "R0010/1/c0010" })
			local below = human(wt, { "approve", "c0010" })
			git(wt, { "switch", "-q", top })
			t.expect(below.ok).toBe(false)
			t.expect(has(say(below), `c0010 is active in R0010: run ./zn approve c0010 on {top}`)).toBe(true)

			for _, id in { "c0010", "c0020", "c0025" } do
				local r = human(wt, { "approve", id })
				expectOk(r, `approve {id} (on the top layer)`)
				local last = lines(r.stdout)
				t.expect(last[#last]).toBe(`It lands with R0010: pushed to {top}, nothing to publish.`)
			end
			approvedAll = true
			git(wt, { "fetch", "-q", "origin" })
			local pushed = git(wt, { "log", "--format=%s", `origin/{top}` })
			for _, id in { "c0010", "c0020", "c0025" } do
				t.expect(has(pushed, `tracker: approve {id}`)).toBe(true)
			end
			local published = human(wt, { "approve", "c0010", "--publish" })
			t.expect(published.ok).toBe(false)
			t.expect(has(say(published), "c0010 is active in R0010: its approval lands with the raft"))
				.toBe(true)
			git(f.other, { "fetch", "-q", "origin" })
			local stack = zn(f.other, { "stack", "R0010" })
			t.expect(has(stack, "1 R0010/1/c0010 c0010 finished")).toBe(true)
			t.expect(has(stack, "2 R0010/2/c0020 c0020 finished")).toBe(true)
			t.expect(has(stack, "3 R0010/3/c0025 c0025 finished")).toBe(true)

			expectOk(
				tr(wt, guessArgs("c0010", "build", "Late choice.", "Found while reviewing.")),
				"guess c0010"
			)
			commitAll(wt, "c0010: a later guess")
			git(wt, { "push", "-q" })
			local r = tr(wt, { "done", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "c0010 (changed: guesses)")).toBe(true)
			t.expect(has(say(r), "c0020 (")).toBe(false)
			t.expect(has(say(r), "c0025 (")).toBe(false)
		end
	)

	it("done lands the raft once every approval holds, with approval.md and guesses.md in done/", function()
		setupA()
		t.expect(approvedAll).toBe(true)
		expectOk(human(wt, { "approve", "c0010" }), "approve c0010 again")
		local landed = tr(wt, { "done", "R0010" })
		t.expect(has(expectOk(landed, "done R0010"), "landed R0010")).toBe(true)
		for _, id in { "c0010", "c0020", "c0025" } do
			t.expect(onOrigin(`{ROOT}/issues/done/{id}/approval.md`) ~= nil).toBe(true)
		end
		local guesses = onOrigin(`{ROOT}/issues/done/c0010/guesses.md`) or ""
		t.expect(has(guesses, "- G1 (build,")).toBe(true)
		t.expect(has(guesses, "- G2 (build,")).toBe(true)
		t.expect(has(onOrigin(`{ROOT}/issues/done/c0025/guesses.md`) or "", "- G1 (build,")).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)
	end)

	it(
		"a raft whose ready commit has no Lands: trailer finishes and lands by today's approval rule",
		function()
			setupA()
			-- a raft readied before trailers existed: ready under the dispatcher writes no trailer (every member is approved),
			-- then one approval is gone from origin/main, as on the old rafts
			zn(f.main, { "ready", "R0040" }, { ZN_DISPATCH = "1" })
			t.expect(has(readyBody("R0040"), "Lands:")).toBe(false)
			elsewhere("c0060 has no approval on main", function(dir)
				git(dir, { "rm", "-q", `{ROOT}/issues/active/c0060/approval.md` })
			end)

			local wt8 = zn(f.main, { "worktree", "R0040" })
			zn(wt8, { "start", "R0040" })
			write(
				wt8,
				`{ROOT}/rafts/active/R0040/final-review-001.md`,
				"# Final Review 001\n\nVerdict: approve\n"
			)
			layerWork(wt8, "delta", "c0060")
			zn(wt8, { "finish", "c0060" })
			zn(wt8, { "start", "R0040" })
			local doc = `{wt8}/{ROOT}/issues/active/c0070/c0070.md`
			local text = fs.readFile(doc)
			fs.writeFile(doc, (string.gsub(text, "\none\n", "\ntwo\n")))
			commitAll(wt8, "design drifted")
			local drifted = tr(wt8, { "finish", "c0070" })
			t.expect(drifted.ok).toBe(false)
			t.expect(has(say(drifted), "contract changed since approval")).toBe(true)
			fs.writeFile(doc, text)
			layerWork(wt8, "epsilon", "c0070")
			zn(wt8, { "finish", "c0070" })
			seal.trace(wt8, "R0040")
			local landed = zn(wt8, { "done", "R0040" })
			t.expect(has(landed, "landed R0040")).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0060/c0060.md`) ~= nil).toBe(true)
			t.expect(onOrigin(`{ROOT}/issues/done/c0060/approval.md`)).toBe(nil)
			t.expect(onOrigin(`{ROOT}/issues/done/c0070/approval.md`) ~= nil).toBe(true)
		end
	)

	-- Fixture B: Guessed bullets -------------------------------------------------------------------------------------
	local fb: trackerfix.Fixture = nil :: any
	local setUpB = false
	local wtB = ""
	local envB: { [string]: string } = {}

	local function trB(dir: string, args: { string }): fixture.Result
		return trackerfix.tr(fb, dir, args, envB)
	end

	local function znB(dir: string, args: { string }): string
		local r = trB(dir, args)
		if not r.ok then
			error(`fixture step ./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
		end
		return r.stdout
	end

	local REVIEW = "# Design Review 001\n\n### F1 [high] The finding\nIt is wrong.\n\nVerdict: revise\n"
	local REFUTE = "# Design Refute 001\n\n- F1: refuted: the reviewer is mistaken.\n"
	local ONE = `# guesses\n- G1 (design, 2026-11-16): The finding. Chose: Keep it. Why: Evidence.\n`

	local function opened(guessed: string): string
		return "\n## Open to the human\n- F1: the finding. Answer: none. Decision: which way?\n"
			.. `  Guessed (agent, 2026-11-16): {guessed}\n`
	end

	local function withReview(seed: { [string]: string }, id: string, doc: string, guesses: string?)
		itemFiles(seed, id, doc)
		seed[`{ROOT}/issues/{id}/design-review-001.md`] = REVIEW
		seed[`{ROOT}/issues/{id}/design-refute-001.md`] = REFUTE
		if guesses then
			seed[`{ROOT}/issues/{id}/guesses.md`] = guesses
		end
	end

	local function newIssue(id: string, extra: string, body: string): string
		return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-16\n{extra}status: {NEW}\n---\n\n# {id}\n\n{CAPTURED}{body}`
	end

	local function setupB()
		if setUpB then
			return
		end
		setUpB = true
		local seed = seedBase()
		withReview(seed, "c0080", issue("c0080", "R0080", "") .. opened("G1"), ONE)
		withReview(seed, "c0081", issue("c0081", "R0081", "") .. opened("G7"), ONE)
		itemFiles(seed, "c0082", issue("c0082", "R0082", ""))
		for _, row in { { "R0080", "c0080" }, { "R0081", "c0081" } } do
			seed[`{ROOT}/rafts/{row[1]}/{row[1]}.md`] = raftDoc(row[1], row[2])
			seed[`{ROOT}/rafts/{row[1]}/check.sh`] = CHECK
		end
		seed[`{ROOT}/rafts/R0082/R0082.md`] = raftDoc("R0082", "c0082", opened("c0082 G9"))
		seed[`{ROOT}/rafts/R0082/check.sh`] = CHECK
		for _, id in { "c0070", "c0071", "c0072" } do
			itemFiles(seed, id, newIssue(id, "", ""))
		end
		itemFiles(seed, "c0090", newIssue("c0090", "idea: challenged\n", opened("G1")))
		seed[`{ROOT}/issues/c0090/idea-review-001.md`] = "# Idea Review 001\n\nVerdict: revise\n"
		local made, _ignored, madeEnv = build("f0399-land-guessed-github.com", seed)
		fb, envB = made, madeEnv
		wtB = `{fb.base}/prep`
		git(fb.main, { "worktree", "add", "-q", "-b", "prep-guessed", wtB, "HEAD" })
		for _, id in { "c0070", "c0071", "c0072" } do
			znB(wtB, { "status", id, "preparing" })
		end
		-- the designs the claims carry: ready, with a refuted finding answered by a Guessed line
		for _, row in { { "c0070", "G1" }, { "c0071", "G7" }, { "c0072", "see above" } } do
			local id, named = row[1], row[2]
			local dir = `{wtB}/{ROOT}/issues/{id}`
			local doc = fs.readFile(`{dir}/{id}.md`)
			doc = string.gsub(doc, "design: draft", "design: ready") .. opened(named)
			fs.writeFile(`{dir}/{id}.md`, doc)
			fs.writeFile(`{dir}/design-review-001.md`, REVIEW)
			fs.writeFile(`{dir}/design-refute-001.md`, REFUTE)
			fs.writeFile(`{dir}/guesses.md`, ONE)
		end
		commitAll(wtB, "the designs")
	end

	it(
		"a Guessed bullet passes status prepared, ready and approve, and still stops status preparing",
		function()
			setupB()
			local idea = trB(wtB, { "status", "c0090", "preparing" })
			t.expect(idea.ok).toBe(false)
			t.expect(has(say(idea), "open to the human")).toBe(true)
			local moved = trB(wtB, { "status", "c0070", "prepared" })
			expectOk(moved, "status c0070 prepared")
			t.expect(has(fs.readFile(`{wtB}/{ROOT}/issues/c0070/c0070.md`), "status: prepared-")).toBe(true)
			local approved = human(wtB, { "approve", "c0080" })
			t.expect(has(expectOk(approved, "approve c0080"), "approved c0080")).toBe(true)
			local ready = trB(fb.main, { "ready", "R0080" })
			t.expect(has(expectOk(ready, "ready R0080"), "readied R0080")).toBe(true)
		end
	)

	it(
		"a Guessed line naming no guess, or one that does not exist, is refused by status prepared and by ready",
		function()
			setupB()
			local missing = trB(wtB, { "status", "c0071", "prepared" })
			t.expect(missing.ok).toBe(false)
			t.expect(
				has(say(missing), "F1's Guessed line names c0071 G7, which is not in c0071's guesses.md")
			)
				.toBe(true)
			t.expect(has(fs.readFile(`{wtB}/{ROOT}/issues/c0071/c0071.md`), "status: prepared-")).toBe(false)
			local none = trB(wtB, { "status", "c0072", "prepared" })
			t.expect(none.ok).toBe(false)
			t.expect(has(say(none), "F1's Guessed line names")).toBe(true)
			t.expect(has(say(none), "which is not in c0072's guesses.md")).toBe(true)
			local ready = trB(fb.main, { "ready", "R0081" })
			t.expect(ready.ok).toBe(false)
			t.expect(has(say(ready), "F1's Guessed line names c0081 G7, which is not in c0081's guesses.md"))
				.toBe(true)
			local raft = trB(fb.main, { "ready", "R0082" })
			t.expect(raft.ok).toBe(false)
			t.expect(has(say(raft), "F1's Guessed line names c0082 G9, which is not in c0082's guesses.md"))
				.toBe(true)
		end
	)

	-- Fixture C: what work next picks for an issue --------------------------------------------------------------------
	it(
		"work next reads the issue facts: draft for a challenged issue, rafting for a prepared one, and wait for a built raft that is not approved",
		function()
			local seed = seedBase()
			itemFiles(seed, "c0100", newIssue("c0100", "idea: challenged\nsize: 300\n", ""))
			seed[`{ROOT}/issues/c0100/idea-review-001.md`] = "# Idea Review 001\n\nVerdict: approve\n"
			local fc, _ignored, envC = build("f0399-land-pick-github.com", seed)
			local function next(args: { string }): fixture.Result
				local argv = { "work", "next" }
				for _, a in args do
					table.insert(argv, a)
				end
				return trackerfix.tr(fc, fc.main, argv, envC)
			end
			local only = next({})
			t.expect(has(expectOk(only, "work next"), "c0100: draft - ")).toBe(true)
			local named = next({ "c0100" })
			t.expect(has(expectOk(named, "work next c0100"), "c0100: draft - ")).toBe(true)

			-- a prepared, sized issue in no raft comes before the issue to design
			trackerfix.elsewhere(fc, {
				[`{ROOT}/issues/c0110/c0110.md`] = issue("c0110", "", "", "size: 300\n"),
				[`{ROOT}/issues/c0110/check.sh`] = CHECK,
			}, "a prepared issue")
			git(fc.main, { "pull", "-q", "--ff-only", "origin", "main" })
			local both = next({})
			t.expect(has(expectOk(both, "work next"), "c0110: rafting - ")).toBe(true)
			local again = next({ "c0100" })
			t.expect(has(expectOk(again, "work next c0100"), "c0100: draft - ")).toBe(true)

			-- the raft of the walked cases, built and not approved, waits (recorded when done refused it)
			t.expect(has(waitLine, "R0010: wait - ")).toBe(true)
			t.expect(has(waitLine, "c0010")).toBe(true)
			t.expect(has(waitLine, "c0020")).toBe(true)
		end
	)

	it(
		"work next records the session that carries an item, and an unnamed call from another session does not resume it",
		function()
			setupA()
			t.expect(onOrigin(`{ROOT}/rafts/active/R0020/R0020.md`) ~= nil).toBe(true)
			-- the running session is found from CLAUDE_CODE_SESSION_ID and a transcript under $HOME/.claude/projects/<cwd>
			local home = `{f.base}/home`
			local cwd = fixture.physical(f.main) or f.main
			local projects = `{home}/.claude/projects/{string.gsub(cwd, "/", "-")}`
			fs.writeDir(projects)
			-- the pinned lune is a rokit shim that reads its tools from HOME
			process.exec("ln", { "-s", `{process.env.HOME}/.rokit`, `{home}/.rokit` })
			for _, sid in { "session-one", "session-two" } do
				write(projects, `{sid}.jsonl`, '{"type":"user","timestamp":"2026-11-16T10:00:00.000Z"}\n')
			end
			local function as(sid: string, args: { string }): fixture.Result
				local argv = { "work", "next" }
				for _, a in args do
					table.insert(argv, a)
				end
				return tr(f.main, argv, { HOME = home, CLAUDE_CODE_SESSION_ID = sid })
			end
			wt20 = zn(f.main, { "worktree", "R0020" })
			zn(wt20, { "start", "R0020" })

			local carriers = `{f.main}/.cache/work/carriers.tsv`
			local named = as("session-one", { "R0020" })
			t.expect(named.ok).toBe(true)
			t.expect(fs.isFile(carriers)).toBe(true)
			local line = fs.readFile(carriers)
			t.expect(string.match(line, "^R0020\t[^\t\n]+\t%d+\n$") ~= nil).toBe(true)
			local who = string.match(line, "^R0020\t([^\t\n]+)\t")

			local other = as("session-two", {})
			t.expect(has(say(other), "Resuming R0020")).toBe(false)
			-- the other session is offered another held raft and records it; R0020's line is what must not change
			t.expect(has(fs.readFile(carriers), line)).toBe(true)
			local own = as("session-one", {})
			t.expect(has(say(own), "Resuming R0020: you hold it and no live session carries it.")).toBe(true)

			-- a carrier that last asked more than six hours ago no longer holds it
			fs.writeFile(carriers, `R0020\t{who}\t{os.time() - 7 * 3600}\n`)
			local stale = as("session-two", {})
			t.expect(has(say(stale), "Resuming R0020: you hold it and no live session carries it."))
				.toBe(true)
			local after = fs.readFile(carriers)
			t.expect(string.match(after, "^R0020\t[^\t\n]+\t%d+\n") ~= nil).toBe(true)
			t.expect(after ~= `R0020\t{who}\t{os.time() - 7 * 3600}\n`).toBe(true)
		end
	)

	it("the usage text lists guess, guesses, ready --on and the issue id for work", function()
		setupA()
		local usage = fixture.exec(f.main, "./zn", {})
		t.expect(usage.ok).toBe(true)
		t.expect(has(usage.stdout, "guess <issue-id> --step")).toBe(true)
		t.expect(has(usage.stdout, "guesses <issue-id|R-id> [--check]")).toBe(true)
		t.expect(has(usage.stdout, "ready <R-id|issue-id> [--on <R-id>]")).toBe(true)
		t.expect(has(usage.stdout, "work [<R-id>|<issue-id>]")).toBe(true)
	end)
end)
