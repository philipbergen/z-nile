--!strict
-- f0265: a claim whose newest beat is older than the stale limit is stale; the open pull requests then decide: one that
-- names the item parks it, none makes it lost. `lost` and `status` say so and list lost work first. A claim nobody ever
-- beat is "no beat", never lost. Whatever cannot be read (the beats, the pull requests, a malformed beat ref) makes
-- nothing lost and refuses a takeover. A lost preparing claim is taken over by `status <id> preparing`; the old
-- claimant's carried move is then refused. Time is ZN_NOW, honoured only inside a check. Fixture under .cache/f0265-lost.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wt2 = "", "" -- two worktrees of the fixture: two terminals
local T0 = os.time()
local STALE = heartbeat.STALE
local LATE = T0 + STALE + 1 -- the first moment a claim that last beat at T0 is stale

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
local function beatStamps(): { string }
	local out = {}
	local refs = fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/zn/hb/" })
	for line in string.gmatch(refs, "[^\n]+") do
		table.insert(out, (string.match(line, "^refs/zn/hb/([%a%-]+)/%d+$")) or line)
	end
	return out
end
local function issue(id: string, status: string): string
	return trackerfix.stub(id, id, status)
end
local function lineOf(text: string, id: string): string
	return string.match(text, `(%f[%w]{id}%f[%W][^\n]*)`) or ""
end
local P = "pickman/.tracker/issues"
local GH = [[#!/bin/sh
if [ "$1" = pr ] && [ "$2" = list ]; then
  [ -f "$FAKE_DIR/ghfail" ] && { echo "gh: fake failure" >&2; exit 1; }
  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"
  exit 0
fi
exit 0
]]

return t.spec("f0265 lost work", function(it)
	it("sets up claimable issues, one claimed and never beaten, a done one, and the fakes", function()
		h = fakecli.new("f0265-lost", {
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"), -- claimed before beats existed
			[`{P}/done/c0060/c0060.md`] = issue("c0060", "active-brisk-amber-otter"), -- keeps its claim stamp
		})
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		local shim = fs.readFile(`{h.bin}/git`)
		fs.writeFile(
			`{h.bin}/git`,
			(
				string.gsub(
					shim,
					"^#!/bin/sh\n",
					'#!/bin/sh\nif [ "$1" = ls-remote ] && [ -f "$FAKE_DIR/lsfail" ]; then echo "fatal: fake ls-remote failure" >&2; exit 128; fi\n',
					1
				)
			)
		)
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "f0265-lost" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "f0265-lost2" }), "worktree"), "%s+$", ""))
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		must(zn(wt, { "status", "c0020", "preparing" }, T0), "claim c0020")
		-- the done item's old claim has a beat on origin, as one that finished mid-work would
		fixture.git(
			h.f.other,
			{ "push", "-q", "origin", `HEAD:refs/zn/hb/active-brisk-amber-otter/{T0 - 99999}` }
		)
	end)

	it("nothing is lost while the beats are fresh; the stale limit is inclusive", function()
		t.expect(zn(h.f.main, { "lost" }, T0 + 60).stdout).toBe("")
		t.expect(zn(h.f.main, { "lost" }, T0 + STALE).stdout).toBe("")
		t.expect(has(zn(h.f.main, { "status" }, T0 + STALE).stdout, "lost")).toBe(false)
	end)

	it(
		"a stale claim with no pull request is lost and listed first; a parked one and a beatless one are not lost",
		function()
			fs.writeFile(
				`{h.fakes}/prs.json`,
				'[{"title":"tracker: prep c0020 Something","headRefName":"prep-something"}]'
			)
			local lost = must(zn(h.f.main, { "lost" }, LATE), "lost")
			t.expect(string.match(lost, "^c0010 preparing %d+m\n$") ~= nil).toBe(true) -- one line: id, state, minutes
			local listing = must(zn(h.f.main, { "status" }, LATE), "status")
			local first = string.match(listing, "^[^\n]+") or ""
			t.expect(string.sub(first, 1, 5)).toBe("c0010") -- lost work is listed first
			t.expect(has(first, "[lost ")).toBe(true)
			t.expect(has(lineOf(listing, "c0020"), "[parked]")).toBe(true)
			t.expect(has(lineOf(listing, "c0050"), "[no beat]")).toBe(true) -- never beaten: not lost, but not hidden
			t.expect(has(lineOf(listing, "c0050"), "lost")).toBe(false)
			t.expect(has(listing, "c0060")).toBe(false) -- a done item keeps its stamp and is never a claim
			-- a dispatcher waiting on the user's answer (questions.md in its run state) parks the claim too
			fs.writeDir(`{h.f.main}/.cache/dispatch/c0010`)
			fs.writeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`, "## Q1\nWhich scope?\n")
			t.expect(has(lineOf(zn(h.f.main, { "status" }, LATE).stdout, "c0010"), "[parked]")).toBe(true)
			t.expect(zn(h.f.main, { "lost" }, LATE).stdout).toBe("")
			fs.removeFile(`{h.f.main}/.cache/dispatch/c0010/questions.md`)
		end
	)

	it("a beat revives a lost claim", function()
		must(zn(h.f.main, { "beat", "c0010" }, LATE), "beat of a lost claim")
		t.expect(zn(h.f.main, { "lost" }, LATE + STALE).stdout).toBe("")
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
		fs.removeFile(`{h.fakes}/lsfail`)
	end)

	it("a takeover is refused for a live claim, a parked one, and whenever the answer is unknown", function()
		local live = zn(wt2, { "status", "c0010", "preparing" }, LATE + 10)
		t.expect(live.ok).toBe(false)
		t.expect(has(live.stderr, "is preparing on origin/main")).toBe(true)
		t.expect(has(live.stderr, "heartbeat")).toBe(true)
		local parked = zn(wt2, { "status", "c0020", "preparing" }, LATE + 5 * STALE)
		t.expect(parked.ok).toBe(false)
		t.expect(has(parked.stderr, "parked")).toBe(true)
		-- unknown: pull requests unreadable, beats unreadable, a malformed beat ref on origin
		fs.writeFile(`{h.fakes}/ghfail`, "1")
		t.expect(zn(wt2, { "status", "c0010", "preparing" }, LATE + 5 * STALE).ok).toBe(false)
		fs.removeFile(`{h.fakes}/ghfail`)
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local blind = zn(wt2, { "status", "c0010", "preparing" }, LATE + 5 * STALE)
		t.expect(blind.ok).toBe(false)
		t.expect(has(blind.stderr, "heartbeat")).toBe(true)
		fs.removeFile(`{h.fakes}/lsfail`)
		fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:refs/zn/hb/garbage" })
		local bad = zn(wt2, { "status", "c0010", "preparing" }, LATE + 5 * STALE)
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stderr, "refs/zn/hb/garbage")).toBe(true)
		local still = zn(h.f.main, { "lost" }, LATE + 5 * STALE) -- the lost claim is still listed, the ref named
		t.expect(has(still.stdout, "c0010")).toBe(true)
		t.expect(has(still.stderr, "refs/zn/hb/garbage")).toBe(true)
		fixture.git(h.f.other, { "push", "-q", "origin", ":refs/zn/hb/garbage" })
	end)

	it(
		"a lost claim is taken over with a fresh stamp, a first beat, and the old claim's beats pruned",
		function()
			local before = stampOf(`{P}/c0010/c0010.md`)
			must(zn(wt2, { "status", "c0010", "preparing" }, LATE + 5 * STALE), "takeover of a lost claim")
			local after = stampOf(`{P}/c0010/c0010.md`)
			t.expect(after ~= before).toBe(true)
			local stamps = beatStamps()
			t.expect(table.find(stamps, after) ~= nil).toBe(true)
			t.expect(table.find(stamps, before)).toBe(nil)
		end
	)

	it("the old claimant's carried move to prepared is refused once its claim was taken over", function()
		local doc = `{wt}/{P}/c0010/c0010.md`
		must(zn(wt, { "sync" }, nil), "sync")
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "design: draft", "design: ready")))
		local r = zn(wt, { "status", "c0010", "prepared" }, LATE + 5 * STALE)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "taken over")).toBe(true)
	end)

	it("ZN_NOW is ignored outside a spec run", function()
		local r = zn(h.f.main, { "lost" }, LATE + 50 * STALE, { PICKMAN_FENCE_SPECS = "" })
		t.expect(r.stdout).toBe("")
	end)
end)
