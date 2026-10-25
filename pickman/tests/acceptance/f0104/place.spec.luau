--!strict
-- f0104 AC4: the keys' adapters. Controls binds every key in View.KEYS, hears key-up and cancel as well as key-down
-- (the arrows are held), tracks them with View.press and hands them to the camera; E sends the aimed shot (only
-- Blaster.intent of a heading, on the Intent remote) and Space sends the hop (f0101's Hop.INTENT, checked in its
-- place.spec). The camera's part, the arrows and the aim, comes in through Controls.keys. The touch side keeps what
-- R0012 builds on: Controls.start(onSnap) and Camera.snap stay, and Main still starts Controls with Camera.snap
-- first. Camera looks with View.steer and aims with View.aim.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function client(name: string): any
	local node: any = game
	for _, part in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(part)
	end
	t.expect(node ~= nil).toBe(true)
	return node
end

local function source(name: string): string
	local src = string.gsub(client(name).Source, "%-%-[^\n]*", "")
	return src
end

local function logic(name: string): any
	local node: any = game
	for _, part in { "ReplicatedStorage", "Shared", "Logic", name } do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function resolved(from: any): { any }
	local out = {}
	for _, spec in place.requireSpecs(from.Source) do
		local target = place.resolveRequire(from, spec)
		if target == nil then
			error(`{from:GetFullName()}: require of "{spec}" does not resolve in the place`)
		end
		table.insert(out, target)
	end
	return out
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

return t.spec("f0104 key adapters", function(it)
	it("Controls binds every key of View.KEYS through View.action, at high priority", function()
		local src = source("Controls")
		for _, word in { "View.KEYS", "View.action(", "BindActionAtPriority", "ContextActionPriority.High" } do
			t.expect(has(src, word)).toBe(true)
		end
	end)

	it("it hears a key going up and a cancelled input, and tracks the arrows with View.press", function()
		local src = source("Controls")
		t.expect(has(src, "UserInputState.End")).toBe(true)
		t.expect(has(src, "UserInputState.Cancel")).toBe(true)
		t.expect(has(src, "View.press(")).toBe(true)
	end)

	it("the camera's part comes in through Controls.keys: arrows and aim", function()
		local src = source("Controls")
		t.expect(has(src, "function Controls.keys(")).toBe(true)
		for _, field in { "arrows", "aim" } do
			t.expect(string.find(src, "%." .. field .. "%(") ~= nil).toBe(true)
		end
	end)

	it("the touch side keeps what it builds on: Controls.start(onSnap) and Camera.snap", function()
		t.expect(string.find(source("Controls"), "function Controls%.start%(%s*onSnap") ~= nil).toBe(true)
		t.expect(has(source("Camera"), "function Camera.snap(")).toBe(true)
		local main = source("Main")
		t.expect(string.find(main, "Controls%.start%(%s*Camera%.snap") ~= nil).toBe(true)
	end)

	it("Main hands the camera's arrows and aim to Controls.keys, before Ready", function()
		local main = source("Main")
		local call = string.match(main, "Controls%.keys%b()") or ""
		for _, part in { "Camera.arrows", "Camera.aim" } do
			t.expect(has(call, part)).toBe(true)
		end
		local keys = string.find(main, "Controls.keys(", 1, true)
		local ready = string.find(main, "ready:FireServer(", 1, true)
		t.expect(keys ~= nil and ready ~= nil and (keys :: number) < (ready :: number)).toBe(true)
	end)

	it("Camera looks with View.steer and aims with View.aim, and has the arrows' entry point", function()
		local src = source("Camera")
		for _, word in { "View.steer(", "View.aim(", "function Camera.arrows(", "function Camera.aim(" } do
			t.expect(has(src, word)).toBe(true)
		end
		-- the mouse still looks through View.look (R0012 guards that very line), and the arrow look runs after it,
		-- on the look the mouse left
		local mouse = string.find(src, "View.look(look, delta.X, delta.Y)", 1, true)
		local arrow = string.find(src, "View%.steer%(%s*steer%s*,%s*look%s*,%s*arrows%s*,%s*dt%s*%)")
		t.expect(mouse ~= nil and arrow ~= nil and (mouse :: number) < (arrow :: number)).toBe(true)
		t.expect(string.find(src, "look%s*=%s*steer%.look") ~= nil).toBe(true)
	end)

	it(
		"E sends the shot as Blaster.intent of the aim, on the one Intent remote, with no wire strings of its own",
		function()
			local controls = client("Controls")
			t.expect(table.find(resolved(controls), logic("Blaster")) ~= nil).toBe(true)
			local src = source("Controls")
			t.expect(string.find(src, ":FireServer%(%s*Blaster%.intent%(") ~= nil).toBe(true)
			local remotes = 0
			for _ in string.gmatch(src, ':WaitForChild%("Intent"%)') do
				remotes += 1
			end
			t.expect(remotes).toBe(1)
			for _, wire in { '"FireN"', '"FireE"', '"FireS"', '"FireW"' } do
				t.expect(has(src, wire)).toBe(false)
			end
		end
	)

	it("Space sends f0101's Hop.INTENT on the Intent remote, and never the string Jump", function()
		local src = source("Controls")
		t.expect(
			string.find(src, 'action%s*==%s*"Jump"%s*then%s*intent:FireServer%(%s*Hop%.INTENT%s*%)') ~= nil
		)
			.toBe(true)
		t.expect(has(src, 'FireServer("Jump")')).toBe(false)
		t.expect(has(src, 'FireServer("Hop")')).toBe(false) -- the constant, not a copy of it
	end)

	it("the arrow look stays on the client: Camera sends nothing", function()
		t.expect(has(source("Camera"), "FireServer")).toBe(false)
		t.expect(has(source("Camera"), "Remotes")).toBe(false)
	end)
end)
