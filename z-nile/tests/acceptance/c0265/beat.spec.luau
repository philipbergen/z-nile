--!strict
-- c0265: a beat is a branch (hb/<claim stamp>) on origin, outside main: one commit, replaced by each beat, whose tree is
-- main's tree and whose parent is main's tip (so ./zn busy never sees it) and whose subject is "hb <stamp> <epoch>".
-- `beat <id>` writes it from any checkout, for the stamp main shows for the item; it never prunes a young branch of a
-- claim this checkout has not fetched, prunes the branch of a claim long gone, never beats from a protected (fenced)
-- checkout, refuses what nobody claims (done items included), and `--watch` refuses to run without a numeric bound.
-- Time is ZN_NOW (epoch seconds), so no case waits. Fixture under .cache/c0265-beat.
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
-- the heartbeat branches on origin, as { stamp, epoch, sha } read from the branch name and the commit subject
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
local function epochsOf(stamp: string): { number }
	local out = {}
	for _, b in beats() do
		if b.stamp == stamp then
			table.insert(out, b.epoch)
		end
	end
	return out
end
-- another terminal's beat: a commit with main's tree and tip as parent, force-pushed as the stamp's branch
local function pushBeat(stamp: string, epoch: number)
	local tree = fixture.git(h.f.other, { "rev-parse", "HEAD^{tree}" })
	local sha = fixture.git(h.f.other, { "commit-tree", tree, "-p", "HEAD", "-m", `hb {stamp} {epoch}` })
	fixture.git(h.f.other, { "push", "-q", "-f", "origin", `{sha}:refs/heads/hb/{stamp}` })
end
local function stampOf(path: string): string
	local text = fixture.git(h.f.origin, { "show", `main:{path}` })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error(`{path} has no status on origin`)
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

return t.spec("c0265 a beat is a branch outside main", function(it)
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
			[`{P}/c0050/c0050.md`] = issue("c0050", "new-a-b-c"),
			-- a raft recombine retired keeps the stamp it was claimed with: it is never a claim
			["pickman/.tracker/rafts/retired/R0099/R0099.md"] = "---\nid: R0099\ntype: chore\ntitle: Gone\nslug: gone\nsingle: false\nissues: []\ndesign: draft\ncreated: 2026-10-06\nstatus: preparing-quiet-copper-falcon\n---\n\n# R0099\n",
			-- a finished raft's issue keeps the claim stamp it was worked under (about 30 do on the real tracker)
			[`{P}/done/c0060/c0060.md`] = issue("c0060", "active-brisk-amber-otter"),
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		-- a counting shim: every network call a command makes (fetch, ls-remote, push) is logged in <fakes>/netcalls
		fs.writeFile(
			`{h.bin}/git`,
			(
				string.gsub(
					fs.readFile(`{h.bin}/git`),
					"^#!/bin/sh\n",
					'#!/bin/sh\ncase "$1" in fetch|ls-remote|push) echo x >> "$FAKE_DIR/netcalls";; esac\n'
						.. 'if [ "$1" = push ] && [ -f "$FAKE_DIR/prunefail" ]; then case "$*" in *":refs/heads/hb/preparing-gone-gone-gone"*) echo "fatal: fake prune refusal" >&2; exit 1;; esac; fi\n',
					1
				)
			)
		)
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-beat" }), "worktree"), "%s+$", ""))
		-- the claims are the worktree's own: every beat below is made from the checkout that made the claim
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		must(zn(wt, { "status", "c0050", "preparing" }, T0), "claim c0050")
	end)

	it(
		"beat writes a one-commit branch with main's tree and tip, authored by the checkout's own identity, touching no file",
		function()
			local main = fixture.git(h.f.origin, { "rev-parse", "main" })
			local stamp = stampOf(`{P}/c0010/c0010.md`)
			must(zn(wt, { "beat", "c0010" }, T0 + 300), "beat")
			local list = beats()
			t.expect(#list).toBe(1)
			t.expect(list[1].stamp).toBe(stamp)
			t.expect(list[1].epoch).toBe(T0 + 300)
			local tip = `refs/heads/hb/{stamp}`
			t.expect(fixture.git(h.f.origin, { "rev-parse", tip .. "^{tree}" }))
				.toBe(fixture.git(h.f.origin, { "rev-parse", "main^{tree}" }))
			t.expect(fixture.git(h.f.origin, { "rev-parse", tip .. "^" })).toBe(main)
			t.expect(fixture.git(h.f.origin, { "log", "-1", "--format=%s", tip }))
				.toBe(`hb {stamp} {T0 + 300}`)
			t.expect(fixture.git(h.f.origin, { "rev-parse", "main" })).toBe(main) -- never a commit on main
			-- the checkout's own identity, never a fixture-looking one made up for the beat: the spec runner reads a new ref
			-- authored @example.invalid as a fixture leak (and the beat's ref is shared by every worktree)
			local own = fixture.git(wt, { "config", "user.email" })
			t.expect(fixture.git(h.f.origin, { "log", "-1", "--format=%ae", tip })).toBe(own)
			t.expect(own ~= "zn-beat@example.invalid").toBe(true)
			t.expect(fixture.git(h.f.main, { "status", "--porcelain" })).toBe("")
			-- ./zn busy sees no change on it
			t.expect(has(zn(h.f.main, { "busy", "z-nile", "pickman" }, T0 + 300).stdout, "hb/")).toBe(false)
		end
	)

	it("a second beat, from a worktree, replaces the commit: one branch per claim", function()
		must(zn(wt, { "beat", "c0010" }, T0 + 600), "beat in the worktree")
		local stamp = stampOf(`{P}/c0010/c0010.md`)
		t.expect(epochsOf(stamp)).toEqual({ T0 + 600 })
		t.expect(#beats()).toBe(1)
		-- the same second, or an older one, is not written again (never backwards)
		local sha = beats()[1].sha
		must(zn(wt, { "beat", "c0010" }, T0 + 600), "beat in the same second")
		must(zn(wt, { "beat", "c0010" }, T0 + 500), "beat in an earlier second")
		t.expect(beats()[1].sha).toBe(sha)
	end)

	it("beat refuses what nobody claims, naming the item and the rule", function()
		for _, id in { "c0020", "c0040", "c0060", "c9999" } do
			local r = zn(wt, { "beat", id }, T0)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, id)).toBe(true)
		end
		t.expect(has(zn(wt, { "beat", "c0020" }, T0).stderr, "no claim")).toBe(true)
		t.expect(has(zn(wt, { "beat", "c0060" }, T0).stderr, "done")).toBe(true) -- its stored status is active-…
		t.expect(#beats()).toBe(1)
	end)

	it("beat finds no claim in a raft recombine retired, whatever stamp it kept", function()
		local r = zn(wt, { "beat", "R0099" }, T0)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "R0099")).toBe(true) -- not found: the tracker does not see a retired raft as an item
	end)

	it("beat refuses to run without an origin (PICKMAN_PUBLISH=0)", function()
		local r = zn(wt, { "beat", "c0010" }, T0, { PICKMAN_PUBLISH = "0" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "origin remote")).toBe(true)
	end)

	it("a beat keeps another terminal's fresh beat of a claim it has not fetched", function()
		-- another terminal claims c0030 and beats; this checkout has not fetched since
		trackerfix.elsewhere(h.f, {
			[`{P}/c0030/c0030.md`] = issue("c0030", "preparing-sunny-heron-lynx"),
		}, "other claims c0030")
		pushBeat("preparing-sunny-heron-lynx", T0 + 1150)
		must(zn(wt, { "beat", "c0010" }, T0 + 1200), "beat in a checkout that has not fetched")
		t.expect(epochsOf("preparing-sunny-heron-lynx")).toEqual({ T0 + 1150 })
	end)

	it(
		"a beat prunes the branch of a stamp no claim holds once it is older than the limit, and only that",
		function()
			pushBeat("preparing-gone-gone-gone", T0 - 5000) -- its claim ended long ago
			pushBeat("preparing-fresh-fresh-fresh", T0 + 1190) -- unclaimed here, but young: may simply not be fetched
			local lostClaim = stampOf(`{P}/c0050/c0050.md`)
			pushBeat(lostClaim, T0 - 5000) -- a LOST claim: still claimed, so its old branch stays as evidence
			-- a refused prune never fails the beat
			fs.writeFile(`{h.fakes}/prunefail`, "1")
			must(zn(wt, { "beat", "c0010" }, T0 + 1300), "beat while a prune is refused")
			fs.removeFile(`{h.fakes}/prunefail`)
			t.expect(epochsOf(stampOf(`{P}/c0010/c0010.md`))).toEqual({ T0 + 1300 })
			t.expect(epochsOf("preparing-gone-gone-gone")).toEqual({ T0 - 5000 })
			must(zn(wt, { "beat", "c0010" }, T0 + 1400), "beat")
			t.expect(epochsOf("preparing-gone-gone-gone")).toEqual({})
			t.expect(epochsOf("preparing-fresh-fresh-fresh")).toEqual({ T0 + 1190 })
			t.expect(epochsOf(lostClaim)).toEqual({ T0 - 5000 })
		end
	)

	it("a protected checkout never beats: the explicit beat refuses there before any network call", function()
		local before = #beats()
		local function net(): number
			local text = if fs.isFile(`{h.fakes}/netcalls`) then fs.readFile(`{h.fakes}/netcalls`) else ""
			return #string.gsub(text, "[^x]", "")
		end
		local netBefore = net()
		-- a protected checkout: the guards in this worktree answer "guarded" (the fixture's own copy of fence.sh)
		local fence = `{wt}/z-nile/lib/fence.sh`
		local original = fs.readFile(fence)
		fs.writeFile(fence, original .. "\npickman_guarded() { echo guarded; }\n")
		local explicit = zn(wt, { "beat", "c0010" }, T0 + 9000)
		fs.writeFile(fence, original)
		t.expect(explicit.ok).toBe(false)
		t.expect(has(explicit.stderr, "protected")).toBe(true)
		t.expect(#beats()).toBe(before)
		t.expect(net()).toBe(netBefore) -- nothing was fetched, listed or pushed
	end)

	it("--watch refuses to run without a numeric bound (outside ./zn run)", function()
		local refused = zn(wt, { "beat", "c0010", "--watch" }, nil, { ZN_BOUNDED_DEADLINE = "" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "./zn run")).toBe(true)
	end)
end)
