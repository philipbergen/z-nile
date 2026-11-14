--!strict
-- c0274: a checkout beats only the claim it made. Every claim publish remembers the stamp in the claiming worktree
-- (the tracker-stamp-<id> file under the checkout's cache folder, the file the automatic beats and the discard read), a bare beat from a checkout that holds
-- no claim is refused, `--adopt` is the stated way to take one on (never over a remembered different stamp, and the main
-- checkout and the dispatcher's `--stamp` form write no memory), and the memory ends only with a claim-ending command
-- run in that checkout. Time is ZN_NOW. Fixture under .cache/c0274-memory.
local CACHE = "." .. "cache" -- spelled apart: c0049/spec-isolation reads a literal mention of a cache folder as a fixture shared by the files that name it
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local h: fakecli.Harness
local wt, wt2, wt3 = "", "", "" -- three worktrees of the fixture: three terminals (wt3 only ever holds a stale memory)
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
local function stampOf(path: string): string
	local text = fixture.git(h.f.origin, { "show", `main:{path}` })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error(`{path} has no status on origin`)
end
-- the heartbeat branches on origin: stamp, epoch and tip of each
local function beats(): { { stamp: string, epoch: number, sha: string } }
	local out = {}
	local lines = fixture.git(
		h.f.origin,
		{ "for-each-ref", "--format=%(refname) %(objectname) %(subject)", "refs/heads/hb/" }
	)
	for line in string.gmatch(lines, "[^\n]+") do
		local stamp, sha, epoch = string.match(line, "^refs/heads/hb/(%S+) (%x+) hb %S+ (%d+)$")
		table.insert(out, { stamp = stamp or line, epoch = tonumber(epoch) or 0, sha = sha or "" })
	end
	return out
end
local function memory(dir: string, id: string): string?
	local path = `{dir}/{CACHE}/tracker-stamp-{id}`
	return if fs.isFile(path) then (string.gsub(fs.readFile(path), "%s+$", "")) else nil
end
local function issue(id: string, status: string, design: string?, raft: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local P = "pickman/.tracker/issues"

return t.spec("c0274 a checkout beats only the claim it made", function(it)
	it("sets up claimable issues, a done item that kept a stamp and two worktrees", function()
		h = fakecli.new("c0274-memory", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
			[`{P}/c0095/c0095.md`] = issue("c0095", "new-a-b-c"),
			[`{P}/c0090/c0090.md`] = issue("c0090", "new-a-b-c"),
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
			[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "ready", "R0010"),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Mem\nslug: mem\nsingle: false\nissues: [c0040]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			[`{P}/done/c0060/c0060.md`] = issue("c0060", "active-brisk-amber-otter"),
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-mem" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-mem2" }), "worktree"), "%s+$", ""))
		wt3 = (string.gsub(must(zn(h.f.main, { "worktree", "c0274-mem3" }), "worktree"), "%s+$", ""))
	end)

	it(
		"every claim publish remembers its stamp in the worktree that made it, and the main checkout none",
		function()
			must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
			t.expect(memory(wt, "c0010")).toBe(stampOf(`{P}/c0010/c0010.md`))
			must(
				zn(wt, { "new", "raft", "chore", "memraft", "c0030", "--project", "pickman" }, T0),
				"new raft"
			)
			local listing = must(zn(h.f.main, { "status" }, T0), "status")
			local rid = string.match(listing, "(R%d+) preparing")
				or error("no rafting claim in the status list")
			t.expect(memory(wt, rid)).toBe(stampOf(`pickman/.tracker/rafts/{rid}/{rid}.md`))
			-- the other terminal and the main checkout made no claim
			t.expect(memory(wt2, "c0010")).toBe(nil)
			t.expect(memory(h.f.main, "c0010")).toBe(nil)
		end
	)

	it(
		"a beat from the checkout that made the claim beats it; a bare beat from one that holds none is refused",
		function()
			local stamp = stampOf(`{P}/c0010/c0010.md`)
			must(zn(wt, { "beat", "c0010" }, T0 + 100), "beat from the claiming worktree")
			local mine
			for _, b in beats() do
				if b.stamp == stamp then
					mine = b
				end
			end
			t.expect(mine ~= nil).toBe(true)
			t.expect((mine :: any).epoch).toBe(T0 + 100)
			local before = beats()
			for _, dir in { h.f.main, wt2 } do
				local bare = zn(dir, { "beat", "c0010" }, T0 + 200)
				t.expect(bare.ok).toBe(false)
				t.expect(has(bare.stderr, "does not hold")).toBe(true)
				t.expect(has(bare.stderr, "--adopt")).toBe(true)
			end
			local after = beats()
			t.expect(#after).toBe(#before)
			for i, b in after do
				t.expect(b.sha).toBe(before[i].sha) -- nothing was written
			end
		end
	)

	it("an item that is not a claim is refused as such, before any memory refusal", function()
		for _, id in { "c0020", "c0060" } do -- new; done with a stamp it kept
			local r = zn(wt2, { "beat", id }, T0 + 200)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "no claim to beat")).toBe(true)
			t.expect(has(r.stderr, "does not hold")).toBe(false)
		end
	end)

	it(
		"--adopt takes on a claim a worktree did not make, remembers it there, and a bare beat works after",
		function()
			local stamp = stampOf(`{P}/c0010/c0010.md`)
			must(zn(wt2, { "beat", "c0010", "--adopt" }, T0 + 300), "adopt in the second worktree")
			t.expect(memory(wt2, "c0010")).toBe(stamp)
			must(zn(wt2, { "beat", "c0010" }, T0 + 400), "a bare beat after the adoption")
			local found = false
			for _, b in beats() do
				found = found or (b.stamp == stamp and b.epoch == T0 + 400)
			end
			t.expect(found).toBe(true)
		end
	)

	it("the dispatcher's form is bound to the stamp it read and writes no memory", function()
		must(zn(wt, { "status", "c0095", "preparing" }, T0 + 500), "claim c0095")
		local stamp = stampOf(`{P}/c0095/c0095.md`)
		local before = beats()
		local stale =
			zn(h.f.main, { "beat", "c0095", "--adopt", "--stamp", "preparing-silver-otter-quiet" }, T0 + 600)
		t.expect(stale.ok).toBe(false)
		t.expect(has(stale.stderr, `c0095's claim was taken over (now {stamp})`)).toBe(true)
		local after = beats()
		t.expect(#after).toBe(#before)
		for i, b in after do
			t.expect(b.sha).toBe(before[i].sha)
		end
		-- the form needs --adopt
		t.expect(zn(h.f.main, { "beat", "c0095", "--stamp", stamp }, T0 + 600).ok).toBe(false)
		-- with the right stamp it beats, and neither the main checkout nor a worktree remembers anything new
		must(
			zn(h.f.main, { "beat", "c0095", "--adopt", "--stamp", stamp }, T0 + 600),
			"the dispatcher's form"
		)
		must(
			zn(wt2, { "beat", "c0095", "--adopt", "--stamp", stamp }, T0 + 650),
			"the dispatcher's form in a worktree"
		)
		t.expect(memory(h.f.main, "c0095")).toBe(nil)
		t.expect(memory(wt2, "c0095")).toBe(nil)
	end)

	it("a main-checkout adoption writes no memory, so a re-claim does not make it refuse", function()
		must(zn(h.f.main, { "beat", "c0095", "--adopt" }, T0 + 700), "main adopts c0095")
		t.expect(memory(h.f.main, "c0095")).toBe(nil)
		local first = stampOf(`{P}/c0095/c0095.md`)
		must(zn(wt, { "status", "c0095", "new" }, T0 + 800), "give c0095 back")
		must(zn(wt, { "status", "c0095", "preparing" }, T0 + 900), "claim c0095 again")
		local second = stampOf(`{P}/c0095/c0095.md`)
		t.expect(second ~= first).toBe(true)
		must(zn(h.f.main, { "beat", "c0095", "--adopt" }, T0 + 1000), "main adopts the new claim")
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == second and b.epoch == T0 + 1000)
		end
		t.expect(found).toBe(true)
	end)

	it(
		"an adoption never overrides a remembered different stamp, and the refusal keeps the memory",
		function()
			-- wt3 claims c0090 and then holds a stale memory: wt2 gives it back and claims it again, so origin shows a new
			-- stamp. wt3 runs nothing but the refused beats (a later layer may refuse its other commands)
			must(zn(wt3, { "status", "c0090", "preparing" }, T0 + 1050), "claim c0090")
			local old = stampOf(`{P}/c0090/c0090.md`)
			must(zn(wt2, { "status", "c0090", "new" }, T0 + 1100), "give c0090 back")
			must(zn(wt2, { "status", "c0090", "preparing" }, T0 + 1200), "claim c0090 again")
			local now = stampOf(`{P}/c0090/c0090.md`)
			t.expect(now ~= old).toBe(true)
			t.expect(memory(wt2, "c0090")).toBe(now)
			local before = beats()
			for _, args in { { "beat", "c0090" }, { "beat", "c0090", "--adopt" } } do
				local r = zn(wt3, args, T0 + 1300)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, `c0090's claim was taken over (now {now})`)).toBe(true)
			end
			local loop = zn(
				wt3,
				{ "beat", "c0090", "--watch" },
				T0 + 1300,
				{ ZN_BOUNDED_DEADLINE = tostring(os.time() + 600) }
			)
			t.expect(loop.ok).toBe(false)
			t.expect(has(loop.stderr, `c0090's claim was taken over (now {now})`)).toBe(true)
			t.expect(memory(wt3, "c0090")).toBe(old) -- never dropped by the observation that refuses
			local after = beats()
			t.expect(#after).toBe(#before)
			for i, b in after do
				t.expect(b.sha).toBe(before[i].sha) -- the new claim's branch was not touched
			end
		end
	)

	it("a claim made before the memory existed is held through tracker-claim-<id>", function()
		must(zn(wt, { "status", "c0020", "preparing" }, T0 + 1400), "claim c0020")
		local stamp = stampOf(`{P}/c0020/c0020.md`)
		fs.removeFile(`{wt}/{CACHE}/tracker-stamp-c0020`) -- what a worktree that claimed before this landed looks like
		t.expect(fs.isFile(`{wt}/{CACHE}/tracker-claim-c0020`)).toBe(true)
		must(zn(wt, { "beat", "c0020" }, T0 + 1500), "beat through the old claim file")
		local found = false
		for _, b in beats() do
			found = found or (b.stamp == stamp and b.epoch == T0 + 1500)
		end
		t.expect(found).toBe(true)
	end)

	it("a claim-ending command run in the checkout ends its memory: give-back and release", function()
		must(
			zn(wt, { "status", "c0020", "new" }, T0 + 1590),
			"give c0020 back, whose memory the case above removed"
		)
		must(zn(wt, { "status", "c0020", "preparing" }, T0 + 1595), "claim c0020 once more")
		t.expect(memory(wt, "c0020") ~= nil).toBe(true)
		must(zn(wt, { "status", "c0020", "new" }, T0 + 1600), "give c0020 back")
		t.expect(memory(wt, "c0020")).toBe(nil)
		local listing = must(zn(h.f.main, { "status" }, T0 + 1600), "status")
		local rid = string.match(listing, "(R%d+) preparing") or error("no rafting claim")
		t.expect(memory(wt, rid) ~= nil).toBe(true)
		must(zn(wt, { "release", rid }, T0 + 1700), "release")
		t.expect(memory(wt, rid)).toBe(nil)
	end)

	it("a raft given back ends both memory files, so its giver is never told it was taken over", function()
		must(
			zn(wt, { "new", "raft", "chore", "gbraft", "c0070", "--project", "pickman" }, T0 + 1800),
			"new raft"
		)
		local listing = must(zn(h.f.main, { "status" }, T0 + 1800), "status")
		local rid = string.match(listing, "(R%d+) preparing") or error("no rafting claim")
		t.expect(fs.isFile(`{wt}/{CACHE}/tracker-stamp-{rid}`)).toBe(true)
		t.expect(fs.isFile(`{wt}/{CACHE}/tracker-claim-{rid}`)).toBe(true)
		must(zn(wt, { "status", rid, "new" }, T0 + 1810), "give the raft back")
		t.expect(fs.isFile(`{wt}/{CACHE}/tracker-stamp-{rid}`)).toBe(false)
		t.expect(fs.isFile(`{wt}/{CACHE}/tracker-claim-{rid}`)).toBe(false)
		-- another terminal claims it; the giver's bare beat is refused as a checkout that holds no claim
		must(zn(wt2, { "status", rid, "preparing" }, T0 + 1820), "another terminal claims the raft")
		local late = zn(wt, { "beat", rid }, T0 + 1830)
		t.expect(late.ok).toBe(false)
		t.expect(has(late.stderr, "does not hold")).toBe(true)
		t.expect(has(late.stderr, "taken over")).toBe(false)
	end)
end)
