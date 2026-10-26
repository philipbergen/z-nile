--!strict
-- f0146 AC3, AC4 and AC5: the gamepad's adapters and documents, as source pins read with comments removed. Controls
-- binds Pad.BUTTONS' key codes beside View.KEYS', reads View.action or Pad.action, passes Pad.CONTINUE on (so
-- FlowView hears it), and never says "Gamepad" (f0027 pins that). Sticks, booted by Main, polls the first gamepad's
-- Thumbstick1 into Pad.steer every frame and sends what it emits on the Intent remote. Camera polls
-- Thumbstick2 into Pad.look and View.look before View.steer. In the lobby, Main boots LobbyPad after LobbyView, and
-- LobbyPad selects the Start button when the last input is a gamepad (Pad.isPad), at start and on
-- LastInputTypeChanged, only when nothing is selected. What the pins leave to the code review: that the polls run every
-- frame, and the Roblox selection behaviour itself (OC1). game-design.md's Platforms row includes gamepad and states
-- the map; architecture.md declares Pad -> View, Pad -> Movement and the Pad row.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()
local lobbyPlace = place.load("lobby.project.json")

local function node(root: any, path: { string }): any
	local n: any = root
	for _, part in path do
		n = n and n:FindFirstChild(part)
	end
	if n == nil then
		error(`no {table.concat(path, ".")}`)
	end
	return n
end

local function code(text: string): string
	local noBlock = string.gsub(text, "%-%-%[(=*)%[.-%]%1%]", "")
	local noLine = string.gsub(noBlock, "%-%-[^\n]*", "")
	return noLine
end

local function client(name: string): string
	return code(node(gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", name }).Source)
end

local function lobbyClient(name: string): string
	return code(node(lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby", name }).Source)
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

local function resolvesPad(root: any, path: { string }): boolean
	local from = node(root, path)
	local pad = node(root, { "ReplicatedStorage", "Shared", "Logic", "Pad" })
	for _, spec in place.requireSpecs(from.Source) do
		if place.resolveRequire(from, spec) == pad then
			return true
		end
	end
	return false
end

return t.spec("f0146 the gamepad's adapters and documents", function(it)
	it(
		"Controls binds Pad.BUTTONS beside View.KEYS, reads View.action or Pad.action, passes the continue on, and never says Gamepad",
		function()
			t.expect(
				resolvesPad(gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", "Controls" })
			)
				.toBe(true)
			local src = client("Controls")
			t.expect(has(src, "Pad.BUTTONS")).toBe(true)
			t.expect(has(src, "View.KEYS")).toBe(true)
			t.expect(string.find(src, "View%.action%([^)]*%)%s*or%s*Pad%.action%(") ~= nil).toBe(true)
			t.expect(has(src, "Pad.CONTINUE")).toBe(true)
			t.expect(has(src, "ContextActionResult.Pass")).toBe(true)
			t.expect(has(src, "Gamepad")).toBe(false)
		end
	)

	it(
		"Sticks, booted by Main, folds the first gamepad's Thumbstick1 into Pad.steer every frame and sends what it emits",
		function()
			t.expect(resolvesPad(gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", "Sticks" }))
				.toBe(true)
			local src = client("Sticks")
			for _, needle in
				{
					"GetGamepadState(",
					"Pad.GAMEPAD",
					"Thumbstick1",
					"Pad.steer(",
					"Heartbeat",
					':WaitForChild("Intent")',
				}
			do
				if not has(src, needle) then
					error(`Sticks lacks {needle}`)
				end
			end
			t.expect(string.find(src, ":FireServer%(%s*turn%s*%)") ~= nil).toBe(true)
			t.expect(string.find(client("Main"), "Sticks%.start%(%)") ~= nil).toBe(true)
		end
	)

	it("Camera polls Thumbstick2 and applies Pad.look through View.look before View.steer", function()
		t.expect(resolvesPad(gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", "Camera" }))
			.toBe(true)
		local src = client("Camera")
		t.expect(has(src, "Thumbstick2")).toBe(true)
		local looked = string.find(src, "View%.look%(%s*look%s*,%s*Pad%.look%(")
		local steered = string.find(src, "View.steer(", 1, true)
		t.expect(looked ~= nil and steered ~= nil and (looked :: number) < (steered :: number)).toBe(true)
		t.expect(has(src, "FireServer")).toBe(false)
	end)

	it(
		"the lobby's Main boots LobbyPad after LobbyView; LobbyPad selects Start for a gamepad only, when nothing is selected",
		function()
			local main = lobbyClient("Main")
			local view = string.find(main, 'require("./LobbyView").start()', 1, true)
			local pad = string.find(main, 'require("./LobbyPad").start()', 1, true)
			t.expect(view ~= nil and pad ~= nil and (view :: number) < (pad :: number)).toBe(true)
			t.expect(
				resolvesPad(lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "LobbyPad" })
			)
				.toBe(true)
			local src = lobbyClient("LobbyPad")
			for _, needle in
				{
					"SelectedObject",
					"Pad.isPad(",
					"GetLastInputType()",
					"LastInputTypeChanged",
					'"Start"',
				}
			do
				if not has(src, needle) then
					error(`LobbyPad lacks {needle}`)
				end
			end
			t.expect(string.find(src, "SelectedObject%s*==%s*nil") ~= nil).toBe(true)
			t.expect(has(src, "FireServer")).toBe(false) -- the button's own handler starts the game
		end
	)

	it(
		"game-design.md's Platforms row includes gamepad and states the map; architecture.md declares Pad",
		function()
			local design = fs.readFile(".tracker/game-design.md")
			for _, phrase in
				{
					"| Platforms | Desktop (keyboard and mouse), mobile (touch) and gamepad: every input produces the same intents (f0146)",
					"**Gamepad** (f0146",
					"left stick and the D-pad turn",
					"right stick looks",
					"R3 recentres",
					"bottom face button jumps",
					"R2 fires",
				}
			do
				if not has(design, phrase) then
					error(`game-design.md lacks: {phrase}`)
				end
			end
			t.expect(has(design, "Gamepad isn't planned")).toBe(false)
			local arch = fs.readFile(".tracker/architecture.md")
			local deps = "\n" .. (string.match(arch, "```deps\n(.-)```") or "")
			t.expect(has(deps, "\nPad -> View\n")).toBe(true)
			t.expect(has(deps, "\nPad -> Movement\n")).toBe(true)
			t.expect(has(arch, "\n| Pad |")).toBe(true)
		end
	)
end)
