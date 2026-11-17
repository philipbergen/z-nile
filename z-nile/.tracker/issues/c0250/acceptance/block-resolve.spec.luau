--!strict
-- c0250 AC1 (the refusals of ./zn status), AC3 to AC7: ./zn block files the escalation note and gives the item to the
-- human in one tracker commit; ./zn resolve records the human's decision and moves the item by the decision table.
-- Real git in a fixture under .cache: a bare origin whose path contains github.com, worktrees, the tracker's own
-- commands, and a `gh` stub that records every call. Fixture: .cache/c0250-block-resolve-github.com.
-- Nothing here touches the real repository. The cases build on each other in order; each decision and each raft has
-- its own item, because a block is consumed by its resolve:
--   issues  c0110 AC3 block, AC6 retry   c0120 AC6 approve   c0130 AC6 amend-design (review-exhausted, F2 and F5 open)
--           c0140 AC6 split   c0150 AC5 and AC6 abort   c0160 AC5 (the actors, an agent's approve)   c0170 not preparing
--           c0175 AC3 (a resolved note)   c0180 and c0181 AC3 (blocked, no note, an unreadable note: re-filed)
--           c0190..c0198 the draft rafts' members
--   rafts   R0010 AC4 (seeded active, c0200 done, c0210 and c0220 active)   R0200 AC3 (a draft raft in rafting)
--           R0210 AC6 (a draft raft: approve acts as retry)   R0220 AC6 (a draft raft: split is refused, amend-design acts as retry)
--           R0020 AC6 amend-design (c0230 the Layer)   R0030 AC6 split (f0240 the Layer)
--           R0040 AC7 approve (c0250 the Layer)        R0050 AC7 retry and start   R0060 AC4 second block
--           R0070 AC4 (detached, no layer started)     R0080 AC7 (c0330 landed, c0335 and c0336 active; retry, ready, start)
--           R0090 AC6 (c0340 landed, c0345 the Layer: the raft goes to done/)   R0300 AC6 (c0350 the Layer: retired/)
local approval = require("@znile/engine/approval")
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local raftplan = require("@znile/engine/raftplan")
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
	ZN_HEADLESS = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}
local AGENT = {
	CLAUDECODE = "1",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	ZN_DISPATCH = "",
	CLAUDE_EFFORT = "high",
	ZN_ACTOR = "",
	ZN_HEADLESS = "",
	CLAUDE_CODE_SESSION_ID = "sess-agent-1",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

-- an environment: the base with some variables changed
local function with(base: { [string]: string }, extra: { [string]: string }): { [string]: string }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

local function problem(extra: string): string
	return `## Problem\nThe thing is slow.{extra}\n\n## Solution\nMake it fast.\n\n## Acceptance criteria\n- AC1: it is fast\n`
end

local TYPES = { c = "chore", f = "feature", d = "defect" }

-- tail: sections after the Problem, Solution and criteria (the open list of a review that ran out of rounds)
local function issue(id: string, status: string, raft: string, design: string, tail: string?): string
	return `---\nid: {id}\ntype: {TYPES[string.sub(id, 1, 1)]}\ntitle: title {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: {design}\nrank: 7\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n{problem(
		""
	)}{tail or ""}`
end

local OPEN_LIST =
	"\n## Open to the human\n- F2: the reader is missing. Answer: refuted. Decision: keep it or not?\n- F5: the cache is slow. Answer: refuted. Decision: defer it?\n"

local function raftDoc(id: string, status: string, issues: string, design: string, grouped: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\n{if grouped
		then `grouped: {grouped}\n`
		else ""}design: {design}\nrank: 3\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n## Theme\nThe {id} theme.\n\n## Order & dependencies\n{string.gsub(
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
	local source: { [string]: string } = extra or TERMINAL
	for k, v in source do
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

-- c0369 section 5's fixture (re-prep of 2026-11-17): an explainer page of f0339's shape that names the contract
-- `id` has on origin/main, published there, so the one approve passes before and after f0339 makes it read one
local function publishPage(id: string)
	fetch()
	local dir = `{f.base}/page-{id}`
	git(f.main, { "worktree", "add", "-q", "--detach", dir, "origin/main" })
	local itemDir = `{ROOT}/issues/{id}`
	local parts = approval.collect(dir, {
		id = id,
		kind = "issue",
		state = "backlog",
		dir = itemDir,
		doc = `{itemDir}/{id}.md`,
		slug = "",
		root = ROOT,
	})
	local hash = contract.hash(parts :: contract.Parts)
	write(
		dir,
		`{itemDir}/explainer.html`,
		`<!doctype html><html><head><meta charset="utf-8"><meta name="zn-contract" content="{hash}"><title>{id}</title></head><body>`
			.. '<section id="idea"><p>Show the person a page before they say yes.</p></section>'
			.. '<section id="before"><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg></section>'
			.. '<section id="changes"><ul><li><code>z-nile/engine/hold.luau</code>: hold()</li></ul></section>'
			.. '<section id="after"><svg viewBox="0 0 10 10"><circle r="3"/></svg></section>'
			.. '<section id="choices"><div class="choice"><ul class="pros"><li>plain</li></ul><ul class="cons"><li>one more file</li></ul></div></section>'
			.. "</body></html>\n"
	)
	git(dir, { "add", "-A" })
	git(dir, { "commit", "-q", "-m", `explainer page for {id}` })
	git(dir, { "push", "-q", "origin", "HEAD:main" })
	git(f.main, { "worktree", "remove", "--force", dir })
	fetch()
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
			for _, id in { "c0110", "c0120", "c0130", "c0140", "c0150", "c0160", "c0175" } do
				item(id, issue(id, PREPARING, "", "draft", if id == "c0130" then OPEN_LIST else nil))
				seed[`{ROOT}/issues/{id}/provenance.md`] =
					`# Provenance: {id}\n\n| when | event | actor | detail |\n|---|---|---|---|\n| 2026-11-01 10:00 | confirmed | human:Philip Bergen | idea |\n`
			end
			item("c0170", issue("c0170", "new-quiet-copper-falcon", "", "draft"))
			-- blocked on origin/main, but with no note (the block's publish was lost) and with an unreadable one: re-filed
			item("c0180", issue("c0180", "blocked-quiet-copper-falcon", "", "draft"))
			seed[`{ROOT}/issues/c0180/c0180.md`] = (
				string.gsub(
					seed[`{ROOT}/issues/c0180/c0180.md`],
					"status: ",
					"blocked: needs-decision\nstatus: ",
					1
				)
			)
			item("c0181", issue("c0181", "blocked-quiet-copper-falcon", "", "draft"))
			seed[`{ROOT}/issues/c0181/c0181.md`] = (
				string.gsub(
					seed[`{ROOT}/issues/c0181/c0181.md`],
					"status: ",
					"blocked: needs-decision\nstatus: ",
					1
				)
			)
			seed[`{ROOT}/issues/c0181/escalation.md`] = "this is not a note\n"
			-- draft rafts in rafting: claimed preparing, their members prepared with an EMPTY raft: line, as real drafts
			-- have on origin/main until the rafting PR lands (F8)
			local drafts: { [string]: { string } } =
				{ R0200 = { "c0190", "c0195" }, R0210 = { "c0191", "c0196" }, R0220 = { "c0192", "c0197" } }
			for raft, members in drafts do
				seed[`{ROOT}/rafts/{raft}/{raft}.md`] = raftDoc(
					raft,
					PREPARING,
					table.concat(members, ", "),
					if raft == "R0220" then "ready" else "draft"
				)
				seed[`{ROOT}/rafts/{raft}/check.sh`] = CHECK
				for _, mid in members do
					item(mid, issue(mid, PREPARED, "", "ready"))
				end
			end
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
					seed[`{ROOT}/issues/done/{id}/{id}.md`] = issue(id, ACTIVE, raft, "ready") -- a landed member keeps the claim stamp, as on main
					seed[`{ROOT}/issues/done/{id}/check.sh`] = CHECK
				end
			end
			activeRaft("R0010", { "c0210", "c0220" }, { "c0200" })
			activeRaft("R0020", { "c0230", "c0235" }, {})
			activeRaft("R0030", { "f0240", "c0245" }, {})
			activeRaft("R0070", { "c0280", "c0285" }, {})
			activeRaft("R0090", { "c0345" }, { "c0340" })
			activeRaft("R0300", { "c0350" }, {})
			for _, raft in { "R0090", "R0300" } do
				seed[`{ROOT}/rafts/active/{raft}/provenance.md`] =
					`# Provenance: {raft}\n\n| when | event | actor | detail |\n|---|---|---|---|\n| 2026-11-01 10:00 | confirmed | human:Philip Bergen | idea |\n`
			end
			-- readied for real below: their members are prepared with a ready design (the seed's approvals make ready pass)
			-- the record z-raft wrote: each member's design hash, and the coherence review that quotes it
			local function preparedRaft(raft: string, members: { string }, landed: { string }?)
				local order = table.concat(landed or {}, ", ")
					.. (if landed then ", " else "")
					.. table.concat(members, ", ")
				local entries: { string } = {}
				for _, id in members do
					local hash = raftplan.recordHash(id, {
						[`{id}.md`] = issue(id, PREPARED, raft, "ready"),
						["check.sh"] = CHECK,
						["acceptance/.gitkeep"] = "",
					})
					table.insert(entries, `{id}@{hash}`)
				end
				local grouped = `[{table.concat(entries, ", ")}]`
				seed[`{ROOT}/rafts/{raft}/{raft}.md`] = raftDoc(raft, PREPARED, order, "ready", grouped)
				seed[`{ROOT}/rafts/{raft}/check.sh`] = CHECK
				seed[`{ROOT}/rafts/{raft}/design-review-001.md`] =
					`# Coherence review of {raft}\nGrouped: {grouped}\n`
				for _, id in members do
					item(id, issue(id, PREPARED, raft, "ready"))
					seed[`{ROOT}/issues/{id}/acceptance/.gitkeep`] = ""
				end
				local landedIds: { string } = landed or {}
				for _, id in landedIds do
					seed[`{ROOT}/issues/done/{id}/{id}.md`] = issue(id, ACTIVE, raft, "ready") -- a landed member keeps the claim stamp, as on main
					seed[`{ROOT}/issues/done/{id}/check.sh`] = CHECK
				end
			end
			preparedRaft("R0040", { "c0250", "c0255" })
			preparedRaft("R0050", { "c0260", "c0265" })
			preparedRaft("R0060", { "c0270", "c0275" })
			preparedRaft("R0080", { "c0335", "c0336" }, { "c0330" })
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
			for _, raft in { "R0040", "R0050", "R0060", "R0080" } do
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

	it("AC3: block refuses the reason tripwire in an agent session and files it from a terminal", function()
		fetch()
		local before = head()
		local path = `{ROOT}/issues/c0160/escalation.md`
		write(prep, path, note("Did the checkout change under us?"))
		local refused = zn(prep, { "block", "c0160", "tripwire" }, AGENT)
		t.expect(refused.ok).toBe(false)
		t.expect(has(say(refused), "block tripwire is the person's")).toBe(true)
		-- a dispatched step is an agent session too
		local dispatched = zn(prep, { "block", "c0160", "tripwire" }, with(AGENT, { ZN_DISPATCH = "1" }))
		t.expect(dispatched.ok).toBe(false)
		-- an agent may file the other reasons
		local other = zn(prep, { "block", "c0160", "bored" }, AGENT)
		t.expect(has(say(other), "bored is not a reason")).toBe(true)
		fetch()
		t.expect(head()).toBe(before)
		t.expect(statusOf(docOf("c0160"))).toBe("preparing")
		fs.removeFile(`{prep}/{path}`)
	end)

	it("AC3: block refuses a note that already holds a resolution", function()
		fetch()
		local before = head()
		local path = `{ROOT}/issues/c0175/escalation.md`
		write(
			prep,
			path,
			note("Which library?")
				.. "\n## Resolution\nDecision: retry\nAnswer: none\nBy: human:Ann\nWhen: 2026-11-01 10:00\n"
		)
		local refused = zn(prep, { "block", "c0175", "needs-decision" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(say(refused), "this is the last block's note: write the new one")).toBe(true)
		fetch()
		t.expect(head()).toBe(before)
		t.expect(statusOf(docOf("c0175"))).toBe("preparing")
		fs.removeFile(`{prep}/{path}`)
	end)

	it(
		"AC3: block refuses an issue that is a member of an active raft, naming the raft and --layer",
		function()
			fetch()
			local before = head()
			local path = `{ROOT}/issues/active/c0220/escalation.md`
			write(prep, path, note("The gate is red on c0220."))
			local refused = zn(prep, { "block", "c0220", "red-gate" })
			t.expect(refused.ok).toBe(false)
			t.expect(
				has(
					say(refused),
					"c0220 is in R0010, readied: block the raft: ./zn block R0010 red-gate --layer c0220"
				)
			).toBe(true)
			fetch()
			t.expect(head()).toBe(before) -- origin/main is unmoved
			t.expect(statusOf(`{ROOT}/issues/active/c0220/c0220.md`)).toBe("active")
			fs.removeFile(`{prep}/{path}`)
		end
	)

	it(
		"AC3: block re-files the note of a blocked item whose note is missing or unreadable, without moving it",
		function()
			fetch()
			local before = head()
			-- c0180 is blocked with no note at all
			local missing = `{ROOT}/issues/c0180/escalation.md`
			write(prep, missing, note("What did c0180 want to ask?"))
			-- a reason other than the one it is blocked with is refused
			local other = zn(prep, { "block", "c0180", "red-gate" })
			t.expect(other.ok).toBe(false)
			t.expect(has(say(other), "c0180 is blocked as needs-decision")).toBe(true)
			znOk(prep, { "block", "c0180", "needs-decision" })
			fetch()
			t.expect(subjects(before)).toEqual({ "tracker: c0180 blocked needs-decision" })
			t.expect(filesOf(head())).toEqual({ `A\t{missing}` }) -- the note alone: the item did not move
			t.expect(statusOf(docOf("c0180"))).toBe("blocked")
			t.expect(has(originFile(missing) or "", "Item: c0180\nReason: needs-decision\nFrom: preparing\n"))
				.toBe(true)
			t.expect(fs.isFile(`{prep}/{missing}`)).toBe(false)
			-- c0181 is blocked with a note that does not parse: it is kept as escalation-001.md and the new one filed
			local mid = head()
			local bad = `{ROOT}/issues/c0181/escalation.md`
			write(prep, bad, note("What did c0181 want to ask?"))
			znOk(prep, { "block", "c0181", "needs-decision" })
			fetch()
			t.expect(subjects(mid)).toEqual({ "tracker: c0181 blocked needs-decision" })
			t.expect(filesOf(head())).toEqual({
				`A\t{ROOT}/issues/c0181/escalation-001.md`,
				`M\t{bad}`,
			})
			t.expect(originFile(`{ROOT}/issues/c0181/escalation-001.md`)).toBe("this is not a note\n")
			t.expect(has(originFile(bad) or "", "What did c0181 want to ask?")).toBe(true)
			t.expect(statusOf(docOf("c0181"))).toBe("blocked")
			-- a blocked item whose note is filed has nothing to re-file
			write(prep, bad, note("Again?"))
			local again = zn(prep, { "block", "c0181", "needs-decision" })
			t.expect(again.ok).toBe(false)
			t.expect(has(say(again), "nothing to re-file")).toBe(true)
			fs.removeFile(`{prep}/{bad}`)
		end
	)

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
			t.expect(has(filed, "\nActor: human:c0250-block-resolve-github.com\n")).toBe(true) -- the git author, in a terminal
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
			t.expect(has(say(again), "nothing to re-file")).toBe(true) -- blocked, and its note is filed
			fs.removeFile(`{prep}/{path}`)
			-- the other issues in design block with their own reasons, for the cases below
			local reasons: { [string]: string } = {
				c0120 = "design-gap",
				c0130 = "review-exhausted",
				c0140 = "needs-decision",
				c0150 = "red-gate",
				c0160 = "tripwire",
			}
			for id, reason in reasons do
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
				-- c0150 is filed from a CLI session: its note names the session, which may not resolve it (F12)
				znOk(
					prep,
					{ "block", id, reason },
					if id == "c0150" then with(TERMINAL, { CLAUDE_CODE_SESSION_ID = "sess-A" }) else nil
				)
			end
			fetch()
			t.expect(front(docOf("c0140"), "blocked")).toBe("needs-decision")
			t.expect(front(docOf("c0160"), "blocked")).toBe("tripwire")
			t.expect(has(originFile(`{ROOT}/issues/c0150/escalation.md`) or "", "\nSession: sess-A\nWhen: "))
				.toBe(true)
			t.expect(has(originFile(`{ROOT}/issues/c0110/escalation.md`) or "", "\nSession:")).toBe(false)
			-- review-exhausted lists the unruled bullets of the open list, and its resume lines carry one --rule each
			local exhausted = originFile(`{ROOT}/issues/c0130/escalation.md`) or ""
			t.expect(has(exhausted, "\nActor: human:")).toBe(true)
			t.expect(has(exhausted, "\nOpen: F2, F5\nWhen: ")).toBe(true)
			t.expect(
				has(
					exhausted,
					'./zn resolve c0130 amend-design --answer "<your answer>" --rule F2="<your ruling>" --rule F5="<your ruling>"\n'
				)
			).toBe(true)
			t.expect(
				has(
					exhausted,
					'./zn resolve c0130 split --answer "<your answer>" --title "<the new issue\'s title>" --rule F2="<your ruling>" --rule F5="<your ruling>"\n'
				)
			).toBe(true)
			t.expect(has(originFile(`{ROOT}/issues/c0140/escalation.md`) or "", "--rule")).toBe(false)
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
			-- layer 1 (c0200) landed; layer 2 (c0210) is the open layer, parked on its branch with its pull request. The
			-- worker's checkout sits on layer 1's branch, as after `done --through`: the Layer is read from origin/main's
			-- tracker state, never from the current branch (F3)
			local parkedAt = `{f.base}/wt-R0010-2`
			git(f.main, { "worktree", "add", "-q", "-b", "R0010/2/c0210", parkedAt, "origin/main" })
			write(parkedAt, "pickman/src/alpha.luau", 'return "alpha"\n')
			git(parkedAt, { "add", "-A" })
			git(parkedAt, { "commit", "-qm", "c0210 work" })
			git(parkedAt, { "push", "-q", "origin", "R0010/2/c0210" })
			git(f.main, { "worktree", "remove", "--force", parkedAt })
			w.R0010 = `{f.base}/wt-R0010`
			git(f.main, { "worktree", "add", "-q", "-b", "R0010/1/c0200", w.R0010, "origin/main" })
			git(w.R0010, { "push", "-q", "origin", "R0010/1/c0200" })
			fs.writeFile(`{state}/base-11`, "main\n") -- both layers have a pull request: only the Layer's is told
			fs.writeFile(`{state}/base-12`, "main\n")
			-- the readied raft's prompt and claim file live in the main checkout
			write(f.main, `{ROOT}/rafts/active/R0010/prompt.md`, "the prompt\n")
			write(f.main, ".cache/tracker-claim-R0010", ACTIVE .. "\n")
			local path = `{ROOT}/rafts/active/R0010/escalation.md`
			write(w.R0010, path, note("The gate stays red on c0210: expected 1, got 2. Retry, or redesign?"))
			-- a --layer that is landed, unknown, or another raft's is refused, and origin/main stays as it was
			local settled = head()
			for _, bad in { "c0200", "c0999", "c0230" } do
				local refusedLayer = zn(w.R0010, { "block", "R0010", "red-gate", "--layer", bad })
				t.expect(refusedLayer.ok).toBe(false)
				t.expect(has(say(refusedLayer), `--layer {bad}`)).toBe(true)
				t.expect(has(say(refusedLayer), "the Layer is one of c0210, c0220")).toBe(true)
			end
			t.expect(
				has(
					say(zn(w.R0010, { "block", "R0010", "red-gate", "--layer", "c0200" })),
					"landed (it is in done/)"
				)
			).toBe(true)
			-- an issue: --layer names a raft's layer only
			write(prep, `{ROOT}/issues/c0175/escalation.md`, note("Why?"))
			t.expect(
				has(
					say(zn(prep, { "block", "c0175", "red-gate", "--layer", "c0210" })),
					"only for ./zn block <R>"
				)
			).toBe(true)
			fs.removeFile(`{prep}/{ROOT}/issues/c0175/escalation.md`)
			fetch()
			t.expect(head()).toBe(settled)
			-- the worker is an agent: the note names it as the actor and the session it ran in
			local out = znOk(w.R0010, { "block", "R0010", "red-gate" }, AGENT)
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
			t.expect(statusOf(`{ROOT}/issues/done/c0200/c0200.md`)).toBe("active")
			t.expect(front(`{ROOT}/issues/done/c0200/c0200.md`, "blocked")).toBe(nil)
			-- the note is in the raft's folder, with its header and the layer the worker was on
			local filed = originFile(`{ROOT}/rafts/R0010/escalation.md`) or ""
			t.expect(has(filed, "Item: R0010\nReason: red-gate\nFrom: active\nLayer: c0210\n")).toBe(true)
			t.expect(has(filed, "\nActor: agent:unknown effort high\nSession: sess-agent-1\nWhen: "))
				.toBe(true)
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
			-- the Layer's pull request is told, though the checkout sat on layer 1's branch (F3)
			t.expect(
				has(
					ghCalls(),
					"pr comment R0010/2/c0210 --body BLOCKED: red-gate: The gate stays red on c0210"
				)
			)
				.toBe(true)
			t.expect(has(ghCalls(), "pr comment R0010/1/c0200")).toBe(false)
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
		local first = zn(w.R0060, { "block", "R0060", "needs-decision" })
		t.expect(first.ok).toBe(true)
		-- the Layer has a branch and no pull request yet: the comment is skipped with a warning
		t.expect(has(say(first), "warning: R0060/1/c0270 has no pull request yet")).toBe(true)
		t.expect(has(ghCalls(), "pr comment R0060/1/c0270")).toBe(false)
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
		"AC4: block from a detached worktree takes the lowest member still in active/ as the Layer, and --layer names another",
		function()
			fetch()
			local function detached(name: string): string
				local dir = `{f.base}/wt-{name}`
				git(f.main, { "worktree", "add", "-q", "--detach", dir, "origin/main" })
				return dir
			end
			-- R0070: no layer started; --layer names the second member, and both members move with the raft
			local wt70 = detached("R0070")
			write(wt70, `{ROOT}/rafts/active/R0070/escalation.md`, note("Which of the two layers is wrong?"))
			local flagged = zn(wt70, { "block", "R0070", "design-gap", "--layer", "c0285" })
			t.expect(flagged.ok).toBe(true)
			fetch()
			local filed = originFile(`{ROOT}/rafts/R0070/escalation.md`) or ""
			t.expect(has(filed, "From: active\nLayer: c0285\n")).toBe(true)
			t.expect(statusOf(docOf("c0280"))).toBe("blocked")
			t.expect(statusOf(docOf("c0285"))).toBe("blocked")
			-- no layer branch exists yet: nothing to comment on, said so, and no gh comment call
			t.expect(has(say(flagged), "warning: c0285 has no layer branch yet")).toBe(true)
			t.expect(has(ghCalls(), "pr comment R0070")).toBe(false)
			-- R0090: a layer already landed (c0340 is in done/): the Layer is the lowest member still in active/
			local wt90 = detached("R0090")
			write(
				wt90,
				`{ROOT}/rafts/active/R0090/escalation.md`,
				note("The design of c0345 misses the reader.")
			)
			znOk(wt90, { "block", "R0090", "design-gap" })
			-- R0300: its only member
			local wt300 = detached("R0300")
			write(
				wt300,
				`{ROOT}/rafts/active/R0300/escalation.md`,
				note("The design of c0350 misses the reader.")
			)
			znOk(wt300, { "block", "R0300", "design-gap" })
			fetch()
			t.expect(
				has(originFile(`{ROOT}/rafts/R0090/escalation.md`) or "", "From: active\nLayer: c0345\n")
			)
				.toBe(true)
			t.expect(
				has(originFile(`{ROOT}/rafts/R0300/escalation.md`) or "", "From: active\nLayer: c0350\n")
			)
				.toBe(true)
			t.expect(has(tree(), `{ROOT}/issues/done/c0340/c0340.md`)).toBe(true) -- the landed member stays
			t.expect(statusOf(`{ROOT}/issues/done/c0340/c0340.md`)).toBe("active")
		end
	)
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
			-- the headless loop (c0253) sets ZN_HEADLESS: refused whoever else is set, with or without --said
			for _, extra in
				{
					with(TERMINAL, { ZN_HEADLESS = "1" }),
					with(AGENT, { ZN_HEADLESS = "1" }),
				}
			do
				local loop = zn(f.main, { "resolve", "c0160", "retry", "--said", "yes" }, extra)
				t.expect(loop.ok).toBe(false)
				t.expect(has(say(loop), "resolve is the human's: a headless session is refused")).toBe(true)
			end
			-- the session that filed the block may not resolve it (c0150's note names sess-A), as the user's agent or not
			for _, extra in
				{
					with(AGENT, { CLAUDE_CODE_SESSION_ID = "sess-A" }),
					with(TERMINAL, { CLAUDE_CODE_SESSION_ID = "sess-A" }),
				}
			do
				local own = zn(f.main, { "resolve", "c0150", "abort", "--said", "yes, abort it" }, extra)
				t.expect(own.ok).toBe(false)
				t.expect(has(say(own), "this session filed the block of c0150")).toBe(true)
			end
			-- a review-exhausted resolve needs one --rule per open id of the note (c0130: F2 and F5), and no other
			local noRules = zn(f.main, { "resolve", "c0130", "amend-design", "--answer", "redo it" })
			t.expect(noRules.ok).toBe(false)
			t.expect(has(say(noRules), "leaves F2 open: add --rule F2=")).toBe(true)
			local oneRule = zn(
				f.main,
				{ "resolve", "c0130", "amend-design", "--answer", "redo it", "--rule", "F2=keep it" }
			)
			t.expect(oneRule.ok).toBe(false)
			t.expect(has(say(oneRule), "leaves F5 open")).toBe(true)
			local strayRule = zn(f.main, {
				"resolve",
				"c0130",
				"amend-design",
				"--rule",
				"F2=keep it",
				"--rule",
				"F5=defer",
				"--rule",
				"F9=never",
			})
			t.expect(strayRule.ok).toBe(false)
			t.expect(has(say(strayRule), "--rule F9: the note's Open: lists F2, F5")).toBe(true)
			local badRule = zn(f.main, { "resolve", "c0130", "amend-design", "--rule", "F2" })
			t.expect(badRule.ok).toBe(false)
			t.expect(has(say(badRule), "give --rule <Fn>=")).toBe(true)
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
				"approve",
				"--answer",
				"retry it",
				"--said",
				"yes, go ahead and retry c0160",
			}, AGENT)
			fetch()
			t.expect(subjects(before)).toEqual({ "tracker: c0160 resolve approve" })
			local resolved = originFile(`{ROOT}/issues/c0160/escalation.md`) or ""
			t.expect(
				has(
					resolved,
					"\n## Resolution\nDecision: approve\nAnswer: retry it\nBy: agent:unknown effort high\n"
				)
			).toBe(true)
			t.expect(has(resolved, 'Said: "yes, go ahead and retry c0160"\n')).toBe(true)
			local record = originFile(`{ROOT}/issues/c0160/provenance.md`) or ""
			t.expect(
				has(
					record,
					'| unblocked | agent:unknown effort high | decision=approve said="yes, go ahead and retry c0160" |'
				)
			).toBe(true)
			t.expect(statusOf(docOf("c0160"))).toBe("new")
			-- the Decided line quotes the user's words, not the agent's answer, and names the option the agent took (F5)
			t.expect(
				has(
					originFile(docOf("c0160")) or "",
					`The thing is slow.\nDecided with the user ({os.date("%Y-%m-%d")}), resolve approve: "yes, go ahead and retry c0160" (the option: retry it)\n\n## Solution`
				)
			).toBe(true)
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
				local more: { string } = extra or {}
				for _, a in more do
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
					`The thing is slow.\nDecided with the user ({date}), resolve approve: "use the json library"\n\n## Solution`
				)
			).toBe(true)
			-- amend-design: back to design with the note as input
			resolve("c0130", "amend-design", {
				"--answer",
				"the design misses the reader",
				"--rule",
				"F2=keep the reader",
				"--rule",
				"F5=defer the cache",
			})
			t.expect(statusOf(docOf("c0130"))).toBe("new")
			t.expect(front(docOf("c0130"), "design")).toBe("draft")
			t.expect(has(originFile(docOf("c0130")) or "", "Decided with the user")).toBe(false)
			-- the rulings are in the note's Resolution, and no document on origin/main was edited by them
			local ruledNote = originFile(`{ROOT}/issues/c0130/escalation.md`) or ""
			t.expect(has(ruledNote, 'Ruled F2: "keep the reader"\nRuled F5: "defer the cache"\nWhen: '))
				.toBe(true)
			t.expect(has(originFile(docOf("c0130")) or "", "Ruled (user")).toBe(false)
			-- ./zn rulings, run in the step's worktree, writes them under the bullets; a bullet with no ruling is refused
			local doc130 = `{prep}/{docOf("c0130")}`
			local original = fs.readFile(doc130)
			fs.writeFile(doc130, original .. "- F9: a later finding. Answer: refuted. Decision: x\n")
			local unrecorded = zn(prep, { "rulings", "c0130" })
			t.expect(unrecorded.ok).toBe(false)
			t.expect(has(say(unrecorded), "F9 has no recorded ruling")).toBe(true)
			t.expect(fs.readFile(doc130))
				.toBe(original .. "- F9: a later finding. Answer: refuted. Decision: x\n") -- untouched
			fs.writeFile(doc130, original)
			local ruledOut = znOk(prep, { "rulings", "c0130" })
			t.expect(has(ruledOut, "ruled c0130")).toBe(true)
			local ruledDoc = fs.readFile(doc130)
			t.expect(
				has(
					ruledDoc,
					`- F2: the reader is missing. Answer: refuted. Decision: keep it or not?\n  Ruled (user, {date}): keep the reader\n`
				)
			).toBe(true)
			t.expect(
				has(
					ruledDoc,
					`- F5: the cache is slow. Answer: refuted. Decision: defer it?\n  Ruled (user, {date}): defer the cache\n`
				)
			).toBe(true)
			t.expect(has(say(zn(prep, { "rulings", "c0130" })), "no unruled bullet")).toBe(true) -- a second run changes nothing
			t.expect(fs.readFile(doc130)).toBe(ruledDoc)
			t.expect(zn(f.main, { "rulings", "c0130" }).ok).toBe(false) -- never the main checkout
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
					`Scope decision (user, {date}): "the parser is its own issue" (split into {newId})\n\n## Solution`
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
			-- a draft raft has no design to approve, amend or split (F13): approve and amend-design act as retry, with
			-- the answer only in the Resolution, and split is refused
			local function blockDraft(raft: string)
				write(
					prep,
					`{ROOT}/rafts/{raft}/escalation.md`,
					note(`Which members does {raft} take?`, {
						"- retry: again (recommended)",
						"- approve: take it as it is",
						"- amend-design: redo the grouping",
						"- split: carve out",
					})
				)
				znOk(prep, { "block", raft, "design-gap" })
				fetch()
				t.expect(statusOf(raftOf(raft))).toBe("blocked")
			end
			blockDraft("R0210")
			blockDraft("R0220")
			local beforeDraft = head()
			znOk(f.main, { "resolve", "R0210", "approve", "--answer", "take the plan as it is" })
			fetch()
			t.expect(subjects(beforeDraft)).toEqual({ "tracker: R0210 resolve approve" })
			t.expect(statusOf(raftOf("R0210"))).toBe("new")
			t.expect(front(raftOf("R0210"), "blocked")).toBe(nil)
			t.expect(front(raftOf("R0210"), "design")).toBe("draft")
			t.expect(has(originFile(raftOf("R0210")) or "", "Decided with the user")).toBe(false)
			for _, mid in { "c0191", "c0196" } do
				t.expect(has(originFile(docOf(mid)) or "", "Decided with the user")).toBe(false)
				t.expect(statusOf(docOf(mid))).toBe("prepared")
			end
			t.expect(
				has(
					originFile(`{ROOT}/rafts/R0210/escalation.md`) or "",
					"Decision: approve\nAnswer: take the plan as it is\n"
				)
			).toBe(true)
			-- split on a draft raft is refused with the way out, and nothing is published
			local atSplit = head()
			local splitDraft =
				zn(f.main, { "resolve", "R0220", "split", "--title", "A new one", "--answer", "carve it" })
			t.expect(splitDraft.ok).toBe(false)
			t.expect(
				has(
					say(splitDraft),
					"a draft raft has no design to split: resolve it amend-design, then split the issue in z-design"
				)
			).toBe(true)
			fetch()
			t.expect(head()).toBe(atSplit)
			t.expect(statusOf(raftOf("R0220"))).toBe("blocked")
			-- amend-design acts as retry: new, and its design stays as it was (not reset to draft)
			znOk(f.main, { "resolve", "R0220", "amend-design", "--answer", "regroup them" })
			fetch()
			t.expect(statusOf(raftOf("R0220"))).toBe("new")
			t.expect(front(raftOf("R0220"), "design")).toBe("ready")
			t.expect(front(raftOf("R0220"), "issues")).toBe("[c0192, c0197]")
			t.expect(statusOf(docOf("c0192"))).toBe("prepared")
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
			blockAt("R0030", "f0240", "needs-decision")
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
			t.expect(statusOf(docOf("f0240"))).toBe("new")
			t.expect(front(docOf("f0240"), "raft")).toBe("")
			t.expect(front(docOf("f0240"), "design")).toBe("draft")
			local layerDoc = originFile(docOf("f0240")) or ""
			local newId = string.match(layerDoc, "%(split into ([fdc]%d%d%d%d)%)") :: string
			t.expect(newId ~= nil).toBe(true)
			-- the new issue takes the Layer member's type: f0240 is a feature (F13)
			t.expect(string.sub(newId, 1, 1)).toBe("f")
			t.expect(has(originFile(docOf(newId)) or "", "\ntype: feature\n")).toBe(true)
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
		"AC6: a raft the Layer leaves with no unlanded member goes to done/ when a member landed and to retired/ when none did",
		function()
			fetch()
			local landedBefore = originFile(`{ROOT}/issues/done/c0340/c0340.md`)
			-- R0090: c0340 landed, c0345 is the Layer
			local before = head()
			local out = znOk(f.main, { "resolve", "R0090", "amend-design", "--answer", "add the reader" })
			fetch()
			t.expect(subjects(before)).toEqual({ "tracker: R0090 resolve amend-design" })
			t.expect(has(out, "the raft has no unlanded member: its folder is now in rafts/done/")).toBe(true)
			local files = tree()
			t.expect(has(files, `{ROOT}/rafts/done/R0090/R0090.md`)).toBe(true)
			t.expect(has(files, `{ROOT}/rafts/R0090/`)).toBe(false)
			t.expect(has(files, `{ROOT}/rafts/active/R0090/`)).toBe(false)
			local moved = originFile(`{ROOT}/rafts/done/R0090/R0090.md`) or ""
			t.expect(has(moved, "\nstatus:")).toBe(false) -- a finished raft carries no status line
			t.expect(has(moved, "\nblocked:")).toBe(false)
			t.expect(has(moved, "\nissues: [c0340]\n")).toBe(true)
			local note90 = originFile(`{ROOT}/rafts/done/R0090/escalation.md`) or ""
			t.expect(has(note90, "\n## Resolution\nDecision: amend-design\nAnswer: add the reader\n"))
				.toBe(true)
			t.expect(has(originFile(`{ROOT}/rafts/done/R0090/provenance.md`) or "", "| unblocked | human:"))
				.toBe(true)
			-- the Layer member is back in design, and the landed member is untouched, byte for byte
			t.expect(statusOf(docOf("c0345"))).toBe("new")
			t.expect(front(docOf("c0345"), "raft")).toBe("")
			t.expect(front(docOf("c0345"), "design")).toBe("draft")
			t.expect(has(originFile(`{ROOT}/issues/c0345/escalation.md`) or "", "Decision: amend-design"))
				.toBe(true)
			t.expect(originFile(`{ROOT}/issues/done/c0340/c0340.md`)).toBe(landedBefore)
			-- R0300: no member landed, so the raft is retired
			znOk(f.main, { "resolve", "R0300", "amend-design", "--answer", "add the reader" })
			fetch()
			files = tree()
			t.expect(has(files, `{ROOT}/rafts/retired/R0300/R0300.md`)).toBe(true)
			t.expect(has(files, `{ROOT}/rafts/R0300/`)).toBe(false)
			local retired = originFile(`{ROOT}/rafts/retired/R0300/R0300.md`) or ""
			t.expect(has(retired, "\nretired: emptied\n")).toBe(true)
			t.expect(has(retired, "\nstatus:")).toBe(false)
			t.expect(has(retired, "\nissues: []\n")).toBe(true)
			t.expect(statusOf(docOf("c0350"))).toBe("new")
			-- R0070, blocked elsewhere, is untouched
			t.expect(statusOf(docOf("c0280"))).toBe("blocked")
			t.expect(statusOf(raftOf("R0070"))).toBe("blocked")
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
			-- run by an agent on the user's word: the Decided line quotes --said, and names the option taken (F5)
			znOk(f.main, {
				"resolve",
				"R0040",
				"approve",
				"--answer",
				"take the json library",
				"--said",
				"yes, accept the json library for c0250",
			}, AGENT)
			fetch()
			t.expect(statusOf(raftOf("R0040"))).toBe("prepared")
			t.expect(statusOf(docOf("c0255"))).toBe("prepared")
			-- the line is in the Layer member's Problem, and nowhere else
			local layer = originFile(docOf("c0250")) or ""
			t.expect(
				has(
					layer,
					`The thing is slow.\nDecided with the user ({date}), resolve approve: "yes, accept the json library for c0250" (the option: take the json library)\n\n## Solution`
				)
			).toBe(true)
			t.expect(statusOf(docOf("c0250"))).toBe("prepared")
			t.expect(front(docOf("c0250"), "blocked")).toBe(nil)
			t.expect(has(originFile(raftOf("R0040")) or "", "Decided with the user")).toBe(false)
			t.expect(has(originFile(docOf("c0255")) or "", "Decided with the user")).toBe(false)
			-- the raft's grouped: entry and its coherence review's Grouped: line for the Layer member are re-recorded, as
			-- compact and remap do (F4); the other member's stay
			local function hashOf(id: string, doc: string): string
				return raftplan.recordHash(
					id,
					{ [`{id}.md`] = doc, ["check.sh"] = CHECK, ["acceptance/.gitkeep"] = "" }
				)
			end
			local oldHash = hashOf("c0250", issue("c0250", PREPARED, "R0040", "ready"))
			local newHash = hashOf("c0250", layer)
			local otherHash = hashOf("c0255", issue("c0255", PREPARED, "R0040", "ready"))
			t.expect(newHash ~= oldHash).toBe(true)
			local raftText = originFile(raftOf("R0040")) or ""
			t.expect(front(raftOf("R0040"), "grouped")).toBe(`[c0250@{newHash}, c0255@{otherHash}]`)
			t.expect(
				has(
					originFile(`{ROOT}/rafts/R0040/design-review-001.md`) or "",
					`Grouped: [c0250@{newHash}, c0255@{otherHash}]`
				)
			).toBe(true)
			t.expect(has(raftText .. (originFile(`{ROOT}/rafts/R0040/design-review-001.md`) or ""), oldHash))
				.toBe(false)
			-- the approved contract changed: ready refuses the raft, naming the member and the user's own approve
			local before = head()
			local refused = zn(f.main, { "ready", "R0040" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "c0250")).toBe(true)
			t.expect(has(say(refused), "approve")).toBe(true)
			fetch()
			t.expect(head()).toBe(before)
			t.expect(statusOf(raftOf("R0040"))).toBe("prepared")
			-- the user approves it with one command, in a terminal, from the main checkout: c0369 records it in a
			-- worktree of origin/main of its own and publishes it (the re-prep of 2026-11-17); with c0369 section 5's
			-- fixture (the page on origin/main, stub openers first on PATH, `yes y |` typing the answer, the exit code
			-- echoed inside script), so the case holds before and after f0339
			publishPage("c0250")
			local stubs = `{f.base}/stubs`
			fs.writeDir(stubs)
			for _, name in { "open", "xdg-open" } do
				write(f.base, `stubs/{name}`, "#!/bin/sh\nexit 0\n")
				fixture.exec(f.main, "chmod", { "+x", `{stubs}/{name}` })
			end
			local approveEnv = envWith()
			approveEnv.PATH = `{stubs}:{approveEnv.PATH or ""}`
			local approved = fixture.exec(
				f.main,
				"sh",
				{ "-c", `yes y | script -q /dev/null sh -c './zn approve c0250; echo "zn-exit=$?"'` },
				{ env = approveEnv }
			)
			t.expect(string.match(approved.stdout, "zn%-exit=(%d+)")).toBe("0")
			t.expect(has(approved.stdout, "published c0250 to origin/main: it counts now")).toBe(true)
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
	it(
		"AC7: a raft with a landed member resumes at layer 2: ready moves only the unlanded members, start reuses the parked branch and PR, the done member is untouched",
		function()
			fetch()
			local doneDoc = `{ROOT}/issues/done/c0330/c0330.md`
			local doneBefore = originFile(doneDoc)
			t.expect(doneBefore ~= nil).toBe(true)
			local wt = (string.gsub(znOk(f.main, { "worktree", "R0080" }), "%s+$", ""))
			-- ready (in the setup) left c0330 in done/ and moved the other two; start opens the first unlanded layer
			t.expect(statusOf(`{ROOT}/rafts/active/R0080/R0080.md`)).toBe("active")
			znOk(wt, { "start", "R0080" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0080/2/c0335")
			local function created(): number
				local n, at = 0, 1
				local calls = ghCalls()
				while true do
					local found = string.find(calls, "pr create --draft", at, true)
					if not found then
						return n
					end
					n += 1
					at = found + 1
				end
			end
			local made = created()
			write(wt, "pickman/src/gamma.luau", 'return "gamma"\n')
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0335 work" })
			git(wt, { "push", "-q", "origin", "R0080/2/c0335" })
			local parked = git(wt, { "rev-parse", "HEAD" })
			write(
				wt,
				`{ROOT}/rafts/active/R0080/escalation.md`,
				note("The gate on c0335 is red.", { "- retry: again (recommended)", "- abort: stop" })
			)
			znOk(wt, { "block", "R0080", "red-gate" })
			fetch()
			t.expect(has(originFile(`{ROOT}/rafts/R0080/escalation.md`) or "", "Layer: c0335\n")).toBe(true)
			t.expect(statusOf(docOf("c0335"))).toBe("blocked")
			t.expect(statusOf(docOf("c0336"))).toBe("blocked")
			t.expect(originFile(doneDoc)).toBe(doneBefore) -- the landed member is not part of the block
			-- retry: the raft and its two members are prepared; the landed member did not move
			znOk(f.main, { "resolve", "R0080", "retry", "--answer", "one more attempt" })
			fetch()
			t.expect(statusOf(raftOf("R0080"))).toBe("prepared")
			t.expect(statusOf(docOf("c0335"))).toBe("prepared")
			t.expect(statusOf(docOf("c0336"))).toBe("prepared")
			t.expect(originFile(doneDoc)).toBe(doneBefore)
			-- ready moves only the unlanded members, and passes with the raft's record as it was
			local readyOut = znOk(f.main, { "ready", "R0080" })
			fetch()
			t.expect(has(readyOut, "readied R0080")).toBe(true)
			t.expect(has(tree(), `{ROOT}/issues/active/c0335/c0335.md`)).toBe(true)
			t.expect(has(tree(), `{ROOT}/issues/active/c0336/c0336.md`)).toBe(true)
			t.expect(has(tree(), `{ROOT}/issues/active/c0330/`)).toBe(false)
			t.expect(originFile(doneDoc)).toBe(doneBefore) -- byte for byte
			-- start resumes on layer 2's own branch, at the commit it was parked at, and opens no second pull request
			git(wt, { "merge", "-q", "--no-edit", "origin/main" })
			znOk(wt, { "start", "R0080" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0080/2/c0335")
			t.expect(git(wt, { "merge-base", "--is-ancestor", parked, "HEAD" })).toBe("")
			t.expect(created()).toBe(made)
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
