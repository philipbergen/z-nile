--!strict
-- f0205 AC6: the built portal place. ReplicatedStorage.Remotes.Cards is the one RemoteEvent the cards use; Carousel and
-- Card are Logic features in ReplicatedStorage.Shared.Logic that require nothing (leaves), and Games a shared config
-- module beside them that requires only Card; the server adapter Cards is in ServerScriptService.Server, reaching the
-- arcade's Wallet in ServerStorage.Arcade, and its Main boots it; the client adapter CarouselView is in the player's
-- scripts and its Main boots it; nothing a client can read requires a server module; and portal's architecture map
-- declares both features with no dependency edge.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local client =
	game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")

-- the source with comments removed and every string's text blanked, so a pin reads code, not prose
local function code(src: string): string
	local s = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	s = string.gsub(s, "%-%-[^\n]*", "")
	s = string.gsub(s, '"[^"\n]*"', '""')
	return s
end

local function modules(): { any }
	local out = {}
	for _, s in place.scripts(game) do
		table.insert(out, s)
	end
	return out
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

return t.spec("f0205 place", function(it)
	it("ReplicatedStorage.Remotes.Cards is a RemoteEvent", function()
		local remotes = RS:FindFirstChild("Remotes")
		t.expect(remotes ~= nil and remotes.ClassName).toBe("Folder")
		local cards = remotes:FindFirstChild("Cards")
		t.expect(cards ~= nil and cards.ClassName).toBe("RemoteEvent")
	end)

	it("Carousel and Card are Logic features, and leaves: they require nothing", function()
		local logic = RS:FindFirstChild("Shared"):FindFirstChild("Logic")
		for _, name in { "Carousel", "Card" } do
			local m = logic:FindFirstChild(name)
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			t.expect(#place.requireSpecs(m.Source)).toBe(0)
		end
	end)

	it("Games is a shared config module that requires only Card", function()
		local m = RS:FindFirstChild("Shared"):FindFirstChild("Games")
		t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
		local specs = place.requireSpecs(m.Source)
		t.expect(#specs).toBe(1)
		local target = place.resolveRequire(m, specs[1])
		t.expect(target).toBe(RS:FindFirstChild("Shared"):FindFirstChild("Logic"):FindFirstChild("Card"))
	end)

	it("the server adapter Cards is in ServerScriptService.Server and reaches the arcade's Wallet", function()
		local m = SSS:FindFirstChild("Server"):FindFirstChild("Cards")
		t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
		local wallet = place.resolveRequire(m, "@game/ServerStorage/Arcade/Wallet")
		t.expect(wallet ~= nil and wallet:GetFullName()).toBe("ServerStorage.Arcade.Wallet")
		local found = false
		for _, spec in place.requireSpecs(m.Source) do
			if place.resolveRequire(m, spec) == wallet then
				found = true
			end
		end
		t.expect(found).toBe(true)
	end)

	it("the server's Main boots Cards", function()
		local main = SSS:FindFirstChild("Server"):FindFirstChild("Main")
		t.expect(main ~= nil and main.ClassName).toBe("Script")
		local src = code(main.Source)
		local spec = "./" .. "Cards"
		t.expect(table.find(place.requireSpecs(main.Source), spec) ~= nil).toBe(true)
		t.expect(string.find(src, 'require%(""%)%.start%(%)') ~= nil).toBe(true)
	end)

	it(
		"the client adapter CarouselView is in the player's scripts, and the client's Main boots it",
		function()
			local m = client:FindFirstChild("CarouselView")
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			local main = client:FindFirstChild("Main")
			t.expect(main ~= nil and main.ClassName).toBe("LocalScript")
			t.expect(table.find(place.requireSpecs(main.Source), "./" .. "CarouselView") ~= nil).toBe(true)
			t.expect(string.find(code(main.Source), 'require%(""%)%.start%(%)') ~= nil).toBe(true)
		end
	)

	it("nothing a client can read requires a server module", function()
		local bad = {}
		local SS = game:GetService("ServerStorage")
		for _, s in modules() do
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

	it(
		"portal's architecture map declares Carousel and Card, and neither depends on another feature",
		function()
			local md = fs.readFile(".tracker/architecture.md")
			t.expect(string.find(md, "### Carousel and Card (f0205)", 1, true) ~= nil).toBe(true)
			local block = string.match(md, "```deps\n(.-)```") or ""
			for line in string.gmatch(block, "[^\n]+") do
				local consumer = string.match(line, "^%s*(%w+)%s*%->")
				t.expect(consumer == "Carousel" or consumer == "Card").toBe(false)
			end
		end
	)
end)
