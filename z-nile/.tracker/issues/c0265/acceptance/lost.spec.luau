--!strict
-- c0265: a claim whose newest sign of life (its newest beat, else the moment it landed) is older than the stale limit is
-- stale; the open pull requests then decide: one that names the item (or anything holding its stamp) parks it, none
-- makes it lost. `lost` and `status` say so and list lost work first. Whatever cannot be read (the beats, the pull
-- requests, a malformed beat ref, a hung remote) makes nothing lost and refuses a takeover. A lost preparing claim,
-- an issue's or a raft's, is taken over by `status <id> preparing`; the old claimant's carried move is then refused and
-- its worktree stops beating. Time is ZN_NOW (honoured only inside a spec run). Fixture under .cache/c0265-lost.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wt2 = "", "" -- two worktrees of the fixture: two terminals
local raftId = "" -- the rafting claim `new raft` made in wt
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
-- the model a board page embeds (<script id="board-data">): decoded, so a case asserts data, not rendered text
local function boardModel(path: string): any
	local html = fs.readFile(path)
	local json = string.match(html, '<script[^>]-id="board%-data"[^>]*>(.-)</script>')
		or error("no board-data in the page")
	return serde.decode("json", json)
end
local function itemOf(model: any, id: string): any
	for _, list in { model.issues, model.rafts } do
		for _, item in list do
			if item.id == id then
				return item
			end
		end
	end
	error(`{id} is not on the board`)
end
local function subjectOf(path: string): string
	return fixture.git(h.f.origin, { "log", "-1", "--format=%s", "main", "--", path })
end
-- the heartbeat branches on origin: their refs, "refs/heads/hb/<stamp>"
local function beatRefs(): { string }
	local out = {}
	local refs = fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/heads/hb/" })
	for line in string.gmatch(refs, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end
local function stampsWithBeats(): { string }
	local out = {}
	for _, ref in beatRefs() do
		table.insert(out, (string.match(ref, "^refs/heads/hb/(.+)$")) or ref)
	end
	return out
end
local function tipOf(stamp: string): string
	return fixture.git(h.f.origin, { "for-each-ref", "--format=%(objectname)", `refs/heads/hb/{stamp}` })
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
-- the git shim: the heartbeat read (a fetch of the hb branches into refs/zn/hb-seen) fails (lsfail) or hangs (lshang) and
-- is counted in <fakes>/lscalls; every fetch is counted in <fakes>/fetchcalls
local SHIM = [[#!/bin/sh
if [ "$1" = fetch ]; then echo f >> "$FAKE_DIR/fetchcalls"; fi
if [ "$1" = fetch ]; then
  case "$*" in
    *hb-seen*)
      echo x >> "$FAKE_DIR/lscalls"
      [ -f "$FAKE_DIR/lsfail" ] && { echo "fatal: fake heartbeat read failure" >&2; exit 128; }
      [ -f "$FAKE_DIR/lshang" ] && sleep 30 ;;
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
			[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
			[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "R0010", "ready"),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Lost\nslug: lost\nsingle: false\nissues: [c0040]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
			[`{P}/c0075/c0075.md`] = issue("c0075", "new-a-b-c"),
			[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"), -- claimed before beats existed
			[`{P}/done/c0060/c0060.md`] = issue("c0060", "active-brisk-amber-otter"), -- keeps its claim stamp
		})
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		local real = fs.readFile(`{h.bin}/git`)
		fs.writeFile(`{h.bin}/git`, (string.gsub(real, "^#!/bin/sh\n", SHIM, 1)))
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-lost" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-lost2" }), "worktree"), "%s+$", ""))
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		must(zn(wt, { "status", "c0020", "preparing" }, T0), "claim c0020")
		must(zn(wt, { "new", "raft", "chore", "lostraft", "c0030", "--project", "pickman" }, T0), "new raft")
		must(zn(h.f.main, { "ready", "R0010" }, T0), "ready R0010") -- readied, nobody starts it
		-- c0010 beats once more, so it is silent for less time than c0050 (never beaten) although its id is lower:
		-- silence order and id order differ, which pins "longest silent first"
		pushBeat(stampOf(`{P}/c0010/c0010.md`), T0 + 600)
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
		t.expect(string.match(lost, "c0010 preparing %d+m\n") ~= nil).toBe(true) -- one line: id, state, minutes
		t.expect(has(lost, "c0050 preparing")).toBe(true) -- never beaten: silent since it landed (flatline)
		t.expect((string.find(lost, "c0050 ", 1, true) or 0) < (string.find(lost, "c0010 ", 1, true) or 0))
			.toBe(true) -- longest silent first, against id order
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
		t.expect(has(lineOf(listing, "c0010"), "[lost ")).toBe(true)
		t.expect(has(lineOf(listing, "c0020"), "[parked]")).toBe(true)
		t.expect(has(listing, "c0060")).toBe(false)
		-- a dispatcher waiting on the user's answer (questions.md in its run state) parks the claim too
		fs.writeDir(`{h.f.main}/.cache/dispatch/c0010`)
		fs.writeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`, "## Q1\nWhich scope?\n")
		t.expect(has(lineOf(zn(h.f.main, { "status" }, LATE).stdout, "c0010"), "[parked]")).toBe(true)
		t.expect(has(zn(h.f.main, { "lost" }, LATE).stdout, "c0010")).toBe(false)
		-- a takeover runs in a worktree, but the run state is the main checkout's: it parks there too
		local parkedTake = zn(wt2, { "status", "c0010", "preparing" }, LATE)
		t.expect(parkedTake.ok).toBe(false)
		t.expect(has(parkedTake.stderr, "parked")).toBe(true)
		fs.removeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`)
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

	it(
		"the board's model carries each verdict, lost work first in its bucket, and none while claims are fresh",
		function()
			local out = `{h.f.main}/.cache/board-lost.html`
			must(zn(h.f.main, { "board", "--out", ".cache/board-lost.html", "-O" }, LATE), "board")
			local model = boardModel(out)
			local c0010 = itemOf(model, "c0010")
			t.expect(c0010.heartbeat).toBe("lost")
			-- minutes from each input's own clock: the last beat is dated T0 + 600, the claim landed earlier
			local landed = tonumber(
				fixture.git(h.f.origin, { "log", "-1", "--format=%ct", "main", "--", `{P}/c0010/c0010.md` })
			)
			t.expect(c0010.minutes).toBe(math.floor((LATE - math.max(landed :: number, T0 + 600)) / 60))
			t.expect(itemOf(model, "c0020").heartbeat).toBe("parked") -- a pull request names it
			t.expect(itemOf(model, "R0010").heartbeat).toBe("parked") -- a pull request names only the raft
			t.expect(itemOf(model, "c0070").heartbeat).toBe(nil) -- not claimed: no verdict
			-- lost work comes first within its bucket: c0050 (lost) before c0020 (parked), against id order
			local bucket = model.views.issues["not"]
			local lostAt, parkedAt = table.find(bucket, "c0050") or 0, table.find(bucket, "c0020") or 0
			t.expect(lostAt > 0 and parkedAt > 0 and lostAt < parkedAt).toBe(true)
			-- and longest silent first among the lost: c0050 (silent longest) before c0010 although its id is higher
			local firstAt, secondAt = table.find(bucket, "c0050") or 0, table.find(bucket, "c0010") or 0
			t.expect(firstAt > 0 and secondAt > 0 and firstAt < secondAt).toBe(true)
			-- pull requests that cannot be read: stale, shown as unconfirmed, never lost
			fs.writeFile(`{h.fakes}/ghfail`, "1")
			must(
				zn(h.f.main, { "board", "--out", ".cache/board-lost.html", "-O" }, LATE),
				"board, no pull requests"
			)
			t.expect(itemOf(boardModel(out), "c0010").heartbeat).toBe("stale")
			fs.removeFile(`{h.fakes}/ghfail`)
			-- fresh claims: no item carries a verdict
			must(
				zn(h.f.main, { "board", "--out", ".cache/board-lost.html", "-O" }, T0 + 60),
				"board while fresh"
			)
			local fresh = boardModel(out)
			for _, list in { fresh.issues, fresh.rafts } do
				for _, item in list do
					t.expect(item.heartbeat).toBe(nil)
				end
			end
		end
	)

	it("the board every publish rebuilds carries the verdicts too", function()
		must(zn(wt2, { "status", "c0070", "preparing" }, LATE), "a publish")
		local model = boardModel(`{h.f.main}/.cache/board.html`)
		t.expect(itemOf(model, "c0010").heartbeat).toBe("lost")
	end)

	it(
		"a protected checkout reads no remote: the board carries no verdicts, status refuses before any fetch, lost says so",
		function()
			local function calls(): number
				local text = if fs.isFile(`{h.fakes}/lscalls`) then fs.readFile(`{h.fakes}/lscalls`) else ""
				return #string.gsub(text, "[^x]", "")
			end
			local common = string.gsub(
				fixture.git(h.f.main, { "rev-parse", "--path-format=absolute", "--git-common-dir" }),
				"%s+$",
				""
			)
			local inherited = process.env.PICKMAN_FENCE_REAL_GIT or ""
			local listed = if inherited ~= "" then `{inherited}:{common}` else common
			local function fetches(): number
				local text = if fs.isFile(`{h.fakes}/fetchcalls`)
					then fs.readFile(`{h.fakes}/fetchcalls`)
					else ""
				return #string.gsub(text, "[^f]", "")
			end
			local before, fetchedBefore = calls(), fetches()
			must(
				zn(
					h.f.main,
					{ "board", "--out", ".cache/board-guarded.html", "-O" },
					LATE,
					{ PICKMAN_FENCE_REAL_GIT = listed }
				),
				"board"
			)
			local model = boardModel(`{h.f.main}/.cache/board-guarded.html`)
			for _, list in { model.issues, model.rafts } do
				for _, item in list do
					t.expect(item.heartbeat).toBe(nil)
				end
			end
			local listing = zn(h.f.main, { "status" }, LATE, { PICKMAN_FENCE_REAL_GIT = listed })
			-- status refuses in a protected checkout as it does today (publishing() is false there), before any fetch
			t.expect(listing.ok).toBe(false)
			t.expect(has(listing.stderr, "protected")).toBe(true)
			t.expect(has(listing.stdout, "[lost")).toBe(false)
			local lostHere = zn(h.f.main, { "lost" }, LATE, { PICKMAN_FENCE_REAL_GIT = listed })
			t.expect(lostHere.ok).toBe(true)
			t.expect(lostHere.stdout).toBe("")
			t.expect(has(lostHere.stderr, "protected checkout")).toBe(true)
			t.expect(calls()).toBe(before) -- no ls-remote: nothing was read from the remote
			t.expect(fetches()).toBe(fetchedBefore) -- and no fetch either
		end
	)

	it("a failed first beat does not fail the claim", function()
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local r = zn(wt2, { "status", "c0075", "preparing" }, LATE)
		fs.removeFile(`{h.fakes}/lsfail`)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "beat: c0075:")).toBe(true) -- said, with the item named (not the board's own note)
		-- and the worktree still keeps the claim alive: the failed attempt wrote its throttle entry
		t.expect(fs.isFile(`{wt2}/.cache/tracker-beats/c0075`)).toBe(true)
		t.expect(string.sub(stampOf(`{P}/c0075/c0075.md`), 1, 10)).toBe("preparing-")
		t.expect(table.find(stampsWithBeats(), stampOf(`{P}/c0075/c0075.md`))).toBe(nil)
	end)

	it("a beat revives a lost claim", function()
		must(zn(h.f.main, { "beat", "c0010", "--adopt" }, LATE), "beat of a lost claim")
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

	it("a failed beat attempt is not retried inside the interval", function()
		local function calls(): number
			local text = if fs.isFile(`{h.fakes}/lscalls`) then fs.readFile(`{h.fakes}/lscalls`) else ""
			return #string.gsub(text, "[^x]", "")
		end
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local due = LATE + 4 * STALE
		local before = calls()
		must(zn(wt, { "lessons", "--tags" }, due), "lessons in the worktree") -- entries are due: one failed attempt each
		local first = calls()
		t.expect(first > before).toBe(true)
		must(zn(wt, { "lessons", "--tags" }, due + 10), "lessons again, inside the interval")
		t.expect(calls()).toBe(first) -- the failed attempt advanced the entries: nothing more is tried
		fs.removeFile(`{h.fakes}/lsfail`)
	end)

	it("a takeover is refused for a live claim, a parked one, and whenever the answer is unknown", function()
		must(zn(h.f.main, { "beat", "c0010", "--adopt" }, LATE + 6 * STALE), "keep c0010 alive")
		local live = zn(wt2, { "status", "c0010", "preparing" }, LATE + 6 * STALE + 10)
		t.expect(live.ok).toBe(false)
		t.expect(has(live.stderr, "is preparing on origin/main")).toBe(true)
		t.expect(has(live.stderr, "heartbeat")).toBe(true)
		local parked = zn(wt2, { "status", "c0020", "preparing" }, LATE + 9 * STALE)
		t.expect(parked.ok).toBe(false)
		t.expect(has(parked.stderr, "parked")).toBe(true)
		-- unknown: pull requests unreadable, beats unreadable, a malformed beat ref on origin
		local at = LATE + 9 * STALE
		fs.writeFile(`{h.fakes}/ghfail`, "1")
		t.expect(zn(wt2, { "status", "c0010", "preparing" }, at).ok).toBe(false)
		fs.removeFile(`{h.fakes}/ghfail`)
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local blind = zn(wt2, { "status", "c0010", "preparing" }, at)
		t.expect(blind.ok).toBe(false)
		t.expect(has(blind.stderr, "heartbeat")).toBe(true)
		fs.removeFile(`{h.fakes}/lsfail`)
		fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:refs/heads/hb/garbage" })
		local bad = zn(wt2, { "status", "c0010", "preparing" }, at)
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stderr, "refs/heads/hb/garbage")).toBe(true)
		-- a malformed ref makes every stale claim unknown, everywhere, and the message says how to clear it
		t.expect(has(bad.stderr, "git push origin :refs/heads/hb/garbage")).toBe(true)
		local still = zn(h.f.main, { "lost" }, at)
		t.expect(has(still.stdout, "c0010")).toBe(false)
		t.expect(has(still.stderr, "refs/heads/hb/garbage")).toBe(true)
		t.expect(has(lineOf(zn(h.f.main, { "status" }, at).stdout, "c0010"), "[stale?]")).toBe(true)
		fixture.git(h.f.other, { "push", "-q", "origin", ":refs/heads/hb/garbage" })
	end)

	it(
		"a lost claim is taken over with a fresh stamp, a first beat, and the old claim's beats pruned",
		function()
			local at = LATE + 9 * STALE
			local before = stampOf(`{P}/c0010/c0010.md`)
			must(zn(wt2, { "status", "c0010", "preparing" }, at), "takeover of a lost claim")
			local after = stampOf(`{P}/c0010/c0010.md`)
			t.expect(after ~= before).toBe(true)
			-- the takeover is recorded in the claim commit's subject: who it took the claim from
			t.expect(subjectOf(`{P}/c0010/c0010.md`)).toBe(`tracker: c0010 preparing (takes over {before})`)
			local stamps = stampsWithBeats()
			t.expect(table.find(stamps, after) ~= nil).toBe(true)
			-- the takeover deleted the old owner's branch and created its own in one push
			t.expect(table.find(stamps, before)).toBe(nil)
			t.expect(tipOf(before)).toBe("")
		end
	)

	it("a lost rafting claim is taken over the same way, its member following", function()
		local at = LATE + 9 * STALE
		local listing = must(zn(h.f.main, { "status" }, at), "status")
		local rid = string.match(listing, "(R%d+) preparing") or error("no rafting claim in the status list")
		raftId = rid
		local doc = `pickman/.tracker/rafts/{rid}/{rid}.md`
		local before = stampOf(doc)
		must(zn(wt2, { "status", rid, "preparing" }, at), "takeover of a rafting claim")
		local after = stampOf(doc)
		t.expect(after ~= before).toBe(true)
		t.expect(stampOf(`{P}/c0030/c0030.md`)).toBe(after)
		t.expect(subjectOf(doc)).toBe(`tracker: {rid} preparing (takes over {before})`)
		t.expect(table.find(stampsWithBeats(), after) ~= nil).toBe(true)
		-- the taker holds the stamp but not the rafting ownership: release needs --force, as after any status R preparing
		local rel = zn(wt2, { "release", rid }, at)
		t.expect(rel.ok).toBe(false)
		t.expect(has(rel.stderr, "not this checkout's")).toBe(true)
	end)

	it(
		"the taker's own carried move passes, because a takeover records the new stamp in its checkout",
		function()
			local doc = `{wt2}/{P}/c0010/c0010.md`
			must(zn(wt2, { "sync" }, LATE + 9 * STALE), "sync")
			fs.writeFile(doc, (string.gsub(fs.readFile(doc), "design: draft", "design: ready")))
			must(zn(wt2, { "status", "c0010", "prepared" }, LATE + 9 * STALE), "the taker's carried move")
		end
	)

	it("the old claimant's carried move is refused, and its worktree stops beating what it lost", function()
		local at = LATE + 9 * STALE
		local doc = `{wt}/{P}/c0010/c0010.md`
		-- the first command the old claimant runs tells it, once, and drops its entry (the stamp check comes first)
		local sync = zn(wt, { "sync" }, at)
		must(sync, "sync")
		t.expect(has(sync.stderr, "c0010's claim was taken over")).toBe(true)
		t.expect(has(sync.stderr, `{raftId}'s claim was taken over`)).toBe(true) -- the rafting claim too, by the same sync
		t.expect(fs.isFile(`{wt}/.cache/tracker-beats/c0010`)).toBe(false)
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "design: draft", "design: ready")))
		local r = zn(wt, { "status", "c0010", "prepared" }, at)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "taken over")).toBe(true)
		-- coming back by an explicit beat or a restarted loop does not adopt the taker's claim: wt remembers the old stamp
		local tipTaken = tipOf(stampOf(`{P}/c0010/c0010.md`))
		local comeBack = zn(wt, { "beat", "c0010" }, at)
		t.expect(comeBack.ok).toBe(false)
		t.expect(has(comeBack.stderr, "c0010's claim was taken over")).toBe(true)
		local loop = zn(
			wt,
			{ "beat", "c0010", "--watch" },
			at,
			{ ZN_BOUNDED_DEADLINE = tostring(os.time() + 600) }
		)
		t.expect(loop.ok).toBe(false)
		t.expect(has(loop.stderr, "c0010's claim was taken over")).toBe(true)
		t.expect(tipOf(stampOf(`{P}/c0010/c0010.md`))).toBe(tipTaken) -- the taker's branch was not touched
		-- the old rafting claimant (wt made it with `new raft`) is refused its carried move too. The stamp-record check
		-- runs before setStatus' member design check, so c0030 left at design: draft does not change the answer
		local rdoc = `{wt}/pickman/.tracker/rafts/{raftId}/{raftId}.md`
		fs.writeFile(rdoc, (string.gsub(fs.readFile(rdoc), "design: draft", "design: ready")))
		local oldRaft = zn(wt, { "status", raftId, "prepared" }, at)
		t.expect(oldRaft.ok).toBe(false)
		t.expect(has(oldRaft.stderr, "taken over")).toBe(true)
		-- an interval later its autobeat sees another stamp on origin: it drops the entry and writes no beat
		local taken = stampOf(`{P}/c0010/c0010.md`)
		local before = #beatRefs()
		local tipBefore = tipOf(taken)
		local told = zn(wt, { "lessons", "--tags" }, at + 2 * STALE)
		t.expect(told.ok).toBe(true)
		t.expect(has(told.stderr, "c0010's claim was taken over")).toBe(false) -- told once, by the first command
		t.expect(#beatRefs()).toBe(before) -- no branch came back for the old stamp, none was added
		t.expect(tipOf(taken)).toBe(tipBefore) -- and the taker's branch was not touched by the old owner
	end)

	it("an entry for a claim that merely ended is dropped with 'claim ended', not 'taken over'", function()
		local at = LATE + 12 * STALE
		local c0070Stamp = stampOf(`{P}/c0070/c0070.md`)
		t.expect(tipOf(c0070Stamp) ~= "").toBe(true)
		must(zn(wt2, { "status", "c0070", "new" }, at), "give c0070 back") -- wt2 claimed it earlier and holds an entry
		local told = zn(wt2, { "lessons", "--tags" }, at + 10)
		t.expect(told.ok).toBe(true)
		t.expect(has(told.stderr, "c0070's claim ended")).toBe(true)
		t.expect(has(told.stderr, "c0070's claim was taken over")).toBe(false)
		t.expect(fs.isFile(`{wt2}/.cache/tracker-beats/c0070`)).toBe(false)
		t.expect(tipOf(c0070Stamp)).toBe("") -- giving the claim back deleted its heartbeat branch
	end)

	it(
		"a lost readied raft is taken over by stop and ready: the old branch goes, a fresh active stamp and branch come, and the stop records the lost stamp",
		function()
			local at = LATE + 14 * STALE
			local doc = "pickman/.tracker/rafts/active/R0010/R0010.md"
			local old = stampOf(doc)
			t.expect(tipOf(old) ~= "").toBe(true)
			t.expect(has(zn(h.f.main, { "lost" }, at).stdout, "R0010 active")).toBe(true)
			must(zn(h.f.main, { "stop", "R0010" }, at), "stop")
			t.expect(tipOf(old)).toBe("") -- stop dropped the heartbeat branch
			t.expect(
				fixture.git(
					h.f.origin,
					{ "log", "-1", "--format=%s", "main", "--", "pickman/.tracker/rafts/R0010/R0010.md" }
				)
			).toBe(`tracker: stop R0010 (claim {old})`)
			must(zn(h.f.main, { "ready", "R0010" }, at + 10), "ready")
			local new = stampOf(doc)
			t.expect(new ~= old).toBe(true)
			t.expect(tipOf(new) ~= "").toBe(true) -- the new claim's first beat
			t.expect(tipOf(old)).toBe("")
		end
	)
end)
