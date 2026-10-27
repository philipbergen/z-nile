--!strict
-- R0058 code review 001 F2: LobbyPad's real source runs on a small stub engine, so the lobby's controller selection is
-- pinned by what it does: with a gamepad as the last input, START GAME is selected at start and when the input type
-- changes to a gamepad with nothing selected; a keyboard, mouse or touch selects nothing; a selection already made (a
-- board tab) is kept; a selection cleared while a gamepad is the last input (ButtonB) is set back to START GAME, and
-- one cleared with the mouse as the last input stays clear. The stub fires SelectedObject's change signal only on a
-- real change, as Roblox does.
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local lobby = place.load("lobby.project.json")
local SOURCE = (function(): string
	local node = lobby:FindFirstChild("StarterPlayer")
	for _, child in { "StarterPlayerScripts", "Lobby", "LobbyPad" } do
		node = node and node:FindFirstChild(child)
	end
	assert(node, "no Lobby.LobbyPad in the lobby place")
	return node.Source
end)()

type Signal = { Connect: (any, (...any) -> ()) -> (), fire: (...any) -> () }
local function signal(): Signal
	local fns: { (...any) -> () } = {}
	return {
		Connect = function(_: any, fn: (...any) -> ())
			table.insert(fns, fn)
		end,
		fire = function(...: any)
			for _, fn in fns do
				fn(...)
			end
		end,
	}
end

local function button(name: string): any
	return {
		Name = name,
		IsA = function(_: any, class: string): boolean
			return class == "GuiObject" or class == "TextButton"
		end,
	}
end

type Lobby = {
	start: any,
	tab: any,
	selected: () -> any,
	select: (obj: any) -> (), -- the player's own selection (or ButtonB's clear, with nil)
	input: (typeName: string) -> (), -- the last input type changes
}

local function boot(lastInput: string): Lobby
	local start, tab = button("Start"), button("Boardall")
	local selectedChanged = signal()
	local lastChanged = signal()
	local last = { name = lastInput }
	local gui = {
		selected = nil :: any,
	}
	local guiService = setmetatable({
		GetPropertyChangedSignal = function(_: any, property: string): Signal
			assert(property == "SelectedObject", property)
			return selectedChanged
		end,
	}, {
		__index = function(_: any, key: string): any
			if key == "SelectedObject" then
				return gui.selected
			end
			return nil
		end,
		__newindex = function(_: any, key: string, value: any)
			assert(key == "SelectedObject", key)
			if gui.selected ~= value then
				gui.selected = value
				selectedChanged.fire()
			end
		end,
	})
	local playerGui = {
		FindFirstChild = function(_: any, name: string, recursive: boolean?): any
			if recursive and name == "Start" then
				return start
			end
			return nil
		end,
	}
	local services: { [string]: any } = {
		GuiService = guiService,
		Players = {
			LocalPlayer = {
				WaitForChild = function(_: any, name: string): any
					assert(name == "PlayerGui", name)
					return playerGui
				end,
			},
		},
		UserInputService = {
			GetLastInputType = function(_: any): any
				return { Name = last.name }
			end,
			LastInputTypeChanged = lastChanged,
		},
	}
	local env = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
		},
		require = function(spec: string): any
			local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			return (require :: any)("@logic/" .. assert(name, spec))
		end,
	}
	local module = luau.load(SOURCE, { environment = env, debugName = "LobbyPad" })() :: any
	module.start()
	return {
		start = start,
		tab = tab,
		selected = function(): any
			return gui.selected
		end,
		select = function(obj: any)
			guiService.SelectedObject = obj
		end,
		input = function(typeName: string)
			last.name = typeName
			lastChanged.fire({ Name = typeName })
		end,
	}
end

return t.spec("LobbyPad on a stub engine", function(it)
	it("a gamepad as the last input at start selects START GAME", function()
		local l = boot("Gamepad1")
		t.expect(l.selected()).toBe(l.start)
	end)

	it("a keyboard, a mouse or a touch as the last input selects nothing", function()
		for _, kind in { "Keyboard", "MouseButton1", "MouseMovement", "Touch" } do
			t.expect(boot(kind).selected()).toBe(nil)
		end
	end)

	it("a change to a gamepad with nothing selected selects START GAME; to a keyboard, nothing", function()
		local l = boot("Keyboard")
		l.input("Keyboard")
		t.expect(l.selected()).toBe(nil)
		l.input("Gamepad2")
		t.expect(l.selected()).toBe(l.start)
	end)

	it("a selection already made (a board tab) is kept when the gamepad is used", function()
		local l = boot("Gamepad1")
		l.select(l.tab)
		t.expect(l.selected()).toBe(l.tab)
		l.input("Gamepad1")
		t.expect(l.selected()).toBe(l.tab)
	end)

	it("a selection cleared with a gamepad as the last input (ButtonB) is set back to START GAME", function()
		local l = boot("Gamepad1")
		l.select(l.tab)
		l.select(nil)
		t.expect(l.selected()).toBe(l.start)
	end)

	it("a selection cleared with the mouse as the last input stays clear", function()
		local l = boot("Gamepad1")
		l.input("MouseMovement")
		l.select(nil)
		t.expect(l.selected()).toBe(nil)
	end)
end)
