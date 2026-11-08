--!strict
-- f0265: a claim whose newest sign (a beat, else the claim's landing) is older than the stale limit is lost: `lost` and
-- `status` say so and list it first, a beat revives it, a claim nobody beat turns lost on the same clock, an origin
-- that cannot be read marks nothing lost, and `status <id> preparing` refuses a live claim and takes over a lost one.
-- Time is ZN_NOW. Fixture under .cache/f0265-lost.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local heartbeat = require("@znile/engine/heartbeat")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt = "" -- a worktree of the fixture
local T0 = os.time()
local STALE = heartbeat.STALE
local DEAD = tostring(T0 + STALE + 120) -- a moment when a claim last signed at T0 is lost

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?): fixture.Result
	local env: { [string]: string } = {}
	if now then
		env.ZN_NOW = tostring(now)
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
-- the beat refs on origin, as { stamp, epoch } read from the remote's own ref names
local function beats(): { { stamp: string, epoch: number } }
	local out = {}
	for line in
		string.gmatch(
			fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/zn/hb/" }),
			"[^\n]+"
		)
	do
		local stamp, epoch = string.match(line, "^refs/zn/hb/([%a%-]+)/(%d+)$")
		table.insert(out, { stamp = stamp :: string, epoch = tonumber(epoch) :: number })
	end
	return out
end
local function stampOf(id: string, path: string): string
	local text = fixture.git(h.f.origin, { "show", `main:{path}` })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error(`{id} has no status on origin`)
end
local function issue(id: string, status: string, design: string?): string
	return (string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`))
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Beat\nslug: beat\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local P = "pickman/.tracker/issues"

return t.spec("f0265 lost work", function(it)
	it("sets up a tracker with new issues, a prepared raft and a claimed issue with fake CLIs", function()
		h = fakecli.new("f0265-lost", {
			[".gitignore"] = ".cache/\n.worktree/\nprompt.md\n",
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
			[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "ready"),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0040"),
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"),
		})
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "f0265-beat" }), "worktree"), "%s+$", ""))
	end)

	it("a claim beats at once, and a later beat replaces it", function()
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		must(zn(h.f.main, { "beat", "c0010" }, T0 + 600), "beat")
		t.expect(#beats()).toBe(1)
	end)

	it(
		"a claim with a fresh beat is not lost; the same claim after the stale limit is, in both views",
		function()
			t.expect(zn(h.f.main, { "lost" }, T0 + 600).stdout).toBe("")
			t.expect(has(zn(h.f.main, { "status" }, T0 + 600).stdout, "lost")).toBe(false)
			local late = T0 + 600 + STALE + 1
			local lost = must(zn(h.f.main, { "lost" }, late), "lost")
			t.expect(has(lost, "c0010")).toBe(true)
			t.expect(has(lost, "c0020")).toBe(false) -- unclaimed work is not lost
			local listing = must(zn(h.f.main, { "status" }, late), "status")
			local first = string.match(listing, "^[^\n]+") or ""
			t.expect(string.sub(first, 1, 5)).toBe("c0010") -- lost work is listed first
			t.expect(has(first, "[lost ")).toBe(true)
		end
	)

	it("beat revives a lost claim, and a stale limit that is not passed yet leaves it live", function()
		local late = T0 + 600 + STALE + 1
		must(zn(h.f.main, { "beat", "c0010" }, late), "beat of a lost claim")
		t.expect(zn(h.f.main, { "lost" }, late).stdout).toBe("")
		t.expect(zn(h.f.main, { "lost" }, late + STALE).stdout).toBe("") -- exactly the limit is live
		t.expect(has(zn(h.f.main, { "lost" }, late + STALE + 1).stdout, "c0010")).toBe(true)
	end)

	it("a claim nobody beat (a stamp with no ref) turns lost from the time it landed", function()
		-- c0050 is preparing on main since the seed commit, with no ref
		local lost = must(zn(h.f.main, { "lost" }, os.time() + STALE + 60), "lost")
		t.expect(has(lost, "c0050")).toBe(true)
		t.expect(has(zn(h.f.main, { "lost" }, os.time()).stdout, "c0050")).toBe(false)
	end)

	it("status refuses to claim an issue whose claim is live, and takes over one that is lost", function()
		local revived = T0 + 600 + STALE + 1 -- the previous case beat then
		local live = zn(wt, { "status", "c0010", "preparing" }, revived + 10)
		t.expect(live.ok).toBe(false)
		t.expect(has(live.stderr, "c0010")).toBe(true)
		t.expect(has(live.stderr, "heartbeat")).toBe(true)
		local before = stampOf("c0010", `{P}/c0010/c0010.md`)
		local late = revived + 3 * STALE
		must(zn(wt, { "status", "c0010", "preparing" }, late), "takeover of a lost claim")
		local after = stampOf("c0010", `{P}/c0010/c0010.md`)
		t.expect(after ~= before).toBe(true) -- a fresh claim stamp
		local stamps = {}
		for _, b in beats() do
			table.insert(stamps, b.stamp)
		end
		t.expect(table.find(stamps, after) ~= nil).toBe(true) -- the new claim beat at once
		t.expect(table.find(stamps, before)).toBe(nil) -- and the old claim's beats are pruned
	end)

	it("an origin that cannot be read marks nothing lost: lost says so and exits 1", function()
		fixture.git(h.f.other, { "remote", "set-url", "origin", `{h.f.base}/gone.git` })
		local r = zn(h.f.other, { "lost" }, tonumber(DEAD) + 10 * STALE)
		t.expect(r.ok).toBe(false)
		t.expect(r.stdout).toBe("")
		t.expect(has(r.stderr, "heartbeat")).toBe(true)
		fixture.git(h.f.other, { "remote", "set-url", "origin", h.f.origin })
	end)
end)
