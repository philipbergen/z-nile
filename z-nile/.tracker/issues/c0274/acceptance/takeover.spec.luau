--!strict
-- c0274: a claim whose verdict is lost (c0265) is taken over by the next claim of it: `status <id> preparing` on an
-- issue, `status <R-id> preparing` on a rafting claim (its members following), stop then ready on a readied raft. Only
-- an explicit lost verdict for the stamp origin still holds allows it; the takeover is recorded in the claim commit's
-- subject, deletes the old owner's heartbeat branch and creates the taker's in one atomic push, and the old owner's
-- later moves (the carried `prepared`, `done`, a beat of any form) are refused. Time is ZN_NOW. Fixture under
-- .cache/c0274-takeover.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wt2, wt3, wt4, wt5 = "", "", "", "", "" -- the old owner's worktree, the taker's, and three that run few commands (below)
local raftId = "" -- the rafting claim `new raft` made in wt
local T0 = os.time()
local STALE = heartbeat.STALE
local LATE = T0 + 3 * STALE -- when everything claimed at about T0 is stale, whatever the seconds the fixture took
local AT = LATE + 9 * STALE
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"
local RESTAMP = "preparing-sunny-heron-lynx"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		FAKE_OTHER = h.f.other,
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
local function subjectOf(path: string): string
	return fixture.git(h.f.origin, { "log", "-1", "--format=%s", "main", "--", path })
end
local function tipOf(stamp: string): string
	return fixture.git(h.f.origin, { "for-each-ref", "--format=%(objectname)", `refs/heads/hb/{stamp}` })
end
local function epochOf(stamp: string): number?
	local subject =
		fixture.git(h.f.origin, { "for-each-ref", "--format=%(subject)", `refs/heads/hb/{stamp}` })
	return tonumber(string.match(subject, "(%d+)$"))
end
-- another terminal's beat: a commit with main's tree and tip as parent, force-pushed as the stamp's branch
local function pushBeat(stamp: string, epoch: number)
	local tree = fixture.git(h.f.other, { "rev-parse", "HEAD^{tree}" })
	local sha = fixture.git(h.f.other, { "commit-tree", tree, "-p", "HEAD", "-m", `hb {stamp} {epoch}` })
	fixture.git(h.f.other, { "push", "-q", "-f", "origin", `{sha}:refs/heads/hb/{stamp}` })
end
local function memory(dir: string, id: string): string?
	local path = `{dir}/.cache/tracker-stamp-{id}`
	return if fs.isFile(path) then (string.gsub(fs.readFile(path), "%s+$", "")) else nil
end
local function issue(id: string, status: string, raft: string?, design: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
-- how many atomic swap pushes the shim has seen
local function swaps(): number
	local text = if fs.isFile(`{h.fakes}/swaps`) then fs.readFile(`{h.fakes}/swaps`) else ""
	return #string.gsub(text, "[^x]", "")
end
local function beatNames(): { string }
	local out = {}
	local refs = fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/heads/hb/" })
	for line in string.gmatch(refs, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end
local function ready(path: string)
	fs.writeFile(path, (string.gsub(fs.readFile(path), "design: draft", "design: ready")))
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local GH = [[#!/bin/sh
if [ "$1" = pr ] && [ "$2" = list ]; then
  [ -f "$FAKE_DIR/ghfail" ] && { echo "gh: fake failure" >&2; exit 1; }
  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"
  exit 0
fi
exit 0
]]
-- the git shim, each trap armed by a marker file it removes first (swapfail stays): the heartbeat read fails (lsfail);
-- another terminal restamps c0080 just before the taker's push to main (race); the old owner beats the claim's branch
-- just before the taker's atomic swap (swaprace); the swap is refused (swapfail)
local SHIM = [[#!/bin/sh
if [ "$1" = fetch ]; then
  case "$*" in
    *hb-seen*)
      [ -f "$FAKE_DIR/lsfail" ] && { echo "fatal: fake heartbeat read failure" >&2; exit 128; } ;;
  esac
fi
if [ "$1" = push ]; then
  case "$*" in
    *--atomic*)
      echo x >> "$FAKE_DIR/swaps"
      [ -f "$FAKE_DIR/swapfail" ] && { echo "fatal: fake swap refusal" >&2; exit 1; }
      if [ -f "$FAKE_DIR/swaprace" ]; then
        rm -f "$FAKE_DIR/swaprace"
        o="$FAKE_OTHER"; tree=$("$REAL_GIT" -C "$o" rev-parse "HEAD^{tree}")
        new=$("$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit-tree "$tree" -p HEAD -m "hb $FAKE_OLDSTAMP 7")
        "$REAL_GIT" -C "$o" push -q -f origin "$new:refs/heads/hb/$FAKE_OLDSTAMP"
      fi ;;
    *:refs/heads/main*)
      if [ -f "$FAKE_DIR/race" ]; then
        rm -f "$FAKE_DIR/race"
        o="$FAKE_OTHER"; f="$o/pickman/.tracker/issues/c0080/c0080.md"
        "$REAL_GIT" -C "$o" pull -q origin main
        sed -i.bak "s/^status: .*/status: preparing-sunny-heron-lynx/" "$f"; rm -f "$f.bak"
        "$REAL_GIT" -C "$o" add -A; "$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit -q -m restamp
        "$REAL_GIT" -C "$o" push -q origin HEAD:main
      fi ;;
  esac
fi
]]

return t.spec("c0274 take over a lost claim", function(it)
	it(
		"sets up lost, parked and never-beaten claims, a rafting claim, a readied raft and the shim",
		function()
			h = fakecli.new("c0274-takeover", {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = "# architecture\n",
				[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
				[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
				[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
				[`{P}/c0080/c0080.md`] = issue("c0080", "new-a-b-c"),
				[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "R0010", "ready"),
				[`{P}/c0040/check.sh`] = CHECK,
				["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Lost\nslug: lost\nsingle: false\nissues: [c0040]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0010\n`,
				["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
				[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"), -- claimed before beats existed
			})
			fs.writeFile(`{h.bin}/gh`, GH)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			local real = string.match(fs.readFile(`{h.bin}/git`), 'exec "([^"]+)" "%$@"')
				or error("no real git in the shim")
			fs.writeFile(
				`{h.bin}/git`,
				(
					string.gsub(
						fs.readFile(`{h.bin}/git`),
						"^#!/bin/sh\n",
						"#!/bin/sh\nREAL_GIT='" .. real .. "'; export REAL_GIT\n" .. string.sub(SHIM, 11),
						1
					)
				)
			)
			wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-take" }), "worktree"), "%s+$", ""))
			wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-take2" }), "worktree"), "%s+$", ""))
			wt3 = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-take3" }), "worktree"), "%s+$", ""))
			wt4 = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-take4" }), "worktree"), "%s+$", ""))
			wt5 = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-take5" }), "worktree"), "%s+$", ""))
			must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
			-- c0020 and c0080 are claimed in a worktree that runs nothing afterwards: a later layer keeps every claim a
			-- worktree holds alive at each of its commands, and these two must still be lost when the cases reach them
			must(zn(wt3, { "status", "c0020", "preparing" }, T0), "claim c0020")
			must(zn(wt3, { "status", "c0080", "preparing" }, T0), "claim c0080")
			must(
				zn(wt5, { "new", "raft", "chore", "lostraft", "c0030", "--project", "pickman" }, T0),
				"new raft"
			)
			must(zn(h.f.main, { "ready", "R0010" }, T0), "ready R0010") -- readied, nobody starts it
			local listing = must(zn(h.f.main, { "status" }, T0), "status")
			raftId = string.match(listing, "(R%d+) preparing") or error("no rafting claim in the status list")
			-- the old owners' branches: one beat each (the claim paths of a later layer make them too)
			pushBeat(stampOf(`{P}/c0010/c0010.md`), T0 + 600)
			pushBeat(stampOf(`pickman/.tracker/rafts/{raftId}/{raftId}.md`), T0 + 600)
			pushBeat(stampOf("pickman/.tracker/rafts/active/R0010/R0010.md"), T0 + 600)
		end
	)

	it(
		"a takeover is refused for a live, a parked, a never-beaten and an unknown claim, naming why",
		function()
			must(zn(h.f.main, { "beat", "c0010", "--adopt" }, LATE + 6 * STALE), "keep c0010 alive")
			local watched = { "c0010", "c0020", "c0050", "c0030" }
			local function snapshot(): string
				local out = {}
				for _, id in watched do
					table.insert(out, `{stampOf(`{P}/{id}/{id}.md`)} {subjectOf(`{P}/{id}/{id}.md`)}`)
				end
				table.insert(out, table.concat(beatNames(), ","))
				return table.concat(out, "\n")
			end
			local before = snapshot()
			local live = zn(wt2, { "status", "c0010", "preparing" }, LATE + 6 * STALE + 10)
			t.expect(live.ok).toBe(false)
			t.expect(has(live.stderr, "c0010 is preparing on origin/main: cannot move to preparing"))
				.toBe(true)
			t.expect(has(live.stderr, "claim alive: last heartbeat 0m ago, limit 15m")).toBe(true)
			-- a pull request names c0020; a dispatcher waiting on questions.md (the main checkout's run state) names c0010
			fs.writeFile(
				`{h.fakes}/prs.json`,
				'[{"title":"tracker: prep c0020 Something","headRefName":"prep-something"}]'
			)
			local parked = zn(wt2, { "status", "c0020", "preparing" }, AT)
			t.expect(parked.ok).toBe(false)
			t.expect(has(parked.stderr, "claim parked")).toBe(true)
			fs.writeDir(`{h.f.main}/.cache/dispatch/c0010`)
			fs.writeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`, "## Q1\nWhich scope?\n")
			local waiting = zn(wt2, { "status", "c0010", "preparing" }, AT)
			t.expect(waiting.ok).toBe(false)
			t.expect(has(waiting.stderr, "claim parked")).toBe(true)
			fs.removeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`)
			-- made before the heartbeat landed and never beaten: not lost, so not taken over until it has beaten once
			local nobeat = zn(wt2, { "status", "c0050", "preparing" }, AT)
			t.expect(nobeat.ok).toBe(false)
			t.expect(has(nobeat.stderr, "c0050 has never beaten: not lost, no takeover")).toBe(true)
			-- unknown: pull requests unreadable, beats unreadable, a malformed beat ref on origin
			fs.writeFile(`{h.fakes}/ghfail`, "1")
			local blindPrs = zn(wt2, { "status", "c0010", "preparing" }, AT)
			fs.removeFile(`{h.fakes}/ghfail`)
			t.expect(blindPrs.ok).toBe(false)
			t.expect(has(blindPrs.stderr, "no heartbeat verdict: pull requests unreadable")).toBe(true)
			fs.writeFile(`{h.fakes}/lsfail`, "1")
			local blind = zn(wt2, { "status", "c0010", "preparing" }, AT)
			fs.removeFile(`{h.fakes}/lsfail`)
			t.expect(blind.ok).toBe(false)
			t.expect(has(blind.stderr, "no heartbeat verdict: heartbeats unreadable")).toBe(true)
			fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:refs/heads/hb/garbage" })
			local bad = zn(wt2, { "status", "c0010", "preparing" }, AT)
			fixture.git(h.f.other, { "push", "-q", "origin", ":refs/heads/hb/garbage" })
			t.expect(bad.ok).toBe(false)
			t.expect(has(bad.stderr, "no heartbeat verdict")).toBe(true)
			t.expect(has(bad.stderr, "git push origin :refs/heads/hb/garbage")).toBe(true)
			-- and nothing moved
			-- a member of the lost rafting claim is taken over through its raft, never alone
			local member = zn(wt2, { "status", "c0030", "preparing" }, AT)
			t.expect(member.ok).toBe(false)
			t.expect(
				has(
					member.stderr,
					`c0030 holds {raftId}'s claim: take it over with ./zn status {raftId} preparing`
				)
			).toBe(true)
			-- and nothing moved: the stamps, their commits and the set of heartbeat branches are as they were
			t.expect(snapshot()).toBe(before)
		end
	)

	it(
		"a lost claim is taken over with a fresh stamp, recorded in the claim commit, its branch swapped",
		function()
			local before = stampOf(`{P}/c0010/c0010.md`)
			t.expect(tipOf(before) ~= "").toBe(true)
			must(zn(wt2, { "status", "c0010", "preparing" }, AT), "takeover of a lost claim")
			local after = stampOf(`{P}/c0010/c0010.md`)
			t.expect(after ~= before).toBe(true)
			-- recorded where git log sees it: who the claim was taken from
			t.expect(subjectOf(`{P}/c0010/c0010.md`)).toBe(`tracker: c0010 preparing (takes over {before})`)
			-- the old owner's branch is deleted and the taker's created, which is the taker's first beat
			t.expect(tipOf(before)).toBe("")
			t.expect(tipOf(after) ~= "").toBe(true)
			t.expect(epochOf(after)).toBe(AT)
			-- the taker remembers its claim; the old owner's worktree still remembers the old one
			t.expect(memory(wt2, "c0010")).toBe(after)
			t.expect(memory(wt, "c0010")).toBe(before)
			-- a plain claim keeps the plain subject
			t.expect(subjectOf(`{P}/c0080/c0080.md`)).toBe("tracker: c0080 preparing")
		end
	)

	it("a lost rafting claim is taken over the same way, its member following", function()
		local doc = `pickman/.tracker/rafts/{raftId}/{raftId}.md`
		local before = stampOf(doc)
		t.expect(stampOf(`{P}/c0030/c0030.md`)).toBe(before)
		must(zn(wt2, { "status", raftId, "preparing" }, AT), "takeover of a rafting claim")
		local after = stampOf(doc)
		t.expect(after ~= before).toBe(true)
		t.expect(stampOf(`{P}/c0030/c0030.md`)).toBe(after)
		t.expect(subjectOf(doc)).toBe(`tracker: {raftId} preparing (takes over {before})`)
		t.expect(tipOf(before)).toBe("")
		t.expect(tipOf(after) ~= "").toBe(true)
		-- the taker becomes the rafting owner (it can fold, unfold and release); the old owner's release is refused
		t.expect(memory(wt2, raftId)).toBe(after)
		t.expect(fs.readFile(`{wt2}/.cache/tracker-claim-{raftId}`)).toBe(after)
		local rel = zn(wt5, { "release", raftId }, AT)
		t.expect(rel.ok).toBe(false)
		t.expect(has(rel.stderr, "not this checkout's") or has(rel.stderr, "claim was taken over")).toBe(true) -- a later layer may refuse first
	end)

	it(
		"the taker's own carried move passes, because a takeover records the new stamp in its checkout",
		function()
			must(zn(wt2, { "sync" }, AT), "sync")
			ready(`{wt2}/{P}/c0010/c0010.md`)
			must(zn(wt2, { "status", "c0010", "prepared" }, AT), "the taker's carried move")
		end
	)

	it(
		"the old claimant's carried move is refused, and its beats of every form are told it lost the claim",
		function()
			local taken = stampOf(`{P}/c0010/c0010.md`)
			local old = memory(wt, "c0010") :: string
			ready(`{wt}/{P}/c0010/c0010.md`) -- the design check would pass: the stamp check is what refuses
			local r = zn(wt, { "status", "c0010", "prepared" }, AT)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "c0010's claim was taken over")).toBe(true) -- a later layer may word the rest
			-- an explicit beat, an adoption over a remembered different stamp and a restarted loop do not adopt the taker's claim
			local tipTaken = tipOf(taken)
			for _, args in { { "beat", "c0010" }, { "beat", "c0010", "--adopt" } } do
				local late = zn(wt, args, AT)
				t.expect(late.ok).toBe(false)
				t.expect(has(late.stderr, `c0010's claim was taken over (now {taken})`)).toBe(true)
			end
			local loop = zn(
				wt,
				{ "beat", "c0010", "--watch" },
				AT,
				{ ZN_BOUNDED_DEADLINE = tostring(os.time() + 600) }
			)
			t.expect(loop.ok).toBe(false)
			t.expect(has(loop.stderr, `c0010's claim was taken over (now {taken})`)).toBe(true)
			t.expect(tipOf(taken)).toBe(tipTaken) -- the taker's branch was not touched
			t.expect(tipOf(old)).toBe("") -- and none came back for the old stamp
			t.expect(memory(wt, "c0010")).toBe(old) -- the refusals never drop the memory
			-- the old rafting claimant (wt made it with `new raft`) is refused its carried move too. The stamp check runs
			-- before the member design check, so c0030 left at design: draft does not change the answer
			local rdoc = `{wt5}/pickman/.tracker/rafts/{raftId}/{raftId}.md`
			ready(rdoc)
			local oldRaft = zn(wt5, { "status", raftId, "prepared" }, AT)
			t.expect(oldRaft.ok).toBe(false)
			t.expect(has(oldRaft.stderr, `{raftId}'s claim was taken over`)).toBe(true)
			-- the old owner's late give-back is refused too (it would end the taker's live claim): an issue's and a raft's
			local rafted = stampOf(`pickman/.tracker/rafts/{raftId}/{raftId}.md`)
			local giveRaft = zn(wt5, { "status", raftId, "new" }, AT)
			t.expect(giveRaft.ok).toBe(false)
			t.expect(has(giveRaft.stderr, `{raftId}'s claim was taken over`)).toBe(true)
			t.expect(stampOf(`pickman/.tracker/rafts/{raftId}/{raftId}.md`)).toBe(rafted)
			local give = zn(wt, { "status", "c0010", "new" }, AT)
			t.expect(give.ok).toBe(false)
			t.expect(has(give.stderr, `c0010's claim was taken over`)).toBe(true)
			t.expect(stampOf(`{P}/c0010/c0010.md`)).toBe(taken)
		end
	)

	it("a takeover that meets a claim restamped between its verdict and its publish is refused", function()
		local old = stampOf(`{P}/c0080/c0080.md`)
		local branchesBefore = table.concat(beatNames(), ",")
		fs.writeFile(`{h.fakes}/race`, "1")
		local r = zn(wt2, { "status", "c0080", "preparing" }, AT)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, RESTAMP)).toBe(true) -- names the stamp it met
		t.expect(stampOf(`{P}/c0080/c0080.md`)).toBe(RESTAMP) -- the other terminal's claim stands
		t.expect(old ~= RESTAMP).toBe(true)
		-- and the loser created and deleted no branch: the set of heartbeat branches is as it was
		t.expect(table.concat(beatNames(), ",")).toBe(branchesBefore)
	end)

	it(
		"an old owner that beats while the swap is made fails the swap's lease: it is re-read and repeated once",
		function()
			-- c0020 is parked by a pull request: lift it, and its claim is lost
			fs.writeFile(`{h.fakes}/prs.json`, "[]")
			pushBeat(stampOf(`{P}/c0020/c0020.md`), T0 + 700)
			local old = stampOf(`{P}/c0020/c0020.md`)
			fs.writeFile(`{h.fakes}/swaprace`, "1")
			local pushes = swaps()
			local r = zn(wt2, { "status", "c0020", "preparing" }, AT, { FAKE_OLDSTAMP = old })
			must(r, "takeover whose swap meets a beat")
			t.expect(swaps() - pushes).toBe(2) -- the first push was rejected by the old branch's lease, the second landed
			local new = stampOf(`{P}/c0020/c0020.md`)
			t.expect(new ~= old).toBe(true)
			t.expect(tipOf(old)).toBe("") -- the old branch (the racing beat's sha) is gone
			t.expect(tipOf(new) ~= "").toBe(true)
			t.expect(has(r.stderr, "swap failed")).toBe(false)
		end
	)

	it("a refused swap is said, and the takeover stands", function()
		pushBeat(stampOf(`{P}/c0080/c0080.md`), T0 + 700)
		fs.writeFile(`{h.fakes}/swapfail`, "1")
		local old = stampOf(`{P}/c0080/c0080.md`)
		local r = zn(wt2, { "status", "c0080", "preparing" }, AT)
		fs.removeFile(`{h.fakes}/swapfail`)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "c0080: the heartbeat branch swap failed")).toBe(true)
		t.expect(stampOf(`{P}/c0080/c0080.md`) ~= old).toBe(true)
		t.expect(subjectOf(`{P}/c0080/c0080.md`)).toBe(`tracker: c0080 preparing (takes over {old})`)
	end)

	it(
		"a lost readied raft is taken over by stop then ready; the stop records the lost stamp and the old lead's done is refused",
		function()
			local doc = "pickman/.tracker/rafts/active/R0010/R0010.md"
			local old = stampOf(doc)
			-- the old lead (wt4, a worktree that has taken nothing over and runs only these commands) adopts the raft, as
			-- z-run does after ready
			must(zn(wt4, { "sync" }, T0), "sync")
			must(zn(wt4, { "beat", "R0010", "--adopt" }, T0 + 100), "adopt the readied raft")
			t.expect(memory(wt4, "R0010")).toBe(old)
			fs.writeFile(`{h.fakes}/prs.json`, "[]") -- no pull request names R0010
			t.expect(has(zn(h.f.main, { "lost" }, AT).stdout, "R0010 active")).toBe(true)
			must(zn(h.f.main, { "stop", "R0010" }, AT), "stop")
			-- stopped and not yet readied: the old lead's done is refused as an ended claim
			local ended = zn(wt4, { "done", "R0010" }, AT)
			t.expect(ended.ok).toBe(false)
			t.expect(
				has(ended.stderr, "R0010's claim ended") or has(ended.stderr, "R0010's claim was taken over")
			)
				.toBe(true) -- a later layer may word it
			local subject = fixture.git(
				h.f.origin,
				{ "log", "-1", "--format=%s", "main", "--", "pickman/.tracker/rafts/R0010/R0010.md" }
			)
			t.expect(string.sub(subject, 1, #"tracker: stop R0010")).toBe("tracker: stop R0010")
			t.expect(string.sub(subject, -#`(claim {old})`)).toBe(`(claim {old})`)
			must(zn(h.f.main, { "ready", "R0010" }, AT + 10), "ready")
			local new = stampOf(doc)
			t.expect(new ~= old).toBe(true)
			-- the old lead comes back and tries to finish the raft: refused by the stamp, before anything runs
			local r = zn(wt4, { "done", "R0010" }, AT)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "R0010's claim was taken over")).toBe(true)
			t.expect(memory(wt4, "R0010")).toBe(old)
			-- the owner's own re-adoption (z-stop step 4's keep path) names the exact stamp it remembers: a plain --adopt and a
			-- wrong stamp are refused, the right one is taken, and then done no longer says the claim was taken over
			t.expect(zn(wt4, { "beat", "R0010", "--adopt" }, AT).ok).toBe(false)
			t.expect(zn(wt4, { "beat", "R0010", "--adopt", "--replace", "active-wrong-wrong-wrong" }, AT).ok)
				.toBe(false)
			t.expect(memory(wt4, "R0010")).toBe(old)
			must(zn(wt4, { "beat", "R0010", "--adopt", "--replace", old }, AT), "the owner re-adopts")
			t.expect(memory(wt4, "R0010")).toBe(new)
			t.expect(has(zn(wt4, { "done", "R0010" }, AT).stderr, "claim was taken over")).toBe(false)
			-- a worktree that remembers the rafting claim (preparing) adopts the readied raft: it moved on, nothing was taken
			fs.writeFile(`{wt3}/.cache/tracker-stamp-R0010`, "preparing-quiet-copper-falcon")
			must(zn(wt3, { "beat", "R0010", "--adopt" }, AT), "adopt after the rafting claim became work")
			t.expect(memory(wt3, "R0010")).toBe(new)
		end
	)
end)
