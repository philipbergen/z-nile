--!strict
-- f0420 step 4b, the worker uses the live layer: `./zn work next` registers its session as a worker, beats, claims the unit
-- its action names and gives it up on the next action. Every case builds its own tracker fixture (two backlog tickets,
-- c0090 and c0091, both to be designed) and its own live daemon in a named state folder under .cache, runs the real
-- `./zn work next` of that fixture with ZN_LIVE_BIN set to this checkout's build, and asks the DAEMON what it holds (the
-- znlive binary, not the command's own output). A worker is a terminal: its own ZN_WORKER_PID (a `sleep` the spec starts),
-- its own ZN_ACCOUNT. No case touches the real repository's live state: ZN_LIVE_DIR is always an absolute fixture folder.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local live = require("@tests/lib/live")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local NEW = "new-amber-otter-marble"

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function item(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-16\nstatus: {NEW}\n---\n\n# {id}\n\n## Problem\nx\n`
end

type World = {
	f: trackerfix.Fixture,
	l: live.Live,
	pids: { [string]: number },
	next: (self: World, who: string, args: { string }?, extra: { [string]: string }?) -> fixture.Result,
	ask: (self: World, op: string) -> { [string]: any },
	workers: (self: World) -> { any },
	claims: (self: World) -> { any },
	events: (self: World) -> { any },
	kill: (self: World, who: string) -> (),
}

local function start(): number
	local r = process.exec("sh", { "-c", "sleep 300 >/dev/null 2>&1 & echo $!" })
	return tonumber((string.match(r.stdout, "%d+"))) :: number
end

-- A fresh tracker fixture, a fresh daemon, three terminals (A, B and C: a pid each), cleaned up whatever the body does.
local function world(name: string, body: (w: World) -> ())
	live.with(`f0420-wl-{name}`, nil, function(l)
		local f = trackerfix.new(`f0420-wk-{name}`, {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			[`{ROOT}/issues/c0090/c0090.md`] = item("c0090"),
			[`{ROOT}/issues/c0091/c0091.md`] = item("c0091"),
		})
		-- the daemon, started with the short limits of a fixture (an emit is a write: it starts one)
		l:zn({ "emit", "spec-start" })
		local w: World = { f = f, l = l, pids = { A = start(), B = start(), C = start() } } :: any
		local function env(who: string?, extra: { [string]: string }?): { [string]: string }
			local e = table.clone(l.env)
			e.ZN_CLI = "claude"
			e.ZN_ACCOUNT = ""
			e.ZN_WORKER_PID = if who then tostring(w.pids[who]) else ""
			for k, v in (extra or {}) :: { [string]: string } do
				e[k] = v
			end
			return e
		end
		function w.next(this: World, who: string, args: { string }?, extra: { [string]: string }?): fixture.Result
			local argv = { "work", "next" }
			for _, a in (args or {}) :: { string } do
				table.insert(argv, a)
			end
			local e = env(who, { ZN_ACCOUNT = `acct-{who}` })
			for k, v in (extra or {}) :: { [string]: string } do
				e[k] = v
			end
			local argv2 = { "scripts/tracker.sh" }
			for _, a in argv do
				table.insert(argv2, a)
			end
			return fixture.exec(this.f.main, "bash", argv2, { env = e })
		end
		function w.ask(this: World, op: string): { [string]: any }
			local r = fixture.exec(this.f.main, this.l.bin, { op }, { env = env(nil) })
			local line = string.match(r.stdout, "^[^\n]+")
			if line == nil then
				return {}
			end
			return serde.decode("json" :: "json", line) :: any
		end
		function w.workers(this: World): { any }
			return (this:ask("workers").workers or {}) :: { any }
		end
		function w.claims(this: World): { any }
			return (this:ask("claims").claims or {}) :: { any }
		end
		function w.events(this: World): { any }
			local r = fixture.exec(this.f.main, this.l.bin, { "events" }, { env = env(nil) })
			local out: { any } = {}
			for line in string.gmatch(r.stdout, "[^\n]+") do
				table.insert(out, serde.decode("json" :: "json", line))
			end
			return out
		end
		function w.kill(this: World, who: string)
			process.exec("kill", { tostring(this.pids[who]) })
		end
		local ok, err = pcall(body, w)
		for _, pid in w.pids do
			process.exec("kill", { "-9", tostring(pid) })
		end
		if not ok then
			error(err, 0)
		end
	end)
end

local function byId(workers: { any }, id: string): any?
	for _, x in workers do
		if x.id == id then
			return x
		end
	end
	return nil
end

local function claimOf(claims: { any }, unit: string): any?
	for _, c in claims do
		if c.unit == unit then
			return c
		end
	end
	return nil
end

local function wait(cond: () -> boolean, seconds: number)
	for _ = 1, seconds * 10 do
		if cond() then
			return
		end
		task.wait(0.1)
	end
end

return t.spec("f0420 step 4b: a worker uses the live layer", function(it)
	it("AC40 a session that runs work next is registered: its cli, its pid, its account and what it can deliver", function()
		world("register", function(w)
			local r = w:next("A")
			t.expect(r.ok).toBe(true)
			local workers = w:workers()
			t.expect(#workers).toBe(1)
			local me = workers[1]
			t.expect(me.cli).toBe("claude")
			t.expect(me.account).toBe("acct-A")
			t.expect(string.find(me.id, `^claude%-{w.pids.A}@`) ~= nil).toBe(true)
			-- what it can deliver is what `./zn model --can` tells for claude (asked of the command, not of the module)
			local can = fixture.exec(w.f.main, "bash", { "scripts/tracker.sh", "model", "--can", "--cli", "claude" })
			local want = string.gsub(can.stdout, "%s+$", "")
			t.expect(want ~= "").toBe(true)
			t.expect(table.concat(me.can, ",")).toBe(want)
		end)
	end)

	it("AC40 registering twice is one worker and one registered event", function()
		world("twice", function(w)
			w:next("A")
			w:next("A")
			t.expect(#w:workers()).toBe(1)
			local registered = 0
			for _, e in w:events() do
				if e.kind == "registered" then
					registered += 1
				end
			end
			t.expect(registered).toBe(1)
		end)
	end)

	it("AC41 every work next beats the heartbeat", function()
		world("beat", function(w)
			w:next("A")
			local first = w:workers()[1].heard
			task.wait(0.3)
			w:next("A")
			local second = w:workers()[1].heard
			t.expect(second > first).toBe(true)
		end)
	end)

	it("AC41 the unit and the activity the worker was given are its claim", function()
		world("claim", function(w)
			local r = w:next("A")
			t.expect(string.find(r.stdout, "^c0090: draft %- ") ~= nil).toBe(true)
			local mine = byId(w:workers(), (w:workers()[1] :: any).id)
			local c = claimOf(w:claims(), "c0090")
			t.expect(c ~= nil).toBe(true)
			t.expect((c :: any).activity).toBe("draft")
			t.expect((c :: any).worker).toBe((mine :: any).id)
			t.expect(#w:claims()).toBe(1)
		end)
	end)

	it("AC42 two workers at once: both registered, the second is not given the unit the first holds", function()
		world("two", function(w)
			local a = w:next("A")
			local b = w:next("B")
			t.expect(string.find(a.stdout, "^c0090: draft %- ") ~= nil).toBe(true)
			t.expect(string.find(b.stdout, "^c0091: draft %- ") ~= nil).toBe(true)
			local workers = w:workers()
			t.expect(#workers).toBe(2)
			t.expect(workers[1].id ~= workers[2].id).toBe(true)
			t.expect(workers[1].account ~= workers[2].account).toBe(true)
			local c0090, c0091 = claimOf(w:claims(), "c0090"), claimOf(w:claims(), "c0091")
			t.expect(c0090 ~= nil and c0091 ~= nil).toBe(true)
			t.expect((c0090 :: any).worker ~= (c0091 :: any).worker).toBe(true)
		end)
	end)

	it("AC42 a unit another worker holds is refused when named, and the answer names the holder", function()
		world("named", function(w)
			w:next("A")
			local holder = (claimOf(w:claims(), "c0090") :: any).worker
			local b = w:next("B", { "c0090" })
			t.expect(b.ok).toBe(true)
			t.expect(has(b.stdout, holder)).toBe(true)
			t.expect(string.find(b.stdout, "^c0090: draft %- ") == nil).toBe(true)
			t.expect((claimOf(w:claims(), "c0090") :: any).worker).toBe(holder)
			t.expect(#w:claims()).toBe(1)
		end)
	end)

	it("AC42 when the first worker releases, the second can take the unit", function()
		world("release", function(w)
			w:next("A")
			-- A's next action ends its activity (nothing to do: the id is not in the tracker)
			w:next("A", { "c0099" })
			t.expect(#w:claims()).toBe(0)
			local b = w:next("B", { "c0090" })
			t.expect(string.find(b.stdout, "^c0090: draft %- ") ~= nil).toBe(true)
			local c = claimOf(w:claims(), "c0090")
			t.expect(c ~= nil).toBe(true)
			local bId = nil
			for _, x in w:workers() do
				if x.account == "acct-B" then
					bId = x.id
				end
			end
			t.expect((c :: any).worker).toBe(bId)
		end)
	end)

	it("AC43 the claim ends with the next action: a worker holds one unit, the one it was last given", function()
		world("moves", function(w)
			w:next("A", { "c0090" })
			t.expect(claimOf(w:claims(), "c0090") ~= nil).toBe(true)
			w:next("A", { "c0091" })
			local claims = w:claims()
			t.expect(#claims).toBe(1)
			t.expect(claims[1].unit).toBe("c0091")
		end)
	end)

	it("AC43 a worker whose process is gone is lost by the daemon and its unit is free for another", function()
		world("gone", function(w)
			w:next("A")
			w:next("B")
			w:kill("A")
			wait(function()
				return claimOf(w:claims(), "c0090") == nil
			end, 8)
			t.expect(claimOf(w:claims(), "c0090") == nil).toBe(true)
			local b = w:next("B")
			t.expect(string.find(b.stdout, "^c0090: draft %- ") ~= nil).toBe(true)
			local claims = w:claims()
			t.expect(#claims).toBe(1)
			t.expect(claims[1].unit).toBe("c0090")
		end)
	end)

	it("AC44 with the layer off the output and the exit code are the layer-on answer's, and nothing is registered", function()
		world("off", function(w)
			local seq = { {}, { "c0091" }, { "c0099" }, { "--one" } }
			local on: { fixture.Result } = {}
			for _, args in seq do
				table.insert(on, w:next("C", args))
				w:next("C", { "c0099" }) -- ends C's activity, so the next call starts the same
			end
			local before = #w:workers()
			for i, args in seq do
				local off = w:next("C", args, { ZN_LIVE = "off" })
				t.expect(off.stdout).toBe(on[i].stdout)
				t.expect(off.stderr).toBe(on[i].stderr)
				t.expect(off.code).toBe(on[i].code)
			end
			t.expect(#w:workers()).toBe(before) -- off registers nothing new
			t.expect(string.find(on[1].stdout, "^c0090: draft %- ") ~= nil).toBe(true)
		end)
	end)

	it("AC44 with no daemon binary or a refusing one the answer is the same, with no message", function()
		world("nobin", function(w)
			local base = w:next("C", {}, { ZN_LIVE = "off" })
			local missing = w:next("C", {}, { ZN_LIVE_BIN = `{w.f.base}/missing` })
			local refusing = `{w.f.base}/refuse`
			local log = `{w.f.base}/refuse.log`
			fs.writeFile(refusing, `#!/bin/sh\necho "$*" >> "{log}"\nexit 3\n`)
			process.exec("chmod", { "+x", refusing })
			local dead = w:next("C", {}, { ZN_LIVE_BIN = refusing })
			for _, r in { missing, dead } do
				t.expect(r.stdout).toBe(base.stdout)
				t.expect(r.stderr).toBe(base.stderr)
				t.expect(r.code).toBe(base.code)
			end
			-- the first refusal ends the attempt: one call, not one per step
			local calls = 0
			for _ in string.gmatch(if fs.isFile(log) then fs.readFile(log) else "", "[^\n]+") do
				calls += 1
			end
			t.expect(calls).toBe(1) -- the dead layer was asked exactly once
		end)
	end)

	it("AC45 an account label that is not a short safe word is not sent, and the command still works", function()
		world("label", function(w)
			local bad = w:next("A", {}, { ZN_ACCOUNT = "x y;touch /tmp/pwned" })
			t.expect(bad.ok).toBe(true)
			t.expect(string.find(bad.stdout, "^c0090: draft %- ") ~= nil).toBe(true)
			local me = w:workers()[1]
			t.expect(me ~= nil).toBe(true)
			t.expect(me.account).toBe(nil)
			w:next("B", {}, { ZN_ACCOUNT = "Work.acct-2_b" })
			local good
			for _, x in w:workers() do
				if x.cli == "claude" and x.account ~= nil then
					good = x
				end
			end
			t.expect(good.account).toBe("Work.acct-2_b")
			local long = w:next("C", {}, { ZN_ACCOUNT = string.rep("x", 33) })
			t.expect(long.ok).toBe(true)
			for _, x in w:workers() do
				t.expect(x.account == nil or #x.account <= 32).toBe(true)
			end
		end)
	end)

	it("AC45 no worker is registered in a default state folder from inside a spec", function()
		world("default", function(w)
			local before = #w:workers()
			local r = w:next("A", {}, {
				ZN_LIVE_DIR = "",
				ZN_LIVE_ROOT = w.f.main,
				ZN_LIVE_ALLOW_DEFAULT = "",
				PICKMAN_FENCE_SPECS = "1",
			})
			t.expect(r.ok).toBe(true)
			t.expect(string.find(r.stdout, "^c0090: draft %- ") ~= nil).toBe(true)
			t.expect(fs.isDir(`{w.f.main}/.cache/live`)).toBe(false)
			t.expect(#w:workers()).toBe(before)
		end)
	end)

	it("AC46 the worker module reads no credential and no CLI config: no file, no home, only named variables", function()
		local text = fs.readFile(`{TOP}/z-nile/engine/workerlive.luau`)
		for _, word in { "readFile", "readDir", "fs.", "HOME", ".claude", ".config", "credential", "token", "email", "keychain", "settings.json" } do
			t.expect(has(string.lower(text), string.lower(word))).toBe(false)
		end
		local allowed = {
			ZN_CLI = true,
			ZN_ACCOUNT = true,
			ZN_WORKER_PID = true,
			CLAUDE_CODE_SESSION_ID = true,
			KIMI_SESSION_ID = true,
			GROK_SESSION_ID = true,
		}
		for name in string.gmatch(text, "process%.env%.([A-Z_]+)") do
			t.expect(allowed[name] == true).toBe(true)
		end
		for name in string.gmatch(text, 'env%["([A-Z_]+)"%]') do
			t.expect(allowed[name] == true).toBe(true)
		end
	end)
end)
