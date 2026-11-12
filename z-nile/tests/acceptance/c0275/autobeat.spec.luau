--!strict
-- c0275: a claim beats from the moment it is made, a worktree keeps what it holds alive, and nothing beats that should
-- not. Every claim publish (`status`, `new raft`, `fold`, `ready`) writes the first beat as a branch, and a worktree writes
-- its throttle mark `.cache/tracker-beats/<id>` (`<stamp> <epoch> <sha>`); the main checkout never does. Any `./zn` command
-- run in a worktree beats the claims whose mark is an interval old (none inside it, no network call either), tells an old
-- owner once that its claim was taken over or ended, and never fails; a protected checkout never beats. A give-back,
-- `release` and `stop` drop the claim's heartbeat branch (`stop` after it read the verdict). A claim held in a worktree
-- starts its background beater (a recording `perl` stands in for the detached start; the real beater is in the proofs).
-- Time is ZN_NOW, so no case waits. Fixture under .cache/c0275-auto.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"
local STALE = heartbeat.STALE
local EVERY = heartbeat.INTERVAL
local T0 = os.time()
local LATE = T0 + 9000

local h: fakecli.Harness
-- wt makes the main claims, wt2 the failing and ended ones, wt3 a claim it never touches again, wt4 takes it over, wt5 the beater
local wt, wt2, wt3, wt4, wt5 = "", "", "", "", ""
local specPid = ""
local rid = "" -- the raft `new raft` claimed

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
local function epochsOf(stamp: string): { number }
	local out = {}
	local subjects =
		fixture.git(h.f.origin, { "for-each-ref", "--format=%(subject)", `refs/heads/hb/{stamp}` })
	for line in string.gmatch(subjects, "[^\n]+") do
		table.insert(out, tonumber(string.match(line, "(%d+)$")) :: number)
	end
	return out
end
local function tipOf(stamp: string): string
	return fixture.git(h.f.origin, { "for-each-ref", "--format=%(objectname)", `refs/heads/hb/{stamp}` })
end
local function markOf(dir: string, id: string): string?
	local f = `{dir}/.cache/tracker-beats/{id}`
	return if fs.isFile(f) then fs.readFile(f) else nil
end
local function refCount(): number
	local _, n = string.gsub(fixture.git(h.f.origin, { "for-each-ref", "refs/heads/hb/" }), "\n", "")
	return n
end
local function net(): number
	local text = if fs.isFile(`{h.fakes}/netcalls`) then fs.readFile(`{h.fakes}/netcalls`) else ""
	return #string.gsub(text, "[^x]", "")
end
local function starts(): { string }
	local out = {}
	if fs.isFile(`{h.fakes}/beater`) then
		for line in string.gmatch(fs.readFile(`{h.fakes}/beater`), "[^\n]+") do
			table.insert(out, line)
		end
	end
	return out
end
local function issue(id: string, status: string, design: string?, raft: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Auto\nslug: auto\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
-- every network call is counted; a marker file makes the pushes of heartbeat branches fail
local SHIM = '#!/bin/sh\ncase "$1" in fetch|ls-remote|push) echo x >> "$FAKE_DIR/netcalls";; esac\n'
	.. 'if [ "$1" = push ] && [ -f "$FAKE_DIR/hbfail" ]; then case "$*" in *":refs/heads/hb/"*) echo "fatal: fake beat refusal" >&2; exit 1;; esac; fi\n'

return t.spec("c0275 automatic beats", function(it)
	it("sets up a tracker, a prepared raft to ready and one to fold into, worktrees and the shims", function()
		h = fakecli.new("c0275-auto", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
			[`{P}/c0075/c0075.md`] = issue("c0075", "new-a-b-c"),
			[`{P}/c0080/c0080.md`] = issue("c0080", "new-a-b-c"),
			[`{P}/c0085/c0085.md`] = issue("c0085", "new-a-b-c"),
			[`{P}/c0086/c0086.md`] = issue("c0086", "new-a-b-c"),
			[`{P}/c0087/c0087.md`] = issue("c0087", "new-a-b-c"),
			[`{P}/c0095/c0095.md`] = issue("c0095", "prepared-quiet-copper-falcon", "ready"),
			[`{P}/c0095/check.sh`] = CHECK,
			[`{P}/c0099/c0099.md`] = issue("c0099", "new-a-b-c"),
			[`{P}/c0040/c0040.md`] = issue("c0040", "prepared-quiet-copper-falcon", "ready", "R0010"),
			[`{P}/c0040/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0040"),
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			[`{P}/c0096/c0096.md`] = issue("c0096", "prepared-quiet-copper-falcon", "ready", "R0030"),
			[`{P}/c0096/check.sh`] = CHECK,
			["pickman/.tracker/rafts/R0030/R0030.md"] = raftDoc("R0030", "c0096"),
			["pickman/.tracker/rafts/R0030/check.sh"] = CHECK,
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		fs.writeFile(`{h.bin}/git`, (string.gsub(fs.readFile(`{h.bin}/git`), "^#!/bin/sh\n", SHIM, 1)))
		-- the detached start of a beater is recorded, not run: its arguments, then the pid the pid file will hold
		local perl = (string.gsub(process.exec("sh", { "-c", "command -v perl" }).stdout, "%s+$", ""))
		specPid = (string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+$", ""))
		fs.writeFile(`{h.fakes}/livepid`, specPid)
		fs.writeFile(
			`{h.bin}/perl`,
			`#!/bin/sh\ncase "$2" in *setsid*) shift 2; echo "$*" >> "$FAKE_DIR/beater"; cat "$FAKE_DIR/livepid"; exit 0;; esac\nexec {perl} "$@"\n`
		)
		process.exec("chmod", { "+x", `{h.bin}/perl` })
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-auto" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-auto-2" }), "worktree"), "%s+$", ""))
		wt3 = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-auto-3" }), "worktree"), "%s+$", ""))
		wt4 = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-auto-4" }), "worktree"), "%s+$", ""))
		wt5 = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-auto-5" }), "worktree"), "%s+$", ""))
	end)

	it("a claim writes the first beat as a branch and the worktree's mark, and main only gets the claim", function()
		local main = fixture.git(h.f.origin, { "rev-parse", "main" })
		must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim c0010")
		local stamp = stampOf(`{P}/c0010/c0010.md`)
		t.expect(epochsOf(stamp)).toEqual({ T0 })
		-- the claim is one commit on main and the beat is not: the beat is one branch whose commit changes nothing
		t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{main}..main` })).toBe("1")
		local tip = `refs/heads/hb/{stamp}`
		t.expect(fixture.git(h.f.origin, { "rev-parse", tip .. "^{tree}" }))
			.toBe(fixture.git(h.f.origin, { "rev-parse", "main^{tree}" }))
		t.expect(fixture.git(h.f.origin, { "log", "-1", "--format=%s", tip })).toBe(`hb {stamp} {T0}`)
		t.expect(has(zn(h.f.main, { "busy", "z-nile", "pickman" }, T0).stdout, "hb/")).toBe(false)
		-- the worktree's mark is the throttle and the lease: stamp, epoch and the sha it wrote
		t.expect(markOf(wt, "c0010")).toBe(`{stamp} {T0} {tipOf(stamp)}`)
	end)

	it("ready beats for the raft it claims, and the main checkout writes no mark", function()
		must(zn(h.f.main, { "ready", "R0010" }, T0, { ZN_BEATER = "1" }), "ready R0010")
		local stamp = stampOf("pickman/.tracker/rafts/active/R0010/R0010.md")
		t.expect(string.sub(stamp, 1, 7)).toBe("active-")
		t.expect(epochsOf(stamp)).toEqual({ T0 })
		t.expect(fs.isDir(`{h.f.main}/.cache/tracker-beats`)).toBe(false)
		-- the main checkout holds no work, so it starts no beater either
		t.expect(#starts()).toBe(0)
	end)

	it("any ./zn command in a worktree that holds a claim beats it once an interval has passed, the main checkout never", function()
		local stamp = stampOf(`{P}/c0010/c0010.md`)
		must(zn(wt, { "status", "c0010" }, T0 + 1000), "status in the worktree")
		t.expect(epochsOf(stamp)).toEqual({ T0 + 1000 })
		must(zn(wt, { "status", "c0010" }, T0 + 1000 + EVERY - 1), "status again, inside the interval")
		t.expect(epochsOf(stamp)).toEqual({ T0 + 1000 }) -- no second push inside the interval
		-- inside the interval a command that reads nothing from origin makes no network call at all
		local before = net()
		must(zn(wt, { "lessons", "--tags" }, T0 + 1000 + EVERY - 1), "a command that makes no network call")
		t.expect(net()).toBe(before)
		-- the main checkout holds no work: a command there beats nothing, however old the last beat
		must(zn(h.f.main, { "status", "c0010" }, T0 + 5000), "status in the main checkout")
		t.expect(epochsOf(stamp)).toEqual({ T0 + 1000 })
		t.expect(markOf(wt, "c0010")).toBe(`{stamp} {T0 + 1000} {tipOf(stamp)}`)
	end)

	it("new raft and fold beat for the raft they claim", function()
		must(zn(wt, { "new", "raft", "chore", "beatraft", "c0020", "--project", "pickman" }, T0 + 1300), "new raft")
		local listing = zn(h.f.main, { "status" }, T0 + 1300).stdout
		rid = string.match(listing, "(R%d+) preparing") or error("no new raft in the status list")
		local stamp = stampOf(`pickman/.tracker/rafts/{rid}/{rid}.md`)
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		t.expect(epochsOf(stamp)).toEqual({ T0 + 1300 })
		t.expect(markOf(wt, rid)).toBe(`{stamp} {T0 + 1300} {tipOf(stamp)}`)
		-- fold into a prepared raft claims it
		must(zn(wt, { "fold", "R0030", "c0095" }, T0 + 1310), "fold")
		local folded = stampOf("pickman/.tracker/rafts/R0030/R0030.md")
		t.expect(string.sub(folded, 1, 10)).toBe("preparing-")
		t.expect(epochsOf(folded)).toEqual({ T0 + 1310 })
		t.expect(markOf(wt, "R0030")).toBe(`{folded} {T0 + 1310} {tipOf(folded)}`)
	end)

	it("a nested ./zn in a protected checkout never beats, and does not touch its marks", function()
		local before = refCount()
		local mark = markOf(wt, "c0010")
		local netBefore = net()
		-- a protected checkout: the guards in this worktree answer "guarded" (the fixture's own copy of fence.sh)
		local fence = `{wt}/z-nile/lib/fence.sh`
		local original = fs.readFile(fence)
		fs.writeFile(fence, original .. "\npickman_guarded() { echo guarded; }\n")
		local nested = zn(wt, { "lessons", "--tags" }, T0 + 9000)
		fs.writeFile(fence, original)
		t.expect(nested.ok).toBe(true)
		t.expect(refCount()).toBe(before)
		t.expect(markOf(wt, "c0010")).toBe(mark) -- not even a failed attempt: the mark is untouched
		t.expect(net()).toBe(netBefore) -- nothing was fetched, listed or pushed first
	end)

	it("a failed first beat does not fail the claim, is said, and the worktree still keeps the claim alive", function()
		fs.writeFile(`{h.fakes}/hbfail`, "1")
		local r = zn(wt2, { "status", "c0075", "preparing" }, T0 + 2000)
		fs.removeFile(`{h.fakes}/hbfail`)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "beat: c0075:")).toBe(true) -- said, with the item named
		local stamp = stampOf(`{P}/c0075/c0075.md`)
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		t.expect(epochsOf(stamp)).toEqual({}) -- no beat landed
		-- the failed attempt wrote the mark (a dated one without a sha), so the next command after an interval beats it
		t.expect(markOf(wt2, "c0075")).toBe(`{stamp} {T0 + 2000} `)
		must(zn(wt2, { "lessons", "--tags" }, T0 + 2000 + 10), "a command inside the interval")
		t.expect(epochsOf(stamp)).toEqual({})
		must(zn(wt2, { "lessons", "--tags" }, T0 + 2000 + EVERY), "a command after the interval")
		t.expect(epochsOf(stamp)).toEqual({ T0 + 2000 + EVERY })
	end)

	it("a failed beat attempt is not retried inside the interval", function()
		local due = T0 + 4000
		fs.writeFile(`{h.fakes}/hbfail`, "1")
		local before = net()
		must(zn(wt2, { "lessons", "--tags" }, due), "a command when the claim is due: one failed attempt")
		local first = net()
		t.expect(first > before).toBe(true)
		must(zn(wt2, { "lessons", "--tags" }, due + 10), "a command inside the interval")
		t.expect(net()).toBe(first) -- the failed attempt advanced the mark: nothing more is tried
		fs.removeFile(`{h.fakes}/hbfail`)
	end)

	it("a claim given back or ended elsewhere is dropped with 'claim ended', and its branch goes with the give-back", function()
		must(zn(wt2, { "status", "c0070", "preparing" }, T0 + 5000), "claim c0070")
		local stamp = stampOf(`{P}/c0070/c0070.md`)
		t.expect(tipOf(stamp) ~= "").toBe(true)
		-- another checkout, which remembers nothing about c0070, gives it back
		must(zn(wt, { "status", "c0070", "new" }, T0 + 5100), "give c0070 back")
		t.expect(tipOf(stamp)).toBe("") -- giving the claim back deleted its heartbeat branch
		local told = zn(wt2, { "lessons", "--tags" }, T0 + 5100 + EVERY)
		t.expect(told.ok).toBe(true)
		t.expect(has(told.stderr, "c0070's claim ended")).toBe(true)
		t.expect(has(told.stderr, "c0070's claim was taken over")).toBe(false)
		t.expect(markOf(wt2, "c0070")).toBe(nil)
		t.expect(has(zn(wt2, { "lessons", "--tags" }, T0 + 5100 + 2 * EVERY + 10).stderr, "c0070")).toBe(false) -- told once
	end)

	it("a give-back from the checkout that made the claim drops its mark and its branch at once", function()
		must(zn(wt, { "status", "c0099", "preparing" }, T0 + 5200), "claim c0099")
		local stamp = stampOf(`{P}/c0099/c0099.md`)
		t.expect(tipOf(stamp) ~= "").toBe(true)
		must(zn(wt, { "status", "c0099", "new" }, T0 + 5210), "give c0099 back")
		t.expect(tipOf(stamp)).toBe("")
		t.expect(markOf(wt, "c0099")).toBe(nil)
	end)

	it("release drops the rafting claim's branch and mark", function()
		local stamp = stampOf(`pickman/.tracker/rafts/{rid}/{rid}.md`)
		t.expect(tipOf(stamp) ~= "").toBe(true)
		must(zn(wt, { "release", rid }, T0 + 6000), "release")
		t.expect(tipOf(stamp)).toBe("")
		t.expect(markOf(wt, rid)).toBe(nil)
	end)

	it("a worktree that holds a claim starts its background beater once; a headless step, a spec and the main checkout start none", function()
		local function ours(id: string): { string }
			local out = {}
			for _, line in starts() do
				if has(line, ` beat {id} --watch`) then
					table.insert(out, line)
				end
			end
			return out
		end
		local claimed = zn(wt5, { "status", "c0085", "preparing" }, T0 + 7000, { ZN_BEATER = "1" })
		must(claimed, "claim c0085")
		local line = ours("c0085")[1] or error(`no beater was started: {claimed.stderr}{table.concat(starts(), "|")}`)
		local top = (string.gsub(fixture.git(wt5, { "rev-parse", "--show-toplevel" }), "%s+$", ""))
		-- the bound is ./zn run's, the loop is beat --watch; the session is the claude process above, when there is one
		t.expect(has(line, `{top}/zn run --time 3600 -- {top}/zn beat c0085 --watch`)).toBe(true)
		local pidFile = fs.readFile(`{wt5}/.cache/tracker-beater/c0085`)
		t.expect(string.match(pidFile, "^" .. specPid .. " %d+%s*$") ~= nil).toBe(true)
		-- the next command finds it alive and starts no second one
		must(zn(wt5, { "lessons", "--tags" }, T0 + 7010, { ZN_BEATER = "1" }), "a command while it runs")
		t.expect(#ours("c0085")).toBe(1)
		-- its pid gone (it ended at its hour, or with the session): the next command starts it again
		fs.writeFile(`{wt5}/.cache/tracker-beater/c0085`, `999999 {os.time() + 3000}`)
		must(zn(wt5, { "lessons", "--tags" }, T0 + 7020, { ZN_BEATER = "1" }), "a command after it ended")
		t.expect(#ours("c0085")).toBe(2)
		-- a spec run starts none unless it asks; a headless step's dispatcher beats for it instead
		must(zn(wt5, { "status", "c0086", "preparing" }, T0 + 7030), "claim c0086 in a spec run")
		t.expect(#ours("c0086")).toBe(0)
		must(zn(wt5, { "status", "c0087", "preparing" }, T0 + 7040, { ZN_BEATER = "1", ZN_DISPATCH = "1" }), "claim c0087 headless")
		t.expect(#ours("c0087")).toBe(0)
		t.expect(markOf(wt5, "c0087") ~= nil).toBe(true) -- it still beats like any claim
		-- an adoption makes the worktree the holder, so it gets a beater too
		must(zn(wt5, { "beat", "R0010", "--adopt" }, T0 + 7050, { ZN_BEATER = "1" }), "adopt R0010")
		t.expect(#ours("R0010")).toBe(1)
		t.expect(markOf(wt5, "R0010") ~= nil).toBe(true)
		-- giving the claim back ends its beater's file (the loop itself stops: its worktree no longer holds the claim)
		must(zn(wt5, { "status", "c0085", "new" }, T0 + 7060), "give c0085 back")
		t.expect(fs.isFile(`{wt5}/.cache/tracker-beater/c0085`)).toBe(false)
	end)

	it("a claim taken over: its taker's first beat is on its own branch, and the old owner is told once and stops beating", function()
		must(zn(wt3, { "status", "c0080", "preparing" }, T0), "claim c0080") -- wt3 runs nothing after this
		local old = stampOf(`{P}/c0080/c0080.md`)
		t.expect(markOf(wt3, "c0080")).toBe(`{old} {T0} {tipOf(old)}`)
		local mine = markOf(wt3, "c0080")
		must(zn(wt4, { "status", "c0080", "preparing" }, LATE), "take c0080 over")
		local new = stampOf(`{P}/c0080/c0080.md`)
		t.expect(new ~= old).toBe(true)
		t.expect(tipOf(old)).toBe("") -- the swap deleted the old owner's branch
		t.expect(epochsOf(new)).toEqual({ LATE }) -- the taker's branch, beaten once (by the swap, then by the first beat)
		t.expect(markOf(wt4, "c0080")).toBe(`{new} {LATE} {tipOf(new)}`)
		local tip = tipOf(new)
		-- the old owner's next command says so, once, and beats nothing
		local told = zn(wt3, { "lessons", "--tags" }, LATE + EVERY)
		t.expect(told.ok).toBe(true)
		t.expect(has(told.stderr, `c0080's claim was taken over (now {new})`)).toBe(true)
		t.expect(markOf(wt3, "c0080")).toBe(nil)
		t.expect(tipOf(new)).toBe(tip)
		t.expect(tipOf(old)).toBe("")
		t.expect(has(zn(wt3, { "lessons", "--tags" }, LATE + 3 * EVERY).stderr, "c0080")).toBe(false)
		t.expect(mine ~= nil).toBe(true)
	end)

	it("stop drops the readied raft's heartbeat branch after reading its verdict", function()
		local stamp = stampOf("pickman/.tracker/rafts/active/R0010/R0010.md")
		t.expect(tipOf(stamp) ~= "").toBe(true)
		local r = zn(h.f.main, { "stop", "R0010" }, LATE)
		must(r, "stop R0010")
		-- the verdict was read from the branch before it went: the claim was lost for the minutes it was quiet
		local subject = fixture.git(h.f.origin, { "log", "-1", "--format=%s", "main" })
		t.expect(has(subject, `(claim {stamp}, lost `)).toBe(true)
		t.expect(tipOf(stamp)).toBe("")
	end)
end)
