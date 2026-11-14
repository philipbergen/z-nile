--!strict
-- c0275: real-time proofs of the background beater, run once by check.sh and never promoted (a spec waits for nothing). A
-- claim made in a worktree starts a real detached `./zn run --time 3600 -- ./zn beat <id> --watch`: it outlives the command
-- that started it, beats while no command runs, and ends when its worktree is gone or no longer holds the claim; and
-- `beat --watch --session <pid>` ends within seconds of that process. (The process table is unreadable in a spec's jail,
-- so the session a claim would tie its beater to is a flag here; the choice of that session is plan.spec's.)
-- Fixture under .cache/c0275-beater.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wt2, wt3, wt4 = "", "", "", ""
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"
-- spelled apart so that the memory files c0274 names in its own specs are not named by a second one (c0049: no two spec files share a fixture directory)
local CACHE = "." .. "cache/"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = { FAKE_DIR = h.fakes, PATH = `{h.bin}:{process.env.PATH}` }
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
local function pushes(): number
	local text = if fs.isFile(`{h.fakes}/beatpush`) then fs.readFile(`{h.fakes}/beatpush`) else ""
	return #string.gsub(text, "[^\n]", "")
end
local function alive(pid: string): boolean
	return process.exec("kill", { "-0", pid }).ok
end
-- waits up to `seconds` for the process to end
local function endsWithin(pid: string, seconds: number): boolean
	local deadline = os.time() + seconds
	while os.time() < deadline do
		if not alive(pid) then
			return true
		end
		task.wait(0.5)
	end
	return not alive(pid)
end
-- waits (up to `seconds`) until the beater has pushed a beat of its own, which it makes once it is in its loop: a fact
-- changed before that is refused at its start, not seen by the loop
local function firstPush(after: number, seconds: number): boolean
	local deadline = os.time() + seconds
	while os.time() < deadline do
		if pushes() > after then
			return true
		end
		task.wait(0.5)
	end
	return pushes() > after
end
local function pidOf(dir: string, id: string): string
	local text = fs.readFile(`{dir}/.cache/tracker-beater/{id}`)
	return string.match(text, "^(%d+) %d+") or error(`no pid in {text}`)
end
local SHIM =
	'#!/bin/sh\nif [ "$1" = push ]; then case "$*" in *":refs/heads/hb/"*) echo p >> "$FAKE_DIR/beatpush";; esac; fi\n'
local EVERY = { ZN_BEATER = "1", ZN_BEAT_EVERY = "1" }

return t.spec("c0275 real-time proofs: the background beater", function(it)
	it("sets up three claimable issues in three worktrees", function()
		h = fakecli.new("c0275-beater", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0100/c0100.md`] = trackerfix.stub("c0100", "c0100", "new-a-b-c"),
			[`{P}/c0101/c0101.md`] = trackerfix.stub("c0101", "c0101", "new-a-b-c"),
			[`{P}/c0102/c0102.md`] = trackerfix.stub("c0102", "c0102", "new-a-b-c"),
			[`{P}/c0104/c0104.md`] = trackerfix.stub("c0104", "c0104", "new-a-b-c"),
			[`{P}/c0104/c0104.md`] = trackerfix.stub("c0104", "c0104", "new-a-b-c"),
			[`{P}/c0105/c0105.md`] = trackerfix.stub("c0105", "c0105", "new-a-b-c"),
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		fs.writeFile(`{h.bin}/git`, (string.gsub(fs.readFile(`{h.bin}/git`), "^#!/bin/sh\n", SHIM, 1)))
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-beater" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-beater-2" }), "worktree"), "%s+$", ""))
		wt3 = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-beater-3" }), "worktree"), "%s+$", ""))
		wt4 = (string.gsub(must(zn(h.f.main, { "worktree", "c0275-beater-4" }), "worktree"), "%s+$", ""))
	end)

	it(
		"a claim's beater outlives the command that started it, beats while no command runs, and ends with its worktree",
		function()
			must(zn(wt, { "status", "c0100", "preparing" }, EVERY), "claim c0100")
			local pid = pidOf(wt, "c0100")
			t.expect(alive(pid)).toBe(true) -- the command is over; the beater is not
			local text = fs.readFile(`{wt}/.cache/tracker-beater/c0100`)
			local deadline = tonumber(string.match(text, "^%d+ (%d+)")) :: number
			t.expect(deadline > os.time() + 3500 and deadline <= os.time() + 3600).toBe(true) -- its hour
			local before = pushes()
			task.wait(5)
			t.expect(pushes() >= before + 2).toBe(true) -- beats made by no command
			t.expect(alive(pid)).toBe(true)
			-- its worktree is moved away (c0277 renames the old one): it ends within seconds, saying so in its log, which its open
			-- file still writes under the new name
			fs.move(wt, `{wt}-old`)
			t.expect(endsWithin(pid, 20)).toBe(true)
			t.expect(has(fs.readFile(`{wt}-old/.cache/tracker-beater/c0100.log`), "its worktree is gone"))
				.toBe(true)
		end
	)

	it("a beater ends, saying why, when its worktree no longer holds the claim", function()
		local seen = pushes()
		must(zn(wt2, { "status", "c0101", "preparing" }, EVERY), "claim c0101")
		t.expect(firstPush(seen + 2, 30)).toBe(true) -- the claim's own first beat, then a tick of the beater's own
		local pid = pidOf(wt2, "c0101")
		t.expect(alive(pid)).toBe(true)
		-- the memory of the claim is gone from the worktree while main still shows the claim
		fs.removeFile(`{wt2}/{CACHE}tracker-stamp-c0101`)
		if fs.isFile(`{wt2}/{CACHE}tracker-claim-c0101`) then
			fs.removeFile(`{wt2}/{CACHE}tracker-claim-c0101`)
		end
		t.expect(endsWithin(pid, 20)).toBe(true)
		t.expect(
			has(
				fs.readFile(`{wt2}/.cache/tracker-beater/c0101.log`),
				"its worktree no longer holds the claim"
			)
		)
			.toBe(true)
	end)

	it("a beater ends when its claim is given back", function()
		must(zn(wt2, { "status", "c0104", "preparing" }, EVERY), "claim c0104")
		local pid = pidOf(wt2, "c0104")
		t.expect(alive(pid)).toBe(true)
		must(zn(wt2, { "status", "c0104", "new" }, EVERY), "give c0104 back")
		t.expect(endsWithin(pid, 20)).toBe(true)
	end)

	it("a beater ends when its worktree is removed", function()
		must(zn(wt4, { "status", "c0105", "preparing" }, EVERY), "claim c0105")
		local pid = pidOf(wt4, "c0105")
		t.expect(alive(pid)).toBe(true)
		fixture.git(h.f.main, { "worktree", "remove", "--force", wt4 })
		t.expect(endsWithin(pid, 20)).toBe(true)
	end)

	it("beat --watch --session stops within seconds of that process, and beat while it ran", function()
		must(zn(wt3, { "status", "c0102", "preparing" }), "claim c0102")
		local before = pushes()
		local started = os.time()
		local r = fixture.exec(wt3, "sh", {
			"-c",
			-- the session is orphaned to init at once, so it is reaped when it ends (a child nobody waits for stays a zombie,
			-- and a zombie still answers kill -0)
			'p=$(sleep 4 >/dev/null 2>&1 & echo $!); exec bash scripts/tracker.sh beat c0102 --watch --session "$p"',
		}, {
			env = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_BEAT_EVERY = "1",
				ZN_BOUNDED_DEADLINE = tostring(os.time() + 90),
			},
		})
		if not (r.ok and has(r.stdout, "its session ended")) then
			error(`the loop ended differently ({r.code}): {r.stdout}{r.stderr}`)
		end
		t.expect(os.time() - started < 40).toBe(true) -- well before its bound (90 s)
		t.expect(pushes() >= before + 2).toBe(true) -- it beat while the session lived
	end)
end)
