--!strict
-- f0025 AC3: the real Sessions and Submits sources run here on a stub `game` (this spec's own small stub, not
-- tests/lib/fakeengine, which f0061 pins and f0065 extends). Sessions steps each session once per step that
-- Session.advance grants, hands every step's events to the runs it was started with, sends a frame only while
-- the player is still in the game, and parks a departed session until the runs let it go. Submits turns those
-- events into one HiscoreStore.submit per run through Hiscores. Sessions requires only Maze and Session, so
-- f0065's boot of it (no runs) behaves as today. Session itself is a spy here: its step returns scripted events.
local Hiscores = require("@logic/Hiscores")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local SESSIONS = "src/server/Sessions.luau"
local SUBMITS = "src/server/Submits.luau"
local LOGIC = "@game/ReplicatedStorage/Shared/Logic/"
local ONE = 1 / Session.STEP_RATE

local function source(path: string): string
	return string.gsub(fs.readFile(path), "%-%-[^\n]*", "")
end

type Signal = { fns: { (...any) -> () }, Connect: (any, (...any) -> ()) -> any, fire: (any, ...any) -> () }

local function signal(): Signal
	local s: Signal
	s = {
		fns = {},
		Connect = function(_: any, fn: (...any) -> ()): any
			table.insert(s.fns, fn)
			return { Disconnect = function() end }
		end,
		fire = function(_: any, ...: any)
			for _, fn in s.fns do
				local ok, err = coroutine.resume(coroutine.create(fn), ...)
				if not ok then
					error(err, 0)
				end
			end
		end,
	}
	return s
end

type Heard = { s: any, events: { any }, here: boolean }
type World = {
	mod: any,
	remotes: { [string]: any },
	playersService: any,
	heartbeat: Signal,
	sent: { { remote: string, player: any } },
	made: { any },
	steps: { [any]: number },
	returned: { [any]: { any } },
	script: { [any]: (n: number) -> { any } },
	heard: { Heard },
	readies: { { any } },
	agains: { any },
	keep: { [any]: boolean },
	submits: { { any } },
	againOk: boolean,
	unknown: { string },
	closers: { () -> () },
	clock: number,
	waiting: { { co: thread, due: number } },
	drives: number,
}

local function folder(children: { [string]: any }): any
	return {
		FindFirstChild = function(_: any, name: string): any
			return children[name]
		end,
		WaitForChild = function(_: any, name: string): any
			local found = children[name]
			assert(found ~= nil, `stub: WaitForChild("{name}") would wait for ever`)
			return found
		end,
	}
end

-- runs: "record" (a recorder that answers from w.keep), "submits" (the real Submits on a recording store),
-- or "none" (Sessions.start() with no runs, as f0065's spec boots it)
local function world(runs: string): World
	local w: World = {
		mod = nil,
		remotes = {},
		playersService = nil,
		heartbeat = signal(),
		sent = {},
		made = {},
		steps = {},
		returned = {},
		script = {},
		heard = {},
		readies = {},
		agains = {},
		keep = {},
		submits = {},
		againOk = false,
		unknown = {},
		closers = {},
		clock = 0,
		waiting = {},
		drives = 0,
	}
	for _, name in { "Ready", "Intent", "Snapshot", "PlayAgain", "ToLobby", "LobbyStatus" } do
		w.remotes[name] = {
			Name = name,
			OnServerEvent = signal(),
			FireClient = function(_: any, player: any)
				table.insert(w.sent, { remote = name, player = player })
			end,
			FireAllClients = function() end,
		}
	end
	w.playersService = { PlayerRemoving = signal(), PlayerAdded = signal() }
	local services: { [string]: any } = {
		Players = w.playersService,
		ReplicatedStorage = folder({ Remotes = folder(w.remotes) }),
		RunService = { Heartbeat = w.heartbeat },
	}
	local spy = setmetatable({
		new = function(_maze: any, seed: any, _config: any): any
			local s = { members = {}, seed = seed }
			table.insert(w.made, s)
			w.steps[s] = 0
			return s
		end,
		join = function(_s: any, _id: string) end,
		submit = function(): (boolean, string?)
			return true, nil
		end,
		step = function(s: any): { any }
			w.steps[s] += 1
			local f = w.script[s]
			local events = if f then f(w.steps[s]) else {}
			w.returned[s] = events
			return events
		end,
		frame = function(s: any, id: string): any
			return { id = id, n = w.steps[s] }
		end,
		playAgain = function(_s: any, _id: string): ({ any }, boolean)
			return {}, w.againOk
		end,
	}, { __index = Session })
	local function env(modules: { [string]: any }): { [string]: any }
		return {
			game = {
				GetService = function(_: any, name: string): any
					local found = services[name]
					assert(found ~= nil, `stub: game:GetService("{name}") is not modelled`)
					return found
				end,
				BindToClose = function(_: any, fn: () -> ())
					table.insert(w.closers, fn)
				end,
			},
			task = {
				wait = function(seconds: number?): number
					table.insert(w.waiting, { co = coroutine.running(), due = w.clock + (seconds or 0) })
					coroutine.yield()
					return seconds or 0
				end,
			},
			-- an unknown module is recorded, not served: f0065's fake serves Sessions only Maze and Session
			require = function(spec: string): any
				local found = modules[spec]
				if found == nil then
					table.insert(w.unknown, spec)
					return {}
				end
				return found
			end,
		}
	end
	local function load(path: string, modules: { [string]: any }): any
		return luau.load(fs.readFile(path), { environment = env(modules), debugName = path })()
	end
	w.mod = load(SESSIONS, { [LOGIC .. "Maze"] = Maze, [LOGIC .. "Session"] = spy })
	if runs == "record" then
		w.mod.start({
			ready = function(s: any, player: any)
				table.insert(w.readies, { s, player })
			end,
			again = function(s: any)
				table.insert(w.agains, s)
			end,
			step = function(s: any, events: { any }, here: boolean): boolean
				table.insert(w.heard, { s = s, events = events, here = here })
				return w.keep[s] ~= false
			end,
		})
	elseif runs == "submits" then
		-- every submit starts a drive that stays in flight until the spec sets w.drives back
		local store = {
			submit = function(...: any)
				table.insert(w.submits, { ... })
				w.drives += 1
			end,
			pending = function(): number
				return w.drives
			end,
		}
		w.mod.start(load(SUBMITS, { [LOGIC .. "Hiscores"] = Hiscores, ["./HiscoreStore"] = store }))
	else
		w.mod.start()
	end
	return w
end

local function join(w: World, userId: number, display: string?, name: string?): any
	local p = {
		UserId = userId,
		Name = name or `Player{userId}`,
		DisplayName = display or "",
		Parent = w.playersService,
	}
	w.remotes.Ready.OnServerEvent:fire(p)
	return p
end

local function leave(w: World, p: any)
	p.Parent = nil
	w.playersService.PlayerRemoving:fire(p)
end

local function frame(w: World, dt: number)
	w.heartbeat:fire(dt)
end

local function frames(w: World, n: number)
	for _ = 1, n do
		frame(w, ONE)
	end
end

-- the server clock that task.wait sleeps on (separate from Heartbeat, which the spec fires itself)
local function tick(w: World, seconds: number)
	w.clock += seconds
	local due: { { co: thread, due: number } } = {}
	local later: { { co: thread, due: number } } = {}
	for _, entry in w.waiting do
		table.insert(if entry.due <= w.clock + 1e-9 then due else later, entry)
	end
	w.waiting = later
	for _, entry in due do
		local ok, err = coroutine.resume(entry.co)
		if not ok then
			error(err, 0)
		end
	end
end

-- start the close handler Submits bound, as the engine does when the server shuts down
local function close(w: World): thread
	t.expect(#w.closers).toBe(1)
	local co = coroutine.create(w.closers[1])
	local ok, err = coroutine.resume(co)
	if not ok then
		error(err, 0)
	end
	return co
end

local function closed(co: thread): boolean
	return coroutine.status(co) == "dead"
end

local function snapshots(w: World, p: any): number
	local n = 0
	for _, f in w.sent do
		if f.remote == "Snapshot" and f.player == p then
			n += 1
		end
	end
	return n
end

local function heardFor(w: World, s: any): { Heard }
	local out: { Heard } = {}
	for _, h in w.heard do
		if h.s == s then
			table.insert(out, h)
		end
	end
	return out
end

local function gameOverAt(step: number, score: number, level: number): (n: number) -> { any }
	return function(n: number): { any }
		if n == step or n == step + 1 then
			return { { kind = "GameOver", player = "x", score = score, level = level } }
		end
		return {}
	end
end

return t.spec("f0025 Sessions wiring", function(it)
	it("the clock, the frame and the config stay as the promoted pins have them", function()
		local src = source(SESSIONS)
		local clocks = 0
		for call in string.gmatch(src, "Session%.newClock%b()") do
			clocks += 1
			t.expect(string.find(call, "^Session%.newClock%(%s*Session%.STEP_RATE%s*%)$") ~= nil).toBe(true)
		end
		t.expect(clocks).toBe(1)
		local created = 0
		for call in string.gmatch(src, "Session%.new%b()") do
			created += 1
			t.expect(string.find(call, "Session%.GAME_CONFIG%s*%)$") ~= nil).toBe(true)
		end
		t.expect(created >= 1).toBe(true)
		t.expect(string.find(src, ":FireClient%(%s*[%w_%.]+%s*,%s*Session%.frame%(") ~= nil).toBe(true)
		for _, banned in
			{
				"Session.snapshot(",
				"PlayerAdded",
				"TICK_RATE",
				"gameover",
				".phase",
				"task.wait",
				"task.delay",
			}
		do
			t.expect((string.find(src, banned, 1, true))).toBe(nil)
		end
		local calls = 0
		for call in string.gmatch(src, "Session%.playAgain%b()") do
			calls += 1
			t.expect(
				string.find(
					call,
					"^Session%.playAgain%(%s*[%w_]+%s*,%s*tostring%(%s*[%w_]+%.UserId%s*%)%s*%)$"
				) ~= nil
			).toBe(true)
		end
		t.expect(calls <= 1).toBe(true)
	end)

	it("the server's Main starts Sessions with Submits as its runs", function()
		local main = source("src/server/Main.server.luau")
		local call = "%.start%(%s*" .. "req" .. 'uire%(%s*"%./Submits"%s*%)%s*%)'
		t.expect(string.find(main, call) ~= nil).toBe(true)
	end)

	it("Sessions requires only Maze and Session, the modules f0065's fake engine serves it", function()
		for _, runs in { "record", "none" } do
			local w = world(runs)
			t.expect(w.unknown).toEqual({})
		end
	end)

	it("Ready makes one session per player and tells the runs once, with that session and player", function()
		local w = world("record")
		local p1 = join(w, 1)
		w.remotes.Ready.OnServerEvent:fire(p1)
		t.expect(#w.made).toBe(1)
		t.expect(#w.readies).toBe(1)
		t.expect(w.readies[1][1]).toBe(w.made[1])
		t.expect(w.readies[1][2]).toBe(p1)
	end)

	it(
		"each step Session.advance grants steps every live session once, with the events it returned",
		function()
			local w = world("record")
			local p1, p2 = join(w, 1), join(w, 2)
			local s1, s2 = w.made[1], w.made[2]
			frame(w, 2 / Session.STEP_RATE)
			t.expect(w.steps[s1]).toBe(2)
			t.expect(w.steps[s2]).toBe(2)
			t.expect(snapshots(w, p1)).toBe(2)
			t.expect(snapshots(w, p2)).toBe(2)
			local heard = heardFor(w, s1)
			t.expect(#heard).toBe(2)
			t.expect(heard[2].here).toBe(true)
			t.expect(heard[2].events).toBe(w.returned[s1])
		end
	)

	it(
		"a frame that grants no step steps nobody and sends nothing, and the clock still carries it",
		function()
			local w = world("record")
			local p1 = join(w, 1)
			local s1 = w.made[1]
			frame(w, 0.5 * ONE)
			t.expect(w.steps[s1]).toBe(0)
			t.expect(snapshots(w, p1)).toBe(0)
			t.expect(#w.heard).toBe(0)
			frame(w, 0.5 * ONE)
			t.expect(w.steps[s1]).toBe(1)
			t.expect(snapshots(w, p1)).toBe(1)
			t.expect(#w.heard).toBe(1)
		end
	)

	it("a long frame catches up at most the clock's cap of steps", function()
		local w = world("record")
		join(w, 1)
		frame(w, 1)
		t.expect(w.steps[w.made[1]]).toBe(Session.MAX_STEPS_PER_ADVANCE)
		t.expect(#w.heard).toBe(Session.MAX_STEPS_PER_ADVANCE)
	end)

	it(
		"once the player's Parent is nil, frames are not sent to them and the runs hear here = false",
		function()
			local w = world("record")
			local p1, p2 = join(w, 1), join(w, 2)
			local s1 = w.made[1]
			frame(w, ONE)
			p1.Parent = nil
			frames(w, 2)
			t.expect(snapshots(w, p1)).toBe(1)
			t.expect(snapshots(w, p2)).toBe(3)
			t.expect(w.steps[s1]).toBe(3)
			local heard = heardFor(w, s1)
			t.expect(heard[1].here).toBe(true)
			t.expect(heard[3].here).toBe(false)
		end
	)

	it("a player still in the game stays live whatever the runs answer", function()
		local w = world("record")
		local p1 = join(w, 1)
		local s1 = w.made[1]
		w.keep[s1] = false
		frames(w, 3)
		t.expect(w.steps[s1]).toBe(3)
		t.expect(snapshots(w, p1)).toBe(3)
	end)

	it(
		"a departed session is parked: stepped with here = false and never sent, until the runs say stop",
		function()
			local w = world("record")
			local p1, p2 = join(w, 1), join(w, 2)
			local s1 = w.made[1]
			frame(w, ONE)
			leave(w, p1)
			frames(w, 3)
			t.expect(w.steps[s1]).toBe(4)
			t.expect(snapshots(w, p1)).toBe(1)
			t.expect(snapshots(w, p2)).toBe(4)
			local heard = heardFor(w, s1)
			t.expect(heard[4].here).toBe(false)
			t.expect(heard[4].events).toBe(w.returned[s1])
			w.keep[s1] = false
			frame(w, ONE)
			t.expect(w.steps[s1]).toBe(5)
			frames(w, 2)
			t.expect(w.steps[s1]).toBe(5)
			t.expect(snapshots(w, p2)).toBe(7)
		end
	)

	it("started with no runs, as f0065 boots it, a departed session is forgotten at once", function()
		local w = world("none")
		local p1 = join(w, 1)
		local s1 = w.made[1]
		frame(w, ONE)
		leave(w, p1)
		frames(w, 3)
		t.expect(w.steps[s1]).toBe(1)
		t.expect(snapshots(w, p1)).toBe(1)
	end)

	it("play again tells the runs only when Logic accepts it", function()
		local w = world("record")
		local p1 = join(w, 1)
		w.againOk = false
		w.remotes.PlayAgain.OnServerEvent:fire(p1)
		t.expect(#w.agains).toBe(0)
		w.againOk = true
		w.remotes.PlayAgain.OnServerEvent:fire(p1)
		-- f0065 removes the handler; while it is there, an accepted play again is a new run
		local handled = string.find(source(SESSIONS), "Session.playAgain(", 1, true) ~= nil
		t.expect(#w.agains).toBe(if handled then 1 else 0)
		if handled then
			t.expect(w.agains[1]).toBe(w.made[1])
		end
	end)

	it(
		"a GameOver while the player is here submits once, with the captured id and name, and stays live",
		function()
			local w = world("submits")
			local p1 = join(w, 1, "  Ada\n", "ada_account")
			local s1 = w.made[1]
			w.script[s1] = gameOverAt(3, 70, 2)
			frames(w, 6)
			t.expect(#w.submits).toBe(1)
			t.expect(w.submits[1]).toEqual({ "1", "Ada", 70, 2, 1 } :: { any })
			t.expect(w.steps[s1]).toBe(6)
			t.expect(snapshots(w, p1)).toBe(6)
			local p2 = join(w, 2, "", "Bob")
			w.script[w.made[2]] = gameOverAt(1, 5, 1)
			frame(w, ONE)
			t.expect(w.submits[2]).toEqual({ "2", "Bob", 5, 1, 1 } :: { any })
			t.expect(snapshots(w, p2)).toBe(1)
		end
	)

	it(
		"a departed run with no GameOver is stepped through the 45-step pause and not on the 46th frame",
		function()
			local w = world("submits")
			local p1 = join(w, 1)
			local s1 = w.made[1]
			leave(w, p1)
			frames(w, Hiscores.LEAVE_STEPS - 1)
			t.expect(w.steps[s1]).toBe(Hiscores.LEAVE_STEPS - 1)
			frame(w, ONE)
			t.expect(w.steps[s1]).toBe(Hiscores.LEAVE_STEPS)
			frame(w, ONE)
			t.expect(w.steps[s1]).toBe(Hiscores.LEAVE_STEPS)
			t.expect(#w.submits).toBe(0)
		end
	)

	it("a GameOver while parked submits and lets the run go", function()
		local w = world("submits")
		local p1 = join(w, 1, "Ada")
		local s1 = w.made[1]
		w.script[s1] = gameOverAt(12, 900, 4)
		frames(w, 2)
		leave(w, p1)
		frames(w, 20)
		t.expect(#w.submits).toBe(1)
		t.expect(w.submits[1]).toEqual({ "1", "Ada", 900, 4, 1 } :: { any })
		t.expect(w.steps[s1]).toBe(12)
	end)

	it("a rejoin is a new run: the parked run and the new one both submit run 1", function()
		local w = world("submits")
		local first = join(w, 1, "Ada")
		local s1 = w.made[1]
		w.script[s1] = gameOverAt(4, 300, 2)
		frames(w, 2)
		leave(w, first)
		local again = join(w, 1, "Ada")
		local s2 = w.made[2]
		t.expect(s2 ~= s1).toBe(true)
		w.script[s2] = gameOverAt(5, 120, 1)
		frames(w, 6)
		t.expect(#w.submits).toBe(2)
		t.expect(w.submits[1]).toEqual({ "1", "Ada", 300, 2, 1 } :: { any })
		t.expect(w.submits[2]).toEqual({ "1", "Ada", 120, 1, 1 } :: { any })
		t.expect(snapshots(w, again)).toBe(6)
	end)

	it("a parked session is stepped once per step Session.advance grants, not once per Heartbeat", function()
		local w = world("record")
		local p1 = join(w, 1)
		local s1 = w.made[1]
		leave(w, p1)
		frame(w, 2 / Session.STEP_RATE)
		t.expect(w.steps[s1]).toBe(2)
		frame(w, 0.5 * ONE)
		t.expect(w.steps[s1]).toBe(2)
		frame(w, 0.5 * ONE)
		t.expect(w.steps[s1]).toBe(3)
	end)

	it(
		"Submits binds one close handler, which returns at once when no run is held and no drive is in flight",
		function()
			local w = world("submits")
			t.expect(#w.closers).toBe(1)
			t.expect(closed(close(w))).toBe(true)
		end
	)

	it(
		"closing waits for a parked run to reach its GameOver and for that drive, while the server keeps stepping",
		function()
			local w = world("submits")
			local p1 = join(w, 1, "Ada")
			local s1 = w.made[1]
			w.script[s1] = gameOverAt(10, 640, 3)
			frames(w, 2)
			leave(w, p1)
			local co = close(w)
			t.expect(closed(co)).toBe(false)
			for _ = 1, 7 do
				frame(w, ONE)
				tick(w, 0.25)
			end
			t.expect(#w.submits).toBe(0)
			t.expect(closed(co)).toBe(false)
			frame(w, ONE)
			tick(w, 0.25)
			t.expect(w.submits[1]).toEqual({ "1", "Ada", 640, 3, 1 } :: { any })
			t.expect(closed(co)).toBe(false)
			tick(w, 1)
			t.expect(closed(co)).toBe(false)
			w.drives = 0
			tick(w, 0.25)
			t.expect(closed(co)).toBe(true)
		end
	)

	it("closing gives up at the close wait when a drive never finishes", function()
		local w = world("submits")
		w.drives = 1
		local co = close(w)
		for _ = 1, 99 do
			tick(w, 0.25)
		end
		t.expect(closed(co)).toBe(false)
		tick(w, 0.25)
		t.expect(closed(co)).toBe(true)
	end)
end)
