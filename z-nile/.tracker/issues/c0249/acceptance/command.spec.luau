--!strict
-- c0249 AC2, AC3, AC4, AC5, AC6, AC10: ./zn rank, ./zn next, ./zn list and ./zn audit in a tracker fixture with a bare
-- origin. `rank` runs in the main checkout (as the board app's rankCommand does) and in a worktree, publishes one commit
-- to origin/main with the changed `rank:` lines and a `ranked` row for each, and brings it into the checkout; `next` prints
-- lost work, then the claimable raft with the best rank, then an issue to draft; `list` shows blocked items first, then
-- the stack; `audit` rejects a malformed rank. Fixture under .cache/c0249-command.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0249-command"
local ME = `human:{NAME}`
local P, RF = "pickman/.tracker/issues", "pickman/.tracker/rafts"
local T0 = os.time()
local LATE = T0 + 3 * 3600 -- far past any claim's stale limit (c0265: 15 minutes)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HUMAN: { [string]: string } = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	CLAUDE_EFFORT = "",
	ZN_ACTOR = "",
	ZN_DISPATCH = "",
}
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local SPEC = "--!strict\n"
local GH =
	'#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = list ]; then\n  [ -f "$FAKE_DIR/ghfail" ] && { echo "gh: fake failure" >&2; exit 1; }\n  echo "[]"; exit 0\nfi\nexit 0\n'

local h: fakecli.Harness
local wt = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function zn(cwd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = table.clone(HUMAN)
	env.FAKE_DIR = h.fakes
	env.PATH = `{h.bin}:{process.env.PATH}`
	env.ZN_AGENT_TOKEN_FILE = h.token
	env.ZN_WATERMARK_DIR = `{h.f.base}/watermark`
	for k, v in (extra or {}) :: { [string]: string } do
		env[k] = v
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(cwd: string, args: { string }, extra: { [string]: string }?): string
	local r = zn(cwd, args, extra)
	if not r.ok then
		error(`{table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function tip(): string
	return fixture.git(h.f.origin, { "rev-parse", "main" })
end
local function onOrigin(path: string): string
	local r = fixture.exec(h.f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else ""
end
local function rankOf(id: string): string
	local path = if string.sub(id, 1, 1) == "R" then `{RF}/{id}/{id}.md` else `{P}/{id}/{id}.md`
	return string.match(onOrigin(path), "\nrank: ([^\n]*)\n") or "unset"
end
local function changedFiles(before: string): string
	local out = fixture.git(h.f.origin, { "diff", "--name-only", before, "main" })
	return (string.gsub(out, "pickman/.tracker/", ""))
end
local function doc(id: string, over: { [string]: string }?): string
	local o: { [string]: string } = over or {}
	return `---\nid: {id}\n{o.rank and `rank: {o.rank}\n` or ""}type: chore\ntitle: {id}\nslug: {id}\nraft: {o.raft or ""}\ndepends_on: {o.depends or "[]"}\n`
		.. `emergent: false\ndesign: {o.design or "draft"}\ncreated: 2026-11-01\n`
		.. `{o.idea and `idea: {o.idea}\n` or ""}status: {o.status or "new-quiet-copper-falcon"}\n---\n\n# {id}\n\n`
		.. `## Problem\nThe {id} problem.\n\n## Solution\nThe {id} solution.\n\n## Design\nThe {id} design.\n\n`
		.. `## Acceptance criteria\nThe {id} criteria.\n\n## Test plan\nThe {id} plan.\n`
end
local function raftDoc(id: string, member: string, grouped: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nsingle: true\nissues: [{member}]\ndesign: ready\n`
		.. `created: 2026-11-01\n{grouped and `grouped: {grouped}\n` or ""}status: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Theme\nThe {id} theme.\n`
end
local function order(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local id = string.match(line, "^(%S+)")
		if id then
			table.insert(out, id)
		end
	end
	return out
end
local function join(list: { string }): string
	return table.concat(list, " ")
end

return t.spec("c0249 rank, next and list", function(it)
	it("sets up ranked, unranked, blocked and dependent issues, two claimable rafts and the fakes", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			["z-nile/next"] = "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n",
		}
		for id, over in
			{
				c0010 = {},
				c0011 = {},
				c0012 = { rank = "10" },
				c0013 = { rank = "20" },
				c0014 = { rank = "30" },
				c0015 = {},
				c0017 = { idea = "unchallenged" }, -- a worker may not draft it: its idea was not challenged
				c0020 = { depends = "[c0021]" }, -- waits on c0021, which is not done
				c0021 = {},
				c0030 = { status = "blocked-quiet-copper-falcon" },
			} :: { [string]: { [string]: string } }
		do
			seed[`{P}/{id}/{id}.md`] = doc(id, over)
			seed[`{P}/{id}/check.sh`] = CHECK
		end
		seed[`{P}/done/c0100/c0100.md`] = doc("c0100", { status = "done-quiet-copper-falcon" })
		seed[`{P}/done/c0100/check.sh`] = CHECK
		seed[`{P}/active/c0090/c0090.md`] =
			doc("c0090", { raft = "R0150", status = "active-quiet-copper-falcon", design = "ready" })
		seed[`{P}/active/c0090/check.sh`] = CHECK
		seed[`{RF}/active/R0150/R0150.md`] = (
			string.gsub(raftDoc("R0150", "c0090"), "prepared%-quiet", "active-quiet")
		)
		seed[`{RF}/active/R0150/check.sh`] = CHECK
		-- two prepared rafts ready would accept: a member each, design ready, a check and a spec, approved by the fixture
		local member201 =
			doc("c0201", { raft = "R0201", design = "ready", status = "prepared-quiet-copper-falcon" })
		local grouped = raftplan.recordHash("c0201", {
			["c0201.md"] = member201,
			["check.sh"] = CHECK,
			["acceptance/hold.spec.luau"] = SPEC,
		})
		seed[`{P}/c0201/c0201.md`] = member201
		seed[`{P}/c0201/check.sh`] = CHECK
		seed[`{P}/c0201/acceptance/hold.spec.luau`] = SPEC
		seed[`{RF}/R0201/R0201.md`] = raftDoc("R0201", "c0201", `[c0201@{grouped}]`)
		seed[`{RF}/R0201/check.sh`] = CHECK
		seed[`{P}/c0202/c0202.md`] =
			doc("c0202", { raft = "R0202", design = "ready", status = "prepared-quiet-copper-falcon" })
		seed[`{P}/c0202/check.sh`] = CHECK
		seed[`{P}/c0202/acceptance/hold.spec.luau`] = SPEC
		seed[`{RF}/R0202/R0202.md`] = raftDoc("R0202", "c0202")
		seed[`{RF}/R0202/check.sh`] = CHECK
		-- an approved issue in no raft: a worker rafts it before drafting anything new
		seed[`{P}/c0203/c0203.md`] =
			doc("c0203", { design = "ready", status = "prepared-quiet-copper-falcon" })
		seed[`{P}/c0203/check.sh`] = CHECK
		seed[`{P}/c0203/acceptance/hold.spec.luau`] = SPEC
		h = fakecli.new(NAME, seed)
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		wt = (string.gsub(must(h.f.main, { "worktree", "c0249-command" }), "%s+$", ""))
		must(wt, { "audit" }) -- the fixture audits clean before any of this
	end)

	it("AC2: rank top, in the main checkout, publishes one commit and fast-forwards the checkout", function()
		local before = tip()
		local out = must(h.f.main, { "rank", "c0014", "top" })
		t.expect(out).toBe("c0014 rank 5 (was 30)")
		t.expect(changedFiles(before)).toBe("issues/c0014/c0014.md\nissues/c0014/provenance.md")
		t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		t.expect(fixture.git(h.f.origin, { "log", "-1", "--format=%s", "main" }))
			.toBe("tracker: rank c0014 top")
		t.expect(rankOf("c0014")).toBe("5")
		-- the main checkout holds the change, and was only fast-forwarded (clean, on main, at origin's tip)
		t.expect(has(fs.readFile(`{h.f.main}/{P}/c0014/c0014.md`), "\nid: c0014\nrank: 5\ntype: chore\n"))
			.toBe(true)
		t.expect(fixture.git(h.f.main, { "rev-parse", "HEAD" })).toBe(tip())
		t.expect(fixture.git(h.f.main, { "status", "--porcelain" })).toBe("")
		-- who set it: a ranked row from the live actor, with the rank and the one it replaced
		local rec = onOrigin(`{P}/c0014/provenance.md`)
		t.expect(has(rec, "# Provenance: c0014")).toBe(true)
		t.expect(has(rec, `| ranked | {ME} | rank=5; was=30 |`)).toBe(true)
		-- the rest of the document is as it was
		local doc14 = onOrigin(`{P}/c0014/c0014.md`)
		t.expect(doc14).toBe((string.gsub(doc("c0014", { rank = "30" }), "rank: 30", "rank: 5")))
	end)

	it("AC2: after puts an item into a gap; a move to where it already is publishes nothing", function()
		local before = tip()
		-- the ranked items are c0014 5, c0012 10, c0013 20: c0015 after c0013 takes 30, ahead of every unset one
		t.expect(must(h.f.main, { "rank", "c0015", "after", "c0013" })).toBe("c0015 rank 30 (was unset)")
		t.expect(changedFiles(before)).toBe("issues/c0015/c0015.md\nissues/c0015/provenance.md")
		t.expect(rankOf("c0015")).toBe("30")
		local mid = tip()
		t.expect(must(h.f.main, { "rank", "c0015", "after", "c0013" })).toBe("c0015: unchanged")
		t.expect(must(h.f.main, { "rank", "c0010", "unset" })).toBe("c0010: unchanged")
		t.expect(tip()).toBe(mid)
	end)

	it(
		"AC2: the board app's form, rank <id> --before <id>, works in a worktree, which merges origin/main",
		function()
			local before = tip()
			t.expect(must(wt, { "rank", "c0021", "--before", "c0010" })).toBe("c0021 rank 40 (was unset)")
			t.expect(changedFiles(before)).toBe("issues/c0021/c0021.md\nissues/c0021/provenance.md")
			t.expect(fixture.git(wt, { "rev-parse", "HEAD" })).toBe(tip())
			t.expect(has(fs.readFile(`{wt}/{P}/c0021/c0021.md`), "\nrank: 40\n")).toBe(true)
			-- the main checkout has not moved: only a command run there brings it forward
			t.expect(fixture.git(h.f.main, { "rev-parse", "HEAD" }) ~= tip()).toBe(true)
			must(h.f.main, { "sync" })
		end
	)

	it(
		"AC2: a move among unset items ranks the unset ones above it (auto) and changes no rank that exists",
		function()
			local before = tip()
			-- the ranked items are c0014 5, c0012 10, c0013 20, c0015 30, c0021 40; c0010 is the first unset one
			local out = must(h.f.main, { "rank", "c0017", "--before", "c0011" })
			t.expect(out).toBe("c0010 rank 50 auto (was unset)\nc0017 rank 60 (was unset)")
			t.expect(changedFiles(before)).toBe(
				"issues/c0010/c0010.md\nissues/c0010/provenance.md\nissues/c0017/c0017.md\nissues/c0017/provenance.md"
			)
			t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
			-- the moved item's rank is plain and its row has no mover; the neighbour's is marked and names the item that moved it
			t.expect(has(onOrigin(`{P}/c0017/c0017.md`), "\nid: c0017\nrank: 60\ntype:")).toBe(true)
			t.expect(has(onOrigin(`{P}/c0010/c0010.md`), "\nid: c0010\nrank: 50 auto\ntype:")).toBe(true)
			t.expect(has(onOrigin(`{P}/c0017/provenance.md`), `| ranked | {ME} | rank=60; was=unset |`))
				.toBe(true)
			t.expect(
				has(
					onOrigin(`{P}/c0010/provenance.md`),
					`| ranked | {ME} | rank=50 auto; was=unset; moved=c0017 |`
				)
			).toBe(true)
			-- no rank that exists changed: c0014 still has its one row
			t.expect(rankOf("c0014")).toBe("5")
			t.expect(rankOf("c0021")).toBe("40")
			t.expect(has(onOrigin(`{P}/c0014/provenance.md`), "rank=5; was=30 |\n")).toBe(true)
			t.expect(has(onOrigin(`{P}/c0014/provenance.md`), "moved=")).toBe(false)
			must(h.f.main, { "sync" })
			t.expect(rankOf("c0011")).toBe("unset") -- below the moved item: left alone
		end
	)

	it("AC2: unset removes the line, and a number sets exactly that rank", function()
		must(h.f.main, { "rank", "c0013", "unset" })
		t.expect(rankOf("c0013")).toBe("unset")
		t.expect(has(onOrigin(`{P}/c0013/c0013.md`), "rank")).toBe(false)
		t.expect(has(onOrigin(`{P}/c0013/provenance.md`), "| rank=unset; was=20; moved=c0017 |")).toBe(false)
		t.expect(has(onOrigin(`{P}/c0013/provenance.md`), "| rank=unset; was=20 |")).toBe(true)
		must(h.f.main, { "rank", "c0011", "7" })
		t.expect(rankOf("c0011")).toBe("7")
		t.expect(fixture.git(h.f.main, { "rev-parse", "HEAD" })).toBe(tip())
	end)

	it("AC2: a refused rank names the rule, publishes nothing and leaves the checkout alone", function()
		local before = tip()
		local function refused(args: { string }, needle: string)
			local r = zn(h.f.main, args)
			t.expect(r.ok).toBe(false)
			local said = r.stderr .. r.stdout
			if not has(said, needle) then
				error(`{table.concat(args, " ")}: expected {needle} in: {said}`, 2)
			end
		end
		refused({ "rank", "c0100", "top" }, "c0100 is done: a rank orders work that is not started")
		refused({ "rank", "c0090", "top" }, "c0090 is active")
		refused({ "rank", "c9999", "top" }, "c9999 is not on origin/main")
		refused({ "rank", "c0010", "after", "c0100" }, "c0100 is not in the backlog stack")
		refused({ "rank", "c0010", "after", "R0201" }, "R0201 is not in the backlog stack")
		refused({ "rank", "c0010", "after", "c0010" }, "cannot go after itself")
		refused({ "rank", "c0010", "0" }, "rank: 0 is not a whole number from 1 to 999999")
		refused({ "rank", "c0010", "007" }, "rank: 007 is not a whole number")
		refused({ "rank", "c0010", "sideways" }, "rank: sideways is not a whole number")
		refused({ "rank", "c0010", "top", "extra" }, "usage: rank <id>")
		refused({ "rank", "c0010", "after" }, "usage: rank <id>")
		refused({ "rank", "c0010", "--sideways", "x" }, "unknown option --sideways")
		refused({ "rank", "nonsense", "top" }, "usage: rank <id>")
		refused({ "rank" }, "usage: rank <id>")
		-- a main checkout that is not on main is not fast-forwarded over
		fixture.git(h.f.main, { "switch", "-q", "-c", "elsewhere" })
		refused({ "rank", "c0010", "top" }, "the main checkout is on elsewhere, not main")
		fixture.git(h.f.main, { "switch", "-q", "main" })
		fixture.git(h.f.main, { "branch", "-q", "-d", "elsewhere" })
		-- a dirty main checkout is not fast-forwarded over
		fs.writeFile(`{h.f.main}/stray.txt`, "x")
		refused({ "rank", "c0010", "top" }, "the main checkout is not clean")
		fs.removeFile(`{h.f.main}/stray.txt`)
		t.expect(tip()).toBe(before)
	end)

	it("AC3: a raft's own rank overrides its members', and an unset one takes their best", function()
		-- nothing is ranked among the rafts yet
		t.expect(must(h.f.main, { "rank", "R0202", "top" })).toBe("R0202 rank 10 (was unset)")
		t.expect(rankOf("R0202")).toBe("10")
		t.expect(has(onOrigin(`{RF}/R0202/provenance.md`), `| ranked | {ME} | rank=10; was=unset |`))
			.toBe(true)
		t.expect(must(h.f.main, { "next" })).toBe("R0202 raft rank 10")
		-- R0201 has no rank of its own: its member c0201 (5) places it ahead of R0202
		must(h.f.main, { "rank", "c0201", "5" })
		t.expect(rankOf("c0201")).toBe("5")
		t.expect(must(h.f.main, { "next" })).toBe("R0201 raft rank 5")
		-- R0201's own rank 50 overrides its member's 5
		must(h.f.main, { "rank", "R0201", "50" })
		t.expect(must(h.f.main, { "next" })).toBe("R0202 raft rank 10")
		-- unset again: it takes its members' best
		must(h.f.main, { "rank", "R0201", "unset" })
		t.expect(rankOf("R0201")).toBe("unset")
		t.expect(must(h.f.main, { "next" })).toBe("R0201 raft rank 5")
		-- a session that takes the next raft sees the member's rank too (R0201 has none of its own)
		t.expect(has(must(h.f.main, { "work", "next" }), "R0201: ready")).toBe(true)
		-- moving a raft places it among the rafts by effective rank: R0201 (5) after R0202 (10) takes 20
		t.expect(must(h.f.main, { "rank", "R0201", "after", "R0202" })).toBe("R0201 rank 20 (was unset)")
		t.expect(must(h.f.main, { "next" })).toBe("R0202 raft rank 10")
		-- a session that takes the next raft takes it in the same order
		t.expect(has(must(h.f.main, { "work", "next" }), "R0202: ready")).toBe(true)
	end)

	it("AC10: a rank on a grouped member changes neither its raft's claimability nor its approval", function()
		-- c0201 was ranked above: R0201's grouped record hashes c0201's document, and ready's check still accepts it
		local approval = onOrigin(`{P}/c0201/approval.md`)
		t.expect(approval ~= "").toBe(true)
		must(h.f.main, { "rank", "c0201", "unset" })
		must(h.f.main, { "rank", "c0201", "top" })
		must(h.f.main, { "rank", "R0201", "unset" })
		t.expect(must(h.f.main, { "next" })).toBe("R0201 raft rank 2")
		t.expect(onOrigin(`{P}/c0201/approval.md`)).toBe(approval)
		must(h.f.main, { "rank", "R0201", "20" })
	end)

	it(
		"AC5: list shows every blocked item first, then the rafts, then the issues, each in the stack's order",
		function()
			must(h.f.main, { "sync" })
			local text = must(h.f.main, { "list", "backlog" })
			-- c0030 is blocked, so it comes before the unblocked rafts R0202 (10) and R0201 (20); then the issues: c0201 2,
			-- c0014 5, c0011 7, c0012 10, c0015 30, c0021 40, c0010 50 (auto), c0017 60, then the unset ones by number
			t.expect(join(order(text)))
				.toBe("c0030 R0202 R0201 c0201 c0014 c0011 c0012 c0015 c0021 c0010 c0017 c0013 c0020 c0202 c0203")
			t.expect(has(text, "c0100")).toBe(false) -- the state filter keeps the order: the done item is not here
			-- with no filter an active or done item counts as unset: after every ranked backlog item of its kind
			local all = join(order(must(h.f.main, { "list" })))
			t.expect(has(all, "c0030 R0202 R0201 R0150 c0201 c0014")).toBe(true)
			t.expect(string.find(all, "c0017", 1, true) < string.find(all, "c0090", 1, true)).toBe(true)
		end
	)

	it(
		"AC5: list puts a lost claim first, after the blocked items, whatever its rank, and says when it cannot read it",
		function()
			-- c0013 is claimed and never beats
			must(wt, { "sync" })
			must(wt, { "status", "c0013", "preparing" }, { ZN_NOW = tostring(T0) })
			must(h.f.main, { "sync" })
			-- fresh, it keeps its place in the stack
			local fresh = order(must(h.f.main, { "list", "backlog" }, { ZN_NOW = tostring(T0 + 60) }))
			t.expect(fresh[1]).toBe("c0030")
			t.expect(fresh[2]).toBe("R0202")
			-- stale, with no pull request naming it: lost, so it is first among the unblocked items
			local late = order(must(h.f.main, { "list", "backlog" }, { ZN_NOW = tostring(LATE) }))
			t.expect(late[1]).toBe("c0030")
			t.expect(late[2]).toBe("c0013")
			t.expect(late[3]).toBe("R0202")
			-- the heartbeats or the pull requests cannot be read: it is not lost, and stderr says why
			fs.writeFile(`{h.fakes}/ghfail`, "1")
			local r = zn(h.f.main, { "list", "backlog" }, { ZN_NOW = tostring(LATE) })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stderr, "list: lost work not read (")).toBe(true)
			t.expect(order(r.stdout)[2]).toBe("R0202")
			-- the same for next: it names the failure and goes on to the raft
			local n = zn(h.f.main, { "next" }, { ZN_NOW = tostring(LATE) })
			t.expect(n.ok).toBe(true)
			t.expect(has(n.stderr, "next: lost work not read (")).toBe(true)
			t.expect((string.gsub(n.stdout, "%s+$", ""))).toBe("R0202 raft rank 10")
			fs.removeFile(`{h.fakes}/ghfail`)
		end
	)

	it("AC4: next puts lost work first, whatever the rank, and not before the claim is stale", function()
		t.expect(must(h.f.main, { "next" }, { ZN_NOW = tostring(T0 + 60) })).toBe("R0202 raft rank 10")
		t.expect(must(h.f.main, { "next" }, { ZN_NOW = tostring(LATE) }))
			.toBe("c0013 lost its heartbeat is stale")
		t.expect(has(must(h.f.main, { "lost" }, { ZN_NOW = tostring(LATE) }), "c0013 preparing ")).toBe(true)
	end)

	it(
		"AC4: with no claimable raft next rafts an approved issue, then takes an issue to draft, skipping what waits, is blocked or is not ready",
		function()
			must(h.f.main, { "ready", "R0201" })
			must(h.f.main, { "ready", "R0202" })
			-- c0203 is approved and in no raft: a worker rafts it before drafting anything new
			t.expect(must(h.f.main, { "next" })).toBe("c0203 rafting approved, in no raft")
			must(wt, { "sync" })
			must(wt, { "status", "c0203", "preparing" })
			-- c0020 (rank 1) waits on c0021; c0017 (rank 2) has an unchallenged idea; c0030 (rank 3) is blocked
			must(h.f.main, { "rank", "c0020", "1" })
			must(h.f.main, { "rank", "c0017", "2" })
			must(h.f.main, { "rank", "c0030", "3" })
			t.expect(must(h.f.main, { "next" })).toBe("c0014 draft rank 5")
			-- the ranks of the skipped items are as they were set
			t.expect(rankOf("c0020")).toBe("1")
			t.expect(rankOf("c0017")).toBe("2")
			t.expect(rankOf("c0030")).toBe("3")
		end
	)

	it(
		"AC4: next reads origin/main, not this checkout: a rank published from a worktree is seen at once",
		function()
			must(wt, { "sync" })
			must(wt, { "rank", "c0012", "2" })
			t.expect(fixture.git(h.f.main, { "rev-parse", "HEAD" }) ~= tip()).toBe(true) -- the main checkout has not moved
			t.expect(must(h.f.main, { "next" })).toBe("c0012 draft rank 2")
		end
	)

	it(
		"AC2: --before with an empty id drops the card below the unset ones: it is unset, and the notice says so",
		function()
			must(h.f.main, { "sync" })
			local before = tip()
			local out = must(h.f.main, { "rank", "c0014", "--before", "" })
			local lines = string.split(out, "\n")
			t.expect(lines[1]).toBe("c0014 rank unset (was 5)")
			t.expect(lines[2])
				.toBe(
					"c0014: dropped below the unset items: it sorts among them by number, and nothing is renumbered"
				)
			t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
			t.expect(changedFiles(before)).toBe("issues/c0014/c0014.md\nissues/c0014/provenance.md")
			t.expect(rankOf("c0014")).toBe("unset")
			t.expect(has(onOrigin(`{P}/c0014/provenance.md`), `| ranked | {ME} | rank=unset; was=5 |`))
				.toBe(true)
			-- already unset and dropped below the unset ones: nothing to do, and the notice still explains
			local again = must(h.f.main, { "rank", "c0014", "--before", "" })
			t.expect(again).toBe(
				"c0014: unchanged\nc0014: dropped below the unset items: it sorts among them by number, and nothing is renumbered"
			)
		end
	)

	it("AC6: the audit rejects a malformed rank in any state and names the item and the rule", function()
		trackerfix.elsewhere(h.f, {
			[`{P}/c0040/c0040.md`] = doc("c0040", { rank = "0" }),
			[`{P}/c0041/c0041.md`] = (string.gsub(doc("c0041"), "\nstatus:", "\nrank: 5\nrank: 6\nstatus:")),
			[`{P}/c0042/c0042.md`] = (string.gsub(doc("c0042"), "\nstatus:", "\n rank: 5\nstatus:")),
			[`{P}/c0043/c0043.md`] = doc("c0043", { rank = "30" }),
			[`{P}/c0044/c0044.md`] = doc("c0044", { rank = "30 auto" }),
			[`{P}/c0045/c0045.md`] = doc("c0045", { rank = "30 AUTO" }),
			[`{P}/done/c0099/c0099.md`] = doc("c0099", { rank = "abc", status = "done-quiet-copper-falcon" }),
			[`{P}/done/c0099/check.sh`] = CHECK,
		}, "malformed ranks")
		must(wt, { "sync" })
		local r = zn(wt, { "audit" })
		t.expect(r.ok).toBe(false)
		local said = r.stdout .. r.stderr
		t.expect(has(said, "error rank pickman/.tracker/issues/c0040: c0040: rank: 0 is not a whole number"))
			.toBe(true)
		t.expect(has(said, "c0041: rank: is written 2 times")).toBe(true)
		t.expect(has(said, "c0042:  rank: 5: write the rank as `rank: <whole number>`")).toBe(true)
		t.expect(has(said, "c0045: rank: 30 AUTO is not a whole number")).toBe(true)
		-- a done item's leftover line is still checked
		t.expect(
			has(said, "error rank pickman/.tracker/issues/done/c0099: c0099: rank: abc is not a whole number")
		)
			.toBe(true)
		t.expect(has(said, "c0043")).toBe(false)
		t.expect(has(said, "c0044")).toBe(false)
	end)
end)
