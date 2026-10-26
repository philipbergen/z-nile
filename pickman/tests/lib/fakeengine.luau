--!strict
-- A fake of the little Roblox the lobby adapters touch, so a spec can run an adapter's real source: the
-- services it asks `game` for, the signals it connects, the instances it builds, with the real Logic.
--
-- What it models (the contract the adapters may rely on, and no more):
--   * instances with Name, Parent, children, :WaitForChild / :FindFirstChild / child-by-name (dot index),
--     :GetChildren / :GetDescendants and :GetAttribute; a WaitForChild on a missing name fails the spec,
--     naming the path (the real call would wait for ever);
--   * the remotes and the attributes are taken from the BUILT lobby place, so a wrong name in an adapter
--     fails here, and the project file and the adapters cannot drift apart;
--   * signals whose handlers run in their own coroutine (a handler that yields stays suspended while the
--     spec carries on); `pcall` across a yield works;
--   * `task.spawn`, `task.defer`, `task.delay` and `task.wait`, driven by the fake clock (`tick`);
--   * an error in a thread the fake resumes later (a spawned or deferred function, a timer, a waiter) does not
--     unwind whoever started it, as in Roblox, but the server call the spec made fails with it afterwards;
--   * `os.clock`, `Instance.new`, `Enum`, `UDim2`, `Vector2`, `Vector3` and `Color3` as plain data;
--   * f0109: `:SetAttribute` (refusing what Roblox refuses: a name that is not 1-100 letters, digits or
--     underscores, and a table, function, thread or Instance value), `:IsA` (only the classes the specs use: a
--     class is itself, and a Part is a BasePart), and `fake.module`, which runs one client view module's real
--     source (MazeView, DangerHud) with the real Logic, a `workspace` (with a CurrentCamera), and the client services a view asks for: GuiService
--     (`GetInsetArea`: no insets), Players (a LocalPlayer with a PlayerGui), RunService (`RenderStepped`, a
--     signal the spec fires) and UserInputService (`TouchEnabled`); a ScreenGui's AbsoluteSize is the screen; and,
--     for these view modules only, `UDim`, `UDim2.fromOffset`, `Vector3` and `NumberSequence(Keypoint)` as plain
--     data (the lobby's environment is unchanged: f0109's re-run of f0061's mutants, E8).
--     `:SetAttribute` refuses Roblox datatypes (Color3, Vector3, UDim2 …) as values, which Roblox accepts,
--     because they are plain tables here; no adapter stores one today (tests/place/fakeengine-attributes.spec).
-- The fake must stay exact in both directions: it must not accept less than it does now (a correct idiom
-- that works today must keep working), and it must not accept more (a wrong adapter that fails today must
-- keep failing: the mutants in f0061's Rules and mutants table that depend on it are re-run, as exact
-- substitutions, whenever it changes).
-- It models nothing about what the real engine does with TeleportAsync (E7 in f0061).
local Awareness = require("@logic/Awareness")
local Flow = require("@logic/Flow")
local Hud = require("@logic/Hud")
local Lobby = require("@logic/Lobby")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local Travel = require("@logic/Travel")
local View = require("@logic/View")
local luau = require("@lune/luau")

local fake = {}

export type Signal = {
	connections: { (...any) -> () },
	Connect: (self: Signal, fn: (...any) -> ()) -> any,
	fire: (self: Signal, ...any) -> (),
}

function fake.signal(): Signal
	local s: Signal
	s = {
		connections = {},
		Connect = function(self: Signal, fn: (...any) -> ())
			table.insert(self.connections, fn)
			return { Disconnect = function() end }
		end,
		fire = function(self: Signal, ...: any)
			for _, fn in self.connections do
				local ok, err = coroutine.resume(coroutine.create(fn), ...)
				if not ok then
					error(err, 0)
				end
			end
		end,
	}
	return s
end

local LOGIC: { [string]: any } = {
	Travel = Travel,
	Lobby = Lobby,
	Flow = Flow,
	Maze = Maze,
	Session = Session,
	View = View,
	Awareness = Awareness,
	Hud = Hud,
}

-- The require an adapter gets: the real Logic modules, or `overrides` for some of them (a spy on Session, say);
-- an override can only replace a module the fake already serves.
local function requirer(overrides: { [string]: any }?): (string) -> any
	if overrides then
		for name in overrides do
			if LOGIC[name] == nil then
				error(`fake engine: no Logic module "{name}" to override`, 0)
			end
		end
	end
	return function(spec: string): any
		local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
		local found = name and ((overrides and overrides[name]) or LOGIC[name])
		if found == nil then
			error(`fake engine: no module for require("{spec}")`, 0)
		end
		return found
	end
end

local function load(source: string, env: { [string]: any }, name: string): any
	local chunk = luau.load(source, { environment = env, debugName = name })
	return chunk()
end

-- The instance model ---------------------------------------------------------------------------------------

local raws: { [any]: { [any]: any } } = setmetatable({}, { __mode = "k" }) :: any

local function fullName(n: any): string
	local parts: { string } = {}
	local at: any = n
	while at ~= nil do
		table.insert(parts, 1, at.Name)
		at = at.Parent
	end
	return table.concat(parts, ".")
end

local function descendants(n: any, out: { any })
	for _, c in raws[n].children do
		table.insert(out, c)
		descendants(c, out)
	end
end

function fake.node(className: string, name: string?): any
	local raw: { [any]: any } =
		{ ClassName = className, Name = name or className, children = {}, attributes = {} }
	local proxy: any = {}
	raw.FindFirstChild = function(_: any, childName: string): any
		for _, c in raw.children do
			if c.Name == childName then
				return c
			end
		end
		return nil
	end
	raw.WaitForChild = function(self: any, childName: string): any
		local found = raw.FindFirstChild(self, childName)
		if found == nil then
			error(`fake engine: {fullName(self)}:WaitForChild("{childName}") would wait for ever`, 0)
		end
		return found
	end
	raw.GetChildren = function(): { any }
		return table.clone(raw.children)
	end
	raw.GetDescendants = function(): { any }
		local out: { any } = {}
		descendants(proxy, out)
		return out
	end
	raw.GetAttribute = function(_: any, attribute: string): any
		return raw.attributes[attribute]
	end
	raw.SetAttribute = function(_: any, attribute: string, value: any)
		if
			type(attribute) ~= "string"
			or #attribute == 0
			or #attribute > 100
			or string.find(attribute, "[^%w_]")
		then
			error(`fake engine: {attribute} is not a valid attribute name`, 0)
		end
		local kind = type(value)
		if kind == "table" or kind == "function" or kind == "thread" or raws[value] ~= nil then
			error(
				`fake engine: an attribute can't hold a value of type {if raws[value]
					then "Instance"
					else kind}`,
				0
			)
		end
		raw.attributes[attribute] = value
	end
	raw.IsA = function(_: any, class: string): boolean
		return raw.ClassName == class
			or (class == "BasePart" and (raw.ClassName == "Part" or raw.ClassName == "WedgePart"))
	end
	setmetatable(proxy, {
		__index = function(_: any, key: any): any
			local v = raw[key]
			if v ~= nil then
				return v
			end
			return raw.FindFirstChild(proxy, key)
		end,
		__newindex = function(_: any, key: any, value: any)
			if key == "Parent" then
				local old = raw.Parent
				if old ~= nil then
					local siblings = raws[old].children
					local at = table.find(siblings, proxy)
					if at then
						table.remove(siblings, at)
					end
				end
				raw.Parent = value
				if value ~= nil then
					table.insert(raws[value].children, proxy)
				end
			else
				raw[key] = value
			end
		end,
	})
	raws[proxy] = raw
	return proxy
end

local function child(parent: any, className: string, name: string): any
	local n = fake.node(className, name)
	n.Parent = parent
	return n
end

-- ReplicatedStorage.Remotes with the RemoteEvents the built place has. Each remote has both ends: the
-- server's (OnServerEvent, FireClient) and the client's (OnClientEvent, FireServer).
local function replicatedStorage(
	lobbyPlace: any,
	sent: { Fired },
	fired: { { any } },
	firedOn: { FiredOn }
): any
	local rs = fake.node("ReplicatedStorage")
	local remotes = child(rs, "Folder", "Remotes")
	for _, built in lobbyPlace.ReplicatedStorage.Remotes:GetChildren() do
		local r = child(remotes, "RemoteEvent", built.Name)
		r.OnServerEvent = fake.signal()
		r.OnClientEvent = fake.signal()
		r.FireClient = function(_: any, player: any, ...: any)
			table.insert(sent, { player = player, args = { ... }, remote = built.Name })
		end
		r.FireServer = function(_: any, ...: any)
			table.insert(fired, { ... })
			table.insert(firedOn, { remote = built.Name, args = { ... } })
		end
	end
	return rs
end

export type Fired = { player: any, args: { any }, remote: string }
export type FiredOn = { remote: string, args: { any } }

local function standardEnv(services: { [string]: any }, overrides: { [string]: any }?): { [string]: any }
	return {
		game = {
			GetService = function(_: any, name: string): any
				local found = services[name]
				if found == nil then
					error(`fake engine: game:GetService("{name}") is not modelled`, 0)
				end
				return found
			end,
		},
		require = requirer(overrides),
		Enum = setmetatable({}, {
			__index = function(_: any, group: string): any
				return setmetatable({}, {
					__index = function(_: any, item: string): string
						return `{group}.{item}`
					end,
				})
			end,
		}),
		UDim2 = {
			new = function(xs: number, xo: number, ys: number, yo: number): any
				return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
			end,
			fromScale = function(x: number, y: number): any
				return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }
			end,
		},
		Vector2 = {
			new = function(x: number, y: number): any
				return { X = x, Y = y }
			end,
		},
		Color3 = {
			new = function(r: number, g: number, b: number): any
				return { R = r, G = g, B = b }
			end,
			fromRGB = function(r: number, g: number, b: number): any
				return { R = r / 255, G = g / 255, B = b / 255 }
			end,
		},
		Instance = {
			new = function(className: string): any
				local n = fake.node(className)
				if className == "TextButton" then
					n.Activated = fake.signal()
				end
				return n
			end,
		},
	}
end

export type View = {
	workspace: any,
	playerGui: any,
	renderStepped: Signal, -- RunService.RenderStepped: the spec fires it
	input: { TouchEnabled: boolean },
}

-- One client view module's real source (MazeView, DangerHud) under the standard environment with the client
-- services a view asks for; returns the module and its view world. A ScreenGui's AbsoluteSize is `screen`.
function fake.module(source: string, name: string, screen: { X: number, Y: number }?): (any, View)
	local size = screen or { X = 1280, Y = 720 }
	local workspace = fake.node("Workspace", "Workspace")
	workspace.CurrentCamera = { FieldOfView = 70 }
	local player = fake.node("Player", "LocalPlayer")
	local playerGui = child(player, "PlayerGui", "PlayerGui")
	local renderStepped = fake.signal()
	local input = { TouchEnabled = false }
	local services = {
		GuiService = {
			GetInsetArea = function(_: any, _which: any): any
				return { Min = { X = 0, Y = 0 }, Max = { X = size.X, Y = size.Y } }
			end,
		},
		Players = { LocalPlayer = player },
		RunService = { RenderStepped = renderStepped },
		UserInputService = input,
	}
	local env = standardEnv(services)
	env.workspace = workspace
	-- the views' extra constructors, only here: the lobby's environment stays exactly as f0061 specified it (an
	-- off-screen button placed by fromOffset must keep failing f0061's specs)
	env.UDim = {
		new = function(scale: number, offset: number): any
			return { Scale = scale, Offset = offset }
		end,
	}
	env.NumberSequence = {
		new = function(points: any): any
			return { Keypoints = points }
		end,
	}
	env.NumberSequenceKeypoint = {
		new = function(time: number, value: number): any
			return { Time = time, Value = value }
		end,
	}
	env.Vector3 = {
		new = function(x: number, y: number, z: number): any
			return { X = x, Y = y, Z = z }
		end,
	}
	local udim2 = table.clone(env.UDim2)
	udim2.fromOffset = function(x: number, y: number): any
		return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } }
	end
	env.UDim2 = udim2
	local new = env.Instance.new
	env.Instance = {
		new = function(className: string): any
			local n = new(className)
			if className == "ScreenGui" then
				n.AbsoluteSize = { X = size.X, Y = size.Y }
			end
			return n
		end,
	}
	return load(source, env, name),
		{
			workspace = workspace,
			playerGui = playerGui,
			renderStepped = renderStepped,
			input = input,
		}
end

-- The server ------------------------------------------------------------------------------------------------

export type Server = {
	clock: { now: number },
	engine: { calls: { { destination: any, players: any, options: any } }, mode: string, held: { thread } },
	sent: { Fired },
	boot: (source: string, ...any) -> any,
	press: (player: any, ...any) -> (),
	fire: (remote: string, player: any, ...any) -> (),
	reports: (remote: string, player: any) -> { { any } },
	tick: (seconds: number) -> (),
	here: (player: any) -> (),
	join: (player: any) -> (),
	leave: (player: any) -> (),
	initFailed: (player: any) -> (),
	release: (index: number, failure: boolean) -> (),
	statuses: (player: any) -> { { any } },
}

-- The lobby's server side, over `lobbyPlace` (place.load("lobby.project.json")). `attributes` overrides the
-- values of attributes the built ServerScriptService carries (naming one it does not carry is an error).
function fake.server(lobbyPlace: any, attributes: { [string]: any }, logic: { [string]: any }?): Server
	local clock = { now = 0 }
	local sent: { Fired } = {}
	local fired: { { any } } = {}
	local storage = replicatedStorage(lobbyPlace, sent, fired, {})
	local scripts = fake.node("ServerScriptService")
	local builtAttributes = lobbyPlace.ServerScriptService:GetAttributes()
	for name, value in builtAttributes do
		raws[scripts].attributes[name] = value
	end
	for name, value in attributes do
		if builtAttributes[name] == nil then
			error(`fake engine: the built lobby has no ServerScriptService attribute "{name}"`, 0)
		end
		raws[scripts].attributes[name] = value
	end
	local engine = {
		calls = {} :: { { destination: any, players: any, options: any } },
		mode = "ok", -- "ok" returns, "error" raises, "hold" yields until the spec releases it
		held = {} :: { thread },
	}
	local init = fake.signal()
	local teleport = fake.node("TeleportService")
	teleport.TeleportInitFailed = init
	teleport.TeleportAsync = function(_: any, destination: any, players: any, options: any)
		table.insert(engine.calls, { destination = destination, players = players, options = options })
		if engine.mode == "error" then
			error("fake teleport failure", 0)
		elseif engine.mode == "hold" then
			table.insert(engine.held, coroutine.running())
			local failure = coroutine.yield()
			if failure then
				error("fake teleport failure", 0)
			end
		end
	end
	local playersService = fake.node("Players")
	playersService.PlayerAdded = fake.signal()
	playersService.PlayerRemoving = fake.signal()
	playersService.GetPlayers = function(): { any }
		return playersService:GetChildren()
	end
	local runService = fake.node("RunService")
	runService.Heartbeat = fake.signal()
	-- errors from threads the fake resumed, raised by the spec-facing call once its own work is done
	local failures: { string } = {}
	local function resume(co: thread, ...: any)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(failures, debug.traceback(co, tostring(err)))
		end
	end
	local function checked<A...>(fn: (A...) -> ()): (A...) -> ()
		return function(...: A...)
			fn(...)
			if #failures > 0 then
				local first = failures[1]
				table.clear(failures)
				error(`fake engine: an adapter thread failed: {first}`, 0)
			end
		end
	end
	local waiting: { { co: thread, due: number } } = {}
	local timers: { { due: number, fn: (...any) -> (), args: { any } } } = {}
	local task = {
		spawn = function(fn: (...any) -> (), ...: any)
			resume(coroutine.create(fn), ...)
		end,
		defer = function(fn: (...any) -> (), ...: any)
			resume(coroutine.create(fn), ...)
		end,
		delay = function(seconds: number, fn: (...any) -> (), ...: any)
			table.insert(timers, { due = clock.now + seconds, fn = fn, args = { ... } })
		end,
		wait = function(seconds: number?): number
			table.insert(waiting, { co = coroutine.running(), due = clock.now + (seconds or 0) })
			coroutine.yield()
			return seconds or 0
		end,
	}
	local services: { [string]: any } = {
		Players = playersService,
		ReplicatedStorage = storage,
		RunService = runService,
		ServerScriptService = scripts,
		TeleportService = teleport,
	}
	local env = standardEnv(services, logic)
	env.os = {
		clock = function(): number
			return clock.now
		end,
		time = os.time,
	}
	env.task = task
	local startGame = storage.Remotes.StartGame
	local server: Server
	server = {
		clock = clock,
		engine = engine,
		sent = sent,
		boot = function(source: string, ...: any): any
			local module = load(source, env, "fake server")
			checked(function(...: any)
				module.start(...)
			end)(...)
			return module
		end,
		press = checked(function(player: any, ...: any)
			startGame.OnServerEvent:fire(player, ...)
		end),
		-- a client's request on any remote the built place has (`press` is the lobby's StartGame)
		fire = checked(function(remote: string, player: any, ...: any)
			storage.Remotes:WaitForChild(remote).OnServerEvent:fire(player, ...)
		end),
		tick = checked(function(seconds: number)
			clock.now += seconds
			for i = #timers, 1, -1 do
				local timer = timers[i]
				if timer.due <= clock.now then
					table.remove(timers, i)
					resume(coroutine.create(timer.fn), table.unpack(timer.args))
				end
			end
			for i = #waiting, 1, -1 do
				local w = waiting[i]
				if w.due <= clock.now then
					table.remove(waiting, i)
					resume(w.co)
				end
			end
			runService.Heartbeat:fire(seconds)
		end),
		here = function(player: any)
			player.Parent = playersService
		end,
		join = checked(function(player: any)
			player.Parent = playersService
			playersService.PlayerAdded:fire(player)
		end),
		leave = checked(function(player: any)
			playersService.PlayerRemoving:fire(player)
			player.Parent = nil
		end),
		initFailed = checked(function(player: any)
			init:fire(player, "Failure", "fake init failure")
		end),
		release = checked(function(index: number, failure: boolean)
			local ok, err = coroutine.resume(engine.held[index], failure)
			if not ok then
				error(err, 0)
			end
		end),
		-- what the server sent this player on one remote, in order
		reports = function(remote: string, player: any): { { any } }
			local out: { { any } } = {}
			for _, f in sent do
				if f.player == player and f.remote == remote then
					table.insert(out, f.args)
				end
			end
			return out
		end,
		statuses = function(player: any): { { any } }
			local out: { { any } } = {}
			for _, f in sent do
				if f.player == player then
					table.insert(out, f.args)
				end
			end
			return out
		end,
	}
	return server
end

-- A fake player: an instance, so Parent says whether it is still in the game.
function fake.player(userId: number): any
	local p = fake.node("Player", `Player{userId}`)
	p.UserId = userId
	return p
end

-- The client ------------------------------------------------------------------------------------------------

export type Client = {
	boot: (source: string, ...any) -> any,
	find: (name: string) -> any,
	status: (phase: string, configured: boolean) -> (),
	activate: () -> (),
	fired: { { any } },
	firedOn: { FiredOn },
	receive: (remote: string, ...any) -> (),
	click: (name: string) -> (),
	key: (keyName: string, state: string?) -> { any },
	bindings: { Binding },
}

-- a ContextActionService binding: its handler, its key codes ("KeyCode.<name>") and whether it asked for an
-- on-screen touch button
export type Binding = { fn: (...any) -> any, keys: { any }, touch: boolean }

-- The lobby's client side over `lobbyPlace`: whatever the view builds is found only if it ends up, through
-- its Parent links, under the PlayerGui.
function fake.client(lobbyPlace: any): Client
	local sent: { Fired } = {}
	local fired: { { any } } = {}
	local firedOn: { FiredOn } = {}
	local storage = replicatedStorage(lobbyPlace, sent, fired, firedOn)
	-- ContextActionService: BindAction records the handler and its key codes ("KeyCode.<name>")
	local bound: { Binding } = {}
	local actions = {
		BindAction = function(_: any, _name: string, fn: (...any) -> any, touch: boolean, ...: any)
			table.insert(bound, { fn = fn, keys = { ... }, touch = touch })
		end,
	}
	local playerGui = fake.node("PlayerGui")
	local localPlayer = fake.node("Player", "LocalPlayer")
	playerGui.Parent = localPlayer
	local services: { [string]: any } = {
		Players = { LocalPlayer = localPlayer },
		ReplicatedStorage = storage,
		ContextActionService = actions,
	}
	local env = standardEnv(services)
	local function find(name: string): any
		for _, d in playerGui:GetDescendants() do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	return {
		boot = function(source: string, ...: any): any
			local module = load(source, env, "fake client")
			module.start(...)
			return module
		end,
		find = find,
		status = function(phase: string, configured: boolean)
			storage.Remotes.Status.OnClientEvent:fire(phase, configured)
		end,
		activate = function()
			find("Start").Activated:fire()
		end,
		fired = fired,
		firedOn = firedOn,
		bindings = bound,
		-- the server sends this client something on a remote the built place has
		receive = function(remote: string, ...: any)
			storage.Remotes:WaitForChild(remote).OnClientEvent:fire(...)
		end,
		-- a tap or click on a button the view put under the PlayerGui; a hidden button gets nothing
		click = function(name: string)
			local b = find(name)
			if b == nil then
				error(`fake engine: no {name} under the PlayerGui`, 0)
			end
			if b.Visible ~= false then
				b.Activated:fire()
			end
		end,
		-- a key event (state "Begin" unless given) to every handler bound to that key; returns their results
		key = function(keyName: string, state: string?): { any }
			local out: { any } = {}
			for _, b in bound do
				if table.find(b.keys, `KeyCode.{keyName}`) then
					local input = { KeyCode = { Name = keyName } }
					table.insert(out, b.fn("action", `UserInputState.{state or "Begin"}`, input))
				end
			end
			return out
		end,
	}
end

return fake
