--!strict
-- f0148 AC3: the lobby's level picker. Lobby.button says which level START starts ("START LEVEL n") when the picker
-- is shown; LobbyView (its real source, on the fake engine) shows the picker's level on START, redraws when it changes,
-- and sends it with the request; Starts hands the player's request to the store hook (`Starts.choosing`) once Travel says go,
-- before the teleport; LobbyPicker (its real source, on a stub engine) shows its two arrows once the player's best is 2
-- or more, starts on the best, steps with a click or a tap and with the Left and Right keys, and its arrows are
-- touch-sized.
local Best = require("@logic/Best")
local Lobby = require("@logic/Lobby")
local Travel = require("@logic/Travel")
local fake = require("@tests/lib/fakeengine")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local lobby = place.load("lobby.project.json")

local function sourceOf(path: { string }): string
	local node: any = lobby
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	assert(node, `{table.concat(path, ".")} in the built lobby`)
	return node.Source
end

local STARTS = { "ServerScriptService", "Lobby", "Starts" }
local VIEW = { "StarterPlayer", "StarterPlayerScripts", "Lobby", "LobbyView" }
local PICKER = { "StarterPlayer", "StarterPlayerScripts", "Lobby", "LobbyPicker" }

-- a stand-in for LobbyPicker as LobbyView sees it: a level (nil when hidden) and change listeners
local function stub(level: number?): any
	local p: any = { value = level, listeners = {} }
	p.level = function(): number?
		return p.value
	end
	p.changed = function(fn: () -> ())
		table.insert(p.listeners, fn)
	end
	p.set = function(v: number?)
		p.value = v
		for _, fn in p.listeners do
			fn()
		end
	end
	return p
end

return t.spec("f0148 the lobby's level picker", function(it)
	it("START says which level it starts when the picker gives one, and is as before without", function()
		t.expect(Lobby.button("idle", true, 3).text).toBe("START LEVEL 3")
		t.expect(Lobby.button("idle", true, 3).enabled).toBe(true)
		t.expect(Lobby.button("idle", true).text).toBe("START GAME")
		t.expect(Lobby.button("going", true, 3).text).toBe("STARTING...")
		t.expect(Lobby.button("cooling", true, 3).text).toBe("START GAME")
		t.expect(Lobby.button("idle", false, 3).text).toBe("UNAVAILABLE")
	end)

	-- Starts ------------------------------------------------------------------------------------------------------

	local function server(choose: any): any
		local s = fake.server(lobby, { GamePlaceId = 4242 })
		local mod = s.boot(sourceOf(STARTS))
		mod.choosing(choose)
		return s
	end

	it(
		"a press that Travel lets go hands the player and the requested level to the store hook, before the teleport",
		function()
			local seen: { any } = {}
			local s: any
			s = server(function(player: any, requested: any)
				table.insert(seen, { player = player, requested = requested, teleports = #s.engine.calls })
			end)
			local p = fake.player(31)
			s.join(p)
			s.press(p, 3)
			t.expect(#seen).toBe(1)
			t.expect(seen[1].player).toBe(p)
			t.expect(seen[1].requested).toBe(3)
			t.expect(seen[1].teleports).toBe(0) -- the choice is stored first
			t.expect(#s.engine.calls).toBe(1)
		end
	)

	it(
		"presses Travel refuses (one under way) reach neither the hook nor the engine; a press with no level passes nil",
		function()
			local seen: { any } = {}
			local s = server(function(_player: any, requested: any)
				table.insert(seen, { requested = requested })
			end)
			local p = fake.player(32)
			s.join(p)
			for _ = 1, 4 do
				s.press(p)
			end
			t.expect(#seen).toBe(1)
			t.expect(seen[1].requested).toBe(nil)
			t.expect(#s.engine.calls).toBe(1)
		end
	)

	it(
		"a press that does not go keeps its level for the next press that does, which may carry none",
		function()
			local seen: { any } = {}
			local s = server(function(_player: any, requested: any)
				table.insert(seen, { level = requested })
			end)
			local p = fake.player(34)
			s.join(p)
			s.engine.mode = "hold"
			s.press(p, 2) -- goes: stored 2, the teleport held
			s.press(p, 3) -- refused while one is under way: kept
			s.release(1, true) -- that teleport fails: a cool-down
			s.tick(5)
			s.engine.mode = "error" -- this one fails too, so a later press can go
			s.press(p) -- a press with no level (a server-side press, as f0145's after a purchase) goes with the kept 3
			t.expect(#seen).toBe(2)
			t.expect(seen[1].level).toBe(2)
			t.expect(seen[2].level).toBe(3)
			s.tick(Travel.DEFAULT.coolSeconds + 1) -- past the cool-down
			s.press(p) -- nothing kept now: no level
			t.expect(#seen).toBe(3)
			t.expect(seen[3].level).toBe(nil)
		end
	)

	it("with no destination nothing is chosen and nothing teleports", function()
		local seen = 0
		local s = fake.server(lobby, {})
		s.boot(sourceOf(STARTS)).choosing(function()
			seen += 1
		end)
		local p = fake.player(33)
		s.join(p)
		s.press(p, 2)
		t.expect(seen).toBe(0)
		t.expect(#s.engine.calls).toBe(0)
	end)

	-- LobbyView ---------------------------------------------------------------------------------------------------

	it("LobbyView shows the picker's level on START and sends it; a hidden picker sends nothing", function()
		local c = fake.client(lobby)
		local view = c.boot(sourceOf(VIEW))
		local p = stub(3)
		view.usePicker(p)
		t.expect(c.find("Start").Text).toBe("START LEVEL 3")
		c.activate()
		t.expect(c.fired[#c.fired]).toEqual({ 3 })
		p.set(2)
		t.expect(c.find("Start").Text).toBe("START LEVEL 2")
		c.activate()
		t.expect(c.fired[#c.fired]).toEqual({ 2 })
		p.set(nil)
		t.expect(c.find("Start").Text).toBe("START GAME")
		c.activate()
		t.expect(#c.fired[#c.fired]).toBe(0)
	end)

	it(
		"LobbyView keeps the status's text with a picker: STARTING... while going, START LEVEL n again when idle",
		function()
			local c = fake.client(lobby)
			local view = c.boot(sourceOf(VIEW))
			view.usePicker(stub(4))
			c.status("going", true)
			t.expect(c.find("Start").Text).toBe("STARTING...")
			t.expect(c.find("Start").Active).toBe(false)
			c.status("idle", true)
			t.expect(c.find("Start").Text).toBe("START LEVEL 4")
		end
	)

	it("LobbyView without a picker is as before", function()
		local c = fake.client(lobby)
		c.boot(sourceOf(VIEW))
		t.expect(c.find("Start").Text).toBe("START GAME")
		c.activate()
		t.expect(#c.fired[#c.fired]).toBe(0)
	end)

	-- LobbyPicker, on a stub engine ------------------------------------------------------------------------------

	type Inst = { [string]: any }
	local function signal(): any
		local s: any = { fns = {} }
		s.Connect = function(_: any, fn: (...any) -> ())
			table.insert(s.fns, fn)
			return { Disconnect = function() end }
		end
		s.fire = function(...: any)
			for _, fn in s.fns do
				fn(...)
			end
		end
		return s
	end
	local function instance(class: string, name: string?): Inst
		local children: { Inst } = {}
		local self: Inst
		self = setmetatable({ ClassName = class, Name = name or class, children = children }, {
			__index = function(_: any, key: string): any
				if key == "WaitForChild" or key == "FindFirstChild" then
					return function(_: any, n: string): Inst?
						for _, c in children do
							if c.Name == n then
								return c
							end
						end
						assert(key == "FindFirstChild", `WaitForChild("{n}") would wait for ever`)
						return nil
					end
				end
				return nil
			end,
			__newindex = function(tbl: any, key: string, value: any)
				if key == "Parent" and value ~= nil then
					table.insert(value.children, tbl)
				end
				rawset(tbl, key, value)
			end,
		}) :: any
		if class == "TextButton" then
			rawset(self, "Activated", signal())
		end
		return self
	end

	local function picker(best: number?): any
		local attributes: { [string]: any } = { [Best.ATTRIBUTE] = best }
		local changed = signal()
		local bound: { any } = {}
		local player = instance("Player", "LocalPlayer")
		rawset(player, "GetAttribute", function(_: any, n: string): any
			return attributes[n]
		end)
		rawset(player, "GetAttributeChangedSignal", function(_: any, n: string): any
			assert(n == Best.ATTRIBUTE, n)
			return changed
		end)
		local gui = instance("PlayerGui", "PlayerGui")
		gui.Parent = player
		local screen = instance("ScreenGui", "Lobby")
		screen.Parent = gui
		local backdrop = instance("Frame", "Backdrop")
		backdrop.Parent = screen
		local env: { [string]: any } = {
			game = {
				GetService = function(_: any, name: string): any
					if name == "Players" then
						return { LocalPlayer = player }
					elseif name == "ContextActionService" then
						return {
							BindActionAtPriority = function(
								_: any,
								action: string,
								fn: any,
								touch: boolean,
								priority: number,
								...: any
							)
								table.insert(bound, {
									action = action,
									fn = fn,
									touch = touch,
									priority = priority,
									keys = { ... },
								})
							end,
						}
					end
					error(`LobbyPicker asks for {name}`)
				end,
			},
			require = function(path: string): any
				local feature = string.match(path, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
				assert(feature, `LobbyPicker requires {path}`)
				return (require :: any)("@logic/" .. feature)
			end,
			Instance = {
				new = function(class: string): Inst
					return instance(class)
				end,
			},
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
				fromRGB = function(r: number, g: number, b: number): any
					return { R = r, G = g, B = b }
				end,
			},
			Enum = setmetatable({}, {
				__index = function(groups: any, group: string): any
					local g = setmetatable({}, {
						__index = function(items: any, item: string): any
							local v =
								{ Name = item, Value = if item == "High" then 2000 else 0, group = group }
							rawset(items, item, v)
							return v
						end,
					})
					rawset(groups, group, g)
					return g
				end,
			}),
		}
		local mod = luau.load(sourceOf(PICKER), { debugName = "LobbyPicker", environment = env })()
		local p = mod.new()
		p.attach()
		local function find(n: string): Inst
			for _, c in backdrop.children do
				if c.Name == n then
					return c
				end
			end
			error(`no {n} under the lobby's Backdrop`)
		end
		return {
			p = p,
			down = find("LevelDown"),
			up = find("LevelUp"),
			setBest = function(v: number)
				attributes[Best.ATTRIBUTE] = v
				changed.fire()
			end,
			bound = bound,
			-- a key press (state Begin unless given) through the bound action; the action's result, or nil if unbound
			key = function(name: string, state: string?): any
				for _, b in bound do
					for _, k in b.keys do
						if k.Name == name then
							return b.fn(
								b.action,
								env.Enum.UserInputState[state or "Begin"],
								{ KeyCode = { Name = name } }
							)
						end
					end
				end
				return nil
			end,
		}
	end

	it(
		"LobbyPicker's arrows are hidden while the best is 1 or unknown, and show once it is 2 or more",
		function()
			for _, best in { nil :: number?, 1 } do
				local k = picker(best)
				t.expect(k.down.Visible).toBe(false)
				t.expect(k.up.Visible).toBe(false)
				t.expect(k.p.level()).toBe(nil)
			end
			local k = picker(1)
			k.setBest(3) -- the server's read arrives after the screen
			t.expect(k.down.Visible).toBe(true)
			t.expect(k.up.Visible).toBe(true)
			t.expect(k.p.level()).toBe(3)
		end
	)

	it(
		"LobbyPicker starts on the best; ◀ steps lower, ▶ higher, within 1..best; only the open way is live",
		function()
			local k = picker(3)
			t.expect(k.p.level()).toBe(3)
			t.expect(k.up.Active).toBe(false)
			t.expect(k.down.Active).toBe(true)
			k.down.Activated.fire()
			t.expect(k.p.level()).toBe(2)
			k.down.Activated.fire()
			k.down.Activated.fire()
			t.expect(k.p.level()).toBe(1)
			t.expect(k.down.Active).toBe(false)
			k.up.Activated.fire()
			t.expect(k.p.level()).toBe(2)
			t.expect(k.down.Text).toBe("◀")
			t.expect(k.up.Text).toBe("▶")
		end
	)

	it("LobbyPicker tells LobbyView of every change: a step, a key and a new best", function()
		local k = picker(3)
		local heard = 0
		k.p.changed(function()
			heard += 1
		end)
		k.down.Activated.fire()
		k.key("Right")
		k.setBest(5)
		t.expect(heard).toBe(3)
	end)

	it(
		"LobbyPicker binds Left and Right above the camera; they step the level and are sunk only when they do",
		function()
			local k = picker(4)
			t.expect(#k.bound).toBe(1)
			local b = k.bound[1]
			t.expect(b.priority >= 2000).toBe(true) -- Enum.ContextActionPriority.High: above the default camera's arrow keys
			t.expect(b.touch).toBe(false) -- no on-screen button of its own
			local names: { string } = {}
			for _, key in b.keys do
				table.insert(names, key.Name)
			end
			table.sort(names)
			t.expect(names).toEqual({ "Left", "Right" })
			t.expect(k.key("Left").Name).toBe("Sink")
			t.expect(k.p.level()).toBe(3)
			t.expect(k.key("Right").Name).toBe("Sink")
			t.expect(k.p.level()).toBe(4)
			t.expect(k.key("Left", "End").Name).toBe("Pass") -- the release does nothing
			t.expect(k.p.level()).toBe(4)
			local none = picker(1)
			t.expect(none.key("Left").Name).toBe("Pass") -- no choice: the camera keeps the key
			t.expect(none.p.level()).toBe(nil)
		end
	)

	it("LobbyPicker's arrows sit either side of START, touch-sized, selectable for a controller", function()
		local k = picker(3)
		for _, b in { k.down, k.up } do
			t.expect(b.Size.X.Offset >= Lobby.BUTTON_MIN_PX).toBe(true)
			t.expect(b.Size.Y.Offset >= Lobby.BUTTON_MIN_PX).toBe(true)
			t.expect(b.Position.Y.Scale).toBe(0.74) -- START's row
			t.expect(b.Selectable).toBe(true)
		end
		t.expect(k.down.Position.X.Scale < 0.25).toBe(true) -- left of START (0.25 to 0.75)
		t.expect(k.up.Position.X.Scale > 0.75).toBe(true)
	end)
end)
