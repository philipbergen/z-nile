--!strict
-- f0421 AC8: `./zn work next <R>` names the review round. Real git in a fixture under .cache (a bare origin whose path
-- contains github.com, a `gh` stub), as f0399/land does. R0010 (an easy member) walks the code review: an unanswered
-- round, an answered serious round below the maximum, an answered low-only round, an answered round at the maximum and an
-- approval. R0020 (an easy and a risky member) is at its third final-review round. R0030 has a member with risk: high.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

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

local f: trackerfix.Fixture = nil :: any
local env: { [string]: string } = {}

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

local function zn(dir: string, args: { string }): string
	local r = tr(dir, args)
	if not r.ok then
		error(`fixture step ./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function layerWork(dir: string, file: string, id: string)
	write(dir, `pickman/src/{file}.luau`, `return "{file}"\n`)
	commitAll(dir, `{id} work`)
end

local wt10, wt20 = "", ""
local setUp = false

local function setup()
	if setUp then
		return
	end
	setUp = true
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		-- main's own limits: the final review takes the code maximum (4), not the design maximum (9) or the defaults
		[".models.toml"] = "[rounds]\ncode = { risky = 4 }\n",
	}
	local rafts: { [string]: string } = { R0010 = "c0010", R0020 = "c0020, c0021", R0030 = "c0030" }
	local risk: { [string]: string } = { c0010 = "easy", c0020 = "easy", c0021 = "risky", c0030 = "high" }
	for rid, members in rafts do
		seed[`{ROOT}/rafts/{rid}/{rid}.md`] = raftDoc(rid, members)
		seed[`{ROOT}/rafts/{rid}/check.sh`] = CHECK
		for mid in string.gmatch(members, "c%d+") do
			seed[`{ROOT}/issues/{mid}/{mid}.md`] = issue(mid, rid, "", `risk: {risk[mid]}\n`)
			seed[`{ROOT}/issues/{mid}/check.sh`] = CHECK
		end
	end
	local made, _log, madeEnv = build("f0421-work-github.com", seed)
	f, env = made, madeEnv
	for _, rid in { "R0010", "R0020", "R0030" } do
		zn(f.main, { "ready", rid })
	end
	wt10 = zn(f.main, { "worktree", "R0010" })
	zn(wt10, { "start", "R0010" })
	layerWork(wt10, "alpha", "c0010")
	zn(wt10, { "finish", "c0010" })
	wt20 = zn(f.main, { "worktree", "R0020" })
	zn(wt20, { "start", "R0020" })
	layerWork(wt20, "beta", "c0020")
	zn(wt20, { "finish", "c0020" })
	zn(wt20, { "start", "R0020" })
	layerWork(wt20, "gamma", "c0021")
	zn(wt20, { "finish", "c0021" })
end

local function next(raft: string): string
	return say(tr(f.main, { "work", "next", raft }))
end

local function put(wt: string, raft: string, files: { [string]: string }, message: string)
	for name, text in files do
		write(wt, `{ROOT}/rafts/active/{raft}/{name}`, text)
	end
	commitAll(wt, message)
end

local function review(n: number, verdict: string, ...: string): string
	local out = `# Review {n}\n\n`
	for i, sev in { ... } do
		out ..= `### F{i} [{sev}] a finding\nEvidence: x\n\n`
	end
	return out .. `Verdict: {verdict}\n`
end

local FIXED = "- F1: fixed abc; consequences: none\n"

return t.spec("f0421: work next names the review round", function(it)
	it("an unanswered changes review asks for its answer", function()
		setup()
		put(wt10, "R0010", { ["review-001.md"] = review(1, "changes", "medium") }, "review 1")
		local out = next("R0010")
		t.expect(has(out, "R0010: review - ")).toBe(true)
		t.expect(has(out, "Answer review-001.md in refute-001.md")).toBe(true)
		t.expect(has(out, "Do not guess a ruling under ./zn dispatch")).toBe(true)
		t.expect(has(out, "the last")).toBe(false)
	end)

	it("an answered serious round below the maximum files the next round, and says what it checks", function()
		setup()
		put(wt10, "R0010", { ["refute-001.md"] = FIXED }, "answer 1")
		local out = next("R0010")
		t.expect(has(out, "R0010: review - ")).toBe(true)
		t.expect(has(out, "run code review round 2 of at most 2")).toBe(true)
		-- F6: the reason names the previous files and the rule of a later round
		t.expect(has(out, "Read review-001.md and refute-001.md")).toBe(true)
		t.expect(has(out, "this round only checks the answers")).toBe(true)
		t.expect(has(out, "accept or re-raise each refutation")).toBe(true)
	end)

	it("a refutation of a serious round below the maximum files the next round with no ruling", function()
		setup()
		put(wt10, "R0010", { ["refute-001.md"] = "- F1: refuted: shown\n" }, "refute 1")
		t.expect(has(next("R0010"), "run code review round 2 of at most 2")).toBe(true)
		put(wt10, "R0010", { ["refute-001.md"] = FIXED }, "answer 1 again")
	end)

	it("an answered round with only low findings is settled: the next action is trace", function()
		setup()
		put(wt10, "R0010", { ["review-001.md"] = review(1, "changes", "low") }, "review 1 is low only")
		t.expect(has(next("R0010"), "R0010: trace - ")).toBe(true)
		-- refuted and not ruled: the settling round needs its ruling first (F4)
		put(wt10, "R0010", { ["refute-001.md"] = "- F1: refuted: shown\n" }, "refute 1")
		local rule = next("R0010")
		t.expect(has(rule, "R0010: review - ")).toBe(true)
		t.expect(has(rule, "list what is refuted or still open under ## Open to the human")).toBe(true)
		put(wt10, "R0010", { ["refute-001.md"] = FIXED }, "answer 1 fixed")
		put(wt10, "R0010", { ["review-001.md"] = review(1, "changes", "medium") }, "review 1 is medium again")
	end)

	it("an answered round at the maximum is settled and says so, and an approval settles", function()
		setup()
		put(wt10, "R0010", {
			["review-002.md"] = review(2, "changes", "high"),
			["refute-002.md"] = FIXED,
		}, "round 2, answered")
		local settled = next("R0010")
		t.expect(has(settled, "R0010: trace - ")).toBe(true)
		-- F9: the settled-at-the-maximum review asks for a guess
		t.expect(
			has(
				settled,
				"review-002.md settled at the maximum (round 2 of 2) with 1 serious findings answered"
			)
		)
			.toBe(true)
		t.expect(has(settled, "record it as a guess (./zn guess <issue> --step build)")).toBe(true)
		put(wt10, "R0010", { ["refute-002.md"] = "" }, "round 2, unanswered")
		local open = next("R0010")
		t.expect(has(open, "Answer review-002.md in refute-002.md")).toBe(true)
		t.expect(has(open, "This is round 2 of 2, the last")).toBe(true)
		put(wt10, "R0010", { ["review-002.md"] = review(2, "approve") }, "round 2 approves")
		local approved = next("R0010")
		t.expect(has(approved, "R0010: trace - ")).toBe(true)
		t.expect(has(approved, "settled at the maximum")).toBe(false)
	end)

	it("a review file with no verdict and no findings is malformed, not settled", function()
		setup()
		put(wt10, "R0010", { ["review-002.md"] = "# Review 2\n\nnothing here\n" }, "round 2 is no review")
		local out = next("R0010")
		t.expect(has(out, "R0010: review - ")).toBe(true)
		t.expect(
			has(out, "review-002.md has no Verdict line and no findings: fix the file or redo the round")
		)
			.toBe(true)
		put(wt10, "R0010", { ["review-002.md"] = review(2, "changes") }, "round 2 changes with no findings")
		t.expect(has(next("R0010"), "has a changes verdict and no findings")).toBe(true)
	end)

	it(
		"a ruling committed on the layer is seen from the main checkout and from the raft's worktree (F2)",
		function()
			setup()
			put(wt10, "R0010", {
				["review-002.md"] = review(2, "changes", "high"),
				["refute-002.md"] = "- F1: refuted: shown\n",
			}, "round 2, refuted")
			local before = next("R0010")
			t.expect(has(before, "list what is refuted or still open under ## Open to the human")).toBe(true)
			local doc = `{wt10}/{ROOT}/rafts/active/R0010/R0010.md`
			local text = fs.readFile(doc)
			text = (string.gsub(text, "\n*$", "\n"))
			fs.writeFile(
				doc,
				text
					.. "\n## Open to the human\n- review-002 F1: a finding. Answer: shown. Decision: accept. Ruled (user, 2026-11-20): accepted.\n"
			)
			commitAll(wt10, "rule round 2 on the layer")
			t.expect(has(next("R0010"), "R0010: trace - ")).toBe(true)
			t.expect(has(say(tr(wt10, { "work", "next", "R0010" })), "R0010: trace - ")).toBe(true)
		end
	)

	it("a raft with an easy and a risky member takes the risky maximum: final round 3", function()
		setup()
		put(wt20, "R0020", {
			["review-001.md"] = review(1, "approve"),
			["trace.md"] = "# trace\n",
			["final-review-001.md"] = review(1, "changes", "high"),
			["final-refute-001.md"] = FIXED,
			["final-review-002.md"] = review(2, "changes", "high"),
			["final-refute-002.md"] = FIXED,
		}, "two final rounds")
		local out = next("R0020")
		t.expect(has(out, "R0020: final-review - ")).toBe(true)
		t.expect(has(out, "Run final review round 3 of at most 4")).toBe(true)
	end)

	it(
		"a final round settles at the code maximum, and the last-round hint names the final review (N2, N3)",
		function()
			setup()
			put(wt20, "R0020", {
				["final-review-003.md"] = review(3, "changes", "high"),
				["final-refute-003.md"] = FIXED,
				["final-review-004.md"] = review(4, "changes", "high"),
			}, "final rounds 3 and 4")
			local open = next("R0020")
			t.expect(has(open, "R0020: final-review - ")).toBe(true)
			t.expect(has(open, "Answer final-review-004.md in final-refute-004.md")).toBe(true)
			t.expect(has(open, "This is round 4 of 4, the last")).toBe(true)
			t.expect(has(open, "(- final-review-004 F1: ...)")).toBe(true)
			-- answered at the code maximum (4): settled. The design maximum (9) would file round 5.
			put(wt20, "R0020", { ["final-refute-004.md"] = FIXED }, "final round 4 answered")
			local settled = next("R0020")
			t.expect(has(settled, "R0020: final-review - ")).toBe(false)
			t.expect(has(settled, "R0020: done - ")).toBe(true)
		end
	)

	it("a lower layer's older raft document never overrides the top layer's ruling (N4b)", function()
		setup()
		put(wt20, "R0020", { ["final-refute-004.md"] = "- F1: refuted: shown\n" }, "final round 4 refuted")
		t.expect(has(next("R0020"), "list what is refuted or still open under ## Open to the human"))
			.toBe(true)
		local doc = `{wt20}/{ROOT}/rafts/active/R0020/R0020.md`
		fs.writeFile(
			doc,
			(string.gsub(fs.readFile(doc), "\n*$", "\n"))
				.. "\n## Open to the human\n- final-review-004 F1: a finding. Answer: shown. Decision: accept. Ruled (user, 2026-11-20): ok.\n"
		)
		commitAll(wt20, "rule final round 4 on the top layer")
		t.expect(has(next("R0020"), "list what is refuted or still open")).toBe(false)
		-- a worktree on layer 1 holds the raft document as it was before the ruling
		local lower = ""
		for ref in
			string.gmatch(
				git(f.main, { "for-each-ref", "--format=%(refname:short)", "refs/heads" }),
				"[^\n]+"
			)
		do
			if string.match(ref, "^R0020/1/") then
				lower = ref
			end
		end
		t.expect(lower ~= "").toBe(true)
		local dir = `{f.base}/lower-layer`
		git(f.main, { "worktree", "add", "-q", dir, lower })
		local said = say(tr(dir, { "work", "next", "R0020" }))
		t.expect(has(said, "list what is refuted or still open")).toBe(false)
		t.expect(has(said, "R0020: ")).toBe(true)
	end)

	it("a member with risk: high stops the raft and names the problem", function()
		setup()
		local out = next("R0030")
		t.expect(has(out, "R0030: none - ")).toBe(true)
		t.expect(has(out, "risk is high: easy, normal or risky")).toBe(true)
	end)
end)
