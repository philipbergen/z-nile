--!strict
-- c0263 AC3, AC5, AC6: the record's writes, in worktrees of a trackerfix fixture with a bare origin. `./zn record`
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
local ME = `human:{NAME}`
local ISSUES, RAFTS = "pickman/.tracker/issues", "pickman/.tracker/rafts"
local HUMAN: { [string]: string } = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	CLAUDE_EFFORT = "",
	ZN_ACTOR = "",
	ZN_DISPATCH = "",
}

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
local W1, W3, W4, W5, W6, W7, W8, W9, W10, W11, W12, W13, W14, W15, W16, W17, W18, W19, W20, W21, W22, W23, W24, W25, W26, W27 =
	"", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""

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
		for _, id in
			{
				"c0010",
				"c0011",
				"c0012",
				"c0013",
				"c0014",
				"c0015",
				"c0016",
				"c0017",
				"c0019",
				"c0021",
				"c0022",
				"c0023",
				"c0024",
				"c0025",
				"c0026",
				"c0027",
				"c0028",
				"c0041",
				"c0042",
				"c0043",
				"c0044",
				"c0045",
				"c0047",
				"c0048",
			}
		do
			seed[`{ISSUES}/{id}/{id}.md`] = draft(id)
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		-- c0014 is moved by the other side below with a file added in it: its files carry text of their own, or git's
		-- rename detection pairs them with the near-identical files of the other drafts and calls the move a split
		seed[`{ISSUES}/c0014/c0014.md`] = draft("c0014")
			.. string.rep("c0014 has its own long paragraph of text.\n", 40)
		seed[`{ISSUES}/c0014/check.sh`] = CHECK .. string.rep("# c0014 has its own long comment line.\n", 40)
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
		-- a done issue: its record is written in a pull request, never published
		seed[`{ISSUES}/done/c0100/c0100.md`] = (
			string.gsub(
				issue("c0100", ""),
				"status: prepared%-quiet%-copper%-falcon",
				"status: done-quiet-copper-falcon"
			)
		)
		seed[`{ISSUES}/done/c0100/check.sh`] = CHECK
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
		W8 = trackerfix.trOk(f, f.main, { "worktree", "raft-h" })
		W10 = trackerfix.trOk(f, f.main, { "worktree", "raft-j" })
		W11 = trackerfix.trOk(f, f.main, { "worktree", "raft-k" })
		W12 = trackerfix.trOk(f, f.main, { "worktree", "raft-l" })
		W13 = trackerfix.trOk(f, f.main, { "worktree", "raft-m" })
		W14 = trackerfix.trOk(f, f.main, { "worktree", "raft-n" })
		W15 = trackerfix.trOk(f, f.main, { "worktree", "raft-o" })
		W16 = trackerfix.trOk(f, f.main, { "worktree", "raft-p" })
		W17 = trackerfix.trOk(f, f.main, { "worktree", "raft-q" })
		W18 = trackerfix.trOk(f, f.main, { "worktree", "raft-r" })
		W19 = trackerfix.trOk(f, f.main, { "worktree", "raft-s" })
		W20 = trackerfix.trOk(f, f.main, { "worktree", "raft-t" })
		W21 = trackerfix.trOk(f, f.main, { "worktree", "raft-u" })
		W22 = trackerfix.trOk(f, f.main, { "worktree", "raft-v" })
		W23 = trackerfix.trOk(f, f.main, { "worktree", "raft-w" })
		W24 = trackerfix.trOk(f, f.main, { "worktree", "raft-x" })
		W25 = trackerfix.trOk(f, f.main, { "worktree", "raft-y" })
		W26 = trackerfix.trOk(f, f.main, { "worktree", "raft-z" })
		W27 = trackerfix.trOk(f, f.main, { "worktree", "raft-aa" })
		W9 = trackerfix.trOk(f, f.main, { "worktree", "raft-i" })
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
		-- who is recorded, per source: each value differs from every other source's, so a command that reads the wrong
		-- one (or none) shows. The last row of the record is the one just published.
		local function lastActor(): string
			local last = ""
			for line in string.gmatch(onOrigin(`{ISSUES}/c0011/provenance.md`), "[^\n]+") do
				last = line
			end
			return string.match(last, "^| [%d%-]+ [%d:]+ | %S+ | (.-) | ") or ""
		end
		local GROK = "agent:grok-4-7 effort xhigh"
		local sources: { { env: { [string]: string }, args: { string }, want: string } } = {
			{
				env = { CLAUDECODE = "1", CLAUDE_EFFORT = "high" },
				args = {},
				want = "agent:unknown effort high",
			},
			{ env = { AI_AGENT = "x" }, args = {}, want = "agent:unknown effort unknown" },
			{ env = { ZN_DISPATCH = "1" }, args = {}, want = "agent:unknown effort unknown" },
			{ env = { CURSOR_AGENT = "1" }, args = {}, want = "agent:unknown effort unknown" },
			{ env = { GROK_SESSION_ID = "s" }, args = {}, want = "agent:unknown effort unknown" },
			{
				env = { ZN_ACTOR = GROK, CLAUDECODE = "1", CLAUDE_EFFORT = "low" },
				args = {},
				want = GROK,
			},
			{ env = { ZN_ACTOR = GROK }, args = { "--actor", "human:Ann" }, want = "human:Ann" },
			{ env = {}, args = {}, want = ME },
		}
		for _, case in sources do
			local args = { "record", "c0011", "ranked" }
			for _, a in case.args do
				table.insert(args, a)
			end
			local had = #rows(onOrigin(`{ISSUES}/c0011/provenance.md`), "ranked")
			trOk(W1, args, case.env)
			t.expect(#rows(onOrigin(`{ISSUES}/c0011/provenance.md`), "ranked")).toBe(had + 1)
			t.expect(lastActor()).toBe(case.want)
		end
		-- a given actor that is not a live form refuses, whatever else the environment says
		local held = tip()
		for _, badEnv in { { ZN_ACTOR = "none" }, { ZN_ACTOR = "unknown" }, { ZN_ACTOR = "robot:x", CLAUDECODE = "1" } } do
			t.expect(tr(W1, { "record", "c0011", "ranked" }, badEnv).ok).toBe(false)
			t.expect(tip()).toBe(held)
		end
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
		-- never in the main checkout (only ever fast-forwarded), and never offline
		local mainHead = fixture.git(f.main, { "rev-parse", "HEAD" })
		t.expect(tr(f.main, { "record", "c0011", "ranked" }).ok).toBe(false)
		t.expect(tr(W1, { "record", "c0011", "ranked" }, { PICKMAN_PUBLISH = "0" }).ok).toBe(false)
		t.expect(tip()).toBe(mark)
		t.expect(fixture.git(f.main, { "rev-parse", "HEAD" })).toBe(mainHead)
	end)

	it("./zn record reaches a raft's record and an active item's, and takes unblocked rows only there", function()
		trOk(W1, { "record", "R0130", "unblocked", "--actor", "human:Ann", "--detail", "block=needs-decision" })
		t.expect(has(onOrigin(`{RAFTS}/R0130/provenance.md`), "| unblocked | human:Ann | block=needs-decision |"))
			.toBe(true)
		trOk(W1, { "record", "c0090", "unblocked", "--actor", "human:Ann", "--detail", "block=red-gate" })
		t.expect(has(onOrigin(`{ISSUES}/active/c0090/provenance.md`), "| unblocked | human:Ann | block=red-gate |"))
			.toBe(true)
		-- an active raft (a whole-raft block, c0250) takes unblocked rows and nothing else; a done item's record is
		-- written in a pull request
		trOk(W1, { "record", "R0150", "unblocked", "--actor", "human:Ann", "--detail", "block=raft" })
		t.expect(has(onOrigin(`{RAFTS}/active/R0150/provenance.md`), "| unblocked | human:Ann | block=raft |"))
			.toBe(true)
		local mark = tip()
		for _, args in
			{
				{ "record", "c0090", "confirmed", "--actor", "human:Ann" },
				{ "record", "R0150", "confirmed", "--actor", "human:Ann" },
				{ "record", "R0150", "ranked", "--actor", "human:Ann" },
				{ "record", "c0100", "unblocked", "--actor", "human:Ann" },
				{ "record", "c0100", "confirmed", "--actor", "human:Ann" },
			}
		do
			local r = tr(W1, args)
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					r.stderr .. r.stdout,
					`record refuses {args[2]}: it is {if args[2] == "c0100" then "done" else "active"}`
				)
			).toBe(true)
			t.expect(tip()).toBe(mark)
		end
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
		-- the abort says how to go on by hand: merge origin/main, and the record's order
		t.expect(has(r.stderr .. r.stdout, "git merge origin/main")).toBe(true)
		t.expect(has(r.stderr .. r.stdout, "leave the records to the engine")).toBe(true)
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
			-- main's row first, then ours
			t.expect(
				(string.find(united, "| unblocked |", 1, true) :: number)
					< string.find(united, "| rafted |", 1, true) :: number
			).toBe(true)
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
		-- a malformed record is found wherever the item is: a backlog raft, an active raft, an active issue, a done issue
		for _, where in
			{
				`{RAFTS}/R0130`,
				`{RAFTS}/active/R0150`,
				`{ISSUES}/active/c0090`,
				`{ISSUES}/done/c0100`,
			}
		do
			local stray = `{W4}/{where}/provenance.md`
			fs.writeFile(stray, "not a record\n")
			local r = tr(W4, { "audit" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "provenance")).toBe(true)
			fs.removeFile(stray)
		end
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
	it("a sync that cannot unite the record aborts and says so: an unparsable side, an edited old row", function()
		local rec = `{W8}/{ISSUES}/c0010/provenance.md`
		local function stateOf(): string
			return fixture.git(W8, { "rev-parse", "HEAD" }) .. fixture.git(W8, { "status", "--porcelain" })
		end
		-- our side commits a record that does not parse; main publishes one
		fs.writeFile(rec, "garbage\n")
		fixture.git(W8, { "add", "-A" })
		fixture.git(W8, { "commit", "-q", "-m", "a record that does not parse" })
		trOk(W1, { "record", "c0010", "ranked", "--actor", "human:Bee", "--detail", "rank=1" })
		local before = stateOf()
		local r = tr(W8, { "sync" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "c0010/provenance.md")).toBe(true)
		t.expect(fixture.exec(W8, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(stateOf()).toBe(before)
		-- our side edited a row both sides share: the union would revert the edit, so the sync stops
		fixture.git(W8, { "reset", "-q", "--hard", "HEAD~1" })
		trOk(W8, { "sync" })
		t.expect(has(fs.readFile(rec), "human:Bee")).toBe(true)
		fs.writeFile(rec, (string.gsub(fs.readFile(rec), "human:Bee", "human:Eve")))
		fixture.git(W8, { "add", "-A" })
		fixture.git(W8, { "commit", "-q", "-m", "an edited row" })
		trOk(W1, { "record", "c0010", "ranked", "--actor", "human:Cy", "--detail", "rank=2" })
		local again = stateOf()
		local r2 = tr(W8, { "sync" })
		t.expect(r2.ok).toBe(false)
		t.expect(has(r2.stderr .. r2.stdout, "row 1")).toBe(true)
		t.expect(fixture.exec(W8, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(stateOf()).toBe(again)
	end)

	it("any other file added in a folder the other side moved stops the sync (as it always did)", function()
		local review = `{W9}/{ISSUES}/c0014/design-review-001.md`
		fs.writeFile(review, "# review\n")
		fixture.git(W9, { "add", "-A" })
		fixture.git(W9, { "commit", "-q", "-m", "our review file" })
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "mv", `{ISSUES}/c0014`, `{ISSUES}/active/c0014` })
		fixture.git(f.other, { "commit", "-q", "-m", "tracker: ready R0157" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		local before = fixture.git(W9, { "rev-parse", "HEAD" })
		local r = tr(W9, { "sync" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "c0014")).toBe(true) -- git names the folder it cannot place the file in
		t.expect(fixture.exec(W9, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(fixture.git(W9, { "rev-parse", "HEAD" })).toBe(before)
		t.expect(fs.isFile(review)).toBe(true)
		t.expect(fixture.git(W9, { "status", "--porcelain" })).toBe("")
	end)
	-- the record is found by its item, not by git's stage shapes: the three mirror shapes of a moved folder, each of which
	-- git reports differently (design-review-009 F1). In each, `./zn sync` leaves exactly one record, beside the item's
	-- document, with the rows in common, main's, ours order, nothing at the old path and a clean tree.
	local function oneRecordBeside(wt: string, doc: string, events: { string })
		local folder = string.match(doc, "^(.*)/[^/]+$") :: string
		local id = string.match(doc, "/([^/]+)/[^/]+$") :: string
		local found: { string } = {}
		for _, entry in string.split(fixture.git(wt, { "ls-files", "--", ISSUES }), "\n") do
			if string.match(entry, `/{id}/provenance%.md$`) then
				table.insert(found, entry)
			end
		end
		t.expect(found).toEqual({ `{folder}/provenance.md` })
		local order: { string } = {}
		for line in string.gmatch(fs.readFile(`{wt}/{folder}/provenance.md`), "[^\n]+") do
			local who = string.match(line, "| (human:%w+) |")
			if who then
				table.insert(order, who)
			end
		end
		t.expect(order).toEqual(events)
		-- read the disk as the engine does (a folder scan), not only the index: no other folder of the item is left, so
		-- `./zn find` answers with the one folder (design-review-010 F1: an emptied folder made every command fail)
		for _, state in { "", "active/", "done/" } do
			local other = `{ISSUES}/{state}{id}`
			if other ~= folder then
				t.expect(fs.isDir(`{wt}/{other}`)).toBe(false)
			end
		end
		local found2 = trOk(wt, { "find", id })
		t.expect(has(found2, folder)).toBe(true)
		t.expect(fixture.exec(wt, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(fixture.git(wt, { "status", "--porcelain" })).toBe("")
	end
	local function appendRow(wt: string, path: string, who: string)
		local rec = `{wt}/{path}`
		fs.writeFile(rec, fs.readFile(rec) .. `| 2026-11-08 11:00 | ranked | human:{who} | rank=1 |\n`)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", `our row {who}` })
	end

	it("our side moved the folder to done/ and main published a row into the active item's record (UA)", function()
		fixture.git(W10, { "mv", `{ISSUES}/active/c0090`, `{ISSUES}/done/c0090` })
		fixture.git(W10, { "commit", "-q", "-m", "our move: done" })
		trOk(W1, { "record", "c0090", "unblocked", "--actor", "human:Main", "--detail", "block=ua" })
		trOk(W10, { "sync" })
		oneRecordBeside(W10, `{ISSUES}/done/c0090/c0090.md`, { "human:Ann", "human:Main" })
	end)

	it("our side moved the folder to done/ and appended; main published a row (DU)", function()
		trOk(W1, { "record", "c0015", "ranked", "--actor", "human:Base", "--detail", "rank=0" })
		trOk(W11, { "sync" })
		fixture.git(W11, { "mv", `{ISSUES}/c0015`, `{ISSUES}/done/c0015` })
		fixture.git(W11, { "commit", "-q", "-m", "our move: done" })
		appendRow(W11, `{ISSUES}/done/c0015/provenance.md`, "Ours1")
		appendRow(W11, `{ISSUES}/done/c0015/provenance.md`, "Ours2")
		trOk(W1, { "record", "c0015", "ranked", "--actor", "human:Main", "--detail", "rank=2" })
		trOk(W11, { "sync" })
		oneRecordBeside(
			W11,
			`{ISSUES}/done/c0015/c0015.md`,
			{ "human:Base", "human:Main", "human:Ours1", "human:Ours2" }
		)
	end)

	it(
		"main published three rows and then moved the folder, after we appended one (UD, git loses the pairing)",
		function()
			trOk(W1, { "record", "c0016", "ranked", "--actor", "human:Base", "--detail", "rank=0" })
			trOk(W12, { "sync" })
			appendRow(W12, `{ISSUES}/c0016/provenance.md`, "Ours")
			for i = 1, 3 do
				trOk(W1, {
					"record",
					"c0016",
					"ranked",
					"--actor",
					`human:Main{string.rep("x", i)}`,
					"--detail",
					`rank={i}`,
				})
			end
			fixture.git(f.other, { "pull", "-q", "origin", "main" })
			fixture.git(f.other, { "mv", `{ISSUES}/c0016`, `{ISSUES}/active/c0016` })
			fixture.git(f.other, { "commit", "-q", "-m", "tracker: ready R0158" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			trOk(W12, { "sync" })
			oneRecordBeside(
				W12,
				`{ISSUES}/active/c0016/c0016.md`,
				{ "human:Base", "human:Mainx", "human:Mainxx", "human:Mainxxx", "human:Ours" }
			)
		end
	)
	it("a record one side deleted and the other changed stops the sync, with the tree as it was", function()
		trOk(W1, { "record", "c0017", "ranked", "--actor", "human:Base", "--detail", "rank=0" })
		trOk(W13, { "sync" })
		fixture.git(W13, { "rm", "-q", `{ISSUES}/c0017/provenance.md` })
		fixture.git(W13, { "commit", "-q", "-m", "we deleted the record" })
		trOk(W1, { "record", "c0017", "ranked", "--actor", "human:Main", "--detail", "rank=1" })
		local before = fixture.git(W13, { "rev-parse", "HEAD" })
		local r = tr(W13, { "sync" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "c0017")).toBe(true)
		t.expect(has(r.stderr .. r.stdout, "has none under this id")).toBe(true)
		t.expect(fixture.exec(W13, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(fixture.git(W13, { "rev-parse", "HEAD" })).toBe(before)
		t.expect(fixture.git(W13, { "status", "--porcelain" })).toBe("")
	end)
	-- the record is found by its item, never by git's pairing of files (design-review-010 F2): near-identical records
	-- of two items, an id that changed on either side, an item that vanished, an item in two places.
	local function rec(id: string, ...: string): string
		local out = `# Provenance: {id}\n\n| when | event | actor | detail |\n|---|---|---|---|\n`
		for _, who in { ... } do
			out ..= `| 2026-11-08 10:00 | ranked | human:{who} | rank=1 |\n`
		end
		return out
	end
	local function atRecord(id: string, state: string): string
		return `{ISSUES}/{state}{id}/provenance.md`
	end
	local function guarded(wt: string, id: string, needles: { string })
		local before = fixture.git(wt, { "rev-parse", "HEAD" })
		local r = tr(wt, { "sync" })
		t.expect(r.ok).toBe(false)
		for _, needle in needles do
			t.expect(has(r.stderr .. r.stdout, needle)).toBe(true)
		end
		t.expect(fixture.exec(wt, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(fixture.git(wt, { "rev-parse", "HEAD" })).toBe(before)
		t.expect(fixture.git(wt, { "status", "--porcelain" })).toBe("")
		t.expect(id ~= "").toBe(true)
	end
	local function renumber(root: string, from: string, to: string, extra: string?)
		fixture.git(root, { "mv", `{ISSUES}/{from}`, `{ISSUES}/{to}` })
		fixture.git(root, { "mv", `{ISSUES}/{to}/{from}.md`, `{ISSUES}/{to}/{to}.md` })
		local doc = `{root}/{ISSUES}/{to}/{to}.md`
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), from, to)))
		local record = `{root}/{ISSUES}/{to}/provenance.md`
		if fs.isFile(record) then
			fs.writeFile(record, (string.gsub(fs.readFile(record), from, to)) .. (extra or ""))
		end
		fixture.git(root, { "add", "-A" })
		fixture.git(root, { "commit", "-q", "-m", `renumber {from} to {to}` })
	end

	it("main renumbered an item both sides appended to: the sync stops, naming the id and remap (i)", function()
		trackerfix.elsewhere(f, { [atRecord("c0021", "")] = rec("c0021", "Base") }, "base record c0021")
		trOk(W14, { "sync" })
		fs.writeFile(`{W14}/{atRecord("c0021", "")}`, rec("c0021", "Base", "Ours"))
		fixture.git(W14, { "add", "-A" })
		fixture.git(W14, { "commit", "-q", "-m", "our row" })
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		renumber(f.other, "c0021", "c0031", "| 2026-11-08 10:00 | ranked | human:Main | rank=1 |\n")
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		guarded(W14, "c0021", { "c0021", "./zn remap" })
	end)

	it("a record we added in a folder main renumbered stops the sync with the missing document named (ii)", function()
		fs.writeFile(`{W15}/{atRecord("c0022", "")}`, rec("c0022", "Ours"))
		fixture.git(W15, { "add", "-A" })
		fixture.git(W15, { "commit", "-q", "-m", "our record" })
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		renumber(f.other, "c0022", "c0032")
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		guarded(W15, "c0022", { "c0022", "no document" })
	end)

	it("git pairs our row with another item's near-identical record: the row stays with its own item (iii)", function()
		trackerfix.elsewhere(f, { [atRecord("c0023", "")] = rec("c0023", "Shared") }, "base record c0023")
		trOk(W16, { "sync" })
		fs.writeFile(`{W16}/{atRecord("c0023", "")}`, rec("c0023", "Shared", "Ours"))
		fixture.git(W16, { "add", "-A" })
		fixture.git(W16, { "commit", "-q", "-m", "our row" })
		-- main: three more rows in c0023's record, a new record for c0024 holding the one shared row, c0023 readied
		trackerfix.elsewhere(f, {
			[atRecord("c0023", "")] = rec("c0023", "Shared", "M1", "M2", "M3"),
			[atRecord("c0024", "")] = rec("c0024", "Shared"),
		}, "main rows")
		fixture.git(f.other, { "mv", `{ISSUES}/c0023`, `{ISSUES}/active/c0023` })
		fixture.git(f.other, { "commit", "-q", "-m", "tracker: ready R0159" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		trOk(W16, { "sync" })
		oneRecordBeside(
			W16,
			`{ISSUES}/active/c0023/c0023.md`,
			{ "human:Shared", "human:M1", "human:M2", "human:M3", "human:Ours" }
		)
		-- the other item's record is exactly what main wrote
		t.expect(fs.readFile(`{W16}/{atRecord("c0024", "")}`)).toBe(rec("c0024", "Shared"))
	end)

	it("our side renumbered an item both sides appended to: the sync stops, naming the id and remap (iv)", function()
		trackerfix.elsewhere(f, { [atRecord("c0025", "")] = rec("c0025", "Base") }, "base record c0025")
		trOk(W17, { "sync" })
		renumber(W17, "c0025", "c0035", "| 2026-11-08 10:00 | ranked | human:Ours | rank=1 |\n")
		trackerfix.elsewhere(f, { [atRecord("c0025", "")] = rec("c0025", "Base", "Main") }, "main row")
		guarded(W17, "c0025", { "c0025", "./zn remap" })
	end)

	it("main deleted the item's folder while we appended to its record: the sync stops naming the item", function()
		trackerfix.elsewhere(f, { [atRecord("c0026", "")] = rec("c0026", "Base") }, "base record c0026")
		trOk(W18, { "sync" })
		fs.writeFile(`{W18}/{atRecord("c0026", "")}`, rec("c0026", "Base", "Ours"))
		fixture.git(W18, { "add", "-A" })
		fixture.git(W18, { "commit", "-q", "-m", "our row" })
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "rm", "-rq", `{ISSUES}/c0026` })
		fixture.git(f.other, { "commit", "-q", "-m", "main removed c0026" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		guarded(W18, "c0026", { "c0026" })
	end)

	it("a commit with the item's record in two places stops the sync naming both paths", function()
		trackerfix.elsewhere(f, { [atRecord("c0027", "")] = rec("c0027", "Base") }, "base record c0027")
		trOk(W19, { "sync" })
		fs.writeDir(`{W19}/{ISSUES}/active/c0027`)
		fs.writeFile(`{W19}/{atRecord("c0027", "active/")}`, rec("c0027", "Base"))
		fs.writeFile(`{W19}/{atRecord("c0027", "")}`, rec("c0027", "Base", "Ours"))
		fixture.git(W19, { "add", "-A" })
		fixture.git(W19, { "commit", "-q", "-m", "a second copy of the record, and a row" })
		trackerfix.elsewhere(f, { [atRecord("c0027", "")] = rec("c0027", "Base", "Main") }, "main row")
		guarded(W19, "c0027", { "two places", atRecord("c0027", "active/") })
	end)

	it("a merge that holds the item's document in two places stops the sync", function()
		trackerfix.elsewhere(f, { [atRecord("c0028", "")] = rec("c0028", "Base") }, "base record c0028")
		trOk(W20, { "sync" })
		fs.writeDir(`{W20}/{ISSUES}/active/c0028`)
		fs.writeFile(`{W20}/{ISSUES}/active/c0028/c0028.md`, fs.readFile(`{W20}/{ISSUES}/c0028/c0028.md`))
		fs.writeFile(`{W20}/{atRecord("c0028", "")}`, rec("c0028", "Base", "Ours"))
		fixture.git(W20, { "add", "-A" })
		fixture.git(W20, { "commit", "-q", "-m", "a copy of the document, and a row" })
		trackerfix.elsewhere(f, { [atRecord("c0028", "")] = rec("c0028", "Base", "Main") }, "main row")
		guarded(W20, "c0028", { "c0028", "document in two places" })
	end)
	it("a raft's record follows its folder to done/ like an issue's does (c0250 blocks whole rafts)", function()
		fixture.git(W26, { "mv", `{RAFTS}/active/R0150`, `{RAFTS}/done/R0150` })
		fixture.git(W26, { "commit", "-q", "-m", "our move: done" })
		trOk(W1, { "record", "R0150", "unblocked", "--actor", "human:RaftMain", "--detail", "block=p5" })
		trOk(W26, { "sync" })
		t.expect(fs.isDir(`{W26}/{RAFTS}/active/R0150`)).toBe(false)
		local text = fs.readFile(`{W26}/{RAFTS}/done/R0150/provenance.md`)
		t.expect(has(text, "human:RaftMain")).toBe(true)
		t.expect(has(text, "# Provenance: R0150")).toBe(true)
		t.expect(has(trOk(W26, { "find", "R0150" }), `{RAFTS}/done/R0150`)).toBe(true)
	end)

	it(
		"a compaction on main reused an id and our row would land in the other item: the sync stops, naming remap (v)",
		function()
			trackerfix.elsewhere(f, {
				[atRecord("c0041", "")] = rec("c0041", "Shared"),
				[atRecord("c0042", "")] = rec("c0042", "Shared"),
			}, "base records c0041 and c0042")
			trOk(W21, { "sync" })
			fs.writeFile(`{W21}/{atRecord("c0041", "")}`, rec("c0041", "Shared", "Ours"))
			fixture.git(W21, { "add", "-A" })
			fixture.git(W21, { "commit", "-q", "-m", "our row for c0041" })
			-- main compacts: c0041 goes, c0042 becomes c0041 (its record, rewritten, is byte for byte c0041's base record)
			fixture.git(f.other, { "pull", "-q", "origin", "main" })
			fixture.git(f.other, { "rm", "-rq", `{ISSUES}/c0041` })
			renumber(f.other, "c0042", "c0041")
			fs.writeFile(`{f.other}/z-nile/compaction.txt`, "c0042 c0041\n")
			fixture.git(f.other, { "add", "-A" })
			fixture.git(f.other, { "commit", "-q", "-m", "tracker: compact ids" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			guarded(W21, "c0041", { "crosses a compaction", "./zn remap" })
		end
	)

	it("the same compaction with no record changed on our side merges: every record is main's (vi)", function()
		trackerfix.elsewhere(f, {
			[atRecord("c0043", "")] = rec("c0043", "Shared"),
			[atRecord("c0044", "")] = rec("c0044", "Shared"),
		}, "base records c0043 and c0044")
		trOk(W22, { "sync" })
		local arch = `{W22}/pickman/.tracker/architecture.md`
		fs.writeFile(arch, fs.readFile(arch) .. "a line we added\n")
		fixture.git(W22, { "add", "-A" })
		fixture.git(W22, { "commit", "-q", "-m", "our change outside the records" })
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "rm", "-rq", `{ISSUES}/c0043` })
		renumber(f.other, "c0044", "c0043")
		fs.writeFile(`{f.other}/z-nile/compaction.txt`, "c0044 c0043\n")
		fixture.git(f.other, { "add", "-A" })
		fixture.git(f.other, { "commit", "-q", "-m", "tracker: compact ids" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		trOk(W22, { "sync" })
		t.expect(fs.readFile(`{W22}/{atRecord("c0043", "")}`)).toBe(rec("c0043", "Shared"))
		t.expect(fs.isDir(`{W22}/{ISSUES}/c0044`)).toBe(false)
		t.expect(has(fs.readFile(arch), "a line we added")).toBe(true)
	end)

	it("a merge of another branch in progress is not ours: the sync refuses and leaves it as it was (vii)", function()
		fixture.git(W23, { "checkout", "-q", "-b", "side" })
		fs.writeFile(`{W23}/side.txt`, "side\n")
		fixture.git(W23, { "add", "-A" })
		fixture.git(W23, { "commit", "-q", "-m", "side work" })
		local sideHead = fixture.git(W23, { "rev-parse", "HEAD" })
		fixture.git(W23, { "checkout", "-q", "-" })
		fs.writeFile(`{W23}/ours.txt`, "ours\n")
		fixture.git(W23, { "add", "-A" })
		fixture.git(W23, { "commit", "-q", "-m", "our work" })
		fixture.git(W23, { "merge", "-q", "--no-commit", "--no-ff", "side" })
		trackerfix.elsewhere(f, { ["pickman/.tracker/notes-vii.md"] = "main moves on\n" }, "main moves on")
		local r = tr(W23, { "sync" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "another branch is in progress")).toBe(true)
		t.expect(fixture.git(W23, { "rev-parse", "MERGE_HEAD" })).toBe(sideHead)
		t.expect(fs.isFile(`{W23}/side.txt`)).toBe(true)
		fixture.git(W23, { "merge", "--abort" })
	end)

	it("a hand merge of origin/main with only the records left conflicted is finished by the sync (viii)", function()
		trackerfix.elsewhere(f, { [atRecord("c0045", "")] = rec("c0045", "Base") }, "base record c0045")
		trOk(W24, { "sync" })
		fs.writeFile(`{W24}/{atRecord("c0045", "")}`, rec("c0045", "Base", "Ours"))
		fixture.git(W24, { "add", "-A" })
		fixture.git(W24, { "commit", "-q", "-m", "our row" })
		trackerfix.elsewhere(f, { [atRecord("c0045", "")] = rec("c0045", "Base", "Main") }, "main row")
		fixture.git(W24, { "fetch", "-q", "origin" })
		t.expect(fixture.exec(W24, "git", { "merge", "--no-commit", "--no-edit", "origin/main" }).ok).toBe(false)
		trOk(W24, { "sync" })
		t.expect(fs.readFile(`{W24}/{atRecord("c0045", "")}`)).toBe(rec("c0045", "Base", "Main", "Ours"))
		t.expect(fixture.exec(W24, "git", { "rev-parse", "-q", "--verify", "MERGE_HEAD" }).ok).toBe(false)
		t.expect(fixture.git(W24, { "status", "--porcelain" })).toBe("")
	end)

	it(
		"a provenance.md in an id-named folder inside an item's folder is not that id's record (the layout publish and audit use)",
		function()
			local sample = `{ISSUES}/c0046/experiments/split/c0047/provenance.md`
			fs.writeDir(`{W25}/{ISSUES}/c0046/experiments/split/c0047`)
			fs.writeFile(`{W25}/{sample}`, rec("c0047", "Sample"))
			fixture.git(W25, { "add", "-A" })
			fixture.git(W25, { "commit", "-q", "-m", "a hand-off sample" })
			trackerfix.elsewhere(f, { [atRecord("c0047", "")] = rec("c0047", "Real") }, "the real record")
			trOk(W25, { "sync" })
			t.expect(fs.readFile(`{W25}/{sample}`)).toBe(rec("c0047", "Sample"))
			t.expect(fs.readFile(`{W25}/{atRecord("c0047", "")}`)).toBe(rec("c0047", "Real"))
		end
	)
	it(
		"a hand merge of origin/main that the engine cannot finish is left as the user had it (never aborted)",
		function()
			trackerfix.elsewhere(f, { [atRecord("c0048", "")] = rec("c0048", "Base") }, "base record c0048")
			trOk(W27, { "sync" })
			fs.writeFile(`{W27}/{atRecord("c0048", "")}`, rec("c0048", "Eve"))
			fixture.git(W27, { "add", "-A" })
			fixture.git(W27, { "commit", "-q", "-m", "we rewrote the shared row" })
			trackerfix.elsewhere(f, { [atRecord("c0048", "")] = rec("c0048", "Base", "Main") }, "main row")
			fixture.git(W27, { "fetch", "-q", "origin" })
			t.expect(fixture.exec(W27, "git", { "merge", "--no-commit", "--no-edit", "origin/main" }).ok).toBe(false)
			local r = tr(W27, { "sync" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr .. r.stdout, "row 1")).toBe(true)
			-- the user's merge is still in progress, on origin/main, with the record still conflicted
			t.expect(fixture.git(W27, { "rev-parse", "MERGE_HEAD" }))
				.toBe(fixture.git(W27, { "rev-parse", "origin/main" }))
			t.expect(fixture.git(W27, { "ls-files", "-u" }) ~= "").toBe(true)
			fixture.git(W27, { "merge", "--abort" })
		end
	)
end)
