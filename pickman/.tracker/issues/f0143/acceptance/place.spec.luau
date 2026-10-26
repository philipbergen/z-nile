--!strict
-- f0143 AC3 and AC4: the boost's adapters and documents. Controls' double taps run in controls.spec (a stub with a
-- scripted clock); here only what the stub can't see: Controls requires Logic/Boost, sends the constant, never the
-- string, and reads the client's real clock. Main hands Boost.status of the frame's boosted to
-- HudView.boost and the frame's boosted to Camera.boosted, and Camera widens its view by Boost.fov. These are
-- source pins, read with comments removed; what they leave to the code review: the order of Forward and the boost
-- on one press, and the colours of the HUD chevron (OC1). game-design.md states the boost; architecture.md declares
-- Session -> Boost and its row.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function node(path: { string }): any
	local n: any = game
	for _, part in path do
		n = n and n:FindFirstChild(part)
	end
	return n
end

local function client(name: string): any
	local n = node({ "StarterPlayer", "StarterPlayerScripts", "Client", name })
	if n == nil then
		error(`the game place has no client script {name}`)
	end
	return n
end

local function code(text: string): string
	local noBlock = string.gsub(text, "%-%-%[(=*)%[.-%]%1%]", "")
	local noLine = string.gsub(noBlock, "%-%-[^\n]*", "")
	return noLine
end

local function source(name: string): string
	return code(client(name).Source)
end

local function resolves(from: any, target: any): boolean
	for _, spec in place.requireSpecs(from.Source) do
		if place.resolveRequire(from, spec) == target then
			return true
		end
	end
	return false
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

local boostModule = node({ "ReplicatedStorage", "Shared", "Logic", "Boost" })

return t.spec("f0143 the boost's adapters and documents", function(it)
	it(
		"Controls requires Logic/Boost, sends Boost.INTENT, never the string, and reads the client's clock",
		function()
			t.expect(boostModule ~= nil).toBe(true)
			local controls = client("Controls")
			t.expect(resolves(controls, boostModule)).toBe(true)
			local src = source("Controls")
			t.expect(string.find(src, ":FireServer%(%s*Boost%.INTENT%s*%)") ~= nil).toBe(true)
			t.expect(has(src, 'FireServer("Boost")')).toBe(false)
			t.expect(string.find(src, "os%.clock%(%)") ~= nil).toBe(true) -- real seconds, the client's clock
		end
	)

	it(
		"Main hands Boost.status to HudView.boost and the frame's boosted to Camera.boosted; Camera widens by Boost.fov",
		function()
			local main = source("Main")
			t.expect(
				string.find(
					main,
					"HudView%.boost%(%s*Boost%.status%(%s*frame%.boosted%s*,%s*frame%.tick%s*%)%s*%)"
				) ~= nil
			).toBe(true)
			t.expect(string.find(main, "Camera%.boosted%(%s*frame%.boosted%s*%)") ~= nil).toBe(true)
			local camera = source("Camera")
			t.expect(has(camera, "function Camera.boosted(")).toBe(true)
			-- the shown tick the hop uses, never the frame's (design review 002 F3; Boost.fov counts from it)
			t.expect(string.find(camera, "local%s+shown%s*=%s*View%.shownTick%(") ~= nil).toBe(true)
			t.expect(
				string.find(
					camera,
					"FieldOfView%s*=%s*View%.SCALE%.fieldOfView%s*%+%s*Boost%.fov%(%s*boosted%s*,%s*shown%s*%)"
				) ~= nil
			).toBe(true)
			-- the hop reads the same shown tick; f0126 adds a third argument (hopTicks), so the pin stops at `shown`
			t.expect(string.find(camera, "Hop%.rise%(%s*hopped%s*,%s*shown%s*[,)]") ~= nil).toBe(true)
			t.expect(has(camera, "FieldOfView")).toBe(true)
			local hud = source("HudView")
			t.expect(has(hud, "function HudView.boost(")).toBe(true)
			-- the chevron's place is Hud's (design review 001 F6), in the lives block's space
			t.expect(string.find(hud, "Hud%.boostIcon%(%s*l%s*,") ~= nil).toBe(true)
			t.expect(has(camera, "FireServer")).toBe(false)
		end
	)

	it(
		"game-design.md states the boost's trigger and numbers; architecture.md declares Session -> Boost",
		function()
			local design = fs.readFile(".tracker/game-design.md")
			for _, phrase in
				{
					"**Speed boost** (f0143",
					"double tap on **W**",
					"two quick swipes up",
					"the D-pad's Up",
					"left stick's click (L3)",
					"double push of the left stick up",
					"cancels a buffered turn",
					"1.5 times",
					"22 steps",
					"90 steps",
					"0.3 s",
				}
			do
				if not has(design, phrase) then
					error(`game-design.md lacks: {phrase}`)
				end
			end
			local arch = fs.readFile(".tracker/architecture.md")
			local deps = string.match(arch, "```deps\n(.-)```") or ""
			t.expect(
				string.find(deps, "\nSession %-> Boost\n") ~= nil
					or string.find(deps, "^Session %-> Boost\n") ~= nil
			).toBe(true)
			t.expect(string.find(arch, "\n| Boost |", 1, true) ~= nil).toBe(true)
		end
	)
end)
