--!strict
-- f0420 step 4b, the worker uses the live layer: `./zn work next` registers its session as a worker, beats, claims the unit
-- its action names and gives it up on the next action. Every case builds its own tracker fixture (two backlog tickets,
-- c0090 and c0091, both to be designed) and its own live daemon in a named state folder under .cache, runs the real
-- `./zn work next` of that fixture with ZN_LIVE_BIN set to this checkout's build, and asks the DAEMON what it holds (the
-- znlive binary, not the command's own output). A worker is a terminal: its own ZN_WORKER_PID (a `sleep` the spec starts),
-- its own ZN_ACCOUNT. No case touches the real repository's live state: ZN_LIVE_DIR is always an absolute fixture folder.
local datetime = require("@lune/datetime")
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
local function world(name: string, body: (w: World) -> (), more: { [string]: string }?)
	live.with(`f0420-wl-{name}`, nil, function(l)
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
			[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		}
		if more == nil then
			seed[`{ROOT}/issues/c0090/c0090.md`] = item("c0090")
			seed[`{ROOT}/issues/c0091/c0091.md`] = item("c0091")
		end
		for path, text in (more or {}) :: { [string]: string } do
			seed[path] = text
		end
		local f = trackerfix.new(`f0420-wk-{name}`, seed)
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
		function w.next(
			this: World,
			who: string,
			args: { string }?,
			extra: { [string]: string }?
		): fixture.Result
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
		local ok, err = pcall(body :: (World) -> any, w)
		for _, pid in l:pids() do
			process.exec("kill", { "-CONT", tostring(pid) }) -- a case may have stopped the daemon: shutdown must reach it
		end
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

local function item2(id: string, raft: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {status}\n---\n\n# {id}\n\n## Problem\nx\n`
end

local PREP = "prepared-quiet-copper-falcon"
local function pitem(id: string, raft: string, deps: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: {raft}\ndepends_on: [{deps}]\nemergent: false\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREP}\n---\n\n# {id}\n\n## Problem\nx\n`
end
local function praft(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREP}\n---\n\n# {id}\n\n## Order & dependencies\n{issues}\n`
end
local RAFT_SEED: { [string]: string } = {
	[`{ROOT}/rafts/R0100/R0100.md`] = praft("R0100", "c0101"),
	[`{ROOT}/issues/c0101/c0101.md`] = pitem("c0101", "R0100", ""),
}
local DEP_SEED: { [string]: string } = {
	[`{ROOT}/rafts/R0090/R0090.md`] = praft("R0090", "c0090"),
	[`{ROOT}/issues/c0090/c0090.md`] = pitem("c0090", "R0090", ""),
	[`{ROOT}/rafts/R0100/R0100.md`] = praft("R0100", "c0100"),
	[`{ROOT}/issues/c0100/c0100.md`] = pitem("c0100", "R0100", "c0090"),
}

return t.spec("f0420 step 4b: a worker uses the live layer", function(it)
	it(
		"AC40 a session that runs work next is registered: its cli, its pid, its account and what it can deliver",
		function()
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
				local can = fixture.exec(
					w.f.main,
					"bash",
					{ "scripts/tracker.sh", "model", "--can", "--cli", "claude" }
				)
				local want = string.gsub(can.stdout, "%s+$", "")
				t.expect(want ~= "").toBe(true)
				t.expect(table.concat(me.can, ",")).toBe(want)
			end)
		end
	)

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
		-- (the claim also raises `heard`, so this case shows the heartbeat moves; the stand-in case below pins the beat call)
		world("beat", function(w)
			w:next("A")
			local first = w:workers()[1].heard
			task.wait(0.3)
			w:next("A")
			local second = w:workers()[1].heard
			t.expect(second > first).toBe(true)
		end)
	end)

	it("AC41 every work next sends the daemon a beat that names the worker, once per call", function()
		-- a recording stand-in for znlive: it answers the ops of a worker and logs every argv
		local f = trackerfix.new("f0420-wk-beatlog", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
			[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			[`{ROOT}/issues/c0090/c0090.md`] = item("c0090"),
		})
		local bin, log = `{f.base}/znlive`, `{f.base}/calls.log`
		fs.writeFile(
			bin,
			'#!/bin/sh\necho "$*" >> "'
				.. log
				.. '"\ncase "$1" in\n'
				.. `  register) echo '\{"ok":true,"seq":1,"worker":"claude-77@h"}' ;;\n`
				.. `  claims) echo '\{"ok":true,"seq":1,"claims":[]}' ;;\n`
				.. `  claim) echo '\{"ok":true,"seq":2,"claim":\{}}' ;;\n`
				.. `  *) echo '\{"ok":true,"seq":1}' ;;\nesac\n`
		)
		process.exec("chmod", { "+x", bin })
		local env =
			{ ZN_LIVE = "", ZN_LIVE_BIN = bin, ZN_LIVE_ROOT = "", ZN_CLI = "claude", ZN_WORKER_PID = "4242" }
		for _ = 1, 2 do
			local r = trackerfix.tr(f, f.main, { "work", "next" }, env)
			t.expect(r.ok).toBe(true)
		end
		local beats, claims = 0, 0
		for line in string.gmatch(fs.readFile(log), "[^\n]+") do
			if line == "beat --worker claude-77@h" then
				beats += 1
			end
			if has(line, "claim --worker claude-77@h --unit c0090 --activity draft") then
				claims += 1
			end
		end
		t.expect(beats).toBe(2)
		t.expect(claims).toBe(2)
	end)

	it("AC42 a unit another worker wins first is left to it: the answer is the next unit, claimed", function()
		-- a stand-in daemon that says c0090 is held by another worker at the moment of the claim (a race the walk cannot see)
		local f = trackerfix.new("f0420-wk-race", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
			[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			[`{ROOT}/issues/c0090/c0090.md`] = item("c0090"),
			[`{ROOT}/issues/c0091/c0091.md`] = item("c0091"),
		})
		local bin, log = `{f.base}/znlive`, `{f.base}/calls.log`
		fs.writeFile(
			bin,
			'#!/bin/sh\necho "$*" >> "'
				.. log
				.. '"\ncase "$1" in\n'
				.. `  register) echo '\{"ok":true,"seq":1,"worker":"claude-77@h"}' ;;\n`
				.. `  claims) echo '\{"ok":true,"seq":1,"claims":[]}' ;;\n`
				.. `  claim) case "$*" in *c0090*) echo '\{"ok":false,"refused":"held","holder":"grok-9@h","unit":"c0090","activity":"draft"}'; exit 1 ;; esac; echo '\{"ok":true,"seq":2,"claim":\{}}' ;;\n`
				.. `  *) echo '\{"ok":true,"seq":1}' ;;\nesac\n`
		)
		process.exec("chmod", { "+x", bin })
		local env =
			{ ZN_LIVE = "", ZN_LIVE_BIN = bin, ZN_LIVE_ROOT = "", ZN_CLI = "claude", ZN_WORKER_PID = "4242" }
		local r = trackerfix.tr(f, f.main, { "work", "next" }, env)
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, "^c0091: draft %- ") ~= nil).toBe(true)
		local last = ""
		for line in string.gmatch(fs.readFile(log), "[^\n]+") do
			if string.sub(line, 1, 6) == "claim " then
				last = line
			end
		end
		t.expect(has(last, "--unit c0091 --activity draft")).toBe(true)
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

	it(
		"AC42 two workers at once: both registered, the second is not given the unit the first holds",
		function()
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
		end
	)

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

	it(
		"AC43 the claim ends with the next action: a worker holds one unit, the one it was last given",
		function()
			world("moves", function(w)
				w:next("A", { "c0090" })
				t.expect(claimOf(w:claims(), "c0090") ~= nil).toBe(true)
				w:next("A", { "c0091" })
				local claims = w:claims()
				t.expect(#claims).toBe(1)
				t.expect(claims[1].unit).toBe("c0091")
			end)
		end
	)

	it(
		"AC43 a worker whose process is gone is lost by the daemon and its unit is free for another",
		function()
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
		end
	)

	it(
		"AC44 with the layer off the output and the exit code are a non-worker's, silent, and nothing is registered",
		function()
			world("off", function(w)
				local plain = { ZN_CLI = "", ZN_WORKER_PID = "", ZN_ACCOUNT = "" } -- no CLI: not a worker at all
				local seq = { {}, { "c0091" }, { "c0099" }, { "--one" } }
				for _, args in seq do
					local base = w:next("C", args, plain)
					t.expect(base.stderr).toBe("")
					local off = w:next("C", args, { ZN_LIVE = "off" })
					local on = w:next("C", args)
					w:next("C", { "c0099" }) -- ends C's activity, so the next call starts the same
					for _, r in { off, on } do
						t.expect(r.stdout).toBe(base.stdout)
						t.expect(r.stderr).toBe("")
						t.expect(r.code).toBe(base.code)
					end
				end
				t.expect(#w:workers()).toBe(1) -- only the layer-on terminal registered: the plain and the off ones did not
				t.expect(string.find(w:next("C", {}, plain).stdout, "^c0090: draft %- ") ~= nil).toBe(true)
			end)
		end
	)

	it(
		"AC44 with no daemon binary, or one that refuses with exit 1, 2 or 3, the answer is a non-worker's and silent",
		function()
			world("nobin", function(w)
				local plain = { ZN_CLI = "", ZN_WORKER_PID = "", ZN_ACCOUNT = "" }
				local base = w:next("C", {}, plain)
				t.expect(base.stderr).toBe("")
				local missing = w:next("C", {}, { ZN_LIVE_BIN = `{w.f.base}/missing` })
				t.expect(missing.stdout).toBe(base.stdout)
				t.expect(missing.stderr).toBe("")
				t.expect(missing.code).toBe(base.code)
				for _, code in { 1, 2, 3 } do
					local refusing = `{w.f.base}/refuse{code}`
					local log = `{w.f.base}/refuse{code}.log`
					fs.writeFile(refusing, `#!/bin/sh\necho "$*" >> "{log}"\nexit {code}\n`)
					process.exec("chmod", { "+x", refusing })
					local dead = w:next("C", {}, { ZN_LIVE_BIN = refusing })
					t.expect(dead.stdout).toBe(base.stdout)
					t.expect(dead.stderr).toBe("")
					t.expect(dead.code).toBe(base.code)
					-- the first refusal ends the attempt: one call, not one per step
					local calls = 0
					for _ in string.gmatch(if fs.isFile(log) then fs.readFile(log) else "", "[^\n]+") do
						calls += 1
					end
					t.expect(calls).toBe(1)
				end
			end)
		end
	)

	it(
		"AC44 a daemon that is stopped answers within the call budget and the output is a non-worker's",
		function()
			world("slow", function(w)
				local function now(): number
					return datetime.now().unixTimestampMillis / 1000
				end
				w:next("A") -- registered, so the stopped daemon is one it knows
				local plain = { ZN_CLI = "", ZN_WORKER_PID = "", ZN_ACCOUNT = "" }
				local t0 = now()
				local base = w:next("C", {}, plain)
				local baseline = now() - t0
				for _, pid in w.l:pids() do
					process.exec("kill", { "-STOP", tostring(pid) })
				end
				local t1 = now()
				local slow = w:next("A", { "c0091" })
				local took = now() - t1
				t.expect(slow.ok).toBe(true)
				t.expect(slow.stderr).toBe("")
				t.expect(string.find(slow.stdout, "^c0091: draft %- ") ~= nil).toBe(true)
				-- the budget is 2 s and the first failed call ends the attempt: baseline plus the budget plus a margin
				t.expect(took < baseline + 2 + 4).toBe(true)
				t.expect(base.stderr).toBe("")
			end)
		end
	)

	it(
		"AC45 an account label that is not a short safe word is not sent, and the command still works",
		function()
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
				t.expect(has(long.stderr, "ZN_ACCOUNT")).toBe(true) -- one hint: the label was dropped
				local found = nil
				for _, x in w:workers() do
					if string.find(x.id, `^claude%-{w.pids.C}@`) then
						found = x
					end
				end
				t.expect(found ~= nil).toBe(true) -- registered all the same
				t.expect((found :: any).account).toBe(nil)
			end)
		end
	)

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

	it(
		"AC46 the worker module reads no credential, token, email or CLI config: no file of its own (the capability list is read through git from .models.toml), no dynamic variable, only named ones and named modules",
		function()
			-- the code, not its comments (which say what it never does)
			local text = (
				string.gsub("\n" .. fs.readFile(`{TOP}/z-nile/engine/workerlive.luau`), "\n%s*%-%-[^\n]*", "")
			)
			for _, word in
				{
					"readFile",
					"readDir",
					"fs.",
					"HOME",
					"/.claude",
					"/.config",
					"~/",
					"credential",
					"token",
					"email",
					"keychain",
					"settings.json",
				}
			do
				t.expect(has(string.lower(text), string.lower(word))).toBe(false)
			end
			local allowed = {
				ZN_CLI = true,
				ZN_ACCOUNT = true,
				ZN_WORKER_PID = true,
				CLAUDE_CODE_SESSION_ID = true,
				KIMI_SESSION_ID = true,
				GROK_SESSION_ID = true,
				ZN_DISPATCH = true,
				ZN_LIVE_NO_START = true,
			}
			t.expect(has(text, "process.env[")).toBe(false) -- no dynamic variable name
			local modules = {
				["./livecall"] = true,
				["./liveemit"] = true,
				["./liveview"] = true,
				["./modelcmd"] = true,
				["./models"] = true,
				["../lib/sh"] = true,
				["@lune/process"] = true,
			}
			for mod in string.gmatch(text, 'require%("([^"]+)"%)') do
				t.expect(modules[mod] == true).toBe(true)
			end
			for name in string.gmatch(text, "process%.env%.([A-Z_]+)") do
				t.expect(allowed[name] == true).toBe(true)
			end
			for name in string.gmatch(text, 'env%["([A-Z_]+)"%]') do
				t.expect(allowed[name] == true).toBe(true)
			end
		end
	)

	it("AC42 a named raft another worker holds waits, naming the holder, and the claim stays", function()
		world("heldraft", function(w)
			local a = w:next("A", { "R0100" })
			t.expect(string.find(a.stdout, "^R0100: ") ~= nil).toBe(true)
			local holder = (claimOf(w:claims(), "R0100") :: any).worker
			local b = w:next("B", { "R0100" })
			t.expect(b.ok).toBe(true)
			t.expect(has(b.stdout, `R0100 is held by {holder}`)).toBe(true)
			t.expect(has(b.stdout, "is not landed yet:")).toBe(false)
			t.expect(string.find(b.stdout, "^R0100: wait %- ") ~= nil).toBe(true)
			t.expect((claimOf(w:claims(), "R0100") :: any).worker).toBe(holder)
			t.expect(#w:claims()).toBe(1)
		end, RAFT_SEED)
	end)

	it("AC42 a named raft whose dependency raft another worker holds waits, naming that holder", function()
		world("heldep", function(w)
			w:next("A", { "R0090" })
			local holder = (claimOf(w:claims(), "R0090") :: any).worker
			local b = w:next("B", { "R0100" })
			t.expect(has(b.stdout, `R0090 is held by {holder}`)).toBe(true)
			t.expect(has(b.stdout, "is not landed yet:")).toBe(false)
			t.expect(string.find(b.stdout, "^R0100: wait %- ") ~= nil).toBe(true)
			t.expect(#w:claims()).toBe(1)
		end, DEP_SEED)
	end)

	it("AC42 a named issue another worker holds answers wait, naming the holder", function()
		world("heldissue", function(w)
			w:next("A", { "c0090" })
			local holder = (claimOf(w:claims(), "c0090") :: any).worker
			local b = w:next("B", { "c0090" })
			t.expect(string.find(b.stdout, "^c0090: wait %- ") ~= nil).toBe(true)
			t.expect(has(b.stdout, holder)).toBe(true)
			t.expect(has(b.stdout, "is not landed yet:")).toBe(false)
		end)
	end)

	it(
		"AC42 two workers started at the same instant, round after round, get two units and two claims",
		function()
			world("together", function(w)
				for round = 1, 4 do
					local out: { fixture.Result } = {}
					local left = 2
					local co = coroutine.running()
					for i, who in { "A", "B" } do
						task.spawn(function()
							out[i] = w:next(who)
							left -= 1
							if left == 0 then
								task.spawn(co)
							end
						end)
					end
					coroutine.yield()
					local units = {}
					for _, r in out do
						units[#units + 1] = string.match(r.stdout, "^(c%d+): draft")
					end
					t.expect(#units).toBe(2)
					t.expect(units[1] ~= units[2]).toBe(true)
					t.expect(#w:claims()).toBe(2)
					w:next("A", { "c0099" }) -- both let go before the next round
					w:next("B", { "c0099" })
					t.expect(#w:claims()).toBe(0)
					t.expect(round > 0).toBe(true)
				end
			end)
		end
	)

	it("AC43 ./zn stop gives back the live claim of a raft and of an issue", function()
		local f = trackerfix.new("f0420-wk-stop", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
			[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			[`{ROOT}/rafts/active/R0200/R0200.md`] = `---\nid: R0200\ntype: chore\ntitle: R0200 raft\nslug: R0200\nsingle: false\nissues: [c0201]\ndesign: ready\ncreated: 2026-11-16\nstatus: active-quiet-red-fox\n---\n\n# R0200\n\n## Order & dependencies\nc0201\n`,
			[`{ROOT}/issues/active/c0201/c0201.md`] = item2("c0201", "R0200", "active-quiet-red-fox"),
			[`{ROOT}/issues/active/c0095/c0095.md`] = item2("c0095", "", "active-jolly-silver-walrus"),
		})
		local bin, log = `{f.base}/znlive`, `{f.base}/calls.log`
		fs.writeFile(
			bin,
			'#!/bin/sh\necho "$*" >> "'
				.. log
				.. '"\ncase "$1" in\n'
				.. `  claims) echo '\{"ok":true,"seq":1,"claims":[\{"unit":"R0200","worker":"w-9@h"},\{"unit":"c0095","worker":"w-8@h"}]}' ;;\n`
				.. `  *) echo '\{"ok":true,"seq":1}' ;;\nesac\n`
		)
		process.exec("chmod", { "+x", bin })
		local env = { ZN_LIVE = "", ZN_LIVE_BIN = bin, ZN_LIVE_ROOT = "" }
		t.expect(trackerfix.tr(f, f.main, { "stop", "R0200" }, env).ok).toBe(true)
		t.expect(trackerfix.tr(f, f.main, { "stop", "c0095" }, env).ok).toBe(true)
		local calls = fs.readFile(log)
		t.expect(has(calls, "release --worker w-9@h --unit R0200 --outcome back")).toBe(true)
		t.expect(has(calls, "release --worker w-8@h --unit c0095 --outcome back")).toBe(true)
	end)

	it(
		"AC40 a session with no ZN_WORKER_PID is registered under its CLI's own process, not the zn process",
		function()
			local f = trackerfix.new("f0420-wk-chain", {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
				[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				[`{ROOT}/issues/c0090/c0090.md`] = item("c0090"),
			})
			-- a stand-in ps with a chain it controls: zn's own process, a shell (5001), then the CLI (5002)
			local stub, pslog = `{f.base}/stub`, `{f.base}/ps.log`
			fs.writeDir(stub)
			fs.writeFile(
				`{stub}/ps`,
				'#!/bin/sh\necho "$*" >> "'
					.. pslog
					.. '"\ncase "$4" in\n  5001) echo "5002 bash" ;;\n  5002) echo "1 /usr/local/bin/claude" ;;\n  *) echo "5001 lune" ;;\nesac\n'
			)
			process.exec("chmod", { "+x", `{stub}/ps` })
			local bin, log = `{f.base}/znlive`, `{f.base}/calls.log`
			fs.writeFile(
				bin,
				'#!/bin/sh\necho "$*" >> "'
					.. log
					.. '"\ncase "$1" in\n'
					.. `  register) echo '\{"ok":true,"seq":1,"worker":"claude-5002@h"}' ;;\n`
					.. `  claims) echo '\{"ok":true,"seq":1,"claims":[]}' ;;\n`
					.. `  *) echo '\{"ok":true,"seq":1,"claim":\{}}' ;;\nesac\n`
			)
			process.exec("chmod", { "+x", bin })
			local env = {
				PATH = `{stub}:{process.env.PATH or ""}`,
				ZN_LIVE = "",
				ZN_LIVE_BIN = bin,
				ZN_LIVE_ROOT = "",
				ZN_CLI = "claude",
				ZN_WORKER_PID = "",
			}
			-- no binary: no ps, no lookup at all
			trackerfix.tr(
				f,
				f.main,
				{ "work", "next" },
				{
					PATH = env.PATH,
					ZN_LIVE = "",
					ZN_LIVE_BIN = `{f.base}/missing`,
					ZN_CLI = "claude",
					ZN_WORKER_PID = "",
				}
			)
			t.expect(fs.isFile(pslog)).toBe(false)
			t.expect(trackerfix.tr(f, f.main, { "work", "next" }, env).ok).toBe(true)
			t.expect(has(fs.readFile(log), "register --cli claude --pid 5002 ")).toBe(true)
		end
	)

	it(
		"AC45 an older daemon that refuses --account is retried without the label, with one hint to rebuild",
		function()
			local f = trackerfix.new("f0420-wk-older", {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
				[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				[`{ROOT}/issues/c0090/c0090.md`] = item("c0090"),
			})
			local bin, log = `{f.base}/znlive`, `{f.base}/calls.log`
			fs.writeFile(
				bin,
				'#!/bin/sh\necho "$*" >> "'
					.. log
					.. '"\ncase "$1" in\n'
					.. '  register) case "$*" in *--account*) exit 2 ;; esac; echo \'{"ok":true,"seq":1,"worker":"claude-4242@h"}\' ;;\n'
					.. `  claims) echo '\{"ok":true,"seq":1,"claims":[]}' ;;\n`
					.. `  *) echo '\{"ok":true,"seq":1,"claim":\{}}' ;;\nesac\n`
			)
			process.exec("chmod", { "+x", bin })
			local env = {
				ZN_LIVE = "",
				ZN_LIVE_BIN = bin,
				ZN_LIVE_ROOT = "",
				ZN_CLI = "claude",
				ZN_WORKER_PID = "4242",
				ZN_ACCOUNT = "work",
			}
			local r = trackerfix.tr(f, f.main, { "work", "next" }, env)
			t.expect(r.ok).toBe(true)
			local registers, claims = 0, 0
			for line in string.gmatch(fs.readFile(log), "[^\n]+") do
				if string.sub(line, 1, 9) == "register " then
					registers += 1
				end
				if string.sub(line, 1, 6) == "claim " then
					claims += 1
				end
			end
			t.expect(registers).toBe(2) -- with the label, then without
			t.expect(claims).toBe(1) -- and the worker went on
			local _, hints = string.gsub(r.stderr, "%./zn live build", "")
			t.expect(hints).toBe(1)
		end
	)

	it("AC44 a nested CLI under ./zn dispatch is not registered as a worker of its own", function()
		local f = trackerfix.new("f0420-wk-dispatch", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
			[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			[`{ROOT}/issues/c0090/c0090.md`] = item("c0090"),
		})
		local bin, log = `{f.base}/znlive`, `{f.base}/calls.log`
		fs.writeFile(bin, '#!/bin/sh\necho "$*" >> "' .. log .. '"\nexit 3\n')
		process.exec("chmod", { "+x", bin })
		local env = {
			ZN_LIVE = "",
			ZN_LIVE_BIN = bin,
			ZN_LIVE_ROOT = "",
			ZN_CLI = "claude",
			ZN_WORKER_PID = "4242",
			ZN_DISPATCH = "1",
		}
		local r = trackerfix.tr(f, f.main, { "work", "next" }, env)
		t.expect(r.stderr).toBe("")
		t.expect(fs.isFile(log)).toBe(false) -- the layer was never called: it is the dispatching worker's step
	end)

	it("AC41 the worker's other zn commands beat too, so a long build is not quiet", function()
		world("othercmd", function(w)
			w:next("A")
			local first = w:workers()[1].heard
			task.wait(0.3)
			local env = table.clone(w.l.env)
			env.ZN_CLI, env.ZN_WORKER_PID, env.ZN_ACCOUNT = "claude", tostring(w.pids.A), "acct-A"
			local r = fixture.exec(w.f.main, "bash", { "scripts/tracker.sh", "list" }, { env = env })
			t.expect(r.stderr).toBe("")
			t.expect(w:workers()[1].heard > first).toBe(true)
			t.expect(#w:workers()).toBe(1) -- a beat registers nobody
		end)
	end)
end)
