--!strict
-- f0143 AC3 and AC4: the boost's adapters and documents. Controls keeps one Boost.Taps per input kind: W's Forward
-- and a swipe up (a touch "turn" effect whose intent is Forward) are folded through Boost.tap, and a pair sends
-- Boost.INTENT on the one Intent remote, never the string. Main hands Boost.status of the frame's boosted to
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
	it("Controls folds W's Forward and a swipe up through Boost.tap, one Taps each, and sends Boost.INTENT, never the string", function()
		t.expect(boostModule ~= nil).toBe(true)
		local controls = client("Controls")
		t.expect(resolves(controls, boostModule)).toBe(true)
		local src = source("Controls")
		local taps = 0
		for _ in string.gmatch(src, "Boost%.taps%(%)") do
			taps += 1
		end
		t.expect(taps).toBe(2) -- the keys' and the touches'
		local folds = 0
		for _ in string.gmatch(src, "Boost%.tap%(") do
			folds += 1
		end
		t.expect(folds >= 2).toBe(true)
		t.expect(string.find(src, ":FireServer%(%s*Boost%.INTENT%s*%)") ~= nil).toBe(true)
		t.expect(has(src, 'FireServer("Boost")')).toBe(false)
		t.expect(string.find(src, "os%.clock%(%)") ~= nil).toBe(true) -- real seconds, the client's clock
		-- the touch path: a turn effect's Forward is folded too
		t.expect(string.find(src, 'effect%.intent%s*==%s*"Forward"') ~= nil).toBe(true)
	end)

	it("Main hands Boost.status to HudView.boost and the frame's boosted to Camera.boosted; Camera widens by Boost.fov", function()
		local main = source("Main.client")
		t.expect(string.find(main, "HudView%.boost%(%s*Boost%.status%(%s*frame%.boosted%s*,%s*frame%.tick%s*%)%s*%)") ~= nil)
			.toBe(true)
		t.expect(string.find(main, "Camera%.boosted%(%s*frame%.boosted%s*%)") ~= nil).toBe(true)
		local camera = source("Camera")
		t.expect(has(camera, "function Camera.boosted(")).toBe(true)
		t.expect(has(camera, "Boost.fov(")).toBe(true)
		t.expect(has(camera, "FieldOfView")).toBe(true)
		t.expect(has(source("HudView"), "function HudView.boost(")).toBe(true)
		t.expect(has(camera, "FireServer")).toBe(false)
	end)

	it("game-design.md states the boost's trigger and numbers; architecture.md declares Session -> Boost", function()
		local design = fs.readFile(".tracker/game-design.md")
		for _, phrase in {
			"**Speed boost** (f0143",
			"double tap on **W**",
			"two quick swipes up",
			"1.5 times",
			"22 steps",
			"90 steps",
			"0.3 s",
		} do
			if not has(design, phrase) then
				error(`game-design.md lacks: {phrase}`)
			end
		end
		local arch = fs.readFile(".tracker/architecture.md")
		local deps = string.match(arch, "```deps\n(.-)```") or ""
		t.expect(string.find(deps, "\nSession %-> Boost\n") ~= nil or string.find(deps, "^Session %-> Boost\n") ~= nil)
			.toBe(true)
		t.expect(string.find(arch, "\n| Boost |", 1, true) ~= nil).toBe(true)
	end)
end)
