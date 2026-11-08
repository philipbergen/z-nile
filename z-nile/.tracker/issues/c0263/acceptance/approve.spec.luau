--!strict
-- c0263 AC4, AC5: `./zn approve <id>` and the refusal of `./zn status <id> prepared` without a current approval, driven
-- for real in worktrees of a trackerfix fixture (a bare origin, the way c0116's claims spec drives the carried move).
-- The approval is a row of the issue's provenance.md, its human is the git author of the `tracker: approve` commit, an
-- agent session needs the user's words, a dispatched worker cannot approve, a redesign makes the approval stale, and a
-- raft's move needs each issue it moves approved.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0263-approve"
local ME = `human:{NAME}` -- trackerfix's git identity
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES = "pickman/.tracker/issues"
-- an agent session's hints must not leak into the human cases
local HUMAN: { [string]: string } =
	{ CLAUDECODE = "", AI_AGENT = "", CLAUDE_EFFORT = "", ZN_ACTOR = "", ZN_DISPATCH = "" }

local function draft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-amber-otter-lynx\n---\n\n# {id}\n\n## Design\nOne.\n`
end

local f: trackerfix.Fixture
local W1, W2 = "", ""

local function env(extra: { [string]: string }?): { [string]: string }
	local out: { [string]: string } = {}
	for k, v in HUMAN do
		out[k] = v
	end
	local more: { [string]: string } = extra or {}
	for k, v in more do
		out[k] = v
	end
	return out
end
local function tr(cwd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, cwd, args, env(extra))
end
local function trOk(cwd: string, args: { string }, extra: { [string]: string }?): string
	local r = tr(cwd, args, extra)
	if not r.ok then
		error(`{table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function setLine(path: string, key: string, value: string)
	local text = fs.readFile(path)
	local s, e = string.find(text, `\n{key}:[^\n]*\n`)
	assert(s and e, `{path} has no {key}:`)
	fs.writeFile(path, string.sub(text, 1, s) .. `{key}: {value}\n` .. string.sub(text, e + 1))
end
local function record(wt: string, id: string): string
	local p = `{wt}/{ISSUES}/{id}/provenance.md`
	return if fs.isFile(p) then fs.readFile(p) else ""
end
-- claims `id` for design here and marks its design ready, as z-design does before its last review
local function ready(wt: string, id: string)
	trOk(wt, { "status", id, "preparing" })
	setLine(`{wt}/{ISSUES}/{id}/{id}.md`, "design", "ready")
end

return t.spec("c0263 approve and the refusal of prepared", function(it)
	it("sets up a fixture with an origin and four drafts", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			-- the counter a published tree has: audit reads it
			["z-nile/next"] = "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n",
		}
		for _, id in { "c0010", "c0011", "c0012", "c0013" } do
			seed[`{ISSUES}/{id}/{id}.md`] = draft(id)
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		-- c0014 and c0016 were approved once and redesigned since (the approval covers another hash); c0015 was prepared
		-- before approvals existed (no record at all); R0110 is a landed prepared raft to fold into, R0120 one holding c0016
		local function prepared(id: string, raft: string): string
			return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 300\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
		end
		local function stale(id: string): string
			return `# Provenance: {id}\n\n| when | event | actor | detail |\n|---|---|---|---|\n| 2026-10-21 10:00 | approved | human:Ann | design=000000000000 |\n`
		end
		local function raftOf(id: string, issues: string): string
			return `---\nid: {id}\ntype: chore\ntitle: Landed\nslug: landed\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Theme\nLanded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
		end
		for _, id in { "c0014", "c0015", "c0016" } do
			seed[`{ISSUES}/{id}/{id}.md`] = prepared(id, if id == "c0016" then "R0120" else "")
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		seed[`{ISSUES}/c0014/provenance.md`] = stale("c0014")
		seed[`{ISSUES}/c0016/provenance.md`] = stale("c0016")
		-- c0017 was never approved and is not on the list; c0018 is on the list at a design it no longer has
		for _, id in { "c0017", "c0018" } do
			seed[`{ISSUES}/{id}/{id}.md`] = prepared(id, "")
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		-- the frozen list: c0015 at its current design (the record hash of its document and check.sh), c0018 at another
		local c15hash =
			raftplan.recordHash("c0015", { ["c0015.md"] = prepared("c0015", ""), ["check.sh"] = CHECK })
		seed["z-nile/provenance-exempt.txt"] = `# frozen\nc0015 {c15hash}\nc0018 000000000000\n`
		seed["pickman/.tracker/rafts/R0110/R0110.md"] = raftOf("R0110", "")
		seed["pickman/.tracker/rafts/R0110/check.sh"] = CHECK
		seed["pickman/.tracker/rafts/R0120/R0120.md"] = raftOf("R0120", "c0016")
		seed["pickman/.tracker/rafts/R0120/check.sh"] = CHECK
		f = trackerfix.new(NAME, seed)
		W1 = trackerfix.trOk(f, f.main, { "worktree", "prep-a" })
		W2 = trackerfix.trOk(f, f.main, { "worktree", "prep-b" })
	end)

	it(
		"prepared is refused until a human has approved, and the approval is a row with the human and the design hash",
		function()
			ready(W1, "c0010")
			local refused = tr(W1, { "status", "c0010", "prepared" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "no current approval")).toBe(true)
			t.expect(has(refused.stderr, "./zn approve c0010")).toBe(true)
			trOk(W1, { "approve", "c0010" })
			local rec = record(W1, "c0010")
			t.expect(has(rec, `| approved | {ME} | design=`)).toBe(true)
			t.expect(
				string.match(rec, "design=(%x+)") ~= nil
					and #(string.match(rec, "design=(%x+)") :: string) == 12
			).toBe(true)
			-- the approve commit is the human's: its author is the git identity, its subject names the issue
			t.expect(fixture.git(W1, { "log", "-1", "--format=%an|%s" }))
				.toBe(`{NAME}|tracker: approve c0010`)
			t.expect(fixture.git(W1, { "status", "--porcelain" })).toBe("")
			-- a dispatched worker cannot prepare a design either, approval or not
			local dispatched = tr(W1, { "status", "c0010", "prepared" }, { ZN_DISPATCH = "1" })
			t.expect(dispatched.ok).toBe(false)
			t.expect(has(dispatched.stderr, "dispatch")).toBe(true)
			-- now the carried move goes through, and it is carried: nothing is published
			local before = fixture.git(f.origin, { "rev-parse", "main" })
			trOk(W1, { "status", "c0010", "prepared" })
			t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
			t.expect(
				string.match(fs.readFile(`{W1}/{ISSUES}/c0010/c0010.md`), "\nstatus: (prepared)%-") ~= nil
			)
				.toBe(true)
			-- the carried move only edits the document: commit it, so the next cases start from a clean worktree
			fixture.git(W1, { "add", "-A" })
			fixture.git(W1, { "commit", "-q", "-m", "tracker: prep c0010" })
		end
	)

	it(
		"approve refuses an agent session, a worker, the main checkout, an unclaimed issue, an undesigned one and no identity, each for its own reason",
		function()
			ready(W1, "c0011")
			local mark = fixture.git(W1, { "rev-parse", "HEAD" })
			local function refused(args: { string }, why: string, extra: { [string]: string }?, cwd: string?)
				local r = tr(cwd or W1, args, extra)
				t.expect(r.ok).toBe(false)
				if not has(r.stderr, why) then
					error(`{table.concat(args, " ")}: stderr lacks "{why}": {r.stderr}`, 2)
				end
				t.expect(fixture.git(W1, { "rev-parse", "HEAD" })).toBe(mark)
				t.expect(has(record(W1, "c0011"), "approved")).toBe(false)
			end
			refused({ "approve", "c0011" }, "dispatch", { ZN_DISPATCH = "1" })
			refused({ "approve", "c0011" }, "worktree", nil, f.main)
			-- an issue claimed but with a draft design, and an issue not claimed at all (its design set by hand)
			trOk(W2, { "status", "c0012", "preparing" })
			local undesigned = tr(W2, { "approve", "c0012" })
			t.expect(undesigned.ok).toBe(false)
			t.expect(has(undesigned.stderr, "design: ready")).toBe(true)
			setLine(`{W2}/{ISSUES}/c0013/c0013.md`, "design", "ready")
			local unclaimed = tr(W2, { "approve", "c0013" })
			t.expect(unclaimed.ok).toBe(false)
			t.expect(has(unclaimed.stderr, "preparing")).toBe(true)
			-- a change outside the issue's folder is not the approval's to commit
			fs.writeFile(`{W1}/stray.txt`, "x\n")
			refused({ "approve", "c0011" }, "outside")
			fs.removeFile(`{W1}/stray.txt`)
			-- and a change in another issue's folder is outside too
			fs.writeFile(
				`{W1}/{ISSUES}/c0012/c0012.md`,
				fs.readFile(`{W1}/{ISSUES}/c0012/c0012.md`) .. "\nedit\n"
			)
			refused({ "approve", "c0011" }, "outside")
			fixture.git(W1, { "checkout", "--", `{ISSUES}/c0012/c0012.md` })
			-- no git identity: the human cannot be named
			refused(
				{ "approve", "c0011" },
				"identity",
				{
					GIT_AUTHOR_NAME = "",
					GIT_AUTHOR_EMAIL = "",
					GIT_COMMITTER_NAME = "",
					GIT_COMMITTER_EMAIL = "",
				}
			)
			-- an agent session or a dispatched step is refused whatever it passes: the human must have run it, and the
			-- refusal tells the user where (their own terminal); there is no option, flag or variable that lets it through
			local sessions: { { [string]: string } } = {
				{ CLAUDECODE = "1", CLAUDE_EFFORT = "high" },
				{ AI_AGENT = "claude-code_2" },
				{ ZN_DISPATCH = "1" },
				{ CLAUDECODE = "1", ZN_ACTOR = "human:" .. NAME },
			}
			for _, extra in sessions do
				refused({ "approve", "c0011" }, "your own terminal", extra)
			end
			refused(
				{ "approve", "c0011", "--said", "the user said yes" },
				"your own terminal",
				{ CLAUDECODE = "1" }
			)
			-- a human session approves: it records the human and the design, with no words and no agent trace
			trOk(W1, { "approve", "c0011" })
			local rec = record(W1, "c0011")
			t.expect(has(rec, `| approved | {ME} | design=`)).toBe(true)
			t.expect(has(rec, "said=")).toBe(false)
			t.expect(has(rec, "via=")).toBe(false)
		end
	)

	it(
		"a redesign makes the approval stale, a stop with no edit keeps it, and a fresh approval makes it current",
		function()
			local doc = `{W1}/{ISSUES}/c0011/c0011.md`
			local function landIt()
				fixture.git(W1, { "add", "-A" })
				fixture.git(W1, { "commit", "-q", "-m", "wip" })
				fixture.git(W1, { "fetch", "-q", "origin" })
				fixture.git(W1, { "merge", "-q", "--no-edit", "origin/main" })
				fixture.git(W1, { "push", "-q", "origin", "HEAD:main" })
			end
			-- prepared with a current approval, landed
			trOk(W1, { "status", "c0011", "prepared" })
			landIt()
			-- a stop gives it back (prepared -> preparing) and nothing changes: the approval still covers it
			trOk(W1, { "status", "c0011", "preparing" })
			trOk(W1, { "status", "c0011", "prepared" })
			landIt()
			-- a redesign after a stop: the approval is stale
			trOk(W1, { "status", "c0011", "preparing" })
			fs.writeFile(doc, fs.readFile(doc) .. "\nA changed rule.\n")
			fixture.git(W1, { "add", "-A" })
			fixture.git(W1, { "commit", "-q", "-m", "redesign" })
			local stale = tr(W1, { "status", "c0011", "prepared" })
			t.expect(stale.ok).toBe(false)
			t.expect(has(stale.stderr, "redesigned since its approval")).toBe(true)
			t.expect(has(stale.stderr, "./zn approve c0011")).toBe(true)
			-- so is an edit to the sequestered check.sh, on its own
			fs.writeFile(doc, (string.gsub(fs.readFile(doc), "\nA changed rule%.\n", "")))
			fs.writeFile(`{W1}/{ISSUES}/c0011/check.sh`, CHECK .. "# edited\n")
			t.expect(tr(W1, { "status", "c0011", "prepared" }).ok).toBe(false)
			fs.writeFile(`{W1}/{ISSUES}/c0011/check.sh`, CHECK)
			fs.writeFile(doc, fs.readFile(doc) .. "\nA changed rule.\n")
			trOk(W1, { "approve", "c0011" })
			trOk(W1, { "status", "c0011", "prepared" })
			-- the approvals stack: two rows now, the newest counts
			local _, n = string.gsub(record(W1, "c0011"), "| approved |", "")
			t.expect(n).toBe(2)
		end
	)

	it(
		"the doors are shut: fold, new raft, ready and raft-plan refuse a prepared issue with no current approval unless the frozen list covers its design, and audit errors",
		function()
			local function tip(): string
				return fixture.git(f.origin, { "rev-parse", "main" })
			end
			local function onOrigin(path: string): string
				return fixture.git(f.origin, { "show", `main:{path}` })
			end
			-- fold and new raft merge origin/main, so the worktree must be clean
			fixture.git(W2, { "add", "-A" })
			fixture.git(W2, { "commit", "-q", "--allow-empty", "-m", "wip" })
			local before = tip()
			-- audit: an error for each prepared issue that has no current approval and is not covered by the list
			local audit = tr(W2, { "audit" })
			t.expect(audit.ok).toBe(false)
			local said = audit.stdout .. audit.stderr
			for _, id in { "c0014", "c0016", "c0017", "c0018" } do
				t.expect(has(said, id)).toBe(true)
			end
			t.expect(has(said, "c0015")).toBe(false) -- listed, design unchanged
			-- each door refuses before it publishes anything, with the reason of its case
			local function door(args: { string }, id: string, why: string)
				local r = tr(W2, args)
				if r.ok then
					error(`{table.concat(args, " ")} was accepted: {r.stdout}{r.stderr}`, 2)
				end
				if not has(r.stderr, id) or not has(r.stderr, why) then
					error(`{table.concat(args, " ")}: stderr lacks {id} / {why}: {r.stderr}`, 2)
				end
			end
			door({ "fold", "R0110", "c0014" }, "c0014", "no longer covers")
			door({ "fold", "R0110", "c0017" }, "c0017", "without an approval")
			door({ "fold", "R0110", "c0018" }, "c0018", "redesigned since the freeze")
			door(
				{ "new", "raft", "chore", "x", "c0017", "--project", "pickman" },
				"c0017",
				"without an approval"
			)
			local ready = tr(f.main, { "ready", "R0120" })
			t.expect(ready.ok).toBe(false)
			t.expect(has(ready.stderr, "c0016")).toBe(true)
			t.expect(has(ready.stderr, "no longer covers")).toBe(true)
			t.expect(tip()).toBe(before)
			t.expect(string.match(onOrigin("pickman/.tracker/rafts/R0110/R0110.md"), "\nstatus: prepared%-"))
				.toBe("\nstatus: prepared-")
			-- raft-plan skips each and plans the listed one, applying nothing half-way
			local plan = tr(W2, { "raft-plan" })
			t.expect(plan.ok).toBe(true)
			for _, id in { "c0014", "c0017", "c0018" } do
				t.expect(has(plan.stdout, `skip {id}`)).toBe(true)
			end
			t.expect(has(plan.stdout, "skip c0015")).toBe(false)
			-- an issue the frozen list covers (listed at its current design) passes
			local ok = tr(W2, { "fold", "R0110", "c0015" })
			if not ok.ok then
				error(ok.stderr .. ok.stdout)
			end
		end
	)

	it("a raft's move refuses each issue it moves that has no current approval", function()
		-- new raft merges origin/main after its claim, so the worktree must be clean
		fixture.git(W2, { "add", "-A" })
		fixture.git(W2, { "commit", "-q", "--allow-empty", "-m", "wip" })
		local out = trOk(W2, { "new", "raft", "chore", "pair", "c0013", "--project", "pickman" })
		local rid = string.match(out, "(R%d+)") :: string
		setLine(`{W2}/{ISSUES}/c0013/c0013.md`, "design", "ready")
		setLine(`{W2}/pickman/.tracker/rafts/{rid}/{rid}.md`, "design", "ready")
		-- approve commits the issue's folder only: the raft's own edit is committed first
		fixture.git(W2, { "add", `pickman/.tracker/rafts/{rid}` })
		fixture.git(W2, { "commit", "-q", "-m", "raft design ready" })
		local refused = tr(W2, { "status", rid, "prepared" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "c0013")).toBe(true)
		t.expect(has(refused.stderr, "no current approval")).toBe(true)
		trOk(W2, { "approve", "c0013" })
		local again = tr(W2, { "status", rid, "prepared" })
		-- the approval no longer blocks it; any other refusal (the raft's own Theme) is the raft's rule
		t.expect(has(again.stderr, "no current approval")).toBe(false)
	end)
end)
