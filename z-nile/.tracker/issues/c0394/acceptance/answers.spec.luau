--!strict
-- c0394 AC9: a review answer may be `dropped <lesson id>: <why>` (a medium or low finding, the lesson must exist and
-- carry the not-worth-doing tag) or `added <id>: <why>` (a medium or low finding, <id> a waiting member of this raft),
-- and a `deferred <id>` already written is still accepted and called legacy. Driven through ./zn done in a real-git
-- fixture under .cache/c0394-answers (as tests/acceptance/c0038/deferred.spec.luau does, with an origin and a gh stub).
-- The fixture builds the added issue the way the tool should (new issue --raft --wait); when the tool does not yet make
-- it that way, the setup patches the same state in by hand, so each case fails only for its own rule.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local RAFT_DIR = `{ROOT}/rafts/active/R0010`
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local LESSONS = "z-nile/skills/zz-rules/lessons"
local FIXED = "fixed abc: ok; consequences: none"

local REVIEW = "# Review 001\n\n"
	.. "### F1 [high] a high finding\nEvidence: x\n\n"
	.. "### F2 [medium] a medium finding\nEvidence: y\n\n"
	.. "### F3 [low] a low finding\nEvidence: z\n\n"
	.. "### F4 [low] another low finding\nEvidence: w\n\n"
	.. "Verdict: changes requested\n"

local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local f: trackerfix.Fixture
local env: { [string]: string } = {}
local wt = ""
local added = "" -- the waiting member of R0010

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function tr(dir: string, args: { string }): fixture.Result
	return trackerfix.tr(f, dir, args, env)
end

local function zn(dir: string, args: { string }): string
	return must(tr(dir, args), "./zn " .. table.concat(args, " "))
end

local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

local function commitAll(dir: string, message: string)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-qm", message })
end

-- Writes the round's review and answers, commits them, finishes the layer, seals the trace and runs done.
local function attempt(answers: { string }): fixture.Result
	write(wt, `{RAFT_DIR}/final-review-001.md`, REVIEW)
	write(wt, `{RAFT_DIR}/final-refute-001.md`, table.concat(answers, "\n") .. "\n")
	commitAll(wt, "round")
	zn(wt, { "finish", "c0010" })
	-- a trace that cannot be built (a raft the tool does not yet understand) makes the done below say so
	pcall(seal.trace, wt, "R0010")
	return tr(wt, { "done", "R0010" })
end

-- A refusal names the finding and its reason, and nothing moved.
local function refused(r: fixture.Result, ...: string)
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		t.expect(has(say(r), needle)).toBe(true)
	end
	t.expect(onOrigin(`{RAFT_DIR}/R0010.md`) ~= nil).toBe(true)
	t.expect(onOrigin(`{ROOT}/rafts/done/R0010/R0010.md`)).toBe(nil)
end

return t.spec("c0394 done judges dropped and added answers, and calls deferred legacy", function(it)
	it("sets up a started raft with a waiting added issue and a backlog follow-up", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{fixture.physical(".")}/../.gitignore`),
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 200 quiet-copper-falcon\nraft 200 quiet-copper-falcon\n",
			[`{LESSONS}/idle-finding.md`] = "---\ntitle: An idle finding is not worth doing\nwhen: build\ntags: [finding, not-worth-doing]\ncheck: Is this finding the idle kind?\n---\nIt costs more than it saves.\n",
			[`{LESSONS}/plain-note.md`] = "---\ntitle: A plain note\nwhen: build\ntags: [finding]\ncheck: Is this a plain note?\n---\nNothing more.\n",
			[`{ROOT}/rafts/R0010/R0010.md`] = `---\nid: R0010\ntype: chore\ntitle: answers\nslug: answers\nsingle: false\nissues: [c0010]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\n`,
			[`{ROOT}/rafts/R0010/check.sh`] = CHECK,
			[`{ROOT}/issues/c0010/c0010.md`] = issue("c0010", "R0010"),
			[`{ROOT}/issues/c0010/check.sh`] = CHECK,
			[`{ROOT}/issues/c0010/acceptance/.gitkeep`] = "",
			[`{ROOT}/issues/c0030/c0030.md`] = issue("c0030", ""),
			[`{ROOT}/issues/c0030/check.sh`] = CHECK,
		}
		f = trackerfix.new("c0394-answers", seed)
		local bin, log = `{f.base}/bin`, `{f.base}/gh.log`
		fs.writeDir(bin)
		local script = `#!/bin/sh\necho "$*" >> "{log}"\n`
			.. 'case "$1 $2" in\n'
			.. '  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
			.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
			.. '  "pr edit") exit 0 ;;\n'
			.. '  "pr view") echo body; exit 0 ;;\n'
			.. "esac\nexit 0\n"
		fs.writeFile(`{bin}/gh`, script)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		zn(wt, { "start", "R0010" })
		local made = tr(wt, {
			"new",
			"issue",
			"c",
			"found-one",
			"--raft",
			"R0010",
			"--wait",
			"--found",
			"R0010 review-001 F3 high",
		})
		t.expect(made.ok).toBe(true)
		added = string.match(made.stdout, "(c%d%d%d%d) waits for approval")
			or string.match(made.stdout, "(c%d%d%d%d)/c%d%d%d%d%.md")
			or ""
		t.expect(added ~= "").toBe(true)
		-- patch what the tool should have written: waits: approval, found:, and the raft's issues: line
		local docPath = `{wt}/{ROOT}/issues/active/{added}/{added}.md`
		local doc = fs.readFile(docPath)
		if not has(doc, "\nwaits: approval\n") then
			fs.writeFile(
				docPath,
				(
					string.gsub(
						doc,
						"\nemergent: true\n",
						"\nemergent: true\nwaits: approval\nfound: R0010 review-001 F3 high\n",
						1
					)
				)
			)
		end
		local raftPath = `{wt}/{RAFT_DIR}/R0010.md`
		local raftText = fs.readFile(raftPath)
		local line = string.match(raftText, "\nissues: %[([^\n]*)%]") or ""
		if not has(line, added) then
			fs.writeFile(
				raftPath,
				(string.gsub(raftText, "\nissues: %[[^\n]*%]", `\nissues: [{line}, {added}]`, 1))
			)
		end
		commitAll(wt, "an added issue")
		-- emergent issue creation moves origin/main: put the layer back on it
		local branch = git(wt, { "branch", "--show-current" })
		git(wt, { "push", "-q" })
		zn(wt, { "restack", "R0010" })
		git(wt, { "fetch", "-q", "origin" })
		git(wt, { "reset", "-q", "--hard", `origin/{branch}` })
		write(wt, "pickman/src/alpha.luau", "alpha\n")
		commitAll(wt, "c0010 work")
	end)

	it("dropped needs a not-worth-doing lesson and a medium or low finding", function()
		-- a high finding cannot be dropped, even with a good lesson
		refused(
			attempt({
				"- F1: dropped idle-finding: not worth it",
				`- F2: {FIXED}`,
				`- F3: {FIXED}`,
				`- F4: {FIXED}`,
			}),
			"F1",
			"high"
		)
		-- a lesson that does not exist
		refused(
			attempt({
				`- F1: {FIXED}`,
				"- F2: dropped no-such-lesson: not worth it",
				`- F3: {FIXED}`,
				`- F4: {FIXED}`,
			}),
			"F2",
			"no-such-lesson"
		)
		-- a lesson without the not-worth-doing tag
		refused(
			attempt({
				`- F1: {FIXED}`,
				"- F2: dropped plain-note: not worth it",
				`- F3: {FIXED}`,
				`- F4: {FIXED}`,
			}),
			"F2",
			"not-worth-doing"
		)
	end)

	it("added needs a waiting member of this raft and takes a high finding", function()
		-- an issue that exists but is not a member of this raft, a member that does not wait, and one that is missing
		refused(
			attempt({ `- F1: {FIXED}`, "- F2: added c0030: later", `- F3: {FIXED}`, `- F4: {FIXED}` }),
			"F2",
			"c0030"
		)
		refused(
			attempt({ `- F1: {FIXED}`, "- F2: added c0010: later", `- F3: {FIXED}`, `- F4: {FIXED}` }),
			"F2",
			"c0010"
		)
		refused(
			attempt({ `- F1: {FIXED}`, "- F2: added c9999: later", `- F3: {FIXED}`, `- F4: {FIXED}` }),
			"F2",
			"c9999"
		)
		-- a high finding may be added: only the invalid F2 is refused, F1 is not named
		local high = attempt({
			`- F1: added {added}: later`,
			"- F2: added c0030: later",
			`- F3: {FIXED}`,
			`- F4: {FIXED}`,
		})
		refused(high, "F2", "c0030")
		t.expect(has(say(high), "F1")).toBe(false)
	end)

	it("a deferred answer is still accepted and called legacy", function()
		local r = attempt({
			`- F1: added {added}: main is worse off without it`,
			"- F2: dropped idle-finding: not worth it",
			`- F3: {FIXED}`,
			"- F4: deferred c0030: same follow-up",
		})
		if not r.ok then
			error(say(r), 0)
		end
		t.expect(has(say(r), "deferred is legacy (c0394)")).toBe(true)
		t.expect(has(say(r), "answer dropped or added")).toBe(true)
		-- the accepted answers let the part land
		t.expect(has(r.stdout, "landed R0010")).toBe(true)
		t.expect(onOrigin(`{ROOT}/issues/done/c0010/c0010.md`) ~= nil).toBe(true)
		-- the legacy follow-up stays in the backlog, where it was
		t.expect(onOrigin(`{ROOT}/issues/c0030/c0030.md`) ~= nil).toBe(true)
	end)
end)
