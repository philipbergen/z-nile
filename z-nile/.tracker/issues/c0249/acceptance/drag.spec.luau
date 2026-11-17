--!strict
-- c0249 AC2, AC3, AC10: what a drag does around other people's work, in a tracker fixture with a bare origin. A move
-- ranks unset items above it, and an unrelated move never reorders the rafts (the unset items it ranks are marked auto,
-- which a raft does not count), while a rank a person puts on a member does; two drags at once give the second a plan
-- made from the first's result (the competitor lands during the first push, through a git shim); a rank published while
-- a prep branch edits `design:` and `status:` merges without a conflict; and a rank that is on origin/main is reported
-- as saved even when this checkout cannot be fast-forwarded. Fixture under .cache/c0249-drag.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local NAME = "c0249-drag"
local P, RF = "pickman/.tracker/issues", "pickman/.tracker/rafts"
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
local GH = '#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = list ]; then echo "[]"; exit 0; fi\nexit 0\n'
-- the competitor: during the first push of a `git` the next command makes, another terminal lands a rank on c0320
local SHIM = [[#!/bin/sh
if [ "$1" = push ] && [ -f "$FAKE_DIR/race" ]; then
  rm -f "$FAKE_DIR/race"
  O="$(cat "$FAKE_DIR/race-clone")"
  "$0" -C "$O" fetch -q origin main
  "$0" -C "$O" reset -q --hard origin/main
  perl -0pi -e 's/\nid: c0320\n/\nid: c0320\nrank: 1\n/' "$O/pickman/.tracker/issues/c0320/c0320.md"
  "$0" -C "$O" add -A
  "$0" -C "$O" -c user.name=race -c user.email=race@example.invalid commit -q -m competitor
  "$0" -C "$O" push -q origin HEAD:main
fi
]]

local h: fakecli.Harness
local wt = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }): fixture.Result
	local env: { [string]: string } = table.clone(HUMAN)
	env.FAKE_DIR = h.fakes
	env.PATH = `{h.bin}:{process.env.PATH}`
	env.ZN_AGENT_TOKEN_FILE = h.token
	env.ZN_WATERMARK_DIR = `{h.f.base}/watermark`
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(cwd: string, args: { string }): string
	local r = zn(cwd, args)
	if not r.ok then
		error(`{table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function onOrigin(path: string): string
	local r = fixture.exec(h.f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else ""
end
local function rankLine(id: string): string
	return string.match(onOrigin(`{P}/{id}/{id}.md`), "\nrank: ([^\n]*)\n") or "unset"
end
local function commits(since: string): string
	return fixture.git(h.f.origin, { "rev-list", "--count", `{since}..main` })
end
local function doc(id: string, over: { [string]: string }?): string
	local o: { [string]: string } = over or {}
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {o.raft or ""}\ndepends_on: []\n`
		.. `emergent: false\ndesign: {o.design or "draft"}\ncreated: 2026-11-01\nstatus: {o.status or "new-quiet-copper-falcon"}\n---\n\n# {id}\n\n`
		.. `## Problem\nThe {id} problem.\n\n## Solution\nThe {id} solution.\n\n## Design\nThe {id} design.\n\n`
		.. `## Acceptance criteria\nThe {id} criteria.\n\n## Test plan\nThe {id} plan.\n`
end
local function raftDoc(id: string, member: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nsingle: true\nissues: [{member}]\ndesign: ready\n`
		.. `created: 2026-11-01\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Theme\nThe {id} theme.\n`
end

return t.spec("c0249 a drag among other people's work", function(it)
	it(
		"sets up unset issues, two claimable rafts whose members are c0312 and c0311, and the git shim",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = "# architecture\n",
				["z-nile/next"] = "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n",
			}
			for _, id in { "c0310", "c0313", "c0320", "c0321" } do
				seed[`{P}/{id}/{id}.md`] = doc(id)
				seed[`{P}/{id}/check.sh`] = CHECK
			end
			-- R0301 holds c0312 and R0302 holds c0311: the rafts' numbers and their members' go in opposite orders
			for _, pair in { { "R0301", "c0312" }, { "R0302", "c0311" } } do
				local rid, member = pair[1], pair[2]
				seed[`{P}/{member}/{member}.md`] =
					doc(member, { raft = rid, design = "ready", status = "prepared-quiet-copper-falcon" })
				seed[`{P}/{member}/check.sh`] = CHECK
				seed[`{P}/{member}/acceptance/hold.spec.luau`] = SPEC
				seed[`{RF}/{rid}/{rid}.md`] = raftDoc(rid, member)
				seed[`{RF}/{rid}/check.sh`] = CHECK
			end
			h = fakecli.new(NAME, seed)
			fs.writeFile(`{h.bin}/gh`, GH)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			local real = fs.readFile(`{h.bin}/git`)
			fs.writeFile(`{h.bin}/git`, (string.gsub(real, "^#!/bin/sh\n", SHIM, 1)))
			fs.writeFile(`{h.fakes}/race-clone`, h.f.other)
			wt = (string.gsub(must(h.f.main, { "worktree", "c0249-drag" }), "%s+$", ""))
			must(wt, { "audit" })
		end
	)

	it(
		"AC3: a drag among unset items never reorders the rafts: the rows it writes for their members carry moved=",
		function()
			t.expect(must(h.f.main, { "next" })).toBe("R0301 raft rank unset")
			local before = fixture.git(h.f.origin, { "rev-parse", "main" })
			-- c0310 after c0312 ranks c0311 and c0312 (the members, above the drop) and c0310
			t.expect(must(h.f.main, { "rank", "c0310", "after", "c0312" })).toBe(table.concat({
				"c0311 rank 10 (was unset)",
				"c0312 rank 20 (was unset)",
				"c0310 rank 30 (was unset)",
			}, "\n"))
			t.expect(commits(before)).toBe("1")
			-- the lines are bare integers; who set them is in provenance.md (moved= on the members', none on the moved item's)
			t.expect(rankLine("c0311")).toBe("10")
			t.expect(rankLine("c0312")).toBe("20")
			t.expect(rankLine("c0310")).toBe("30")
			t.expect(has(onOrigin(`{P}/c0311/provenance.md`), "rank=10; was=unset; moved=c0310 |")).toBe(true)
			t.expect(has(onOrigin(`{P}/c0312/provenance.md`), "rank=20; was=unset; moved=c0310 |")).toBe(true)
			t.expect(has(onOrigin(`{P}/c0310/provenance.md`), "rank=30; was=unset |")).toBe(true)
			t.expect(has(onOrigin(`{P}/c0310/provenance.md`), "moved=")).toBe(false)
			-- the raft that was first is still first: with every rank counted, R0302 (member c0311, 10) would have jumped it
			t.expect(must(h.f.main, { "next" })).toBe("R0301 raft rank unset")
			-- `work next` reads the members' records the same way (workread.collect), so it takes R0301 as well
			t.expect(has(must(h.f.main, { "work", "next" }), "R0301: ready")).toBe(true)
			t.expect(has(must(h.f.main, { "list", "backlog" }), "R0301")).toBe(true)
			local listed = must(h.f.main, { "list", "backlog" })
			t.expect(string.find(listed, "R0301", 1, true) < string.find(listed, "R0302", 1, true)).toBe(true)
		end
	)

	it(
		"AC3: a rank a person puts on a member moves its raft, and asking for a moved-written rank's place makes it a person's",
		function()
			-- c0311 (10, written by the drag) asked for its own place, the top: no line changes, a row without moved= is
			-- appended, and the rank is now a person's: R0302 (member c0311) follows it
			local at = fixture.git(h.f.origin, { "rev-parse", "main" })
			t.expect(must(h.f.main, { "rank", "c0311", "top" })).toBe("c0311 rank 10 (was 10)")
			t.expect(fixture.git(h.f.origin, { "diff", "--name-only", `{at}..main` }))
				.toBe(`{P}/c0311/provenance.md`)
			t.expect(rankLine("c0311")).toBe("10")
			t.expect(has(onOrigin(`{P}/c0311/provenance.md`), "rank=10; was=10 |")).toBe(true)
			t.expect(must(h.f.main, { "next" })).toBe("R0302 raft rank 10")
			t.expect(has(must(h.f.main, { "work", "next" }), "R0302: ready")).toBe(true)
			-- asking again changes nothing: it is a person's now
			local again = fixture.git(h.f.origin, { "rev-parse", "main" })
			t.expect(must(h.f.main, { "rank", "c0311", "top" })).toBe("c0311: unchanged")
			t.expect(fixture.git(h.f.origin, { "rev-parse", "main" })).toBe(again)
			must(h.f.main, { "rank", "c0311", "5" })
			t.expect(rankLine("c0311")).toBe("5")
			t.expect(must(h.f.main, { "next" })).toBe("R0302 raft rank 5")
			-- c0312 (20, written by the drag) asked for the top: now a person's rank, and R0301 follows it
			t.expect(must(h.f.main, { "rank", "c0312", "top" })).toBe("c0312 rank 2 (was 20)")
			t.expect(rankLine("c0312")).toBe("2")
			t.expect(must(h.f.main, { "next" })).toBe("R0301 raft rank 2")
		end
	)

	it("AC2: two drags at once: the second plans again from the first's result, in two commits", function()
		local before = fixture.git(h.f.origin, { "rev-parse", "main" })
		-- the competitor ranks c0320 (1) during our first push; c0321 to the top then finds no room above rank 1
		fs.writeFile(`{h.fakes}/race`, "1")
		local out = must(h.f.main, { "rank", "c0321", "top" })
		t.expect(fs.isFile(`{h.fakes}/race`)).toBe(false) -- the competitor ran
		t.expect(commits(before)).toBe("2")
		t.expect(fixture.git(h.f.origin, { "log", "-2", "--format=%s", "main" }))
			.toBe("tracker: rank c0321 top\ncompetitor")
		-- planned from a base that holds the competitor's rank: renumbered under it, not placed beside a stale 1
		t.expect(out).toBe(table.concat({
			"c0321 rank 10 (was unset)",
			"c0320 rank 20 (was 1)",
			"c0312 rank 30 (was 2)",
			"c0311 rank 40 (was 5)",
			"c0310 rank 50 (was 30)",
		}, "\n"))
		t.expect(rankLine("c0321")).toBe("10")
		t.expect(rankLine("c0320")).toBe("20")
		-- the competitor's document is not lost, only renumbered
		t.expect(has(onOrigin(`{P}/c0320/provenance.md`), "rank=20; was=1; moved=c0321")).toBe(true)
	end)

	it(
		"AC10: a rank published while a prep branch edits design and status merges without a conflict",
		function()
			-- a prep edits `design:` and `status:` of its document and commits, as z-design's carried move does
			local docPath = `{wt}/{P}/c0313/c0313.md`
			must(wt, { "sync" })
			local text = fs.readFile(docPath)
			text = string.gsub(text, "design: draft", "design: reviewed")
			text = string.gsub(
				text,
				"status: new%-quiet%-copper%-falcon",
				"status: prepared-quiet-copper-falcon"
			)
			fs.writeFile(docPath, text)
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "prep c0313" })
			-- meanwhile a rank is published on the same document from the main checkout
			must(h.f.main, { "rank", "c0313", "top" })
			t.expect(rankLine("c0313")).toBe("5")
			local r = zn(wt, { "sync" })
			t.expect(r.ok).toBe(true)
			local merged = fs.readFile(docPath)
			t.expect(has(merged, "\nid: c0313\nrank: 5\n")).toBe(true)
			t.expect(has(merged, "design: reviewed")).toBe(true)
			t.expect(has(merged, "status: prepared-quiet-copper-falcon")).toBe(true)
			t.expect(has(merged, "<<<<<<<")).toBe(false)
		end
	)

	it(
		"AC2: a rank on origin/main is reported as saved when this checkout cannot be fast-forwarded",
		function()
			fs.writeFile(`{h.f.main}/.git/index.lock`, "")
			local before = fixture.git(h.f.origin, { "rev-parse", "main" })
			local r = zn(h.f.main, { "rank", "c0310", "top" })
			fs.removeFile(`{h.f.main}/.git/index.lock`)
			t.expect(r.ok).toBe(true)
			t.expect(
				has(r.stderr, "rank: saved on origin/main, but this checkout could not be brought up to date")
			)
				.toBe(true)
			t.expect(commits(before)).toBe("1")
			t.expect(rankLine("c0310")).toBe("2")
			must(h.f.main, { "sync" })
			t.expect(fixture.git(h.f.main, { "rev-parse", "HEAD" }))
				.toBe(fixture.git(h.f.origin, { "rev-parse", "main" }))
		end
	)
end)
