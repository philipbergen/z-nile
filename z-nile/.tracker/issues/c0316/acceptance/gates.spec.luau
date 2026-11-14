--!strict
-- c0316 AC5 and AC6: the landing gates refuse work with an escape nobody learned from, naming the entry to write.
-- The real CLI runs in tracker fixtures under .cache (tests/lib/trackerfix): `status <id> prepared` in a prep worktree
-- (c0316.md section 3, row 1), `done` on a built raft (row 2), `stop`, `ready` and `work next` on a started raft
-- (rows 3 and the stop paragraph), and `land` on a capture that sets `reworks:`. Every fixture has its own repository
-- and an origin; the real repository is never touched.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end
local function git(dir: string, args: { string }, options: fixture.Options?): string
	return fixture.git(dir, args, options)
end
-- stderr and stdout together: a refusal is printed on stderr, but the gate may say more on either
local function said(r: fixture.Result): string
	return r.stderr .. r.stdout
end

-- ---------------------------------------------------------------------------------------------------------------
-- status prepared
-- ---------------------------------------------------------------------------------------------------------------
local P: trackerfix.Fixture
local pw = "" -- the prep worktree

-- A design review with one low finding F1. `stage` is its `Stage:` line (the stage whose work holds the mistake).
local function review(stage: string?): string
	local line = if stage then `Stage: {stage}\n` else ""
	return "# Review 001\n\n### F1 [low] a claim\nWhere: a\nEvidence: b\nCritique: c\nConsequences: none\n"
		.. `Recommendation: d\n{line}\nVerdict: approve\n`
end

local function hex(c: string): string
	return string.rep(c, 64)
end
-- approval.md with one row per letter (the file's own grammar: when, who, hash, parts)
local function approvals(letters: { string }): string
	local lines = { "# approval", "when\twho\thash\tparts" }
	for i, c in letters do
		table.insert(lines, `2026-11-0{i}T10:00:00Z\tann\t{hex(c)}\tdesign={hex(c)}`)
	end
	return table.concat(lines, "\n") .. "\n"
end

-- A new issue claimed for design in the prep worktree, its design set to ready (what z-design leaves), as
-- c0116/issue-design does it. Returns the id and the issue's folder in the worktree.
local function prepIssue(slug: string): (string, string)
	local made = trackerfix.trOk(P, pw, { "new", "issue", "c", slug, "--project", "pickman" })
	local id = string.match(made, "(c%d+)") :: string
	local dir = `{pw}/pickman/.tracker/issues/{id}`
	local doc = `{dir}/{id}.md`
	fs.writeFile(doc, (string.gsub(fs.readFile(doc), "idea: unchallenged", "idea: challenged", 1)))
	fs.writeFile(
		`{dir}/idea-review-001.md`,
		"# Idea review 001\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n"
	)
	git(pw, { "add", "-A" })
	git(pw, { "commit", "-q", "-m", `tracker: idea {id}` })
	git(pw, { "fetch", "-q", "origin" })
	git(pw, { "merge", "-q", "--no-edit", "origin/main" })
	git(pw, { "push", "-q", "origin", "HEAD:main" })
	trackerfix.trOk(P, pw, { "status", id, "preparing" })
	local text = fs.readFile(doc)
	local s, e = string.find(text, "\ndesign: draft\n", 1, true)
	assert(s and e, "design: line")
	fs.writeFile(doc, string.sub(text, 1, s) .. "design: ready\n" .. string.sub(text, e + 1))
	return id, dir
end

local function prepared(id: string): fixture.Result
	return trackerfix.tr(P, pw, { "status", id, "prepared" })
end
local function stampOf(dir: string, id: string): string
	return string.match(fs.readFile(`{dir}/{id}.md`), "\nstatus: (%S+)") or ""
end
-- the issue is prepared when its status stamp says so (the carried move writes the document, nothing is published)
local function isPrepared(dir: string, id: string): boolean
	return string.match(stampOf(dir, id), "^prepared%-") ~= nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- done
-- ---------------------------------------------------------------------------------------------------------------
local D: trackerfix.Fixture
local dw = "" -- the raft's worktree
local denv: { [string]: string } = {}
local marker = ""

local CHECK_HEAD =
	'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
local DOC = table.concat({
	"---",
	"id: c0010",
	"type: chore",
	"title: alpha module",
	"slug: c0010",
	"raft: R0010",
	"depends_on: []",
	"emergent: false",
	"design: ready",
	"created: 2026-11-11",
	`status: {PREPARED}`,
	"---",
	"",
	"# c0010: alpha module",
	"",
	"## Problem",
	"Alpha value is not computed.",
	"",
	"## Solution",
	"Add `pickman/src/alpha.luau` returning the alpha table.",
	"",
	"## Design",
	"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
	"",
	"## Acceptance criteria",
	"- AC1: alpha module exists",
	"",
}, "\n")
local RAFT = table.concat({
	"---",
	"id: R0010",
	"type: chore",
	"title: one-ticket stack",
	"slug: one-ticket-stack",
	"single: false",
	"issues: [c0010]",
	"design: ready",
	"created: 2026-11-11",
	`status: {PREPARED}`,
	"---",
	"",
	"# R0010: one-ticket stack",
	"",
	"## Order & dependencies",
	"c0010",
	"",
}, "\n")

local function zn(args: { string }): fixture.Result
	return trackerfix.tr(D, dw, args, denv)
end
local function znOk(args: { string }): string
	local r = zn(args)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

-- ---------------------------------------------------------------------------------------------------------------
-- stop, ready, work next
-- ---------------------------------------------------------------------------------------------------------------
local S: trackerfix.Fixture
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local function issueDoc(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Members\nslug: members\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function onOrigin(path: string): string?
	local r = fixture.exec(S.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local RAFT_DOC = "pickman/.tracker/rafts/R0010/R0010.md"

-- A prepared raft with one member, readied and started in its worktree (dw) with the member's code written. The
-- raft's check.sh touches a marker file, so a spec can tell whether it ran.
local function buildRaft(name: string)
	local seed: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
	}
	-- the raft's check records that it ran: done must refuse before it does
	D = trackerfix.new(name, seed)
	marker = `{D.base}/raft-check-ran`
	local raftCheck = CHECK_HEAD
		.. `check "RC1: alpha exists" bash -c 'touch "{marker}"; test -f "$ZN_ROOT/pickman/src/alpha.luau"'\nfinish\n`
	local memberCheck = CHECK_HEAD
		.. 'check "AC1: alpha exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
	write(D.main, "pickman/.tracker/issues/c0010/c0010.md", DOC)
	write(D.main, "pickman/.tracker/issues/c0010/check.sh", memberCheck)
	write(D.main, "pickman/.tracker/issues/c0010/acceptance/.gitkeep", "")
	write(D.main, "pickman/.tracker/rafts/R0010/R0010.md", RAFT)
	write(D.main, "pickman/.tracker/rafts/R0010/check.sh", raftCheck)
	seal.stamp(D.main, "c0316-gates")
	git(D.main, { "add", "-A" })
	git(D.main, { "commit", "-qm", "prep R0010" })
	git(D.main, { "push", "-q", "origin", "HEAD:main" })
	local bin = `{D.base}/bin`
	fs.writeDir(bin)
	fs.writeFile(
		`{bin}/gh`,
		'#!/bin/sh\ncase "$1 $2" in\n'
			.. '  "pr list") echo 1; exit 0 ;;\n'
			.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
			.. '  "pr view") echo main; exit 0 ;;\n'
			.. '  "pr edit") exit 0 ;;\n'
			.. "esac\nexit 0\n"
	)
	process.exec("chmod", { "+x", `{bin}/gh` })
	denv = { PATH = `{bin}:{process.env.PATH or ""}` }
	trackerfix.trOk(D, D.main, { "ready", "R0010" })
	dw = trackerfix.trOk(D, D.main, { "worktree", "R0010" })
	znOk({ "start", "R0010" })
	write(dw, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
end

return t.spec("c0316 the landing gates refuse an escape with no harvest entry", function(it)
	it("sets up a prep worktree", function()
		P = trackerfix.new("c0316-gates-prepared", nil)
		pw = trackerfix.trOk(P, P.main, { "worktree", "prep-gates" })
		trackerfix.trOk(P, pw, { "sync" })
	end)

	it(
		"AC5: status prepared refuses an issue with an unharvested finding and names the entry to write; with the entry it passes",
		function()
			local id, dir = prepIssue("unharvested-finding")
			-- the finding names its own stage, so only the missing entry is wrong
			fs.writeFile(`{dir}/design-review-001.md`, review("design"))
			local r = prepared(id)
			t.expect(r.ok).toBe(false)
			local out = said(r)
			t.expect(has(out, `{id} design-review-001 F1`)).toBe(true)
			t.expect(has(out, "harvest each in harvest.md (a lesson id, or one-off: <reason>)")).toBe(true)
			t.expect(has(out, `./zn lessons --uncovered {id}`)).toBe(true)
			t.expect(isPrepared(dir, id)).toBe(false) -- the refusal moved nothing
			fs.writeFile(`{dir}/harvest.md`, `# Harvest: {id}\n\n- design-review-001 F1: one-off: a typo\n`)
			local ok = prepared(id)
			if not ok.ok then
				error(said(ok))
			end
			t.expect(isPrepared(dir, id)).toBe(true)
			git(pw, { "add", "-A" })
			git(pw, { "commit", "-q", "-m", "case 1" })
		end
	)

	it(
		"AC5: status prepared refuses a second approval with no escape entry, and a new review with an unmarked finding; a review committed before the date is exempt",
		function()
			local id, dir = prepIssue("redesigned")
			-- a second approval row: the contract was approved again, so the approved design changed
			fs.writeFile(`{dir}/approval.md`, approvals({ "a", "b" }))
			local first = prepared(id)
			t.expect(first.ok).toBe(false)
			local out = said(first)
			t.expect(has(out, `{id} escape redesign 2`)).toBe(true)
			t.expect(has(out, "harvest each in harvest.md")).toBe(true)
			t.expect(isPrepared(dir, id)).toBe(false)
			-- the escape is harvested, and a review with a finding that has no Stage line is written (not committed)
			local reviewPath = `{dir}/design-review-001.md`
			fs.writeFile(reviewPath, review(nil))
			fs.writeFile(
				`{dir}/harvest.md`,
				`# Harvest: {id}\n\n- escape redesign 2 (design): one-off: the contract was reworded\n`
					.. "- design-review-001 F1: one-off: a typo\n"
			)
			local second = prepared(id)
			t.expect(second.ok).toBe(false)
			local out2 = said(second)
			t.expect(has(out2, `{id} design-review-001 F1`)).toBe(true)
			t.expect(has(out2, "no Stage line")).toBe(true)
			t.expect(has(out2, "escape redesign")).toBe(false) -- that one is harvested now
			-- the same review committed before STAGED_SINCE is exempt from the stage line (its entry still counts)
			local old = "2026-01-01T00:00:00Z"
			git(pw, { "add", reviewPath })
			git(
				pw,
				{ "commit", "-q", "-m", "an old review" },
				{ env = { GIT_AUTHOR_DATE = old, GIT_COMMITTER_DATE = old } }
			)
			local third = prepared(id)
			if not third.ok then
				error(said(third))
			end
			t.expect(isPrepared(dir, id)).toBe(true)
			git(pw, { "add", "-A" })
			git(pw, { "commit", "-q", "-m", "case 2" })
			-- and a review committed after the date is not exempt: the same finding in a review dated 2030 is refused
			local id2, dir2 = prepIssue("new-review")
			fs.writeFile(`{dir2}/design-review-001.md`, review(nil))
			fs.writeFile(`{dir2}/harvest.md`, `# Harvest: {id2}\n\n- design-review-001 F1: one-off: a typo\n`)
			local late = "2030-01-01T00:00:00Z"
			git(pw, { "add", `{dir2}/design-review-001.md` })
			git(
				pw,
				{ "commit", "-q", "-m", "a new review" },
				{ env = { GIT_AUTHOR_DATE = late, GIT_COMMITTER_DATE = late } }
			)
			local newer = prepared(id2)
			t.expect(newer.ok).toBe(false)
			t.expect(has(said(newer), "no Stage line")).toBe(true)
			-- with the line it passes
			fs.writeFile(`{dir2}/design-review-001.md`, review("design"))
			local marked = prepared(id2)
			if not marked.ok then
				error(said(marked))
			end
			t.expect(isPrepared(dir2, id2)).toBe(true)
			git(pw, { "add", "-A" })
			git(pw, { "commit", "-q", "-m", "case 2b" })
		end
	)

	it("AC5: status prepared passes an issue with no review and one approval, as before", function()
		local id, dir = prepIssue("plain")
		fs.writeFile(`{dir}/approval.md`, approvals({ "a" }))
		local r = prepared(id)
		if not r.ok then
			error(said(r))
		end
		t.expect(isPrepared(dir, id)).toBe(true)
		git(pw, { "add", "-A" })
		git(pw, { "commit", "-q", "-m", "case 3" })
	end)

	it("sets up a built raft with a member design review", function()
		buildRaft("c0316-gates-done-github.com")
		-- the member's design review has one finding and the raft's harvest is empty
		write(
			dw,
			"pickman/.tracker/issues/active/c0010/design-review-001.md",
			"# Review 001\n\n### F1 [low] a claim\nWhere: a\nEvidence: b\nCritique: c\nConsequences: none\n"
				.. "Recommendation: d\nStage: design\n\nVerdict: approve\n"
		)
		write(
			dw,
			"pickman/.tracker/rafts/active/R0010/final-review-001.md",
			"# Final Review 001\n\nVerdict: approve\n"
		)
		git(dw, { "add", "-A" })
		git(dw, { "commit", "-qm", "c0010 implementation" })
		git(dw, { "push", "-q" })
	end)

	it(
		"AC5: done refuses a raft whose member has an unharvested finding, before any check runs, and lands once it is harvested",
		function()
			local r = zn({ "done", "R0010" })
			t.expect(r.ok).toBe(false)
			local out = said(r)
			t.expect(has(out, "c0010 design-review-001 F1")).toBe(true)
			t.expect(has(out, "harvest each in harvest.md (a lesson id, or one-off: <reason>)")).toBe(true)
			t.expect(has(out, "./zn lessons --uncovered R0010 c0010")).toBe(true)
			t.expect(fs.isFile(marker)).toBe(false) -- the raft's check.sh never ran
			-- the member's lesson is written, then the stack is finished and traced the way a lead does it
			write(
				dw,
				"pickman/.tracker/issues/active/c0010/harvest.md",
				"# Harvest: c0010\n\n- design-review-001 F1: one-off: a typo\n"
			)
			git(dw, { "add", "-A" })
			git(dw, { "commit", "-qm", "c0010 harvest" })
			znOk({ "finish", "c0010" })
			seal.trace(dw, "R0010")
			git(dw, { "push", "-q" })
			local landed = zn({ "done", "R0010" })
			if not landed.ok then
				error(said(landed))
			end
			t.expect(has(landed.stdout, "landed R0010")).toBe(true)
			t.expect(fs.isFile(marker)).toBe(true) -- now the check ran
		end
	)

	it("sets up a second built raft for the final review", function()
		buildRaft("c0316-gates-final-github.com")
	end)

	it(
		"AC5: a final-review finding harvested after the trace, with its lesson, leaves the trace current and done lands",
		function()
			git(dw, { "add", "-A" })
			git(dw, { "commit", "-qm", "c0010 implementation" })
			znOk({ "finish", "c0010" })
			seal.trace(dw, "R0010") -- trace.md, and a first final-review-001 that approves
			-- after the trace: the final review finds something, and the lead answers it
			write(
				dw,
				"pickman/.tracker/rafts/active/R0010/final-review-001.md",
				"# Final Review 001\n\n### F1 [medium] a missed case\nWhere: a\nEvidence: b\nCritique: c\n"
					.. "Consequences: none\nRecommendation: d\nStage: implementation\n\nVerdict: changes\n"
			)
			write(
				dw,
				"pickman/.tracker/rafts/active/R0010/final-refute-001.md",
				"- F1: fixed 0123abc: the case is handled; consequences: none\n"
			)
			git(dw, { "add", "-A" })
			git(dw, { "commit", "-qm", "R0010: final-review-001 changes" })
			-- a later commit, still after the trace: the finding's harvest entry, its lesson, and a member's note
			write(
				dw,
				"pickman/.tracker/rafts/active/R0010/harvest.md",
				"# Harvest: R0010\n\n- final-review-001 F1: zz-rules/final-case\n"
			)
			write(
				dw,
				"pickman/.tracker/issues/active/c0010/harvest.md",
				"# Harvest: c0010\n\n- note a remark of the final review: zz-rules/final-case\n"
			)
			write(
				dw,
				"z-nile/skills/zz-rules/lessons/final-case.md",
				"---\ntitle: A case the final review found\nwhen: build\ntags: [review]\n"
					.. "check: Is the case handled?\n---\nHandle it.\n"
			)
			git(dw, { "add", "-A" })
			git(dw, { "commit", "-qm", "R0010: harvest the final review" })
			git(dw, { "push", "-q" })
			local current = zn({ "trace", "R0010", "--check" })
			if not current.ok then
				error(said(current))
			end
			local landed = zn({ "done", "R0010" })
			if not landed.ok then
				error(said(landed))
			end
			t.expect(has(landed.stdout, "landed R0010")).toBe(true)
		end
	)

	it("sets up two readied rafts", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0010"),
			["pickman/.tracker/issues/c0010/c0010.md"] = issueDoc("c0010", "R0010"),
			["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc("R0020", "c0020"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issueDoc("c0020", "R0020"),
		}
		for _, dir in
			{
				"pickman/.tracker/rafts/R0010",
				"pickman/.tracker/issues/c0010",
				"pickman/.tracker/rafts/R0020",
				"pickman/.tracker/issues/c0020",
			}
		do
			seed[`{dir}/check.sh`] = CHECK
		end
		S = trackerfix.new("c0316-gates-stop", seed)
	end)

	it(
		"AC6: stop of a started raft writes stops: 1 and says the stop is an escape; stop of a raft that never started writes nothing",
		function()
			-- R0020 is readied and stopped without a start: an un-ready
			trackerfix.trOk(S, S.main, { "ready", "R0020" })
			local unready = trackerfix.tr(S, S.main, { "stop", "R0020" })
			t.expect(unready.ok).toBe(true)
			t.expect(has(said(unready), "is an escape")).toBe(false)
			t.expect(has(onOrigin("pickman/.tracker/rafts/R0020/R0020.md") or "", "stops:")).toBe(false)
			-- R0010 is started (a layer branch is on origin), then stopped
			trackerfix.trOk(S, S.main, { "ready", "R0010" })
			local wt = trackerfix.trOk(S, S.main, { "worktree", "R0010" })
			trackerfix.trOk(S, wt, { "start", "R0010" })
			git(wt, { "push", "-q", "origin", "HEAD" }) -- the layer branch is published whatever start does
			local stopped = trackerfix.tr(S, S.main, { "stop", "R0010" })
			if not stopped.ok then
				error(said(stopped))
			end
			local out = said(stopped)
			t.expect(has(out, "stop 1 of R0010 is an escape")).toBe(true)
			t.expect(has(out, "R0010's harvest.md")).toBe(true)
			t.expect(has(out, "- escape stop 1 (<stage>)")).toBe(true)
			t.expect(string.match(onOrigin(RAFT_DOC) or "", "\nstops: 1\n") ~= nil).toBe(true)
		end
	)

	it(
		"AC6: ready and work next refuse a raft with a stop and no entry, and take it once the entry is on main",
		function()
			local refused = trackerfix.tr(S, S.main, { "ready", "R0010" })
			t.expect(refused.ok).toBe(false)
			local why = said(refused)
			t.expect(has(why, "R0010 was stopped after it started (stop 1)")).toBe(true)
			t.expect(has(why, 'add "- escape stop 1 (<stage>): …"')).toBe(true)
			local queue = trackerfix.tr(S, S.main, { "work", "next" })
			t.expect(queue.ok).toBe(true)
			t.expect(has(queue.stdout, "was stopped after it started (stop 1)")).toBe(true)
			t.expect(has(queue.stdout, "R0010: ready")).toBe(false)
			-- the entry reaches main by pull request in real life; here another terminal pushes it
			trackerfix.elsewhere(S, {
				["pickman/.tracker/rafts/R0010/harvest.md"] = "# Harvest: R0010\n\n- escape stop 1 (design): one-off: the check was too dear\n",
			}, "R0010 stop 1 lesson")
			local taken = trackerfix.tr(S, S.main, { "work", "next" })
			t.expect(taken.ok).toBe(true)
			t.expect(string.find(taken.stdout, "^R0010: ready") ~= nil).toBe(true)
			local ready = trackerfix.tr(S, S.main, { "ready", "R0010" })
			if not ready.ok then
				error(said(ready))
			end
		end
	)

	it("AC6: land takes a capture that sets reworks", function()
		local wt = trackerfix.trOk(S, S.main, { "worktree", "capture-rework" })
		local made = trackerfix.trOk(
			S,
			wt,
			{ "new", "issue", "d", "fix-alpha", "--desc", "Alpha is wrong.", "--project", "pickman" }
		)
		local id = string.match(made, "(d%d+)") :: string
		local doc = `{wt}/pickman/.tracker/issues/{id}/{id}.md`
		local text = fs.readFile(doc)
		-- the template of the day: with a `reworks:` line (empty) or, before the template has one, without
		local withLine, n = string.gsub(text, "\nreworks:[^\n]*", "\nreworks: c0010", 1)
		if n == 0 then
			withLine = (string.gsub(text, "\ndepends_on:[^\n]*", "%0\nreworks: c0010", 1))
		end
		t.expect(string.find(withLine, "\nreworks: c0010", 1, true) ~= nil).toBe(true)
		fs.writeFile(doc, withLine)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", `tracker: new {id} fix-alpha` })
		local before = git(S.origin, { "rev-parse", "main" })
		local landed = trackerfix.tr(S, wt, { "land" }, { PICKMAN_LAND_GATE = "true" })
		if not landed.ok then
			error(said(landed))
		end
		t.expect(git(S.origin, { "rev-parse", "main" }) ~= before).toBe(true)
		local onMain = onOrigin(`pickman/.tracker/issues/{id}/{id}.md`) or ""
		t.expect(has(onMain, "\nreworks: c0010")).toBe(true)
	end)
end)
