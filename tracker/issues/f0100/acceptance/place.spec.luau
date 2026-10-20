--!strict
-- f0100 AC5: the blaster's adapters are thin and the server stays the judge. A shot travels as a fire intent on
-- the existing Intent remote (no new remote, and the server adapter is unchanged: Session.submit takes it; the key
-- that sends it is f0104's, checked there). The HUD draws the frame's count with Hud.shotIcons, and the beam
-- is drawn from View.beamEnd, decides nothing and sends nothing.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function find(path: { string }): any
	local node = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function client(name: string): any
	return find({ "StarterPlayer", "StarterPlayerScripts", "Client", name })
end

local function server(name: string): any
	return find({ "ServerScriptService", "Server", name })
end

-- a script's source without comments, so a mention in a comment proves nothing
local function source(node: any): string
	t.expect(node ~= nil).toBe(true)
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

local function logic(name: string): any
	return find({ "ReplicatedStorage", "Shared", "Logic", name })
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

return t.spec("f0100 blaster adapters", function(it)
	it("Blaster is a Logic feature in the place", function()
		local node = logic("Blaster")
		t.expect(node ~= nil and node.ClassName).toBe("ModuleScript")
	end)

	it("the remotes are the same four: a shot rides the Intent remote", function()
		local names = {}
		for _, child in find({ "ReplicatedStorage", "Remotes" }):GetChildren() do
			table.insert(names, child.Name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "Intent", "PlayAgain", "Ready", "Snapshot" })
	end)

	it("the server adapter is untouched by the blaster: it hands every intent to Session.submit", function()
		local src = source(server("Sessions"))
		t.expect(has(src, "Session.submit(s, tostring(player.UserId), raw)")).toBe(true)
		for _, word in { "Blaster", '"FireN"', '"FireE"', '"FireS"', '"FireW"', "shots" } do
			t.expect(has(src, word)).toBe(false)
		end
	end)

	it("Main hands each frame's shots to the HUD and the frame to the beam", function()
		local src = source(client("Main"))
		t.expect(string.find(src, "HudView%.shots%(%s*frame%.shots%s*%)") ~= nil).toBe(true)
		t.expect(string.find(src, "BlastView%.push%(%s*frame%s*%)") ~= nil).toBe(true)
		t.expect(string.find(src, "BlastView%.start%(%s*Camera%.pose%s*%)") ~= nil).toBe(true)
	end)

	it("HudView draws the shots with Hud.shotIcons and has a shots entry point", function()
		local src = source(client("HudView"))
		t.expect(has(src, "function HudView.shots(")).toBe(true)
		t.expect(has(src, "Hud.shotIcons(")).toBe(true)
	end)

	it(
		"the beam is a client module that draws the server's shot, from View.beamEnd, and decides nothing",
		function()
			local node = client("BlastView")
			t.expect(node ~= nil and node.ClassName).toBe("ModuleScript")
			local src = source(node)
			t.expect(has(src, "View.beamEnd(")).toBe(true)
			t.expect(has(src, "function BlastView.push(")).toBe(true)
			-- it draws only a shot the server took in that frame's step
			t.expect(string.find(src, "frame%.shot") ~= nil).toBe(true)
			t.expect(string.find(src, "%.tick%s*==%s*frame%.tick") ~= nil).toBe(true)
			t.expect(has(src, "function BlastView.fire(")).toBe(false)
			for _, word in
				{ "FireServer", "OnClientEvent", "Logic/Ghosts", "Logic/Blaster", "play.score", ".shots" }
			do
				t.expect(has(src, word)).toBe(false)
			end
		end
	)
end)
