--!strict
-- f0206 AC7: the built portal place. ReplicatedStorage.Remotes.Boards is a RemoteEvent beside f0205's Cards; Board is
-- a Logic feature in ReplicatedStorage.Shared.Logic whose requires stay inside Logic; the server adapter BoardRelay is
-- in ServerScriptService.Server, reaching the arcade's Boards in ServerStorage.Arcade and its HiscoreGames, and the
-- server's Main starts it once; the client adapter BoardsView is in the player's scripts, requires CarouselView (whose
-- Boards slots it fills) and never a server module, and the client's Main starts it once (each Main is run with a
-- spy, so any spelling of the boot passes); portal's architecture map declares Board; and the arcade's map says E3 is
-- settled here.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local game = place.load()
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local ID = renamed.id("f0206") -- this item, across a compaction
local client =
	game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")

local function under(node: any, ancestor: any): boolean
	local p = node
	while p ~= nil do
		if p == ancestor then
			return true
		end
		p = p.Parent
	end
	return false
end

local function reaches(m: any, target: any): boolean
	for _, spec in place.requireSpecs(m.Source) do
		if place.resolveRequire(m, spec) == target then
			return true
		end
	end
	return false
end

local function standin(): any
	local s: any
	s = setmetatable({}, {
		__index = function(): any
			return s
		end,
		__call = function(): any
			return nil
		end,
	})
	return s
end

-- runs a Main's real source where `require(target)` is a spy, and answers how many times its start was called
local function starts(main: any, target: string): number
	local count = 0
	local spy = {
		start = function()
			count += 1
		end,
	}
	local env: { [string]: any } = {
		game = standin(),
		script = standin(),
		print = function() end,
		warn = function() end,
		require = function(spec: string): any
			if spec == target then
				return spy
			end
			return standin() -- another adapter, this issue's or a later one's
		end,
	}
	luau.load(main.Source, { debugName = main.Name, environment = env })()
	return count
end

return t.spec("f0206 place", function(it)
	it("ReplicatedStorage.Remotes.Boards is a RemoteEvent, beside the cards' remote", function()
		local remotes = RS:FindFirstChild("Remotes")
		t.expect(remotes ~= nil and remotes.ClassName).toBe("Folder")
		local boards = remotes:FindFirstChild("Boards")
		t.expect(boards ~= nil and boards.ClassName).toBe("RemoteEvent")
		local cards = remotes:FindFirstChild("Cards")
		t.expect(cards ~= nil and cards.ClassName).toBe("RemoteEvent")
	end)

	it("Board is a Logic feature whose every require stays inside ReplicatedStorage.Shared.Logic", function()
		local logic = RS:FindFirstChild("Shared"):FindFirstChild("Logic")
		local m = logic:FindFirstChild("Board")
		t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
		for _, s in place.scripts(game) do
			if under(s, m) then
				for _, spec in place.requireSpecs(s.Source) do
					local target = place.resolveRequire(s, spec)
					t.expect(target ~= nil and under(target, logic)).toBe(true)
				end
			end
		end
	end)

	it(
		"BoardRelay is in ServerScriptService.Server and reaches the arcade's Boards and HiscoreGames",
		function()
			local m = SSS:FindFirstChild("Server"):FindFirstChild("BoardRelay")
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			local boards = SS:FindFirstChild("Arcade"):FindFirstChild("Boards")
			t.expect(boards ~= nil).toBe(true)
			t.expect(reaches(m, boards)).toBe(true)
			t.expect(reaches(m, RS:FindFirstChild("Arcade"):FindFirstChild("HiscoreGames"))).toBe(true)
			t.expect(reaches(m, RS:FindFirstChild("Shared"):FindFirstChild("Logic"):FindFirstChild("Board")))
				.toBe(true)
		end
	)

	it("the server's Main starts BoardRelay once", function()
		local main = SSS:FindFirstChild("Server"):FindFirstChild("Main")
		t.expect(main ~= nil and main.ClassName).toBe("Script")
		t.expect(starts(main, "./" .. "BoardRelay")).toBe(1)
	end)

	it(
		"BoardsView is in the player's scripts, requires CarouselView, and the client's Main starts it once",
		function()
			local m = client:FindFirstChild("BoardsView")
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			t.expect(reaches(m, client:FindFirstChild("CarouselView"))).toBe(true)
			t.expect(reaches(m, RS:FindFirstChild("Arcade"):FindFirstChild("HiscoreGames"))).toBe(true)
			local main = client:FindFirstChild("Main")
			t.expect(main ~= nil and main.ClassName).toBe("LocalScript")
			t.expect(starts(main, "./" .. "BoardsView")).toBe(1)
		end
	)

	it("nothing a client can read requires a server module", function()
		local bad = {}
		for _, s in place.scripts(game) do
			if under(s, RS) or under(s, client) then
				for _, spec in place.requireSpecs(s.Source) do
					local target = place.resolveRequire(s, spec)
					if target ~= nil and (under(target, SS) or under(target, SSS)) then
						table.insert(bad, `{s:GetFullName()} -> {spec}`)
					end
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it("portal's architecture map declares Board", function()
		-- its edges, if a later issue gives it any, are the meta spec's to check (every require declared)
		local md = fs.readFile(".tracker/architecture.md")
		t.expect(string.find(md, `### Board ({ID})`, 1, true) ~= nil).toBe(true)
	end)

	it("the arcade's map says its E3 is settled by f0206, with the snapshot per board", function()
		local md = fs.readFile("../arcade/.tracker/architecture.md")
		local e3 = string.match(md, "%*%*E3:%*%*[^\n]*") or ""
		t.expect(string.find(e3, `Settled by {ID}`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(e3, "snapshot", 1, true) ~= nil).toBe(true)
	end)
end)
