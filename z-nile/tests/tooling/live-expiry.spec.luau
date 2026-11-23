--!strict
-- f0420 step 4c (pure): the notice a worker that lost its claim is shown, the history line of `work status`, and the
-- carrier rows an expiry frees. The daemon's own rules (expiry, marker, restart, race) are Go tests in go/internal/live.
local fs = require("@lune/fs")
local live = require("@tests/lib/live")
local liveloss = require("@znile/engine/liveloss")
local liveview = require("@znile/engine/liveview")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local work = require("@znile/engine/work")
local workerlive = require("@znile/engine/workerlive")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function decode(text: string): { [string]: any }
	local first = string.match(text, "^[^\n]+") or ""
	local ok, v = pcall(serde.decode, "json" :: "json", first)
	return if ok and type(v) == "table" then v else {}
end

local function sleeper(): number
	local r = process.exec("sh", { "-c", "sleep 60 </dev/null >/dev/null 2>&1 & echo $!" })
	return tonumber((string.gsub(r.stdout, "%s+", ""))) :: number
end

-- The first op starts the daemon with these limits (a named state directory takes them): a claim expires after 2 s of silence.
local function start(l: live.Live, worker: string, pid: number)
	local r = l:zn({
		"register",
		"--worker",
		worker,
		"--cli",
		"fake",
		"--pid",
		tostring(pid),
		"--lost-after",
		"1",
		"--expire-after",
		"2",
	})
	t.expect(r.code).toBe(0)
end

local function untilLoss(l: live.Live): boolean
	for _ = 1, 100 do
		if #((decode(l:zn({ "losses" }).stdout).losses or {}) :: { any }) > 0 then
			return true
		end
		task.wait(0.1)
	end
	return false
end

-- Runs the bounded runner on `sleep 3` with a beat every second whose command appends a line to a file; returns the lines.
local function beats(limit: string, env: { [string]: string }): number
	local dir = `{process.cwd}/.cache/live-expiry-bounded`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	local e: { [string]: string } =
		{ ZN_BOUNDED_BEAT_SECONDS = "1", ZN_BOUNDED_BEAT_CMD = `echo b >> {dir}/beats`, ZN_LIVE = "" }
	for k, v in env do
		e[k] = v
	end
	local r = process.exec(
		"perl",
		{ `{ROOT}/z-nile/lib/bounded.pl`, "--time", limit, "--", "sleep", "3" },
		{ env = e } :: any
	)
	t.expect(r.ok).toBe(true)
	if not fs.isFile(`{dir}/beats`) then
		return 0
	end
	local n = 0
	for _ in string.gmatch(fs.readFile(`{dir}/beats`), "b\n") do
		n += 1
	end
	return n
end

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local LOSS: liveloss.Loss = {
	worker = "claude-7@h",
	unit = "R0100",
	activity = "code",
	at = 1_700_000_000,
	since = 1_699_990_000,
	reason = "silent for 1800 s",
	holder = "grok-3@h",
	session = "sess-1",
}

return t.spec("f0420 step 4c: claim expiry, as the worker and the board see it", function(it)
	it("the notice names the unit, the activity, the time, the holder and what to do", function()
		local text = liveloss.notice(LOSS, 1_700_000_100)
		t.expect(string.sub(text, 1, 10)).toBe("LOST CLAIM")
		t.expect(has(text, "R0100")).toBe(true)
		t.expect(has(text, "code")).toBe(true)
		t.expect(has(text, "grok-3@h")).toBe(true)
		t.expect(has(text, "PST") or has(text, "PDT")).toBe(true)
		t.expect(has(text, "do not push")).toBe(true)
		t.expect(has(text, "./zn work next")).toBe(true)
	end)

	it("the notice says so when nobody holds the unit now", function()
		local free = table.clone(LOSS)
		free.holder = nil
		t.expect(has(liveloss.notice(free, 1_700_000_100), "nobody holds it now")).toBe(true)
	end)

	it("the answer of work next is a wait that starts with the notice", function()
		local d = liveloss.answer({ LOSS }, 1_700_000_100)
		t.expect(d.action).toBe("wait")
		t.expect(string.sub(d.why, 1, 10)).toBe("LOST CLAIM")
		t.expect(d.raft).toBe("")
	end)

	it("freeCarriers drops only the rows of the lost worker's session on that unit", function()
		local carriers = {
			R0100 = { session = "sess-1", age = 5 },
			R0200 = { session = "sess-1", age = 5 },
			R0300 = { session = "sess-2", age = 5 },
		}
		local freed = liveloss.freeCarriers(carriers, { LOSS })
		t.expect(freed.R0100).toBe(nil)
		t.expect(freed.R0200 ~= nil).toBe(true)
		t.expect(freed.R0300 ~= nil).toBe(true)
		t.expect(carriers.R0100 ~= nil).toBe(true) -- the input is not changed
	end)

	it("work status shows an expired claim as expired, with the time, and who holds it now", function()
		local view = liveview.slim({
			ok = true,
			at = 1_700_000_100,
			workers = {},
			claims = {},
			losses = { LOSS },
		} :: any)
		t.expect(view ~= nil).toBe(true)
		local lines = liveview.lossLines(view :: any)
		t.expect(#lines).toBe(1)
		t.expect(has(lines[1], "R0100")).toBe(true)
		t.expect(has(lines[1], "expired")).toBe(true)
		t.expect(has(lines[1], "claude-7@h")).toBe(true)
		t.expect(has(lines[1], "grok-3@h")).toBe(true)
	end)

	it(
		"a long bounded command beats at its start and every interval, a short one or a layer that is off never",
		function()
			t.expect(beats("20", {}) >= 3).toBe(true)
			t.expect(beats("20", { ZN_BOUNDED_BEAT_SECONDS = "100" })).toBe(0) -- a command that cannot outlast one interval needs no beat
			t.expect(beats("20", { ZN_LIVE = "off" })).toBe(0)
		end
	)

	it("a daemon frees a silent worker's claim, tells the worker once, and hands the unit on", function()
		live.with("f0420-expiry-cli", nil, function(l)
			local pid = sleeper()
			start(l, "A", pid)
			t.expect(l:zn({ "claim", "--worker", "A", "--unit", "u1", "--activity", "code" }).code).toBe(0)
			t.expect(untilLoss(l)).toBe(true)
			t.expect(#(decode(l:zn({ "claims" }).stdout).claims :: { any })).toBe(0)
			local late = decode(l:zn({ "beat", "--worker", "A" }).stdout)
			t.expect(#(late.losses :: { any })).toBe(1)
			t.expect(late.losses[1].unit).toBe("u1")
			-- B is handed the unit; the old worker's claim of it is refused
			l:zn({ "register", "--worker", "B", "--cli", "fake", "--pid", tostring(pid) })
			t.expect(l:zn({ "claim", "--worker", "B", "--unit", "u1", "--activity", "code" }).code).toBe(0)
			t.expect(l:zn({ "claim", "--worker", "A", "--unit", "u1", "--activity", "code" }).code).toBe(1)
			local all = decode(l:zn({ "losses" }).stdout).losses
			t.expect(all[1].holder).toBe("B")
			t.expect(l:zn({ "notice", "--worker", "A" }).code).toBe(0)
			t.expect(#(decode(l:zn({ "beat", "--worker", "A" }).stdout).losses :: { any })).toBe(0)
			t.expect(#(decode(l:zn({ "losses" }).stdout).losses :: { any })).toBe(1) -- the history stays
			process.exec("kill", { tostring(pid) })
		end)
	end)

	it("work next of the worker that lost a claim answers with the loss once, and claims nothing", function()
		live.with("f0420-expiry-next", nil, function(l)
			local pid = sleeper()
			start(l, "A", pid)
			l:zn({ "claim", "--worker", "A", "--unit", "c0090", "--activity", "draft" })
			t.expect(untilLoss(l)).toBe(true)
			local saved: { [string]: string? } = {}
			local names = {
				"ZN_LIVE",
				"ZN_LIVE_BIN",
				"ZN_LIVE_DIR",
				"ZN_LIVE_ROOT",
				"ZN_LIVE_ALLOW_DEFAULT",
				"ZN_LIVE_NO_START",
				"ZN_LIVE_SOCKDIR",
				"ZN_WORKER",
			}
			for _, n in names do
				saved[n] = process.env[n]
				process.env[n] = l.env[n] or ""
			end
			process.env.ZN_WORKER = "A"
			local input: any = { rafts = {}, issues = {}, session = "s" }
			local first = workerlive.decide(work, input)
			local second = workerlive.decide(work, { rafts = {}, issues = {}, session = "s" })
			for _, n in names do
				process.env[n] = saved[n] or ""
			end
			process.exec("kill", { tostring(pid) })
			t.expect(first.action).toBe("wait")
			t.expect(string.sub(first.why, 1, 10)).toBe("LOST CLAIM")
			t.expect(string.find(first.why, "c0090", 1, true) ~= nil).toBe(true)
			t.expect(string.sub(second.why or "", 1, 10) ~= "LOST CLAIM").toBe(true)
			t.expect(#(decode(l:zn({ "claims" }).stdout).claims :: { any })).toBe(0)
		end)
	end)
end)
