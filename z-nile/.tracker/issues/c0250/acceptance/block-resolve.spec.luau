--!strict
-- c0250 AC1 (the refusals of ./zn status), AC3 to AC7: ./zn block files the escalation note and gives the item to the
-- human in one tracker commit; ./zn resolve records the human's decision and moves the item by the decision table.
-- Real git in a fixture under .cache: a bare origin whose path contains github.com, worktrees, the tracker's own
-- commands, and a `gh` stub that records every call. Fixture: .cache/c0250-block-resolve-github.com.
-- Nothing here touches the real repository. The cases build on each other in order; each decision and each raft has
-- its own item, because a block is consumed by its resolve:
--   issues  c0110 AC3 block, AC6 retry   c0120 AC6 approve   c0130 AC6 amend-design   c0140 AC6 split   c0150 AC6 abort
--           c0160 AC5 (the actors)       c0170 not preparing  c0190..c0198 the raft members below
--   rafts   R0010 AC4 (seeded active, c0200 done, c0210 and c0220 active)   R0200 AC3 (a draft raft in rafting)
--           R0020 AC6 amend-design (c0230 the Layer)   R0030 AC6 split (c0240 the Layer)
--           R0040 AC7 approve (c0250 the Layer)        R0050 AC7 retry and start   R0060 AC4 second block
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARING = "preparing-quiet-copper-falcon"
local PREPARED = "prepared-quiet-copper-falcon"
local ACTIVE = "active-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

-- a terminal: no agent marker is set (an empty variable is not set to the hint), and an agent session sets one
local TERMINAL = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	ZN_DISPATCH = "",
	CLAUDE_EFFORT = "",
	ZN_ACTOR = "",
}
local AGENT = {
	CLAUDECODE = "1",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	ZN_DISPATCH = "",
	CLAUDE_EFFORT = "high",
	ZN_ACTOR = "",
}

local function problem(extra: string): string
	return `## Problem\nThe thing is slow.{extra}\n\n## Solution\nMake it fast.\n\n## Acceptance criteria\n- AC1: it is fast\n`
end

local function issue(id: string, status: string, raft: string, design: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: title {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: {design}\nrank: 7\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n{problem(
		extra or ""
	)}`
end

local function raftDoc(id: string, status: string, issues: string, design: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\ndesign: {design}\nrank: 3\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n## Theme\nThe {id} theme.\n\n## Order & dependencies\n{string.gsub(
		issues,
		", ",
		"\n"
	)}\n`
end

-- the worker's note: the four sections, one option per decision named, exactly one recommended
local function note(question: string, options: { string }?): string
	local out = table.concat(
		options or { "- retry: one more attempt (recommended)", "- approve: accept it", "- abort: give up" },
		"\n"
	)
	return `## Question\n{question}\n\n## What was tried\nTwo attempts.\n\n## Open findings or error\nF1: the gate is red: expected 1, got 2.\n\n## Options\n{out}\n`
end

-- gh records every call and keeps each pull request's base; `pr list --head` answers the number the layer's branch
-- names (R00<r>0/<n>/... is PR <r><n>), `pr create` makes it
local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
num() { echo "$1" | sed -n 's|^R00\(.\)0/\(.\)/.*|\1\2|p'; }
after() { want="$1"; shift; prev=""; for a in "$@"; do if [ "$prev" = "$want" ]; then echo "$a"; return; fi; prev="$a"; done; }
case "$1 $2" in
  "pr list") n=$(num "$(after --head "$@")")
    if [ -n "$n" ] && [ -e "@STATE@/base-$n" ]; then
      case "$*" in *number*) echo "$n" ;; *url*) echo "https://github.com/x/y/pull/$n" ;; esac
    fi
    exit 0 ;;
  "pr create") n=$(num "$(after --head "$@")"); after --base "$@" > "@STATE@/base-$n"; echo "https://github.com/x/y/pull/$n"; exit 0 ;;
  "pr view") cat "@STATE@/base-$3" 2>/dev/null || echo main; exit 0 ;;
esac
exit 0
]=]

local f: trackerfix.Fixture
local log, state = "", ""
local env: { [string]: string } = {}
local prep = "" -- a worktree for the issues in design
local w: { [string]: string } = {} -- a worktree per raft

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function envWith(extra: { [string]: string }?): { [string]: string }
	local out = table.clone(env)
	for k, v in extra or TERMINAL do
		out[k] = v
	end
	return out
end

local function zn(dir: string, args: { string }, extra: { [string]: string }?): fixture.Result
	return fixture.exec(dir, "./zn", args, { env = envWith(extra) })
end

local function znOk(dir: string, args: { string }, extra: { [string]: string }?): string
	local r = zn(dir, args, extra)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return r.stdout
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function originFile(path: string): string?
	local r = fixture.exec(f.main, "git", { "show", `origin/main:{path}` })
	return if r.ok then r.stdout else nil
end

local function tree(): string
	return git(f.main, { "ls-tree", "-r", "--name-only", "origin/main" })
end

local function head(): string
	return git(f.main, { "rev-parse", "origin/main" })
end

local function fetch()
	git(f.main, { "fetch", "-q", "origin" })
end

local function front(path: string, key: string): string?
	local text = originFile(path)
	return if text
		then string.match(
			"\n" .. (string.match(text, "^%-%-%-\n(.-)\n%-%-%-") or "") .. "\n",
			`\n{key}: ?([^\n]*)\n`
		)
		else nil
end

local function ghCalls(): string
	return if fs.isFile(log) then fs.readFile(log) else ""
end

-- the commit subjects on origin/main since `from`, oldest first
local function subjects(from: string): { string }
	local out: { string } = {}
	for line in
		string.gmatch(
			git(f.main, { "log", "--reverse", "--format=%s", `{from}..origin/main` }) .. "\n",
			"([^\n]*)\n"
		)
	do
		if line ~= "" then
			table.insert(out, line)
		end
	end
	return out
end

local function filesOf(commit: string): { string }
	local out: { string } = {}
	for line in
		string.gmatch(
			git(f.main, { "show", "--no-renames", "--name-status", "--format=", commit }) .. "\n",
			"([^\n]*)\n"
		)
	do
		if line ~= "" then
			table.insert(out, line)
		end
	end
	table.sort(out)
	return out
end

local function docOf(id: string): string
	return `{ROOT}/issues/{id}/{id}.md`
end

local function raftOf(id: string): string
	return `{ROOT}/rafts/{id}/{id}.md`
end

-- the status words of an item on origin/main: `blocked`, `new`, ...
local function statusOf(path: string): string
	return string.match(front(path, "status") or "?", "^(%a+)") or "?"
end

return t.spec("c0250 block and resolve", function(it)
	it(
		"sets up a github-shaped origin with issues in design, readied and seeded rafts, and a gh that records its calls",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["z-nile/next"] = "issue 400 quiet-copper-falcon\nraft 70 quiet-copper-falcon\n",
			}
			local function item(id: string, text: string)
				seed[`{ROOT}/issues/{id}/{id}.md`] = text
				seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
			end
			-- issues in design (preparing), with a rank and an existing provenance row
			for _, id in { "c0110", "c0120", "c0130", "c0140", "c0150", "c0160" } do
				item(id, issue(id, PREPARING, "", "draft"))
				seed[`{ROOT}/issues/{id}/provenance.md`] =
					`# Provenance: {id}\n\n| when | event | actor | detail |\n|---|---|---|---|\n| 2026-11-01 10:00 | confirmed | human:Philip Bergen | idea |\n`
			end
			item("c0170", issue("c0170", "new-quiet-copper-falcon", "", "draft"))
			-- a draft raft in rafting: claimed preparing, its members prepared
			seed[`{ROOT}/rafts/R0200/R0200.md`] = raftDoc("R0200", PREPARING, "c0190, c0195", "draft")
			seed[`{ROOT}/rafts/R0200/check.sh`] = CHECK
			item("c0190", issue("c0190", PREPARED, "R0200", "ready"))
			item("c0195", issue("c0195", PREPARED, "R0200", "ready"))
			-- seeded active rafts: members carry the raft's claim; a landed member is in done/
			local function activeRaft(raft: string, members: { string }, done: { string })
				local all = table.concat(done, ", ")
					.. (if #done > 0 then ", " else "")
					.. table.concat(members, ", ")
				seed[`{ROOT}/rafts/active/{raft}/{raft}.md`] = raftDoc(raft, ACTIVE, all, "ready")
				seed[`{ROOT}/rafts/active/{raft}/check.sh`] = CHECK
				for _, id in members do
					seed[`{ROOT}/issues/active/{id}/{id}.md`] = issue(id, ACTIVE, raft, "ready")
					seed[`{ROOT}/issues/active/{id}/check.sh`] =
						`#!/usr/bin/env bash\n{CHECK}# {ROOT}/issues/active/{id}/check.sh\n`
					seed[`{ROOT}/issues/active/{id}/acceptance/.gitkeep`] = ""
				end
				for _, id in done do
					seed[`{ROOT}/issues/done/{id}/{id}.md`] = issue(id, "done", raft, "ready")
					seed[`{ROOT}/issues/done/{id}/check.sh`] = CHECK
				end
			end
			activeRaft("R0010", { "c0210", "c0220" }, { "c0200" })
			activeRaft("R0020", { "c0230", "c0235" }, {})
			activeRaft("R0030", { "c0240", "c0245" }, {})
			-- readied for real below: their members are prepared with a ready design (the seed's approvals make ready pass)
			local function preparedRaft(raft: string, members: { string })
				seed[`{ROOT}/rafts/{raft}/{raft}.md`] =
					raftDoc(raft, PREPARED, table.concat(members, ", "), "ready")
				seed[`{ROOT}/rafts/{raft}/check.sh`] = CHECK
				for _, id in members do
					item(id, issue(id, PREPARED, raft, "ready"))
					seed[`{ROOT}/issues/{id}/acceptance/.gitkeep`] = ""
				end
			end
			preparedRaft("R0040", { "c0250", "c0255" })
			preparedRaft("R0050", { "c0260", "c0265" })
			preparedRaft("R0060", { "c0270", "c0275" })
			f = trackerfix.new("c0250-block-resolve-github.com", seed)
			local bin = `{f.base}/bin`
			log, state = `{f.base}/gh.log`, `{f.base}/gh-state`
			fs.writeDir(bin)
			fs.writeDir(state)
			fs.writeFile(`{bin}/gh`, (string.gsub((string.gsub(GH, "@LOG@", log)), "@STATE@", state)))
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			-- the worktree for the issues in design: a branch of origin/main
			prep = `{f.base}/wt-prep`
			git(f.main, { "worktree", "add", "-q", "-b", "prep-c0110", prep, "origin/main" })
			for _, raft in { "R0040", "R0050", "R0060" } do
				znOk(f.main, { "ready", raft })
			end
			fetch()
		end
	)

	it("AC1: ./zn status refuses to block", function()
		local before = head()
		local blocks = zn(prep, { "status", "c0110", "blocked" })
		t.expect(blocks.ok).toBe(false)
		t.expect(has(say(blocks), "only ./zn block blocks")).toBe(true)
		-- nothing was published
		fetch()
		t.expect(head()).toBe(before)
		t.expect(statusOf(docOf("c0110"))).toBe("preparing")
	end)

	it(
		"AC3: block on a preparing issue publishes one commit with the status, the reason and the note, and refuses a bad reason, a bad note and the main checkout",
		function()
			local before = head()
			local path = `{ROOT}/issues/c0110/escalation.md`
			-- no note yet
			local missing = zn(prep, { "block", "c0110", "needs-decision" })
			t.expect(missing.ok).toBe(false)
			t.expect(has(say(missing), "escalation.md")).toBe(true)
			-- a reason outside the list
			write(prep, path, note("Which library?"))
			local bored = zn(prep, { "block", "c0110", "bored" })
			t.expect(bored.ok).toBe(false)
			t.expect(has(say(bored), "bored is not a reason")).toBe(true)
			t.expect(has(say(bored), "review-exhausted")).toBe(true)
			-- a note missing a section, an option naming no decision, two recommendations
			write(
				prep,
				path,
				(string.gsub(note("Which library?"), "## What was tried\nTwo attempts.\n\n", ""))
			)
			local noSection = zn(prep, { "block", "c0110", "needs-decision" })
			t.expect(noSection.ok).toBe(false)
			t.expect(has(say(noSection), "What was tried")).toBe(true)
			write(prep, path, note("Which library?", { "- maybe: dunno (recommended)", "- retry: again" }))
			local noDecision = zn(prep, { "block", "c0110", "needs-decision" })
			t.expect(noDecision.ok).toBe(false)
			t.expect(has(say(noDecision), "maybe")).toBe(true)
			write(
				prep,
				path,
				note("Which library?", { "- retry: again (recommended)", "- abort: stop (recommended)" })
			)
			local two = zn(prep, { "block", "c0110", "needs-decision" })
			t.expect(two.ok).toBe(false)
			t.expect(has(say(two), "exactly one")).toBe(true)
			-- the main checkout: the note was written in a worktree
			write(f.main, path, note("Which library?"))
			local inMain = zn(f.main, { "block", "c0110", "needs-decision" })
			t.expect(inMain.ok).toBe(false)
			t.expect(has(say(inMain), "block runs where the note was written")).toBe(true)
			fs.removeFile(`{f.main}/{path}`)
			-- an item that is not preparing or active
			write(prep, `{ROOT}/issues/c0170/escalation.md`, note("Why?"))
			local isNew = zn(prep, { "block", "c0170", "needs-decision" })
			t.expect(isNew.ok).toBe(false)
			t.expect(has(say(isNew), "c0170 is new")).toBe(true)
			fs.removeFile(`{prep}/{ROOT}/issues/c0170/escalation.md`)
			-- and a missing item
			local nobody = zn(prep, { "block", "c0999", "needs-decision" })
			t.expect(nobody.ok).toBe(false)
			fetch()
			t.expect(head()).toBe(before) -- every refusal left origin/main as it was
			-- the good block: one commit on origin/main
			write(prep, path, note("Which library should we take?"))
			local out = znOk(prep, { "block", "c0110", "needs-decision" })
			t.expect(has(out, "blocked c0110")).toBe(true)
			fetch()
			local made = subjects(before)
			t.expect(made).toEqual({ "tracker: c0110 blocked needs-decision" })
			t.expect(filesOf(head()))
				.toEqual({ `A\t{ROOT}/issues/c0110/escalation.md`, `M\t{docOf("c0110")}` })
			t.expect(statusOf(docOf("c0110"))).toBe("blocked")
			t.expect(string.match(front(docOf("c0110"), "status") or "", "^blocked%-%a+%-%a+%-%a+$") ~= nil)
				.toBe(true)
			t.expect(front(docOf("c0110"), "blocked")).toBe("needs-decision")
			t.expect(front(docOf("c0110"), "rank")).toBe("7")
			local filed = originFile(path) or ""
			t.expect(
				has(filed, "# Escalation: c0110\nItem: c0110\nReason: needs-decision\nFrom: preparing\n")
			)
				.toBe(true)
			t.expect(has(filed, "\nActor: human:")).toBe(true)
			t.expect(string.match(filed, "\nWhen: %d%d%d%d%-%d%d%-%d%d %d%d:%d%d\n") ~= nil).toBe(true)
			t.expect(has(filed, "## Question\nWhich library should we take?\n")).toBe(true)
			t.expect(has(filed, '\n## Resume\n./zn resolve c0110 retry --answer "<your answer>"\n'))
				.toBe(true)
			t.expect(has(filed, "./zn resolve c0110 split")).toBe(false) -- the note offers three decisions
			-- the worktree's copy is gone: main's is the note
			t.expect(fs.isFile(`{prep}/{path}`)).toBe(false)
			-- a block of a block is refused: the item is no longer preparing
			write(prep, path, note("Again?"))
			local again = zn(prep, { "block", "c0110", "needs-decision" })
			t.expect(again.ok).toBe(false)
			fs.removeFile(`{prep}/{path}`)
			-- the other issues in design block with their own reasons, for the cases below
			for id, reason in
				{
					c0120 = "design-gap",
					c0130 = "review-exhausted",
					c0140 = "needs-decision",
					c0150 = "red-gate",
					c0160 = "tripwire",
				}
			do
				write(
					prep,
					`{ROOT}/issues/{id}/escalation.md`,
					note(`What about {id}?`, {
						"- retry: again (recommended)",
						"- approve: accept",
						"- amend-design: redesign",
						"- split: carve out",
						"- abort: stop",
					})
				)
				znOk(prep, { "block", id, reason })
			end
			fetch()
			t.expect(front(docOf("c0140"), "blocked")).toBe("needs-decision")
			t.expect(front(docOf("c0160"), "blocked")).toBe("tripwire")
			-- a draft raft in rafting blocks too
			write(prep, `{ROOT}/rafts/R0200/escalation.md`, note("Which members?"))
			znOk(prep, { "block", "R0200", "design-gap" })
			fetch()
			t.expect(statusOf(raftOf("R0200"))).toBe("blocked")
			t.expect(front(raftOf("R0200"), "blocked")).toBe("design-gap")
			t.expect(has(originFile(`{ROOT}/rafts/R0200/escalation.md`) or "", "From: preparing")).toBe(true)
			t.expect(statusOf(docOf("c0190"))).toBe("prepared") -- its members are not touched
		end
	)
	it(
		"AC4: block on an active raft moves it and its active members to the backlog blocked, keeps a done member, adds the note, removes the prompt, names the parked branch and comments on the PR",
		function()
			fetch()
			local before = head()
			-- layer 2 (c0210) is the open layer, parked on its branch; layer 1 (c0200) landed
			w.R0010 = `{f.base}/wt-R0010`
			git(f.main, { "worktree", "add", "-q", "-b", "R0010/2/c0210", w.R0010, "origin/main" })
			write(w.R0010, "pickman/src/alpha.luau", 'return "alpha"\n')
			git(w.R0010, { "add", "-A" })
			git(w.R0010, { "commit", "-qm", "c0210 work" })
			git(w.R0010, { "push", "-q", "origin", "R0010/2/c0210" })
			-- the readied raft's prompt and claim file live in the main checkout
			write(f.main, `{ROOT}/rafts/active/R0010/prompt.md`, "the prompt\n")
			write(f.main, ".cache/tracker-claim-R0010", ACTIVE .. "\n")
			local path = `{ROOT}/rafts/active/R0010/escalation.md`
			write(w.R0010, path, note("The gate stays red on c0210: expected 1, got 2. Retry, or redesign?"))
			local out = znOk(w.R0010, { "block", "R0010", "red-gate" })
			fetch()
			t.expect(subjects(before)).toEqual({ "tracker: R0010 blocked red-gate" })
			-- the raft and the members still in active/ are in the backlog, blocked, with the reason
			local files = tree()
			for _, id in { "c0210", "c0220" } do
				t.expect(has(files, `{ROOT}/issues/{id}/{id}.md`)).toBe(true)
				t.expect(has(files, `{ROOT}/issues/active/{id}/`)).toBe(false)
				t.expect(statusOf(docOf(id))).toBe("blocked")
				t.expect(front(docOf(id), "blocked")).toBe("red-gate")
				t.expect(front(docOf(id), "raft")).toBe("R0010")
			end
			t.expect(has(files, `{ROOT}/rafts/R0010/R0010.md`)).toBe(true)
			t.expect(has(files, `{ROOT}/rafts/active/R0010/`)).toBe(false)
			t.expect(statusOf(raftOf("R0010"))).toBe("blocked")
			t.expect(front(raftOf("R0010"), "blocked")).toBe("red-gate")
			t.expect(front(raftOf("R0010"), "rank")).toBe("3")
			t.expect(string.match(front(raftOf("R0010"), "status") or "", "^blocked%-") ~= nil).toBe(true)
			-- the landed member stays where it is, untouched
			t.expect(has(files, `{ROOT}/issues/done/c0200/c0200.md`)).toBe(true)
			t.expect(statusOf(`{ROOT}/issues/done/c0200/c0200.md`)).toBe("done")
			t.expect(front(`{ROOT}/issues/done/c0200/c0200.md`, "blocked")).toBe(nil)
			-- the note is in the raft's folder, with its header and the layer the worker was on
			local filed = originFile(`{ROOT}/rafts/R0010/escalation.md`) or ""
			t.expect(has(filed, "Item: R0010\nReason: red-gate\nFrom: active\nLayer: c0210\n")).toBe(true)
			t.expect(has(filed, "expected 1, got 2")).toBe(true)
			-- check.sh paths are rewritten back, as stop does
			t.expect(has(originFile(`{ROOT}/issues/c0210/check.sh`) or "", `# {ROOT}/issues/c0210/check.sh`))
				.toBe(true)
			t.expect(has(originFile(`{ROOT}/issues/c0210/check.sh`) or "", "issues/active/")).toBe(false)
			-- the prompt and the claim file are gone, the main checkout follows origin/main, the worktree's note is gone
			t.expect(fs.isFile(`{f.main}/{ROOT}/rafts/active/R0010/prompt.md`)).toBe(false)
			t.expect(fs.isFile(`{f.main}/.cache/tracker-claim-R0010`)).toBe(false)
			t.expect(git(f.main, { "rev-parse", "HEAD" })).toBe(head())
			t.expect(fs.isFile(`{f.main}/{ROOT}/rafts/R0010/escalation.md`)).toBe(true)
			t.expect(fs.isFile(`{w.R0010}/{path}`)).toBe(false)
			-- the parked branch is named and left as it is, and the open layer's PR is told
			t.expect(has(out, "R0010/2/c0210")).toBe(true)
			t.expect(has(out, "left as they are")).toBe(true)
			t.expect(
				git(f.main, { "rev-parse", "--verify", "-q", "refs/remotes/origin/R0010/2/c0210" }) ~= ""
			)
				.toBe(true)
			t.expect(
				has(
					ghCalls(),
					"pr comment R0010/2/c0210 --body BLOCKED: red-gate: The gate stays red on c0210"
				)
			)
				.toBe(true)
		end
	)
	it("AC4: a second block keeps the resolved note as escalation-001.md", function()
		fetch()
		-- R0060 is readied; its first block, a resolve and a ready again; then it blocks a second time
		w.R0060 = `{f.base}/wt-R0060`
		git(f.main, { "worktree", "add", "-q", "-b", "R0060/1/c0270", w.R0060, "origin/main" })
		local active = `{ROOT}/rafts/active/R0060/escalation.md`
		local backlog = `{ROOT}/rafts/R0060/escalation.md`
		write(w.R0060, active, note("First question: which approach?"))
		znOk(w.R0060, { "block", "R0060", "needs-decision" })
		fetch()
		t.expect(has(originFile(backlog) or "", "First question")).toBe(true)
		znOk(f.main, { "resolve", "R0060", "retry", "--answer", "take the first approach" })
		fetch()
		t.expect(statusOf(raftOf("R0060"))).toBe("prepared")
		znOk(f.main, { "ready", "R0060" })
		fetch()
		-- readied again, the resolved note travelled with the raft into active/
		t.expect(has(tree(), `{ROOT}/rafts/active/R0060/escalation.md`)).toBe(true)
		git(w.R0060, { "merge", "-q", "--ff-only", "origin/main" })
		write(w.R0060, active, note("Second question: the gate is red again, retry?"))
		local before = head()
		znOk(w.R0060, { "block", "R0060", "red-gate" })
		fetch()
		t.expect(subjects(before)).toEqual({ "tracker: R0060 blocked red-gate" })
		local current = originFile(backlog) or ""
		local kept = originFile(`{ROOT}/rafts/R0060/escalation-001.md`) or ""
		t.expect(has(current, "Second question")).toBe(true)
		t.expect(has(current, "## Resolution")).toBe(false)
		t.expect(has(current, "Reason: red-gate")).toBe(true)
		-- the first note is kept whole, with its resolution
		t.expect(has(kept, "First question")).toBe(true)
		t.expect(has(kept, "Reason: needs-decision")).toBe(true)
		t.expect(has(kept, "## Resolution\nDecision: retry\nAnswer: take the first approach\n")).toBe(true)
		t.expect(has(kept, "Second question")).toBe(false)
		-- nothing else of the raft was left behind in active/
		t.expect(has(tree(), `{ROOT}/rafts/active/R0060/`)).toBe(false)
		t.expect(statusOf(raftOf("R0060"))).toBe("blocked")
		t.expect(statusOf(docOf("c0270"))).toBe("blocked")
	end)
	it(
		"AC5: resolve is refused with ZN_DISPATCH, needs --said in an agent session and records it, needs none in a terminal, and refuses an item that is not blocked",
		function()
			fetch()
			local before = head()
			local headless = { CLAUDECODE = "1", ZN_DISPATCH = "1", CLAUDE_EFFORT = "high" }
			local refused = zn(f.main, { "resolve", "c0160", "retry", "--said", "yes, retry" }, headless)
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "resolve is the human's: a headless session is refused")).toBe(true)
			-- a dispatched step has no said that opens it, whatever it quotes
			local dispatchedTerminal = zn(f.main, { "resolve", "c0160", "retry" }, { ZN_DISPATCH = "1" })
			t.expect(dispatchedTerminal.ok).toBe(false)
			t.expect(has(say(dispatchedTerminal), "headless session is refused")).toBe(true)
			-- an agent session quotes the user: no --said, or an empty one, is refused
			local noSaid = zn(f.main, { "resolve", "c0160", "retry" }, AGENT)
			t.expect(noSaid.ok).toBe(false)
			t.expect(has(say(noSaid), "--said")).toBe(true)
			local emptySaid = zn(f.main, { "resolve", "c0160", "retry", "--said", "  " }, AGENT)
			t.expect(emptySaid.ok).toBe(false)
			-- the other refusals: a word that is not a decision, both answers, split with no title, an item not blocked
			local shrug = zn(f.main, { "resolve", "c0160", "shrug" })
			t.expect(shrug.ok).toBe(false)
			t.expect(has(say(shrug), "shrug is not a decision")).toBe(true)
			fs.writeFile(`{f.base}/answer.txt`, "an answer\n")
			local both = zn(
				f.main,
				{ "resolve", "c0160", "retry", "--answer", "x", "--answer-file", `{f.base}/answer.txt` }
			)
			t.expect(both.ok).toBe(false)
			t.expect(has(say(both), "--answer or --answer-file, not both")).toBe(true)
			local noTitle = zn(f.main, { "resolve", "c0160", "split", "--answer", "carve it" })
			t.expect(noTitle.ok).toBe(false)
			t.expect(has(say(noTitle), "--title")).toBe(true)
			local notBlocked = zn(f.main, { "resolve", "c0170", "retry" })
			t.expect(notBlocked.ok).toBe(false)
			t.expect(has(say(notBlocked), "c0170 is new on origin/main, not blocked")).toBe(true)
			local missing = zn(f.main, { "resolve", "c0999", "retry" })
			t.expect(missing.ok).toBe(false)
			fetch()
			t.expect(head()).toBe(before)
			t.expect(statusOf(docOf("c0160"))).toBe("blocked")
			-- an agent on the user's word: recorded quoted, with the user's message
			znOk(f.main, {
				"resolve",
				"c0160",
				"retry",
				"--answer",
				"retry it",
				"--said",
				"yes, go ahead and retry c0160",
			}, AGENT)
			fetch()
			t.expect(subjects(before)).toEqual({ "tracker: c0160 resolve retry" })
			local resolved = originFile(`{ROOT}/issues/c0160/escalation.md`) or ""
			t.expect(
				has(
					resolved,
					"\n## Resolution\nDecision: retry\nAnswer: retry it\nBy: agent:unknown effort high\n"
				)
			).toBe(true)
			t.expect(has(resolved, 'Said: "yes, go ahead and retry c0160"\n')).toBe(true)
			local record = originFile(`{ROOT}/issues/c0160/provenance.md`) or ""
			t.expect(
				has(
					record,
					'| unblocked | agent:unknown effort high | decision=retry said="yes, go ahead and retry c0160" |'
				)
			).toBe(true)
			t.expect(statusOf(docOf("c0160"))).toBe("new")
			-- a terminal needs no quote, and records no Said line
			local beforeHuman = head()
			znOk(f.main, { "resolve", "c0110", "retry", "--answer-file", `{f.base}/answer.txt` })
			fetch()
			t.expect(subjects(beforeHuman)).toEqual({ "tracker: c0110 resolve retry" })
			local human = originFile(`{ROOT}/issues/c0110/escalation.md`) or ""
			t.expect(has(human, "\nAnswer: an answer\nBy: human:")).toBe(true)
			t.expect(has(human, "Said:")).toBe(false)
			t.expect(has(originFile(`{ROOT}/issues/c0110/provenance.md`) or "", "| unblocked | human:"))
				.toBe(true)
			-- a second resolve of the same block is refused
			local twice = zn(f.main, { "resolve", "c0110", "abort" })
			t.expect(twice.ok).toBe(false)
			t.expect(has(say(twice), "not blocked")).toBe(true)
		end
	)
	it(
		"AC6: each decision from preparing moves the issue as the table says, appends the resolution, removes blocked:, writes one unblocked row and keeps rank:",
		function()
			local date = os.date("%Y-%m-%d") :: string
			local function unblockedRows(id: string): number
				local n = 0
				for _ in string.gmatch(originFile(`{ROOT}/issues/{id}/provenance.md`) or "", "| unblocked |") do
					n += 1
				end
				return n
			end
			local function resolve(id: string, decision: string, extra: { string }?): string
				fetch()
				local before = head()
				local args = { "resolve", id, decision }
				for _, a in extra or {} do
					table.insert(args, a)
				end
				local out = znOk(f.main, args)
				fetch()
				t.expect(subjects(before)).toEqual({ `tracker: {id} resolve {decision}` })
				-- the item keeps its rank, loses blocked:, and its note holds the resolution
				t.expect(front(docOf(id), "rank")).toBe("7")
				t.expect(front(docOf(id), "blocked")).toBe(nil)
				local noteText = originFile(`{ROOT}/issues/{id}/escalation.md`) or ""
				t.expect(has(noteText, `\n## Resolution\nDecision: {decision}\n`)).toBe(true)
				t.expect(unblockedRows(id)).toBe(1)
				t.expect(has(originFile(`{ROOT}/issues/{id}/provenance.md`) or "", `decision={decision}`))
					.toBe(true)
				-- the confirmed row that was there is still first
				t.expect(
					string.match(
						originFile(`{ROOT}/issues/{id}/provenance.md`) or "",
						"| confirmed | human:Philip Bergen | idea |\n| [%d%-: ]+ | unblocked |"
					) ~= nil
				).toBe(true)
				return out
			end
			-- retry (resolved in AC5): the next design step reads the note with its resolution
			t.expect(statusOf(docOf("c0110"))).toBe("new")
			t.expect(front(docOf("c0110"), "design")).toBe("draft")
			t.expect(front(docOf("c0110"), "rank")).toBe("7")
			t.expect(front(docOf("c0110"), "blocked")).toBe(nil)
			t.expect(unblockedRows("c0110")).toBe(1)
			-- approve: the answer is the user's decision, written into the Problem
			resolve("c0120", "approve", { "--answer", "use the json library" })
			t.expect(statusOf(docOf("c0120"))).toBe("new")
			t.expect(front(docOf("c0120"), "design")).toBe("draft")
			local approved = originFile(docOf("c0120")) or ""
			t.expect(
				has(
					approved,
					`The thing is slow.\nDecided with the user ({date}), resolve: "use the json library"\n\n## Solution`
				)
			).toBe(true)
			-- amend-design: back to design with the note as input
			resolve("c0130", "amend-design", { "--answer", "the design misses the reader" })
			t.expect(statusOf(docOf("c0130"))).toBe("new")
			t.expect(front(docOf("c0130"), "design")).toBe("draft")
			t.expect(has(originFile(docOf("c0130")) or "", "Decided with the user")).toBe(false)
			-- abort: the claim is given back
			resolve("c0150", "abort")
			t.expect(statusOf(docOf("c0150"))).toBe("new")
			t.expect(string.match(front(docOf("c0150"), "status") or "", "^new%-%a+%-%a+%-%a+$") ~= nil)
				.toBe(true)
			t.expect(has(originFile(`{ROOT}/issues/c0150/escalation.md`) or "", "Answer: none")).toBe(true)
			-- split: a new backlog issue titled by --title, with the answer as its Problem, and the scope decision on the item
			local out = resolve(
				"c0140",
				"split",
				{ "--title", "Carve out the parser", "--answer", "the parser is its own issue" }
			)
			local newId = string.match(out, "new issue (c%d%d%d%d)") :: string
			t.expect(newId ~= nil).toBe(true)
			t.expect(newId ~= "c0140").toBe(true)
			t.expect(statusOf(docOf("c0140"))).toBe("new")
			t.expect(front(docOf("c0140"), "design")).toBe("draft")
			t.expect(
				has(
					originFile(docOf("c0140")) or "",
					`Scope decision (user, {date}): "the parser is its own issue" (split into {newId})`
				)
			).toBe(true)
			local made = originFile(docOf(newId)) or ""
			t.expect(has(made, "title: Carve out the parser")).toBe(true)
			t.expect(has(made, "slug: carve-out-the-parser")).toBe(true)
			t.expect(has(made, "\nidea: unchallenged\n")).toBe(true)
			t.expect(has(made, "## Problem\nthe parser is its own issue")).toBe(true)
			t.expect(statusOf(docOf(newId))).toBe("new")
			t.expect(has(tree(), `{ROOT}/issues/{newId}/check.sh`)).toBe(true)
			-- the counter went past the new number
			local counter = originFile("z-nile/next") or ""
			t.expect(string.match(counter, "^issue (%d+) ") ~= nil).toBe(true)
			t.expect(tonumber(string.match(counter, "^issue (%d+) ")))
				.toBe(tonumber(string.sub(newId, 2)) :: number + 1)
			-- a draft raft in rafting: new, and its members untouched
			fetch()
			local before = head()
			znOk(f.main, { "resolve", "R0200", "retry" })
			fetch()
			t.expect(subjects(before)).toEqual({ "tracker: R0200 resolve retry" })
			t.expect(statusOf(raftOf("R0200"))).toBe("new")
			t.expect(front(raftOf("R0200"), "blocked")).toBe(nil)
			t.expect(front(raftOf("R0200"), "rank")).toBe("3")
			t.expect(statusOf(docOf("c0190"))).toBe("prepared")
		end
	)
	it(
		"AC6: amend-design and split on a raft take the Layer member out of the raft, and split makes a new backlog issue and a Scope decision line",
		function()
			local date = os.date("%Y-%m-%d") :: string
			local function unblockedRows(path: string): number
				local n = 0
				for _ in string.gmatch(originFile(path) or "", "| unblocked |") do
					n += 1
				end
				return n
			end
			-- block R0020 and R0030 at their first layer, each from its worktree on the layer's branch
			local function blockAt(raft: string, layerIssue: string, reason: string)
				local dir = `{f.base}/wt-{raft}`
				git(f.main, { "worktree", "add", "-q", "-b", `{raft}/1/{layerIssue}`, dir, "origin/main" })
				git(dir, { "push", "-q", "origin", `{raft}/1/{layerIssue}` })
				write(
					dir,
					`{ROOT}/rafts/active/{raft}/escalation.md`,
					note(`The design of {layerIssue} misses the reader.`, {
						"- amend-design: redesign it (recommended)",
						"- split: carve the reader out",
						"- retry: again",
					})
				)
				znOk(dir, { "block", raft, reason })
				fetch()
			end
			blockAt("R0020", "c0230", "design-gap")
			blockAt("R0030", "c0240", "needs-decision")
			for _, raft in { "R0020", "R0030" } do
				t.expect(statusOf(raftOf(raft))).toBe("blocked")
			end
			t.expect(
				string.match(originFile(`{ROOT}/rafts/R0020/escalation.md`) or "", "Layer: c0230") ~= nil
			)
				.toBe(true)
			-- amend-design: the Layer member leaves the raft and goes back to design; the raft is prepared with the rest
			local before = head()
			znOk(f.main, { "resolve", "R0020", "amend-design", "--answer", "add the reader to the design" })
			fetch()
			t.expect(subjects(before)).toEqual({ "tracker: R0020 resolve amend-design" })
			t.expect(statusOf(raftOf("R0020"))).toBe("prepared")
			t.expect(front(raftOf("R0020"), "blocked")).toBe(nil)
			t.expect(front(raftOf("R0020"), "issues")).toBe("[c0235]")
			t.expect(front(raftOf("R0020"), "rank")).toBe("3")
			t.expect(statusOf(docOf("c0230"))).toBe("new")
			t.expect(front(docOf("c0230"), "raft")).toBe("")
			t.expect(front(docOf("c0230"), "design")).toBe("draft")
			t.expect(front(docOf("c0230"), "blocked")).toBe(nil)
			t.expect(has(originFile(`{ROOT}/issues/c0230/escalation.md`) or "", "Decision: amend-design"))
				.toBe(true) -- z-design reads the note there
			t.expect(
				has(
					originFile(`{ROOT}/issues/c0230/escalation.md`) or "",
					"The design of c0230 misses the reader."
				)
			).toBe(true)
			-- the rest of the raft goes back prepared, no longer blocked, still in the raft
			t.expect(statusOf(docOf("c0235"))).toBe("prepared")
			t.expect(front(docOf("c0235"), "raft")).toBe("R0020")
			t.expect(front(docOf("c0235"), "blocked")).toBe(nil)
			t.expect(unblockedRows(`{ROOT}/rafts/R0020/provenance.md`)).toBe(1)
			t.expect(unblockedRows(`{ROOT}/issues/c0230/provenance.md`)).toBe(0) -- the one row is the raft's
			-- split: the same on the Layer member, a new issue for the carved-out part, and the user's scope decision
			-- run by an agent on the user's word: the scope decision quotes the user's message, not the agent's answer
			znOk(f.main, {
				"resolve",
				"R0030",
				"split",
				"--title",
				"Read the file",
				"--answer",
				"the reader is its own issue",
				"--said",
				"yes, split the reader out",
			}, AGENT)
			fetch()
			t.expect(statusOf(raftOf("R0030"))).toBe("prepared")
			t.expect(front(raftOf("R0030"), "issues")).toBe("[c0245]")
			t.expect(statusOf(docOf("c0240"))).toBe("new")
			t.expect(front(docOf("c0240"), "raft")).toBe("")
			t.expect(front(docOf("c0240"), "design")).toBe("draft")
			local layerDoc = originFile(docOf("c0240")) or ""
			local newId = string.match(layerDoc, "%(split into (c%d%d%d%d)%)") :: string
			t.expect(newId ~= nil).toBe(true)
			t.expect(
				has(
					layerDoc,
					`Scope decision (user, {date}): "yes, split the reader out" (split into {newId})`
				)
			)
				.toBe(true)
			t.expect(has(originFile(docOf(newId)) or "", "title: Read the file")).toBe(true)
			t.expect(has(originFile(docOf(newId)) or "", "## Problem\nthe reader is its own issue"))
				.toBe(true)
			t.expect(front(docOf(newId), "raft")).toBe("")
			t.expect(statusOf(docOf("c0245"))).toBe("prepared")
			t.expect(unblockedRows(`{ROOT}/rafts/R0030/provenance.md`)).toBe(1)
			t.expect(has(layerDoc, "the reader is its own issue")).toBe(false) -- the answer is the new issue's Problem
		end
	)
	it(
		"AC7: approve on a raft writes the Decided line in the Layer member, and ready refuses until that member is approved again",
		function()
			local date = os.date("%Y-%m-%d") :: string
			fetch()
			local dir = `{f.base}/wt-R0040`
			git(f.main, { "worktree", "add", "-q", "-b", "R0040/1/c0250", dir, "origin/main" })
			write(
				dir,
				`{ROOT}/rafts/active/R0040/escalation.md`,
				note(
					"May c0250 depend on the json library?",
					{ "- approve: accept the dependency (recommended)", "- retry: try without it" }
				)
			)
			znOk(dir, { "block", "R0040", "design-gap" })
			fetch()
			znOk(f.main, { "resolve", "R0040", "approve", "--answer", "take the json library" })
			fetch()
			t.expect(statusOf(raftOf("R0040"))).toBe("prepared")
			t.expect(statusOf(docOf("c0255"))).toBe("prepared")
			-- the line is in the Layer member's Problem, and nowhere else
			local layer = originFile(docOf("c0250")) or ""
			t.expect(
				has(
					layer,
					`The thing is slow.\nDecided with the user ({date}), resolve: "take the json library"\n\n## Solution`
				)
			).toBe(true)
			t.expect(statusOf(docOf("c0250"))).toBe("prepared")
			t.expect(front(docOf("c0250"), "blocked")).toBe(nil)
			t.expect(has(originFile(raftOf("R0040")) or "", "Decided with the user")).toBe(false)
			t.expect(has(originFile(docOf("c0255")) or "", "Decided with the user")).toBe(false)
			-- the approved contract changed: ready refuses the raft, naming the member and the user's own approve
			local before = head()
			local refused = zn(f.main, { "ready", "R0040" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "c0250")).toBe(true)
			t.expect(has(say(refused), "approve")).toBe(true)
			fetch()
			t.expect(head()).toBe(before)
			t.expect(statusOf(raftOf("R0040"))).toBe("prepared")
			-- the user approves it in a worktree, in a terminal, and publishes it
			local wt = `{f.base}/wt-approve`
			git(f.main, { "worktree", "add", "-q", "-b", "approve-c0250", wt, "origin/main" })
			local approved = fixture.exec(
				wt,
				"script",
				{ "-q", "/dev/null", "./zn", "approve", "c0250" },
				{ env = envWith() }
			)
			t.expect(approved.ok).toBe(true)
			local published = fixture.exec(
				wt,
				"script",
				{ "-q", "/dev/null", "./zn", "approve", "c0250", "--publish" },
				{ env = envWith() }
			)
			t.expect(published.ok).toBe(true)
			fetch()
			local ready = zn(f.main, { "ready", "R0040" })
			t.expect(say(ready)).toBe(say(ready) .. "") -- keeps the output in the failure message below
			t.expect(ready.ok).toBe(true)
			fetch()
			t.expect(has(tree(), `{ROOT}/rafts/active/R0040/R0040.md`)).toBe(true)
			t.expect(statusOf(`{ROOT}/rafts/active/R0040/R0040.md`)).toBe("active")
		end
	)
	it(
		"AC7: retry on a raft makes it prepared, and ready and start resume at the blocked layer on its parked branch",
		function()
			fetch()
			local function count(text: string, part: string): number
				local n, at = 0, 1
				while true do
					local found = string.find(text, part, at, true)
					if not found then
						return n
					end
					n += 1
					at = found + #part
				end
			end
			local wt = (string.gsub(znOk(f.main, { "worktree", "R0050" }), "%s+$", ""))
			znOk(wt, { "start", "R0050" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0050/1/c0260")
			t.expect(count(ghCalls(), "pr create --draft")).toBe(1)
			write(wt, "pickman/src/beta.luau", 'return "beta"\n')
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0260 work" })
			git(wt, { "push", "-q", "origin", "R0050/1/c0260" })
			local parked = git(wt, { "rev-parse", "HEAD" })
			-- the same check failed after a real second attempt: block, with the layer the worker was on
			write(
				wt,
				`{ROOT}/rafts/active/R0050/escalation.md`,
				note(
					"The gate on c0260 is still red.",
					{ "- retry: one more attempt (recommended)", "- abort: stop" }
				)
			)
			znOk(wt, { "block", "R0050", "red-gate" })
			fetch()
			t.expect(statusOf(raftOf("R0050"))).toBe("blocked")
			t.expect(has(originFile(`{ROOT}/rafts/R0050/escalation.md`) or "", "Layer: c0260")).toBe(true)
			-- ready refuses the blocked raft, naming the command that gets past it
			local before = head()
			local refused = zn(f.main, { "ready", "R0050" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "R0050")).toBe(true)
			t.expect(has(say(refused), "blocked")).toBe(true)
			fetch()
			t.expect(head()).toBe(before)
			-- retry: prepared again, rank and members as they were
			local retried = znOk(f.main, { "resolve", "R0050", "retry", "--answer", "one more attempt" })
			t.expect(has(retried, "resolved R0050")).toBe(true)
			fetch()
			t.expect(statusOf(raftOf("R0050"))).toBe("prepared")
			t.expect(front(raftOf("R0050"), "rank")).toBe("3")
			t.expect(front(raftOf("R0050"), "issues")).toBe("[c0260, c0265]")
			t.expect(statusOf(docOf("c0260"))).toBe("prepared")
			t.expect(statusOf(docOf("c0265"))).toBe("prepared")
			-- ready takes it again, with no new approval: nothing in its contract changed
			znOk(f.main, { "ready", "R0050" })
			fetch()
			t.expect(statusOf(`{ROOT}/rafts/active/R0050/R0050.md`)).toBe("active")
			-- the parked branch is where it was, and start resumes on it: same branch, same commit, no second PR
			git(wt, { "merge", "-q", "--no-edit", "origin/main" })
			znOk(wt, { "start", "R0050" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0050/1/c0260")
			t.expect(git(wt, { "merge-base", "--is-ancestor", parked, "HEAD" })).toBe("")
			t.expect(git(wt, { "merge-base", "--is-ancestor", parked, "origin/R0050/1/c0260" })).toBe("")
			t.expect(count(ghCalls(), "pr create --draft")).toBe(1)
			-- layer 2 was not cut: the blocked layer is resumed, not skipped
			t.expect(
				fixture.exec(f.main, "git", { "show-ref", "--verify", "--quiet", "refs/heads/R0050/2/c0265" }).ok
			).toBe(false)
		end
	)
	it("AC6: abort on a raft leaves it prepared and names the parked branches and PRs", function()
		fetch()
		t.expect(statusOf(raftOf("R0060"))).toBe("blocked") -- blocked a second time in AC4
		local before = head()
		local out = znOk(f.main, { "resolve", "R0060", "abort", "--answer", "not worth it" })
		fetch()
		t.expect(subjects(before)).toEqual({ "tracker: R0060 resolve abort" })
		t.expect(statusOf(raftOf("R0060"))).toBe("prepared")
		t.expect(front(raftOf("R0060"), "blocked")).toBe(nil)
		t.expect(front(raftOf("R0060"), "rank")).toBe("3")
		t.expect(statusOf(docOf("c0270"))).toBe("prepared")
		t.expect(statusOf(docOf("c0275"))).toBe("prepared")
		-- the parked branch is named, and left as it is
		t.expect(has(out, "R0060/1/c0270")).toBe(true)
		t.expect(has(out, "left as they are")).toBe(true)
		t.expect(
			fixture.exec(f.main, "git", { "show-ref", "--verify", "--quiet", "refs/heads/R0060/1/c0270" }).ok
		)
			.toBe(true)
		-- the archived first note and the second one, now resolved, are both kept
		t.expect(has(originFile(`{ROOT}/rafts/R0060/escalation.md`) or "", "Decision: abort")).toBe(true)
		t.expect(has(originFile(`{ROOT}/rafts/R0060/escalation-001.md`) or "", "Decision: retry")).toBe(true)
	end)

	it("AC1: ./zn status refuses to unblock a blocked item and names resolve", function()
		fetch()
		t.expect(statusOf(raftOf("R0010"))).toBe("blocked") -- blocked in AC4, never resolved
		local before = head()
		for _, to in { "new", "prepared", "preparing", "done" } do
			local r = zn(prep, { "status", "R0010", to })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "R0010 is blocked: only ./zn resolve unblocks it")).toBe(true)
		end
		-- active is refused whoever asks, and stays refused
		t.expect(zn(prep, { "status", "R0010", "active" }).ok).toBe(false)
		-- the same through the member of a blocked raft
		local member = zn(prep, { "status", "c0210", "new" })
		t.expect(member.ok).toBe(false)
		t.expect(has(say(member), "only ./zn resolve unblocks")).toBe(true)
		fetch()
		t.expect(head()).toBe(before)
		t.expect(statusOf(raftOf("R0010"))).toBe("blocked")
	end)
end)
