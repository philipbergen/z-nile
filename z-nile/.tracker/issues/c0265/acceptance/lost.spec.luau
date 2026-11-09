--!strict
-- c0265: a claim whose newest sign of life (its newest beat, else the moment it landed) is older than the stale limit is
-- stale; the open pull requests then decide: one that names the item (or anything holding its stamp) parks it, none
-- makes it lost. `lost` and `status` say so and list lost work first. Whatever cannot be read (the beats, the pull
-- requests, a malformed beat ref) makes nothing lost. Time is ZN_NOW (honoured only inside a spec run). Fixture under
-- .cache/c0265-lost.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wt2, wt3 = "", "", "" -- three worktrees: wt made the claims, wt2 holds none, wt3 made one and runs nothing else
local T0 = os.time()
local STALE = heartbeat.STALE
-- a moment when everything claimed at about T0 is stale, whatever the seconds the fixture took to build
local LATE = T0 + 3 * STALE
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- ./zn in `cwd` with the fakes first on PATH (the fake gh answers `pr list` from <fakes>/prs.json) and ZN_NOW
local function zn(cwd: string, args: { string }, now: number?, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
	if now then
		env.ZN_NOW = tostring(now)
	end
	for k, v in (extra or {}) :: { [string]: string } do
		env[k] = v
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function stampOf(path: string): string
	local text = fixture.git(h.f.origin, { "show", `main:{path}` })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error(`{path} has no status on origin`)
end
-- another terminal's beat: a commit with main's tree and tip as parent, force-pushed as the stamp's branch
local function pushBeat(stamp: string, epoch: number)
	local tree = fixture.git(h.f.other, { "rev-parse", "HEAD^{tree}" })
	local sha = fixture.git(h.f.other, { "commit-tree", tree, "-p", "HEAD", "-m", `hb {stamp} {epoch}` })
	fixture.git(h.f.other, { "push", "-q", "-f", "origin", `{sha}:refs/heads/hb/{stamp}` })
end
local function issue(id: string, status: string, raft: string?, design: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
local function lineOf(text: string, id: string): string
	return string.match(text, `(%f[%w]{id}%f[%W][^\n]*)`) or ""
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local P = "pickman/.tracker/issues"
local GH = [[#!/bin/sh
if [ "$1" = pr ] && [ "$2" = list ]; then
  [ -f "$FAKE_DIR/ghfail" ] && { echo "gh: fake failure" >&2; exit 1; }
  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"
  exit 0
fi
exit 0
]]
-- the git shim: the heartbeat read (a fetch of the hb branches into refs/zn/hb-seen) fails (lsfail), fails once on a ref
-- lock a sibling worktree holds (lockonce), and
-- is counted in <fakes>/lscalls; every fetch is counted in <fakes>/fetchcalls
local SHIM = [[#!/bin/sh
if [ "$1" = push ] && [ -f "$FAKE_DIR/hbpushfail" ]; then case "$*" in *":refs/heads/hb/"*) echo "fatal: fake first-beat refusal" >&2; exit 1;; esac; fi
if [ "$1" = log ] && [ -f "$FAKE_DIR/landingpin" ]; then case "$*" in *--first-parent*-1*engine/heartbeat.luau*) echo 4102444800; exit 0;; esac; fi
if [ "$1" = log ] && [ -f "$FAKE_DIR/nolanding" ]; then case "$*" in *engine/heartbeat.luau*) echo "fatal: fake log failure" >&2; exit 128;; esac; fi
if [ "$1" = log ] && [ -f "$FAKE_DIR/nolog" ]; then echo "fatal: fake log failure" >&2; exit 128; fi
if [ "$1" = fetch ]; then echo f >> "$FAKE_DIR/fetchcalls"; fi
if [ "$1" = fetch ]; then
  case "$*" in
    *hb-seen*)
      echo x >> "$FAKE_DIR/lscalls"
      [ -f "$FAKE_DIR/lsfail" ] && { echo "fatal: fake heartbeat read failure" >&2; exit 128; }
      if [ -f "$FAKE_DIR/lockonce" ]; then rm -f "$FAKE_DIR/lockonce"; echo "error: cannot lock ref 'refs/zn/hb-seen/x': is at a but expected b" >&2; exit 1; fi ;;
  esac
fi
]]

return t.spec("c0265 lost work", function(it)
	it("sets up claimable issues, a never-beaten claim, a done one, a prepared raft and the fakes", function()
		h = fakecli.new("c0265-lost", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0075/c0075.md`] = issue("c0075", "new-a-b-c"),
			[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
			[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "R0010", "ready"),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Lost\nslug: lost\nsingle: false\nissues: [c0040]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"), -- claimed before beats existed
			[`{P}/done/c0060/c0060.md`] = issue("c0060", "active-brisk-amber-otter"), -- keeps its claim stamp
		})
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		local real = fs.readFile(`{h.bin}/git`)
		fs.writeFile(`{h.bin}/git`, (string.gsub(real, "^#!/bin/sh\n", SHIM, 1)))
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-lost" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-lost-2" }), "worktree"), "%s+$", ""))
		wt3 = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-lost-3" }), "worktree"), "%s+$", ""))
		-- c0075 is made after the landing and never beaten: its first beat is refused, and wt3 runs no other command (a
		-- later layer beats the claims a worktree holds at each of its commands)
		fs.writeFile(`{h.fakes}/hbpushfail`, "1")
		must(zn(wt3, { "status", "c0075", "preparing" }, T0), "claim c0075")
		fs.removeFile(`{h.fakes}/hbpushfail`)
		-- the premise of the flatline cases: c0075 was made in a later second than the seed commit, the fixture's "landing"
		local claimedAt = tonumber(
			fixture.git(h.f.origin, { "log", "-1", "--format=%ct", "main", "--", `{P}/c0075/c0075.md` })
		)
		local landedAt = tonumber(fixture.git(h.f.origin, {
			"log",
			"-1",
			"--format=%ct",
			"--diff-filter=A",
			"main",
			"--",
			"z-nile/engine/heartbeat.luau",
		}))
		t.expect((claimedAt :: number) > (landedAt :: number)).toBe(true)
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		must(zn(wt, { "status", "c0020", "preparing" }, T0), "claim c0020")
		must(zn(wt, { "new", "raft", "chore", "lostraft", "c0030", "--project", "pickman" }, T0), "new raft")
		must(zn(h.f.main, { "ready", "R0010" }, T0), "ready R0010") -- readied, nobody starts it
		-- c0010 beats once more, so it is silent for less time than c0030 (never beaten) although its id is lower:
		-- silence order and id order differ, which pins "longest silent first". c0050 was claimed in the seed commit,
		-- the same second the heartbeat "landed": it is older than the landing and never beaten, so it reads [no beat]
		pushBeat(stampOf(`{P}/c0010/c0010.md`), T0 + 570)
		-- a raft recombine retired keeps the stamp it was claimed with: never a claim, whatever its silence. Added after the
		-- seed, so it is made after the heartbeat "landed" (the seed): were it a claim it would be lost
		trackerfix.elsewhere(h.f, {
			["pickman/.tracker/rafts/retired/R0099/R0099.md"] = "---\nid: R0099\ntype: chore\ntitle: Gone\nslug: gone\nsingle: false\nissues: []\ndesign: draft\ncreated: 2026-10-06\nstatus: preparing-quiet-copper-falcon\n---\n\n# R0099\n",
		}, "a raft recombine retired")
		-- the done item's old claim has a beat on origin, as one that finished mid-work would
		pushBeat("active-brisk-amber-otter", T0 - 99999)
	end)

	it("nothing is lost while the claims are fresh", function()
		t.expect(zn(h.f.main, { "lost" }, T0 + 60).stdout).toBe("")
		t.expect(zn(h.f.main, { "lost" }, T0 + STALE).stdout).toBe("")
		t.expect(has(zn(h.f.main, { "status" }, T0 + STALE).stdout, "[lost")).toBe(false)
	end)

	it("a stale claim with no pull request is lost and listed first; a parked one is not lost", function()
		fs.writeFile(
			`{h.fakes}/prs.json`,
			'[{"title":"tracker: prep c0020 Something","headRefName":"prep-something"}]'
		)
		local lost = must(zn(h.f.main, { "lost" }, LATE), "lost")
		-- one line: id, state, minutes floored; c0010's last beat is the T0 + 570 one, so 2130 s = 35.5 m at LATE: floored to 35 (rounded up would say 36)
		t.expect(has(lost, "c0010 preparing 35m\n")).toBe(true)
		t.expect(has(lost, "c0040 active")).toBe(true) -- a raft's members each get their own line
		t.expect(has(lost, "c0075 preparing")).toBe(true) -- never beaten, made after the landing: silent since it landed (flatline)
		t.expect((string.find(lost, "c0030 ", 1, true) or 0) < (string.find(lost, "c0010 ", 1, true) or 0))
			.toBe(true) -- longest silent first, against id order (c0030 is silent since its claim, c0010 since T0 + 570)
		t.expect(has(lost, "c0050")).toBe(false) -- made before the landing, never beaten: [no beat], not lost
		t.expect(has(lost, "R0010 active")).toBe(true) -- readied and not started
		t.expect(has(lost, "c0020")).toBe(false) -- a pull request names it
		t.expect(has(lost, "c0060")).toBe(false) -- a done item keeps its stamp and is never a claim
		local listing = must(zn(h.f.main, { "status" }, LATE), "status")
		local seenOther = false
		for line in string.gmatch(listing, "[^\n]+") do
			local isLost = has(line, "[lost ")
			t.expect(isLost and seenOther).toBe(false) -- every lost line comes before every other line
			seenOther = seenOther or not isLost
		end
		t.expect(has(lineOf(listing, "c0010"), "[lost 35m]")).toBe(true)
		-- and the status list orders them the same way: c0030 (silent longest) before c0010, against id order
		t.expect(
			(string.find(listing, "c0030 ", 1, true) or 0) < (string.find(listing, "c0010 ", 1, true) or 0)
		)
			.toBe(true)
		t.expect(has(lineOf(listing, "c0020"), "[parked]")).toBe(true)
		t.expect(has(lineOf(listing, "c0050"), "[no beat]")).toBe(true)
		t.expect(has(listing, "c0060")).toBe(false)
		-- a dispatcher waiting on the user's answer (questions.md in its run state) parks the claim too
		fs.writeDir(`{h.f.main}/.cache/dispatch/c0010`)
		fs.writeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`, "## Q1\nWhich scope?\n")
		t.expect(has(lineOf(zn(h.f.main, { "status" }, LATE).stdout, "c0010"), "[parked]")).toBe(true)
		t.expect(has(zn(h.f.main, { "lost" }, LATE).stdout, "c0010")).toBe(false)
		-- a command in a worktree reads the run state of the main checkout: it parks there too (a worktree that holds
		-- no claim: one that made c0010's claim may beat it, and a beat makes it live, not parked)
		local fromWorktree = zn(wt2, { "status" }, LATE).stdout
		fs.removeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`)
		t.expect(has(lineOf(fromWorktree, "c0010"), "[parked]")).toBe(true)
	end)

	it("a pull request naming only the raft parks the raft and its member, which share its stamp", function()
		fs.writeFile(
			`{h.fakes}/prs.json`,
			'[{"title":"R0010: lost raft","headRefName":"R0010-lost"},{"title":"tracker: prep c0020","headRefName":"p"}]'
		)
		local lost = must(zn(h.f.main, { "lost" }, LATE), "lost")
		t.expect(has(lost, "R0010")).toBe(false)
		t.expect(has(lost, "c0040")).toBe(false)
		local listing = must(zn(h.f.main, { "status" }, LATE), "status")
		t.expect(has(lineOf(listing, "R0010"), "[parked]")).toBe(true)
		t.expect(has(lineOf(listing, "c0040"), "[parked]")).toBe(true)
	end)

	it("a raft recombine retired is never a claim: no line in lost, no marker in status", function()
		local at = LATE + 3 * STALE
		t.expect(has(zn(h.f.main, { "lost" }, at).stdout, "R0099")).toBe(false)
		local line = lineOf(zn(h.f.main, { "status" }, at).stdout, "R0099")
		t.expect(has(line, "[")).toBe(false)
	end)

	it(
		"a claim whose landing time cannot be read and that never beat is unconfirmed: [stale?], not lost",
		function()
			local at = LATE + 3 * STALE
			fs.writeFile(`{h.fakes}/nolog`, "1")
			local lost = zn(h.f.main, { "lost" }, at)
			local listing = zn(h.f.main, { "status" }, at)
			fs.removeFile(`{h.fakes}/nolog`)
			t.expect(has(lost.stdout, "c0075")).toBe(false)
			t.expect(has(lost.stdout, "c0050")).toBe(false)
			t.expect(has(lineOf(listing.stdout, "c0075"), "[stale?]")).toBe(true)
			t.expect(has(lineOf(listing.stdout, "c0050"), "[stale?]")).toBe(true)
		end
	)

	it("an unreadable landing of the heartbeat never makes a beatless claim lost: [no beat]", function()
		local at = LATE + 3 * STALE
		t.expect(has(zn(h.f.main, { "lost" }, at).stdout, "c0075")).toBe(true) -- readable: lost, as it is made after the landing
		fs.writeFile(`{h.fakes}/nolanding`, "1")
		local lost = zn(h.f.main, { "lost" }, at)
		local listing = zn(h.f.main, { "status" }, at)
		fs.removeFile(`{h.fakes}/nolanding`)
		t.expect(has(lost.stdout, "c0075")).toBe(false)
		t.expect(has(lineOf(listing.stdout, "c0075"), "[no beat]")).toBe(true)
	end)

	it("an unreadable pull request list is never read as complete: 200 entries or not a list", function()
		local saved = fs.readFile(`{h.fakes}/prs.json`)
		local entries = {}
		for i = 1, 200 do
			table.insert(entries, `\{"title":"x {i}","headRefName":"b{i}"}`)
		end
		fs.writeFile(`{h.fakes}/prs.json`, `[{table.concat(entries, ",")}]`)
		local full = zn(h.f.main, { "lost" }, LATE)
		t.expect(full.ok).toBe(false)
		t.expect(has(full.stderr, "pull requests unreadable")).toBe(true)
		fs.writeFile(`{h.fakes}/prs.json`, '{"message":"rate limited"}')
		local obj = zn(h.f.main, { "lost" }, LATE)
		t.expect(obj.ok).toBe(false)
		t.expect(has(obj.stderr, "pull requests unreadable")).toBe(true)
		fs.writeFile(`{h.fakes}/prs.json`, saved)
	end)

	it("a protected checkout reads no remote: status refuses before any fetch, lost says so", function()
		local function calls(): number
			local text = if fs.isFile(`{h.fakes}/lscalls`) then fs.readFile(`{h.fakes}/lscalls`) else ""
			return #string.gsub(text, "[^x]", "")
		end
		local function fetches(): number
			local text = if fs.isFile(`{h.fakes}/fetchcalls`) then fs.readFile(`{h.fakes}/fetchcalls`) else ""
			return #string.gsub(text, "[^f]", "")
		end
		local before, fetchedBefore = calls(), fetches()
		-- the guards in the main checkout answer "guarded" (the fixture's own copy of fence.sh)
		local fence = `{h.f.main}/z-nile/lib/fence.sh`
		local original = fs.readFile(fence)
		fs.writeFile(fence, original .. "\npickman_guarded() { echo guarded; }\n")
		local listing = zn(h.f.main, { "status" }, LATE)
		-- status refuses in a protected checkout as it does today (publishing() is false there), before any fetch
		t.expect(listing.ok).toBe(false)
		t.expect(has(listing.stderr, "protected")).toBe(true)
		t.expect(has(listing.stdout, "[lost")).toBe(false)
		local lostHere = zn(h.f.main, { "lost" }, LATE)
		fs.writeFile(fence, original)
		t.expect(lostHere.ok).toBe(true)
		t.expect(lostHere.stdout).toBe("")
		t.expect(has(lostHere.stderr, "protected checkout")).toBe(true)
		t.expect(calls()).toBe(before) -- no ls-remote: nothing was read from the remote
		t.expect(fetches()).toBe(fetchedBefore) -- and no fetch either
	end)

	it("a beat revives a lost claim", function()
		must(zn(wt, { "beat", "c0010" }, LATE), "beat of a lost claim")
		t.expect(has(zn(h.f.main, { "lost" }, LATE + STALE).stdout, "c0010")).toBe(false)
		t.expect(has(zn(h.f.main, { "lost" }, LATE + STALE + 1).stdout, "c0010")).toBe(true)
	end)

	it("what cannot be read marks nothing lost: lost exits 1 and says why, status still lists", function()
		fs.writeFile(`{h.fakes}/ghfail`, "1")
		local r = zn(h.f.main, { "lost" }, LATE + 5 * STALE)
		t.expect(r.ok).toBe(false)
		t.expect(r.stdout).toBe("")
		t.expect(has(r.stderr, "pull requests")).toBe(true)
		local listing = zn(h.f.main, { "status" }, LATE + 5 * STALE)
		t.expect(listing.ok).toBe(true)
		t.expect(has(lineOf(listing.stdout, "c0010"), "[stale?]")).toBe(true) -- stale, unconfirmed: not lost
		t.expect(has(listing.stdout, "[lost")).toBe(false)
		fs.removeFile(`{h.fakes}/ghfail`)
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local beatsGone = zn(h.f.main, { "lost" }, LATE + 5 * STALE)
		t.expect(beatsGone.ok).toBe(false)
		t.expect(beatsGone.stdout).toBe("")
		t.expect(has(beatsGone.stderr, "heartbeat")).toBe(true)
		local list = zn(h.f.main, { "status" }, LATE + 5 * STALE)
		t.expect(list.ok).toBe(true) -- the list prints as it always did
		t.expect(has(list.stderr, "heartbeats unreadable")).toBe(true)
		t.expect(has(list.stdout, "[lost")).toBe(false)
		fs.removeFile(`{h.fakes}/lsfail`)
	end)

	it(
		"a malformed beat ref makes every stale claim unknown, everywhere, and the message says how to clear it",
		function()
			local at = LATE + 9 * STALE
			fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:refs/heads/hb/garbage" })
			local still = zn(h.f.main, { "lost" }, at)
			t.expect(has(still.stdout, "c0010")).toBe(false)
			t.expect(has(still.stderr, "refs/heads/hb/garbage")).toBe(true)
			t.expect(has(still.stderr, "git push origin :refs/heads/hb/garbage")).toBe(true)
			t.expect(has(lineOf(zn(h.f.main, { "status" }, at).stdout, "c0010"), "[stale?]")).toBe(true)
			fixture.git(h.f.other, { "push", "-q", "origin", ":refs/heads/hb/garbage" })
			t.expect(has(zn(h.f.main, { "lost" }, at).stdout, "c0010")).toBe(true) -- cleared: lost again
		end
	)

	it("a claim made before the landing is judged like any other once it has beaten", function()
		local c0050 = stampOf(`{P}/c0050/c0050.md`)
		pushBeat(c0050, T0 + 100) -- another terminal's beat, long ago
		local at = LATE + 12 * STALE
		local lost = zn(h.f.main, { "lost" }, at).stdout
		t.expect(has(lost, "c0050 preparing")).toBe(true)
		t.expect(has(lineOf(zn(h.f.main, { "status" }, at).stdout, "c0050"), "[lost ")).toBe(true)
	end)

	it(
		"a ref lock a sibling worktree holds for the heartbeat read is retried once: lost and beat still answer",
		function()
			local at = LATE + 14 * STALE
			fs.writeFile(`{h.fakes}/lockonce`, "1")
			local lost = zn(h.f.main, { "lost" }, at)
			t.expect(lost.ok).toBe(true)
			t.expect(has(lost.stdout, "c0010")).toBe(true)
			t.expect(fs.isFile(`{h.fakes}/lockonce`)).toBe(false) -- the first read took the failure, the retry the answer
			fs.writeFile(`{h.fakes}/lockonce`, "1")
			must(zn(wt, { "beat", "c0010" }, at), "beat through a locked read")
			t.expect(has(zn(h.f.main, { "lost" }, at).stdout, "c0010")).toBe(false) -- it landed
		end
	)

	it("the landing is read with the arguments heartbeat.landingArgs() names", function()
		local at = LATE + 3 * STALE
		-- the shim answers a late landing only to a read naming --first-parent and -1 on the module; any other read of
		-- it falls through to git, whose answer is the seed's second
		fs.writeFile(`{h.fakes}/landingpin`, "1")
		local lost = zn(h.f.main, { "lost" }, at)
		local listing = zn(h.f.main, { "status" }, at)
		fs.removeFile(`{h.fakes}/landingpin`)
		t.expect(has(lost.stdout, "c0075")).toBe(false)
		t.expect(has(lineOf(listing.stdout, "c0075"), "[no beat]")).toBe(true)
	end)
end)
