--!strict
-- f0206 AC7: the built portal place. ReplicatedStorage.Remotes.Boards is a RemoteEvent beside f0205's Cards; Board is
-- a Logic feature in ReplicatedStorage.Shared.Logic that requires nothing (a leaf); the server adapter BoardRelay is in
-- ServerScriptService.Server, reaching the arcade's Boards in ServerStorage.Arcade and its HiscoreGames, and the
-- server's Main boots it after Cards; the client adapter BoardsView is in the player's scripts, requires CarouselView
-- (whose Boards slots it fills) and never a server module, and the client's Main boots it after CarouselView;
-- portal's architecture map declares Board with no dependency edge; and the arcade's map says E3 is settled here.
local fs = require("@lune/fs")
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

-- the source with comments removed and every string's text blanked, so a pin reads code, not prose
local function code(src: string): string
	local s = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	s = string.gsub(s, "%-%-[^\n]*", "")
	s = string.gsub(s, '"[^"\n]*"', '""')
	return s
end

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

-- the position of the boot of `name` in a Main's requires, or nil
local function boot(main: any, name: string): number?
	return table.find(place.requireSpecs(main.Source), "./" .. name)
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

	it("Board is a Logic feature, and a leaf: it requires nothing", function()
		local m = RS:FindFirstChild("Shared"):FindFirstChild("Logic"):FindFirstChild("Board")
		t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
		t.expect(#place.requireSpecs(m.Source)).toBe(0)
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

	it("the server's Main boots BoardRelay, after Cards", function()
		local main = SSS:FindFirstChild("Server"):FindFirstChild("Main")
		t.expect(main ~= nil and main.ClassName).toBe("Script")
		local relay, cards = boot(main, "BoardRelay"), boot(main, "Cards")
		t.expect(relay ~= nil).toBe(true)
		t.expect(cards ~= nil and relay ~= nil and cards < relay).toBe(true)
		t.expect(select(2, string.gsub(code(main.Source), 'require%(""%)%.start%(%)', "")) >= 2).toBe(true)
	end)

	it(
		"BoardsView is in the player's scripts, requires CarouselView, and the client's Main boots it after",
		function()
			local m = client:FindFirstChild("BoardsView")
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			t.expect(reaches(m, client:FindFirstChild("CarouselView"))).toBe(true)
			t.expect(reaches(m, RS:FindFirstChild("Arcade"):FindFirstChild("HiscoreGames"))).toBe(true)
			local main = client:FindFirstChild("Main")
			local view, carousel = boot(main, "BoardsView"), boot(main, "CarouselView")
			t.expect(view ~= nil).toBe(true)
			t.expect(carousel ~= nil and view ~= nil and carousel < view).toBe(true)
			t.expect(select(2, string.gsub(code(main.Source), 'require%(""%)%.start%(%)', "")) >= 2)
				.toBe(true)
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

	it("portal's architecture map declares Board, which depends on no other feature", function()
		local md = fs.readFile(".tracker/architecture.md")
		t.expect(string.find(md, `### Board ({ID})`, 1, true) ~= nil).toBe(true)
		local block = string.match(md, "```deps\n(.-)```") or ""
		for line in string.gmatch(block, "[^\n]+") do
			local consumer = string.match(line, "^%s*(%w+)%s*%->")
			t.expect(consumer == "Board").toBe(false)
		end
	end)

	it("the arcade's map says its E3 is settled by f0206, with the snapshot per board", function()
		local md = fs.readFile("../arcade/.tracker/architecture.md")
		local e3 = string.match(md, "%*%*E3:%*%*[^\n]*") or ""
		t.expect(string.find(e3, `Settled by {ID}`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(e3, "snapshot", 1, true) ~= nil).toBe(true)
	end)
end)
