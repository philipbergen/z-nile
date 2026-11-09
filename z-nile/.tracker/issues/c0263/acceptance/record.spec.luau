--!strict
-- c0263 AC3, AC4, AC5: the record's writes, in worktrees of a trackerfix fixture with a bare origin. `./zn record`
-- publishes a row for the tickets that will call it (a raft's record and an active item's too, with the events each
-- may take) and refuses the rest; the engine's merges of origin/main (sync, fold's, land's) union a conflict confined
-- to provenance.md and abort on any other; a record added where the other side moved the folder (ready) follows the
-- folder and is united there; `./zn audit` refuses a malformed one. (The commands that write rows in a PR or on a
-- status change are c0282's and c0283's.)
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0263-record"
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
local W1, W3, W4, W5, W6, W7 = "", "", "", "", "", ""

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
		seed[`{ISSUES}/active/c0090/c0090.md`] = (
			string.gsub(
				issue("c0090", "R0150"),
				"status: prepared%-quiet%-copper%-falcon",
				"status: active-quiet-copper-falcon"
			)
		)
		seed[`{ISSUES}/active/c0090/check.sh`] = CHECK
		seed[`{RAFTS}/active/R0150/R0150.md`] = (
			string.gsub(
				raftDoc("R0150", "c0090"),
				"status: prepared%-quiet%-copper%-falcon",
				"status: active-quiet-copper-falcon"
			)
		)
		seed[`{RAFTS}/active/R0150/check.sh`] = CHECK
		for _, r in { { "R0110", "" }, { "R0130", "c0050" }, { "R0140", "c0070" } } do
			seed[`{RAFTS}/{r[1]}/{r[1]}.md`] = raftDoc(r[1], r[2])
			seed[`{RAFTS}/{r[1]}/check.sh`] = CHECK
		end
		f = trackerfix.new(NAME, seed)
		W1 = trackerfix.trOk(f, f.main, { "worktree", "prep-a" })
		W3 = trackerfix.trOk(f, f.main, { "worktree", "raft-c" })
		W4 = trackerfix.trOk(f, f.main, { "worktree", "raft-d" })
		W5 = trackerfix.trOk(f, f.main, { "worktree", "raft-e" })
		W6 = trackerfix.trOk(f, f.main, { "worktree", "raft-f" })
		W7 = trackerfix.trOk(f, f.main, { "worktree", "capture-g" })
		-- the fixture audits clean before any of this, so a refusal below is the record's
		trOk(W1, { "audit" })
	end)

	it("./zn record publishes the events other tickets will call and refuses the rest", function()
		local before = tip()
		trOk(W1, { "record", "c0011", "confirmed", "--actor", "human:Ann", "--detail", 'said="yes"' })
		local rec = onOrigin(`{ISSUES}/c0011/provenance.md`)
		t.expect(has(rec, '| confirmed | human:Ann | said="yes"')).toBe(true)
		t.expect(fixture.git(f.origin, { "diff", "--name-only", before, "main" })).toBe(`{ISSUES}/c0011/provenance.md`)
		-- a published append is built from origin/main's file, never from the worktree's: a row only this worktree holds
		-- (committed here, not published) does not leak to main, and the merge afterwards unites it with main's
		trOk(W1, { "sync" })
		local mine = `{W1}/{ISSUES}/c0011/provenance.md`
		fs.writeFile(mine, fs.readFile(mine) .. "| 2026-11-08 09:00 | ranked | human:Zed | rank=9 |\n")
		fixture.git(W1, { "add", "-A" })
		fixture.git(W1, { "commit", "-q", "-m", "a row only this worktree holds" })
		trOk(W1, { "record", "c0011", "ranked", "--detail", "rank=3" })
		t.expect(has(onOrigin(`{ISSUES}/c0011/provenance.md`), "human:Zed")).toBe(false)
		t.expect(#rows(onOrigin(`{ISSUES}/c0011/provenance.md`), "ranked")).toBe(1)
		t.expect(#rows(fs.readFile(mine), "ranked")).toBe(2)
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
		-- the command refuses an event another command writes by itself, before the publisher is asked
		local refused = tr(W1, { "record", "c0011", "approved" })
		t.expect(has(refused.stderr .. refused.stdout, "written by their own commands")).toBe(true)
	end)

	it("./zn record reaches a raft's record and an active item's, and takes unblocked rows only there", function()
		trOk(W1, { "record", "R0130", "unblocked", "--actor", "human:Ann", "--detail", "block=needs-decision" })
		t.expect(has(onOrigin(`{RAFTS}/R0130/provenance.md`), "| unblocked | human:Ann | block=needs-decision |"))
			.toBe(true)
		trOk(W1, { "record", "c0090", "unblocked", "--actor", "human:Ann", "--detail", "block=red-gate" })
		t.expect(has(onOrigin(`{ISSUES}/active/c0090/provenance.md`), "| unblocked | human:Ann | block=red-gate |"))
			.toBe(true)
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

	it(
		"a record follows its item's folder when the other side moves it (ready moves a backlog item to active/)",
		function()
			local rec = `{W5}/{ISSUES}/c0019/provenance.md`
			local head = "# Provenance: c0019\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
			fs.writeFile(rec, head .. "| 2026-11-08 10:00 | rafted | human:Ann | raft=R0155 |\n")
			fixture.git(W5, { "add", "-A" })
			fixture.git(W5, { "commit", "-q", "-m", "our row" })
			-- main: a row published into the same record, then the folder moved to active/ (what `ready` does)
			fixture.git(f.other, { "pull", "-q", "origin", "main" })
			fs.writeFile(
				`{f.other}/{ISSUES}/c0019/provenance.md`,
				head .. "| 2026-11-08 10:05 | unblocked | human:Bee |  |\n"
			)
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
		end
	)

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
		fs.writeFile(
			`{W4}/{RAFTS}/R0130/provenance.md`,
			"# Provenance: R0130\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
		)
		trOk(W4, { "audit" })
		fs.removeFile(`{W4}/{RAFTS}/R0130/provenance.md`)
		trOk(W4, { "audit" })
	end)
	it("fold's merge of origin/main unions the record too", function()
		local rec = `{W3}/{ISSUES}/c0040/provenance.md`
		local head = "# Provenance: c0040\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
		fs.writeFile(rec, head .. "| 2026-11-08 10:00 | ranked | human:Ann | rank=1 |\n")
		fixture.git(W3, { "add", "-A" })
		fixture.git(W3, { "commit", "-q", "-m", "our row" })
		trOk(W1, { "record", "c0040", "ranked", "--actor", "human:Bee", "--detail", "rank=2" })
		trOk(W3, { "fold", "R0110", "c0040" })
		local united = fs.readFile(rec)
		t.expect(#rows(united, "ranked")).toBe(2)
		local bee, ann = string.find(united, "human:Bee", 1, true), string.find(united, "human:Ann", 1, true)
		t.expect((bee :: number) < (ann :: number)).toBe(true)
	end)

	it("a record only our side added follows the folder the other side moved (git's file location conflict)", function()
		local rec = `{W6}/{ISSUES}/c0012/provenance.md`
		local head = "# Provenance: c0012\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
		fs.writeFile(rec, head .. "| 2026-11-08 10:00 | ranked | human:Ann | rank=1 |\n")
		fixture.git(W6, { "add", "-A" })
		fixture.git(W6, { "commit", "-q", "-m", "our row" })
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "mv", `{ISSUES}/c0012`, `{ISSUES}/active/c0012` })
		fixture.git(f.other, { "commit", "-q", "-m", "tracker: ready R0156" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		trOk(W6, { "sync" })
		t.expect(fs.isDir(`{W6}/{ISSUES}/c0012`)).toBe(false)
		t.expect(#rows(fs.readFile(`{W6}/{ISSUES}/active/c0012/provenance.md`), "ranked")).toBe(1)
		t.expect(fs.isFile(`{W6}/{ISSUES}/active/c0012/check.sh`)).toBe(true)
		t.expect(fixture.git(W6, { "status", "--porcelain" })).toBe("")
	end)
	it(
		"land merges origin/main with the same union: a united record is land's scope refusal, never a failed merge",
		function()
			local rec = `{W7}/{ISSUES}/c0013/provenance.md`
			local head = "# Provenance: c0013\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
			fs.writeFile(rec, head .. "| 2026-11-08 10:00 | ranked | human:Ann | rank=1 |\n")
			fixture.git(W7, { "add", "-A" })
			fixture.git(W7, { "commit", "-q", "-m", "our row" })
			trOk(W1, { "record", "c0013", "ranked", "--actor", "human:Bee", "--detail", "rank=2" })
			local landed = tr(W7, { "land" }, { PICKMAN_LAND_GATE = "true" })
			t.expect(landed.ok).toBe(false)
			local out = landed.stderr .. landed.stdout
			t.expect(has(out, "merging origin/main failed")).toBe(false)
			t.expect(has(out, "provenance.md")).toBe(true) -- the scope refusal names the record
			t.expect(#rows(fs.readFile(rec), "ranked")).toBe(2)
			t.expect(fixture.exec(W7, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		end
	)
end)
