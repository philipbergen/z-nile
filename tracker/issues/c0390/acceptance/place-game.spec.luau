--!strict
-- c0390 AC3: place.resolveRequire resolves @game paths from the root of the instance tree, as
-- Roblox does, and still rejects every other alias.
local place = require("@tests/lib/place")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local function make(class: string, name: string, parent: any?): any
	local i = roblox.Instance.new(class)
	i.Name = name
	i.Parent = parent
	return i
end

-- root/ReplicatedStorage/Shared/Logic/{View, Maze/Grid}; root/StarterPlayer/.../Client/{Main, Camera}
local root = make("Folder", "game")
local rs = make("Folder", "ReplicatedStorage", root)
local shared = make("Folder", "Shared", rs)
local logic = make("Folder", "Logic", shared)
local view = make("ModuleScript", "View", logic)
local maze = make("ModuleScript", "Maze", logic)
local grid = make("ModuleScript", "Grid", maze)
local sp = make("Folder", "StarterPlayer", root)
local sps = make("Folder", "StarterPlayerScripts", sp)
local client = make("Folder", "Client", sps)
local main = make("LocalScript", "Main", client)
local camera = make("ModuleScript", "Camera", client)

return t.spec("c0390 place.resolveRequire @game", function(it)
	it("resolves from the root of the tree, whatever the requiring script's depth", function()
		t.expect(place.resolveRequire(camera, "@game/ReplicatedStorage/Shared/Logic/View")).toBe(view)
		t.expect(place.resolveRequire(main, "@game/ReplicatedStorage/Shared/Logic/Maze")).toBe(maze)
		-- resolver coverage only: src may require @game/ReplicatedStorage/... alone (architecture rule 5)
		t.expect(place.resolveRequire(grid, "@game/StarterPlayer/StarterPlayerScripts/Client/Camera"))
			.toBe(camera)
		t.expect(place.resolveRequire(view, "@game/ReplicatedStorage/Shared/Logic/Maze/Grid")).toBe(grid)
	end)

	it("returns nil for missing instances and non-modules", function()
		t.expect(place.resolveRequire(camera, "@game/ReplicatedStorage/Shared/Logic/Nope")).toBe(nil)
		t.expect(place.resolveRequire(camera, "@game/ReplicatedStorage/Shared/Logic")).toBe(nil)
		t.expect(place.resolveRequire(camera, "@game/StarterPlayer/StarterPlayerScripts/Client/Main"))
			.toBe(nil)
	end)

	it("rejects malformed @game paths", function()
		for _, spec in
			{
				"@game",
				"@game/",
				"@game//ReplicatedStorage/Shared/Logic/View",
				"@game/ReplicatedStorage/./Shared/Logic/View",
				"@game/ReplicatedStorage/Shared/../Shared/Logic/View",
				"@game/ReplicatedStorage/Shared/Logic/View/",
			}
		do
			t.expect(place.resolveRequire(camera, spec)).toBe(nil)
		end
	end)

	it("other aliases still resolve to nil", function()
		t.expect(place.resolveRequire(camera, "@logic/View")).toBe(nil)
		t.expect(place.resolveRequire(camera, "@gamer/ReplicatedStorage/Shared/Logic/View")).toBe(nil)
		t.expect(place.resolveRequire(camera, "@Game/ReplicatedStorage/Shared/Logic/View")).toBe(nil)
	end)

	it("works on the Rojo-built place", function()
		local game = place.load()
		local mainScript =
			game:GetService("ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Main")
		-- Shared.Logic is a Folder, so it is not requireable; Main is a Script
		t.expect(place.resolveRequire(mainScript, "@game/ReplicatedStorage/Shared/Logic")).toBe(nil)
		t.expect(place.resolveRequire(mainScript, "@game/ServerScriptService/Server/Main")).toBe(nil)
		-- a module added to the built place resolves from a script in another root
		local builtLogic =
			game:GetService("ReplicatedStorage"):FindFirstChild("Shared"):FindFirstChild("Logic")
		local probe = make("ModuleScript", "C0390Probe", builtLogic)
		local ok, err = pcall(function()
			t.expect(place.resolveRequire(mainScript, "@game/ReplicatedStorage/Shared/Logic/C0390Probe"))
				.toBe(probe)
		end)
		probe.Parent = nil
		if not ok then
			error(err, 0)
		end
	end)
end)
