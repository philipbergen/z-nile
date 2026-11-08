--!strict
-- c0263 AC5, AC6, AC7: the record's writes, through the commands that make them, in worktrees of a trackerfix fixture
-- with a bare origin. `status <id> new` appends an `unblocked` row in its published commit (and the publish validator
-- lets that file through, append-only); `./zn record` publishes a `confirmed` row for the tickets that will call it;
-- `new raft`, `fold` and `recombine` append a `rafted` row per ticket, `unfold` and `release` none; a raft's give-back
-- records its issues and not the raft; `./zn record` also reaches a raft's record and an active item's; `./zn audit`
-- refuses a malformed one. The no-origin path (done, an emergent issue) is
-- lifecycle.spec.luau.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0263-record"
local ME = `human:{NAME}`
local SONNET = "agent:claude-sonnet-5-5 effort high"
local OPUS = "agent:claude-opus-5-5 effort high"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES, RAFTS = "pickman/.tracker/issues", "pickman/.tracker/rafts"
local HUMAN: { [string]: string } =
	{ CLAUDECODE = "", AI_AGENT = "", CLAUDE_EFFORT = "", ZN_ACTOR = "", ZN_DISPATCH = "" }

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
local W1, W2, W3, W4, W5 = "", "", "", "", ""

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
local function land(wt: string)
	fixture.git(wt, { "fetch", "-q", "origin" })
	fixture.git(wt, { "merge", "-q", "--no-edit", "origin/main" })
	fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
	fixture.git(f.main, { "pull", "-q", "origin", "main" })
end

return t.spec("c0263 the record's writes", function(it)
	it("sets up a fixture with an origin, drafts, prepared issues and landed prepared rafts", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			-- the counter a published tree has: audit reads it
			["z-nile/next"] = "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n",
		}
		for _, id in { "c0010", "c0011", "c0012", "c0013", "c0019" } do
			seed[`{ISSUES}/{id}/{id}.md`] = draft(id)
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		for _, id in { "c0040", "c0050", "c0070" } do
			seed[`{ISSUES}/{id}/{id}.md`] = issue(id, "")
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		seed[`{ISSUES}/c0070/c0070.md`] = issue("c0070", "R0140")
		seed[`{ISSUES}/c0050/c0050.md`] = issue("c0050", "R0130")
		-- an active raft holding an active issue (a worker blocks while it holds a raft: c0250)
		seed[`{ISSUES}/active/c0090/c0090.md`] = (string.gsub(issue("c0090", "R0150"), "status: prepared%-quiet%-copper%-falcon", "status: active-quiet-copper-falcon"))
		seed[`{ISSUES}/active/c0090/check.sh`] = CHECK
		seed[`{RAFTS}/active/R0150/R0150.md`] = (string.gsub(raftDoc("R0150", "c0090"), "status: prepared%-quiet%-copper%-falcon", "status: active-quiet-copper-falcon"))
		seed[`{RAFTS}/active/R0150/check.sh`] = CHECK
		for _, r in { { "R0110", "" }, { "R0130", "c0050" }, { "R0140", "c0070" } } do
			seed[`{RAFTS}/{r[1]}/{r[1]}.md`] = raftDoc(r[1], r[2])
			seed[`{RAFTS}/{r[1]}/check.sh`] = CHECK
		end
		f = trackerfix.new(NAME, seed)
		W1 = trackerfix.trOk(f, f.main, { "worktree", "prep-a" })
		W2 = trackerfix.trOk(f, f.main, { "worktree", "raft-b" })
		W3 = trackerfix.trOk(f, f.main, { "worktree", "raft-c" })
		W4 = trackerfix.trOk(f, f.main, { "worktree", "raft-d" })
		W5 = trackerfix.trOk(f, f.main, { "worktree", "raft-e" })
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
			{ "new", "raft", "chore", "pair", "c0011", "c0012", "--project", "pickman" },
			{ ZN_ACTOR = SONNET, ZN_VIA = "dispatch:raft-plan" }
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
	end)

	it("fold and recombine append a rafted row per ticket, unfold keeps the history", function()
		trOk(W3, { "fold", "R0110", "c0040" }, { ZN_ACTOR = OPUS })
		local rec = localRecord(W3, "c0040")
		t.expect(has(rec, `| rafted | {OPUS} | raft=R0110`)).toBe(true)
		trOk(W3, { "unfold", "R0110", "c0040" })
		-- append-only: the row stays, the raft: line is gone
		t.expect(#rows(localRecord(W3, "c0040"), "rafted")).toBe(1)
		t.expect(string.match(fs.readFile(`{W3}/{ISSUES}/c0040/c0040.md`), "\nraft: ([^\n]*)\n")).toBe("")
		trOk(W4, { "recombine", "R0130", "R0140" }, { ZN_ACTOR = SONNET })
		local moved = localRecord(W4, "c0070")
		t.expect(has(moved, `| rafted | {SONNET} | raft=R0130`)).toBe(true)
		t.expect(fs.isFile(`{W4}/{RAFTS}/R0130/provenance.md`)).toBe(false)
	end)

	it(
		"./zn record publishes the events other tickets will call and refuses the rest",
		function()
			land(W3)
			local before = tip()
			trOk(W1, { "record", "c0011", "confirmed", "--actor", "human:Ann", "--detail", 'said="yes"' })
			local rec = onOrigin(`{ISSUES}/c0011/provenance.md`)
			t.expect(has(rec, '| confirmed | human:Ann | said="yes"')).toBe(true)
			t.expect(fixture.git(f.origin, { "diff", "--name-only", before, "main" }))
				.toBe(`{ISSUES}/c0011/provenance.md`)
			trOk(W1, { "record", "c0011", "ranked", "--detail", "rank=3" })
			t.expect(#rows(onOrigin(`{ISSUES}/c0011/provenance.md`), "ranked")).toBe(1)
			-- the closed list, the actor grammar, and the events another command writes
			local mark = tip()
			for _, args in
				{
					{ "record", "c0011", "invented" },
					{ "record", "c0011", "approved" },
					{ "record", "c0011", "rafted" },
					{ "record", "c0011", "confirmed", "--actor", "somebody" },
					{ "record", "c0099", "confirmed" },
				}
			do
				t.expect(tr(W1, args).ok).toBe(false)
				t.expect(tip()).toBe(mark)
			end
		end
	)

	it("./zn record reaches a raft's record and an active item's, and takes unblocked rows only there", function()
		trOk(W1, { "record", "R0130", "unblocked", "--actor", "human:Ann", "--detail", "block=needs-decision" })
		t.expect(has(onOrigin(`{RAFTS}/R0130/provenance.md`), "| unblocked | human:Ann | block=needs-decision |")).toBe(true)
		trOk(W1, { "record", "c0090", "unblocked", "--actor", "human:Ann", "--detail", "block=red-gate" })
		t.expect(has(onOrigin(`{ISSUES}/active/c0090/provenance.md`), "| unblocked | human:Ann | block=red-gate |")).toBe(true)
		local mark = tip()
		t.expect(tr(W1, { "record", "c0090", "confirmed", "--actor", "human:Ann" }).ok).toBe(false)
		t.expect(tip()).toBe(mark)
	end)

	it("a conflict outside provenance.md aborts the merge and leaves the tree as it was", function()
		local doc = `{W4}/{ISSUES}/c0050/c0050.md`
		local rec = `{W4}/{ISSUES}/c0050/provenance.md`
		local head = "# Provenance: c0050\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
		local function edit(text: string, title: string): string
			return (string.gsub(text, "\ntitle: [^\n]*\n", `\ntitle: {title}\n`, 1))
		end
		fs.writeFile(doc, edit(fs.readFile(doc), "ours"))
		fs.writeFile(rec, head .. "| 2026-11-08 10:00 | unblocked | human:Ann |  |\n")
		fixture.git(W4, { "add", "-A" })
		fixture.git(W4, { "commit", "-q", "-m", "our edit" })
		local before = fixture.git(W4, { "rev-parse", "HEAD" })
		trackerfix.elsewhere(f, {
			[`{ISSUES}/c0050/c0050.md`] = edit(fs.readFile(doc), "theirs"),
			[`{ISSUES}/c0050/provenance.md`] = head .. "| 2026-11-08 10:05 | unblocked | human:Bee |  |\n",
		}, "their edit")
		local r = tr(W4, { "sync" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "c0050.md")).toBe(true)
		t.expect(fixture.exec(W4, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(fixture.git(W4, { "rev-parse", "HEAD" })).toBe(before)
		t.expect(fixture.git(W4, { "status", "--porcelain" })).toBe("")
		-- the same two appends without the document conflict are unioned (main's row first, then ours)
		fixture.git(W4, { "reset", "-q", "--hard", "HEAD~1" })
		fs.writeFile(rec, head .. "| 2026-11-08 10:00 | unblocked | human:Ann |  |\n")
		fixture.git(W4, { "add", "-A" })
		fixture.git(W4, { "commit", "-q", "-m", "our row" })
		trOk(W4, { "sync" })
		local united = fs.readFile(rec)
		t.expect(has(united, "human:Bee")).toBe(true)
		t.expect(has(united, "human:Ann")).toBe(true)
		local bee, ann = string.find(united, "human:Bee", 1, true), string.find(united, "human:Ann", 1, true)
		t.expect((bee :: number) < (ann :: number)).toBe(true)
	end)

	it("a record follows its item's folder when the other side moves it (ready moves a backlog item to active/)", function()
		local rec = `{W5}/{ISSUES}/c0019/provenance.md`
		local head = "# Provenance: c0019\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
		fs.writeFile(rec, head .. "| 2026-11-08 10:00 | rafted | human:Ann | raft=R0155 |\n")
		fixture.git(W5, { "add", "-A" })
		fixture.git(W5, { "commit", "-q", "-m", "our row" })
		-- main: a row published into the same record, then the folder moved to active/ (what `ready` does)
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fs.writeFile(`{f.other}/{ISSUES}/c0019/provenance.md`, head .. "| 2026-11-08 10:05 | unblocked | human:Bee |  |\n")
		fixture.git(f.other, { "add", "-A" })
		fixture.git(f.other, { "commit", "-q", "-m", "tracker: record c0019 unblocked" })
		fixture.git(f.other, { "mv", `{ISSUES}/c0019`, `{ISSUES}/active/c0019` })
		fixture.git(f.other, { "commit", "-q", "-m", "tracker: ready R0155" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		trOk(W5, { "sync" })
		-- one record, in the item's new folder, holding both sides' rows (main's first), and nothing left at the old path
		t.expect(fs.isDir(`{W5}/{ISSUES}/c0019`)).toBe(false)
		local united = fs.readFile(`{W5}/{ISSUES}/active/c0019/provenance.md`)
		t.expect(#rows(united, "unblocked")).toBe(1)
		t.expect(#rows(united, "rafted")).toBe(1)
		t.expect(fixture.git(W5, { "status", "--porcelain" })).toBe("")
	end)

	it("audit refuses a malformed record and a header naming another id, and accepts one in a raft's folder", function()
		local p = `{W4}/{ISSUES}/c0050/provenance.md`
		fs.writeFile(p, "not a record\n")
		local bad = tr(W4, { "audit" })
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stdout .. bad.stderr, "provenance")).toBe(true)
		fs.writeFile(p, "# Provenance: c0099\n\n| when | event | actor | detail |\n|---|---|---|---|\n")
		local other = tr(W4, { "audit" })
		t.expect(other.ok).toBe(false)
		t.expect(has(other.stdout .. other.stderr, "c0099")).toBe(true)
		fs.removeFile(p)
		-- a raft's own record (c0250 blocks whole rafts) is fine
		fs.writeFile(`{W4}/{RAFTS}/R0130/provenance.md`, "# Provenance: R0130\n\n| when | event | actor | detail |\n|---|---|---|---|\n")
		trOk(W4, { "audit" })
		fs.removeFile(`{W4}/{RAFTS}/R0130/provenance.md`)
		trOk(W4, { "audit" })
	end)
end)
