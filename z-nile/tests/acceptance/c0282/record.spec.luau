--!strict
-- c0282 AC6: the lifecycle rows' writes, through the commands that make them, in worktrees of a trackerfix fixture
-- with a bare origin. `status <id> new` appends an `unblocked` row in its published commit (and the publish validator
-- lets that file through, append-only); `new raft`, `fold` and `recombine` append a `rafted` row per ticket, `unfold`
-- and `release` none; a raft's give-back records its issues and not the raft. The no-origin path (done, an emergent
-- issue) is lifecycle.spec.luau; `./zn provenance record`, the merge and audit are c0263's.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0282-record"
local ME = `human:{NAME}`
local SONNET = "agent:claude-sonnet-5-5 effort high"
local OPUS = "agent:claude-opus-5-5 effort high"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES, RAFTS = "pickman/.tracker/issues", "pickman/.tracker/rafts"
-- every variable a command that records reads, cleared: the one list is the engine's (a marker added to the hint is
-- cleared here too)
local HUMAN: { [string]: string } = {}
for _, name in provenance.ENV_VARS do
	HUMAN[name] = ""
end

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 300\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function draft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-amber-otter-lynx\n---\n\n# {id}\n`
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Landed\nslug: landed\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nLanded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
end

local f: trackerfix.Fixture
local W1, W2, W3, W4 = "", "", "", ""

local function env(extra: { [string]: string }?): { [string]: string }
	local out: { [string]: string } = table.clone(HUMAN)
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
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function onOrigin(path: string): string
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else ""
end
local function rows(text: string, event: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		if has(line, `| {event} |`) then
			table.insert(out, line)
		end
	end
	return out
end
local function localRecord(wt: string, id: string): string
	local p = `{wt}/{ISSUES}/{id}/provenance.md`
	return if fs.isFile(p) then fs.readFile(p) else ""
end
return t.spec("c0282 the lifecycle rows' writes", function(it)
	it("sets up a fixture with an origin, drafts, prepared issues and landed prepared rafts", function()
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
		for _, id in { "c0040", "c0050", "c0070", "c0080" } do
			seed[`{ISSUES}/{id}/{id}.md`] = issue(id, "")
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		seed[`{ISSUES}/c0070/c0070.md`] = issue("c0070", "R0140")
		seed[`{ISSUES}/c0050/c0050.md`] = issue("c0050", "R0130")
		for _, r in { { "R0110", "" }, { "R0130", "c0050" }, { "R0140", "c0070" } } do
			seed[`{RAFTS}/{r[1]}/{r[1]}.md`] = raftDoc(r[1], r[2])
			seed[`{RAFTS}/{r[1]}/check.sh`] = CHECK
		end
		f = trackerfix.new(NAME, seed)
		W1 = trackerfix.trOk(f, f.main, { "worktree", "prep-a" })
		W2 = trackerfix.trOk(f, f.main, { "worktree", "raft-b" })
		W3 = trackerfix.trOk(f, f.main, { "worktree", "raft-c" })
		W4 = trackerfix.trOk(f, f.main, { "worktree", "raft-d" })
		-- the fixture audits clean before any of this, so a refusal below is the record's
		trOk(W1, { "audit" })
	end)

	it(
		"status new publishes an unblocked row in the same commit, the publish validator lets the file through append-only",
		function()
			trOk(W1, { "status", "c0010", "preparing" })
			local before = tip()
			t.expect(onOrigin(`{ISSUES}/c0010/provenance.md`)).toBe("")
			trOk(W1, { "status", "c0010", "new" }, { ZN_ACTOR = SONNET })
			local rec = onOrigin(`{ISSUES}/c0010/provenance.md`)
			t.expect(#rows(rec, "unblocked")).toBe(1)
			t.expect(has(rec, `| unblocked | {SONNET} |`)).toBe(true)
			-- one commit changed the status document and the record, and nothing else
			local changed = fixture.git(f.origin, { "diff", "--name-only", before, "main" })
			t.expect(changed).toBe(`{ISSUES}/c0010/c0010.md\n{ISSUES}/c0010/provenance.md`)
			-- a move that changes nothing (the issue is already new) publishes nothing and records nothing
			local settled = tip()
			t.expect(tr(W1, { "status", "c0010", "new" }, { ZN_ACTOR = SONNET }).ok).toBe(false)
			t.expect(tip()).toBe(settled)
			-- every give-back appends: two rows, the first untouched; the flag beats the environment
			trOk(W1, { "status", "c0010", "preparing" })
			trOk(W1, { "status", "c0010", "new", "--actor", OPUS }, { ZN_ACTOR = SONNET })
			local two = onOrigin(`{ISSUES}/c0010/provenance.md`)
			t.expect(#rows(two, "unblocked")).toBe(2)
			t.expect(has(two, `| unblocked | {SONNET} |`)).toBe(true)
			t.expect(has(two, `| unblocked | {OPUS} |`)).toBe(true)
			-- an agent session with no actor says so, a bad actor refuses before anything is published
			trOk(W1, { "status", "c0010", "preparing" })
			trOk(W1, { "status", "c0010", "new" }, { CLAUDECODE = "1", CLAUDE_EFFORT = "medium" })
			t.expect(
				has(onOrigin(`{ISSUES}/c0010/provenance.md`), "| unblocked | agent:unknown effort medium |")
			)
				.toBe(true)
			trOk(W1, { "status", "c0010", "preparing" })
			local mark = tip()
			for _, bad in { "nonsense", "none", "unknown", "human:A (from git)" } do
				t.expect(tr(W1, { "status", "c0010", "new", "--actor", bad }).ok).toBe(false)
				t.expect(tip()).toBe(mark)
			end
			t.expect(tr(W1, { "status", "c0010", "new" }, { ZN_ACTOR = "robot:x" }).ok).toBe(false)
			trOk(W1, { "status", "c0010", "new" })
			t.expect(has(onOrigin(`{ISSUES}/c0010/provenance.md`), `| unblocked | {ME} |`)).toBe(true)
		end
	)

	it("a raft's give-back records its issues and never the raft; release records nothing", function()
		local out = trOk(
			W2,
			{ "new", "raft", "chore", "pair", "c0011", "c0012", "--project", "pickman", "--actor", SONNET },
			{ ZN_ACTOR = OPUS, ZN_VIA = "dispatch:raft-plan" }
		)
		local rid = string.match(out, "(R%d+)") :: string
		-- the old-flow raft claimed two new drafts; each got a rafted row, one per ticket, in the worktree
		for _, id in { "c0011", "c0012" } do
			local rec = localRecord(W2, id)
			t.expect(#rows(rec, "rafted")).toBe(1)
			t.expect(has(rec, `| rafted | {SONNET} | raft={rid}; via=dispatch:raft-plan |`)).toBe(true)
		end
		t.expect(fs.isFile(`{W2}/{RAFTS}/{rid}/provenance.md`)).toBe(false)
		trOk(W2, { "status", rid, "new" }, { ZN_ACTOR = OPUS })
		-- a published append is built from origin/main's file: the worktree's rafted row never reaches main
		for _, id in { "c0011", "c0012" } do
			t.expect(#rows(onOrigin(`{ISSUES}/{id}/provenance.md`), "rafted")).toBe(0)
		end
		-- the worktree held a committed rafted row and main got an unblocked row: the engine's merge unioned the file
		for _, id in { "c0011", "c0012" } do
			t.expect(#rows(onOrigin(`{ISSUES}/{id}/provenance.md`), "unblocked")).toBe(1)
			local merged = localRecord(W2, id)
			t.expect(#rows(merged, "rafted")).toBe(1)
			t.expect(#rows(merged, "unblocked")).toBe(1)
		end
		t.expect(fixture.git(W2, { "status", "--porcelain" })).toBe("")
		t.expect(onOrigin(`{RAFTS}/{rid}/provenance.md`)).toBe("")
		trOk(W2, { "audit" })
		-- release gives a rafting claim back without a row
		local second = trOk(W3, { "new", "raft", "chore", "solo", "c0013", "--project", "pickman" })
		local rid2 = string.match(second, "(R%d+)") :: string
		-- no ZN_VIA, no via=
		t.expect(has(localRecord(W3, "c0013"), "| rafted |")).toBe(true)
		t.expect(has(localRecord(W3, "c0013"), "via=")).toBe(false)
		trOk(W3, { "release", rid2, "--force" })
		t.expect(onOrigin(`{ISSUES}/c0013/provenance.md`)).toBe("")
		-- a raft's give-back skips a member that is prepared (a prepared member is never restamped): no row for it
		trOk(W2, { "status", "R0140", "preparing" })
		trOk(W2, { "status", "R0140", "new" }, { ZN_ACTOR = OPUS })
		t.expect(onOrigin(`{ISSUES}/c0070/provenance.md`)).toBe("")
		t.expect(onOrigin(`{RAFTS}/R0140/provenance.md`)).toBe("")
	end)

	it("fold and recombine append a rafted row per ticket, unfold keeps the history", function()
		trOk(W3, { "fold", "R0110", "c0040", "--actor", OPUS }, { ZN_ACTOR = SONNET })
		local rec = localRecord(W3, "c0040")
		t.expect(has(rec, `| rafted | {OPUS} | raft=R0110`)).toBe(true)
		trOk(W3, { "unfold", "R0110", "c0040" })
		-- append-only: the row stays, the raft: line is gone
		t.expect(#rows(localRecord(W3, "c0040"), "rafted")).toBe(1)
		t.expect(string.match(fs.readFile(`{W3}/{ISSUES}/c0040/c0040.md`), "\nraft: ([^\n]*)\n")).toBe("")
		-- a bad actor or a bad ZN_VIA refuses recombine before it claims anything
		local mark = tip()
		for _, env in { { ZN_ACTOR = "robot:x" }, { ZN_VIA = "dispatch" } } do
			local refused = tr(W4, { "recombine", "R0130", "R0140" }, env)
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "ZN_VIA") or has(refused.stderr, "not an actor")).toBe(true)
			t.expect(tip()).toBe(mark)
		end
		trOk(W4, { "recombine", "R0130", "R0140", "--actor", SONNET }, { ZN_ACTOR = OPUS })
		local moved = localRecord(W4, "c0070")
		t.expect(has(moved, `| rafted | {SONNET} | raft=R0130`)).toBe(true)
		t.expect(fs.isFile(`{W4}/{RAFTS}/R0130/provenance.md`)).toBe(false)
	end)

	it(
		"a bad actor or a bad ZN_VIA refuses new raft and fold before anything is published or written",
		function()
			local mark = tip()
			local cases: { { args: { string }, cwd: string, env: { [string]: string }, says: string } } = {
				{
					args = { "new", "raft", "chore", "bad", "c0013", "--project", "pickman" },
					cwd = W1,
					env = { ZN_ACTOR = "robot:x" },
					says = "not an actor",
				},
				{
					args = { "new", "raft", "chore", "bad", "c0013", "--project", "pickman" },
					cwd = W1,
					env = { ZN_VIA = "dispatch" },
					says = "ZN_VIA",
				},
				{
					args = { "new", "raft", "chore", "bad", "c0013", "--project", "pickman" },
					cwd = W1,
					env = { GIT_AUTHOR_NAME = "", GIT_AUTHOR_EMAIL = "" },
					says = "git identity",
				},
				{
					args = { "status", "c0012", "new" },
					cwd = W1,
					env = { GIT_AUTHOR_NAME = "", GIT_AUTHOR_EMAIL = "" },
					says = "git identity",
				},
				{
					args = { "fold", "R0110", "c0040" },
					cwd = W3,
					env = { ZN_ACTOR = "none" },
					says = "not an actor",
				},
				{
					args = { "fold", "R0110", "c0040", "--actor", "human:A (from git)" },
					cwd = W3,
					env = {},
					says = "not an actor",
				},
				{ args = { "fold", "R0110", "c0040" }, cwd = W3, env = { ZN_VIA = "x:y" }, says = "ZN_VIA" },
			}
			for i, case in cases do
				local r = tr(case.cwd, case.args, case.env)
				if r.ok or not has(r.stderr .. r.stdout, case.says) then
					error(`case {i} wanted a refusal saying "{case.says}"\n{r.stdout}{r.stderr}`)
				end
				t.expect(tip()).toBe(mark)
				t.expect(fixture.git(case.cwd, { "status", "--porcelain" })).toBe("")
			end
			-- a command that records nothing reads no actor: a plain new issue goes through with a bad ZN_ACTOR
			trOk(W1, { "new", "issue", "c", "stray", "--project", "pickman" }, { ZN_ACTOR = "robot:x" })
			t.expect(fs.isFile(`{W3}/{ISSUES}/c0040/c0040.md`)).toBe(true)
			t.expect(string.match(fs.readFile(`{W3}/{ISSUES}/c0040/c0040.md`), "\nraft: ([^\n]*)\n")).toBe("")
			-- a stray ZN_VIA shape is only a dispatcher step: a good one is recorded, nothing else is
			trOk(W3, { "fold", "R0110", "c0040" }, { ZN_ACTOR = OPUS, ZN_VIA = "dispatch:raft-plan" })
			t.expect(
				has(localRecord(W3, "c0040"), `| rafted | {OPUS} | raft=R0110; via=dispatch:raft-plan |`)
			)
				.toBe(true)
		end
	)

	it("a member record that does not parse refuses fold before the claim is published", function()
		trOk(W3, { "unfold", "R0110", "c0040" })
		local path = `{W3}/{ISSUES}/c0040/provenance.md`
		local good = fs.readFile(path)
		fs.writeFile(path, good .. "a hand edit\n")
		fixture.git(W3, { "add", "-A" })
		fixture.git(W3, { "commit", "-q", "-m", "a hand edit of a record" })
		local mark = tip()
		local r = tr(W3, { "fold", "R0110", "c0040" }, { ZN_ACTOR = OPUS })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0040/provenance.md: line")).toBe(true)
		t.expect(tip()).toBe(mark)
		t.expect(fixture.git(W3, { "status", "--porcelain" })).toBe("")
		fixture.git(W3, { "reset", "-q", "--hard", "HEAD~1" })
	end)

	it("raft-plan --apply hands its --actor to every command it runs", function()
		local out = trOk(W3, { "raft-plan", "--apply", "--actor", "human:Zed" }, { ZN_ACTOR = SONNET })
		t.expect(has(out, "new raft")).toBe(true)
		for _, id in { "c0040", "c0080" } do
			t.expect(has(localRecord(W3, id), "| rafted | human:Zed | raft=R")).toBe(true)
		end
	end)
end)
