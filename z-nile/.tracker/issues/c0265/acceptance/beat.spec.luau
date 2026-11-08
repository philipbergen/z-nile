--!strict
-- c0265: a beat is a ref (refs/zn/hb/<claim stamp>/<epoch>) pushed to origin outside main: a claim writes the first
-- one, `beat` writes the next from any checkout and deletes the older (never a young beat of a claim this checkout has
-- not fetched), `ready` and `new raft` beat for the raft they claim, any ./zn command in a worktree that holds a claim
-- beats it once an interval has passed, `--watch` runs only under ./zn run and ends before its bound, and `beat`
-- refuses what nobody claims, done items included. Time is ZN_NOW (epoch seconds), so no case waits. Fixture under .cache/c0265-beat.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

-- the checkout's top: specs run in their home (c0120)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local h: fakecli.Harness
local wt = "" -- a worktree of the fixture
local T0 = os.time()

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = { FAKE_DIR = h.fakes, PATH = `{h.bin}:{process.env.PATH}` }
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
local function issue(id: string, status: string, design: string?, raft: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Beat\nslug: beat\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local P = "pickman/.tracker/issues"

return t.spec("c0265 a beat is a ref outside main", function(it)
	it("sets up a tracker with new issues, a prepared raft and a claimed issue with fake CLIs", function()
		h = fakecli.new("c0265-beat", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
			[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "ready", "R0010"),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0040"),
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"),
			-- a finished raft's issue keeps the claim stamp it was worked under (about 30 do on the real tracker)
			[`{P}/done/c0060/c0060.md`] = issue("c0060", "active-brisk-amber-otter"),
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-beat" }), "worktree"), "%s+$", ""))
	end)

	it("a claim writes the first beat as a ref, and main only gets the claim", function()
		local main = fixture.git(h.f.origin, { "rev-parse", "main" })
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		local stamp = stampOf("c0010", `{P}/c0010/c0010.md`)
		local list = beats()
		t.expect(#list).toBe(1)
		t.expect(list[1].stamp).toBe(stamp)
		t.expect(list[1].epoch).toBe(T0)
		-- the claim is one commit on main and the beat is not: nothing else moved, no branch was made for it
		t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{main}..main` })).toBe("1")
		t.expect(fixture.git(h.f.origin, { "for-each-ref", "--format=%(refname)", "refs/heads/" }))
			.toBe("refs/heads/main")
	end)

	it("beat pushes a ref from the main checkout too, replaces the older one, and touches no file", function()
		local main = fixture.git(h.f.origin, { "rev-parse", "main" })
		must(zn(h.f.main, { "beat", "c0010" }, T0 + 300), "beat in the main checkout")
		must(zn(h.f.main, { "beat", "c0010" }, T0 + 600), "beat again")
		local list = beats()
		t.expect(#list).toBe(1) -- the older beats of the stamp are deleted
		t.expect(list[1].epoch).toBe(T0 + 600)
		t.expect(fixture.git(h.f.origin, { "rev-parse", "main" })).toBe(main)
		t.expect(fixture.git(h.f.main, { "status", "--porcelain" })).toBe("")
	end)

	it("beat refuses what nobody claims, naming the item and the rule", function()
		for _, id in { "c0020", "c0040", "c0060", "c9999" } do
			local r = zn(h.f.main, { "beat", id }, T0)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, id)).toBe(true)
		end
		t.expect(has(zn(h.f.main, { "beat", "c0020" }, T0).stderr, "no claim")).toBe(true)
		t.expect(has(zn(h.f.main, { "beat", "c0060" }, T0).stderr, "done")).toBe(true) -- its stored status is active-…
		t.expect(#beats()).toBe(1)
	end)

	it("ready beats for the raft it claims", function()
		must(zn(h.f.main, { "ready", "R0010" }, T0), "ready R0010")
		local stamp = stampOf("R0010", "pickman/.tracker/rafts/active/R0010/R0010.md")
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == stamp and b.epoch == T0)
		end
		t.expect(found).toBe(true)
		t.expect(string.sub(stamp, 1, 7)).toBe("active-")
	end)

	it("any ./zn command in a worktree that holds a claim beats it once an interval has passed", function()
		local stamp = stampOf("c0010", `{P}/c0010/c0010.md`)
		local function mine(): { number }
			local out = {}
			for _, b in beats() do
				if b.stamp == stamp then
					table.insert(out, b.epoch)
				end
			end
			return out
		end
		must(zn(wt, { "status", "c0010" }, T0 + 1000), "status in the worktree") -- its last beat from here: T0
		t.expect(mine()).toEqual({ T0 + 1000 })
		must(zn(wt, { "status", "c0010" }, T0 + 1100), "status again, inside the interval")
		t.expect(mine()).toEqual({ T0 + 1000 }) -- no second push inside the interval
		-- the main checkout holds no work: a command there beats nothing, however old the last beat
		must(zn(h.f.main, { "status", "c0010" }, T0 + 5000), "status in the main checkout")
		t.expect(mine()).toEqual({ T0 + 1000 })
	end)

	it("a beat keeps another terminal's fresh beat of a claim it has not fetched", function()
		-- another terminal claims c0030 and beats; this checkout has not fetched since
		trackerfix.elsewhere(h.f, {
			[`{P}/c0030/c0030.md`] = issue("c0030", "preparing-sunny-heron-lynx"),
		}, "other claims c0030")
		fixture.git(
			h.f.other,
			{ "push", "-q", "origin", `HEAD:refs/zn/hb/preparing-sunny-heron-lynx/{T0 + 1150}` }
		)
		must(zn(h.f.main, { "beat", "c0010" }, T0 + 1200), "beat in a checkout that has not fetched")
		local found = false
		for _, b in beats() do
			found = found or b.stamp == "preparing-sunny-heron-lynx"
		end
		t.expect(found).toBe(true)
	end)

	it("new raft beats for the raft it claims", function()
		must(
			zn(wt, { "new", "raft", "chore", "beatraft", "c0020", "--project", "pickman" }, T0 + 1300),
			"new raft"
		)
		local listing = zn(h.f.main, { "status" }, T0 + 1300).stdout
		local rid = string.match(listing, "(R%d+) preparing") or error("no new raft in the status list")
		local stamp = stampOf(rid, `pickman/.tracker/rafts/{rid}/{rid}.md`)
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == stamp and b.epoch == T0 + 1300)
		end
		t.expect(found).toBe(true)
	end)

	it("a nested ./zn in a protected checkout never beats", function()
		local entry = `{wt}/.cache/tracker-beats/c0010`
		local before = #beats()
		local entryBefore = fs.readFile(entry)
		-- the fence's own spelling: the canonical git common directory, appended to what the runner already lists
		local common = string.gsub(
			fixture.git(h.f.main, { "rev-parse", "--path-format=absolute", "--git-common-dir" }),
			"%s+$",
			""
		)
		local inherited = process.env.PICKMAN_FENCE_REAL_GIT or ""
		local listed = if inherited ~= "" then `{inherited}:{common}` else common
		must(
			zn(wt, { "lessons", "--tags" }, T0 + 9000, { PICKMAN_FENCE_REAL_GIT = listed }),
			"a nested command"
		)
		t.expect(#beats()).toBe(before)
		t.expect(fs.readFile(entry)).toBe(entryBefore) -- not even a failed attempt: the entry is untouched
		-- the explicit command refuses there too, naming the rule (the fence's pre-push hook is only the second line)
		local explicit = zn(wt, { "beat", "c0010" }, T0 + 9000, { PICKMAN_FENCE_REAL_GIT = listed })
		t.expect(explicit.ok).toBe(false)
		t.expect(has(explicit.stderr, "protected")).toBe(true)
		t.expect(#beats()).toBe(before)
	end)

	it("--watch refuses to run without a numeric bound (outside ./zn run)", function()
		local refused = zn(wt, { "beat", "c0010", "--watch" }, nil, { ZN_BOUNDED_DEADLINE = "" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "./zn run")).toBe(true)
	end)
end)
