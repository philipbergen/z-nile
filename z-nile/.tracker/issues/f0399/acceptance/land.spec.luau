--!strict
-- f0399 AC8 to AC12, AC16: guesses.md written by `./zn guess` and read by `./zn guesses`; a raft readied with
-- `lands: approved`, finished with a note, refused by `done` until every approval holds, still finished after
-- `./zn approve` on the layer, and landed with approval.md and guesses.md in done/; a raft with no `lands:` line lands by
-- today's rule; a Guessed bullet and the work next picks for an issue. Real git in fixtures under .cache (a bare origin
-- whose path contains github.com, a `gh` stub). Approving is the person's command: it runs under `script`, which gives it
-- a terminal (as approve.spec does).
--   fixture A (R0010: c0010 approved and c0020 not; c0050 alone; R0040: c0030 and c0040, readied then made a raft from
--   before `lands:`) carries cases 1 to 8 in order. Fixture B holds the Guessed bullets (cases 9, 10), fixture C the
--   issue picks of work next (case 11, with the raft's wait recorded in case 5). Case 8 passes on today's engine.
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

local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{string.gsub(
		issues,
		", ",
		"\n"
	)}\n`
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
	}
end

local function itemFiles(seed: { [string]: string }, id: string, doc: string)
	seed[`{ROOT}/issues/{id}/{id}.md`] = doc
	seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
end

-- Fixture A -----------------------------------------------------------------------------------------------------------
local f: trackerfix.Fixture = nil :: any
local setUpA = false
local env: { [string]: string } = {}
local wtPrep, wt, wt8 = "", "", ""
local readied, built, refused, approvedAll = false, false, false, false
local waitLine = ""
local tipBefore = ""

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

-- a setup command: today's engine runs it, so a failure is a broken fixture
local function zn(dir: string, args: { string }): string
	local r = tr(dir, args)
	if not r.ok then
		error(`fixture step ./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

-- an f0399 command: not built yet, so a failure is the assertion that it works
local function expectOk(r: fixture.Result, what: string): string
	if not r.ok then
		error(`expected ./zn {what} to succeed ({r.code}): {say(r)}`, 2)
	end
	return r.stdout
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

local function guessArgs(id: string, step: string, open: string, why: string): { string }
	return { "guess", id, "--step", step, "--open", open, "--chose", "Two.", "--why", why }
end

local function setupA()
	if setUpA then
		return
	end
	setUpA = true
	local seed = seedBase()
	seed[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`)
	seed[`{ROOT}/rafts/R0010/R0010.md`] = raftDoc("R0010", "c0010, c0020")
	seed[`{ROOT}/rafts/R0010/check.sh`] = CHECK
	seed[`{ROOT}/rafts/R0040/R0040.md`] = raftDoc("R0040", "c0030, c0040")
	seed[`{ROOT}/rafts/R0040/check.sh`] = CHECK
	itemFiles(seed, "c0010", issue("c0010", "R0010", ""))
	itemFiles(seed, "c0020", issue("c0020", "R0010", ""))
	itemFiles(seed, "c0030", issue("c0030", "R0040", ""))
	itemFiles(seed, "c0040", issue("c0040", "R0040", "## Design\none\n"))
	itemFiles(seed, "c0050", issue("c0050", "", ""))
	local made, _ignored, madeEnv = build("f0399-land-github.com", seed)
	f, env = made, madeEnv
	-- the seed stamps every design-ready issue; c0020 and c0050 are the ones with no approval
	for _, id in { "c0020", "c0050" } do
		fs.removeFile(`{f.main}/{ROOT}/issues/{id}/approval.md`)
	end
	commitAll(f.main, "no approval for c0020 and c0050")
	git(f.main, { "push", "-q", "origin", "HEAD:main" })
	wtPrep = `{f.base}/prep`
	git(f.main, { "worktree", "add", "-q", "-b", "prep-f0399", wtPrep, "HEAD" })
end

local function layerWork(dir: string, file: string, id: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	commitAll(dir, `{id} work`)
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
			local empty = tr(wtPrep, guessArgs("c0050", "design", "Empty why.", ""))
			t.expect(empty.ok).toBe(false)
			t.expect(fs.readFile(`{dir}/guesses.md`)).toBe(text)
		end
	)

	it(
		"guesses prints each member's guesses with its approval state, and --check fails on a malformed file",
		function()
			setupA()
			local dir = `{wtPrep}/{ROOT}/issues/c0050`
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
			t.expect(raft).toEqual({ "c0010: 0 guesses, approved", "c0020: 0 guesses, not approved" })

			local clean = tr(wtPrep, { "guesses", "c0050", "--check" })
			t.expect(clean.ok).toBe(true)
			t.expect(clean.stdout).toBe("")
			local bad = `{wtPrep}/{ROOT}/issues/c0020/guesses.md`
			fs.writeFile(bad, `# guesses\n- G2 (design, {TODAY}): Skips G1. Chose: x. Why: y.\n`)
			local broken = tr(wtPrep, { "guesses", "c0020", "--check" })
			fs.removeFile(bad)
			t.expect(broken.code).toBe(1)
			t.expect(broken.stdout).toBe("")
			t.expect(broken.stderr ~= "").toBe(true)
			t.expect(fs.isFile(dir .. "/guesses.md")).toBe(true)
		end
	)

	it("ready accepts a raft with an unapproved member and writes lands: approved", function()
		setupA()
		local r = tr(f.main, { "ready", "R0010" })
		readied = r.ok
		t.expect(has(expectOk(r, "ready R0010 (c0020 has no approval)"), "readied R0010")).toBe(true)
		git(f.origin, { "rev-parse", "main" })
		local doc = onOrigin(`{ROOT}/rafts/active/R0010/R0010.md`) or ""
		t.expect(has(doc, "\nlands: approved\n")).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/active/c0020/c0020.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/active/c0020/approval.md`)).toBe(nil)
		t.expect(onOrigin(`{ROOT}/issues/active/c0010/approval.md`) ~= nil).toBe(true)
	end)

	it("finish on a lands raft goes on and names the unapproved member", function()
		setupA()
		t.expect(readied).toBe(true)
		wt = zn(f.main, { "worktree", "R0010" })
		zn(wt, { "start", "R0010" })
		write(wt, `{ROOT}/rafts/active/R0010/final-review-001.md`, "# Final Review 001\n\nVerdict: approve\n")
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
	end)

	it("done on a lands raft lands nothing and names every member whose approval does not hold", function()
		setupA()
		t.expect(built).toBe(true)
		-- the approved member drifts: a guess recorded for it on the top layer, committed
		expectOk(tr(wt, guessArgs("c0010", "build", "Retry count.", "A real second attempt.")), "guess c0010")
		commitAll(wt, "c0010: a guess")
		seal.trace(wt, "R0010")
		tipBefore = git(f.origin, { "rev-parse", "main" })
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

	it(
		"after approve on the layer the layer is still finished and a later guess makes done wait again, naming guesses",
		function()
			setupA()
			t.expect(refused).toBe(true)
			for _, id in { "c0010", "c0020" } do
				local r = human(wt, { "approve", id })
				expectOk(r, `approve {id} (on the layer)`)
				local last = lines(r.stdout)
				t.expect(last[#last]).toBe("It lands with R0010: nothing to publish.")
			end
			approvedAll = true
			local published = human(wt, { "approve", "c0010", "--publish" })
			t.expect(published.ok).toBe(false)
			t.expect(has(say(published), "c0010 is active in R0010: its approval lands with the raft"))
				.toBe(true)
			git(wt, { "push", "-q" })
			git(f.other, { "fetch", "-q", "origin" })
			local stack = zn(f.other, { "stack", "R0010" })
			t.expect(has(stack, "1 R0010/1/c0010 c0010 finished")).toBe(true)
			t.expect(has(stack, "2 R0010/2/c0020 c0020 finished")).toBe(true)

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
		end
	)

	it("done lands the raft once every approval holds, with approval.md and guesses.md in done/", function()
		setupA()
		t.expect(approvedAll).toBe(true)
		expectOk(human(wt, { "approve", "c0010" }), "approve c0010 again")
		git(wt, { "push", "-q" })
		local landed = tr(wt, { "done", "R0010" })
		t.expect(has(expectOk(landed, "done R0010"), "landed R0010")).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/c0010/approval.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/c0020/approval.md`) ~= nil).toBe(true)
		local guesses = onOrigin(`{ROOT}/issues/done/c0010/guesses.md`) or ""
		t.expect(has(guesses, "- G1 (build,")).toBe(true)
		t.expect(has(guesses, "- G2 (build,")).toBe(true)
		t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`) ~= nil).toBe(true)
	end)

	it("a raft with no lands: line finishes and lands by today's approval rule", function()
		setupA()
		-- a raft readied before approvals moved to the landing: ready, then the lands: line and one approval gone
		zn(f.main, { "ready", "R0040" })
		git(f.other, { "pull", "-q", "origin", "main" })
		local rdoc = `{f.other}/{ROOT}/rafts/active/R0040/R0040.md`
		fs.writeFile(rdoc, (string.gsub(fs.readFile(rdoc), "lands: approved\n", "")))
		git(f.other, { "rm", "-q", `{ROOT}/issues/active/c0030/approval.md` })
		commitAll(f.other, "R0040 as readied before lands:")
		git(f.other, { "push", "-q", "origin", "HEAD:main" })
		git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })

		wt8 = zn(f.main, { "worktree", "R0040" })
		zn(wt8, { "start", "R0040" })
		write(
			wt8,
			`{ROOT}/rafts/active/R0040/final-review-001.md`,
			"# Final Review 001\n\nVerdict: approve\n"
		)
		layerWork(wt8, "gamma", "c0030")
		zn(wt8, { "finish", "c0030" })
		zn(wt8, { "start", "R0040" })
		local doc = `{wt8}/{ROOT}/issues/active/c0040/c0040.md`
		local text = fs.readFile(doc)
		fs.writeFile(doc, (string.gsub(text, "\none\n", "\ntwo\n")))
		commitAll(wt8, "design drifted")
		local drifted = tr(wt8, { "finish", "c0040" })
		t.expect(drifted.ok).toBe(false)
		t.expect(has(say(drifted), "contract changed since approval")).toBe(true)
		fs.writeFile(doc, text)
		layerWork(wt8, "delta", "c0040")
		zn(wt8, { "finish", "c0040" })
		seal.trace(wt8, "R0040")
		local landed = zn(wt8, { "done", "R0040" })
		t.expect(has(landed, "landed R0040")).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/c0030/c0030.md`) ~= nil).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/c0030/approval.md`)).toBe(nil)
		t.expect(onOrigin(`{ROOT}/issues/done/c0040/approval.md`) ~= nil).toBe(true)
	end)

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

	local ONE = `# guesses\n- G1 (design, 2026-11-16): The finding. Chose: Keep it. Why: Evidence.\n`

	local function setupB()
		if setUpB then
			return
		end
		setUpB = true
		local seed = seedBase()
		seed[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`)
		withReview(seed, "c0080", issue("c0080", "R0080", "") .. opened("G1"), ONE)
		seed[`{ROOT}/rafts/R0080/R0080.md`] = raftDoc("R0080", "c0080")
		seed[`{ROOT}/rafts/R0080/check.sh`] = CHECK
		itemFiles(seed, "c0070", newIssue("c0070", "", ""))
		itemFiles(seed, "c0071", newIssue("c0071", "", ""))
		itemFiles(seed, "c0090", newIssue("c0090", "idea: challenged\n", opened("G1")))
		seed[`{ROOT}/issues/c0090/idea-review-001.md`] = "# Idea Review 001\n\nVerdict: revise\n"
		local made, _ignored, madeEnv = build("f0399-land-guessed-github.com", seed)
		fb, envB = made, madeEnv
		wtB = `{fb.base}/prep`
		git(fb.main, { "worktree", "add", "-q", "-b", "prep-guessed", wtB, "HEAD" })
		for _, id in { "c0070", "c0071" } do
			znB(wtB, { "status", id, "preparing" })
		end
		-- the designs the two claims carry: ready, with a refuted finding answered by a Guessed line
		for _, row in { { "c0070", "G1" }, { "c0071", "G7" } } do
			local id, named = row[1], row[2]
			local dir = `{wtB}/{ROOT}/issues/{id}`
			local doc = fs.readFile(`{dir}/{id}.md`)
			doc = string.gsub(doc, "design: draft", "design: ready") .. opened(named)
			fs.writeFile(`{dir}/{id}.md`, doc)
			fs.writeFile(`{dir}/design-review-001.md`, REVIEW)
			fs.writeFile(`{dir}/design-refute-001.md`, REFUTE)
			fs.writeFile(`{dir}/guesses.md`, ONE)
		end
		commitAll(wtB, "the two designs")
	end

	it(
		"a Guessed bullet passes status prepared, ready and approve, and still stops status preparing",
		function()
			setupB()
			local idea = trB(wtB, { "status", "c0090", "preparing" })
			t.expect(idea.ok).toBe(false)
			t.expect(has(say(idea), "open to the human")).toBe(true)
			local moved = trB(wtB, { "status", "c0070", "prepared" })
			t.expect(has(expectOk(moved, "status c0070 prepared"), "")).toBe(true)
			t.expect(has(fs.readFile(`{wtB}/{ROOT}/issues/c0070/c0070.md`), "status: prepared-")).toBe(true)
			local approved = human(wtB, { "approve", "c0080" })
			t.expect(has(expectOk(approved, "approve c0080"), "approved c0080")).toBe(true)
			local ready = trB(fb.main, { "ready", "R0080" })
			t.expect(has(expectOk(ready, "ready R0080"), "readied R0080")).toBe(true)
		end
	)

	it("a Guessed line naming a guess that does not exist is refused", function()
		setupB()
		local r = trB(wtB, { "status", "c0071", "prepared" })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "F1's Guessed line names c0071 G7, which is not in c0071's guesses.md"))
			.toBe(true)
		t.expect(has(fs.readFile(`{wtB}/{ROOT}/issues/c0071/c0071.md`), "status: prepared-")).toBe(false)
	end)

	-- Fixture C: what work next picks for an issue --------------------------------------------------------------------
	it(
		"work next reads the issue facts: draft for a challenged issue, rafting for a prepared one, and wait for a built raft that is not approved",
		function()
			local seed = seedBase()
			seed[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`)
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
			local prepared = issue("c0110", "", "", "size: 300\n")
			trackerfix.elsewhere(fc, {
				[`{ROOT}/issues/c0110/c0110.md`] = prepared,
				[`{ROOT}/issues/c0110/check.sh`] = CHECK,
			}, "a prepared issue")
			git(fc.main, { "pull", "-q", "--ff-only", "origin", "main" })
			local both = next({})
			t.expect(has(expectOk(both, "work next"), "c0110: rafting - ")).toBe(true)
			local again = next({ "c0100" })
			t.expect(has(expectOk(again, "work next c0100"), "c0100: draft - ")).toBe(true)

			-- the raft of cases 3 to 5, built and not approved, waits (recorded when done refused it)
			t.expect(has(waitLine, "R0010: wait - ")).toBe(true)
			t.expect(has(waitLine, "c0010")).toBe(true)
			t.expect(has(waitLine, "c0020")).toBe(true)
		end
	)

	it("the usage text lists guess, guesses, ready --on and the issue id for work", function()
		setupA()
		local usage = fixture.exec(f.main, "./zn", {})
		t.expect(usage.ok).toBe(true)
		t.expect(has(usage.stdout, "guess <issue-id> --step")).toBe(true)
		t.expect(has(usage.stdout, "guesses <issue-id|R-id> [--check]")).toBe(true)
		t.expect(has(usage.stdout, "--on <R-id>")).toBe(true)
		t.expect(has(usage.stdout, "work [<R-id>|<issue-id>]")).toBe(true)
	end)
end)
