--!strict
-- f0208 AC6: the built portal place. ReplicatedStorage.Remotes.Play is the play buttons' RemoteEvent; Play, Pairing
-- and Arena are Logic features whose requires stay inside Logic (Play requires Card) and Modes a shared config module
-- that requires Play and nothing outside Shared; the server adapters Plays and Invites are in
-- ServerScriptService.Server, Plays reaching the arcade's Wallet and Receipts, and the server's Main boots Plays; the client adapter PlayButtons is in the player's
-- scripts and the client's Main boots it and the arcade's test purchase screen; nothing a client can read requires a
-- server module; portal's architecture map declares the features and the edge Play -> Card; and portal's
-- tests/inputs.tsv declares that this spec reads that map.
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local renamed = require("@tests/lib/renamed")
local sel = require("@znile/lib/select")
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

local function targets(m: any): { any }
	local out = {}
	for _, spec in place.requireSpecs(m.Source) do
		table.insert(out, place.resolveRequire(m, spec))
	end
	return out
end

local function boots(main: any, spec: string): boolean
	if table.find(place.requireSpecs(main.Source), spec) == nil then
		return false
	end
	local src = code(main.Source)
	return string.find(src, 'require%(""%)%.start%(%)') ~= nil
end

return t.spec("f0208 place", function(it)
	it("ReplicatedStorage.Remotes.Play is a RemoteEvent", function()
		local remotes = RS:FindFirstChild("Remotes")
		local play = remotes and remotes:FindFirstChild("Play")
		t.expect(play ~= nil and play.ClassName).toBe("RemoteEvent")
	end)

	it(
		"Play, Pairing and Arena are Logic features whose requires stay inside Logic; Play requires Card",
		function()
			local logic = RS:FindFirstChild("Shared"):FindFirstChild("Logic")
			for _, name in { "Play", "Pairing", "Arena" } do
				local m = logic:FindFirstChild(name)
				t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
				for _, target in targets(m) do
					t.expect(target ~= nil and under(target, logic) and target ~= m).toBe(true)
				end
			end
			local play = targets(logic:FindFirstChild("Play"))
			t.expect(table.find(play, logic:FindFirstChild("Card")) ~= nil).toBe(true)
		end
	)

	it("Modes is a shared config module that requires Play, and nothing outside Shared", function()
		local shared = RS:FindFirstChild("Shared")
		local m = shared:FindFirstChild("Modes")
		t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
		local found = targets(m)
		for _, target in found do
			t.expect(target ~= nil and under(target, shared)).toBe(true)
		end
		t.expect(table.find(found, shared:FindFirstChild("Logic"):FindFirstChild("Play")) ~= nil).toBe(true)
	end)

	it("Plays and Invites are server adapters; Plays reaches the arcade's Wallet and Receipts", function()
		local server = SSS:FindFirstChild("Server")
		local plays = server:FindFirstChild("Plays")
		t.expect(plays ~= nil and plays.ClassName).toBe("ModuleScript")
		local invites = server:FindFirstChild("Invites")
		t.expect(invites ~= nil and invites.ClassName).toBe("ModuleScript")
		local names = {}
		for _, target in targets(plays) do
			if target ~= nil then
				table.insert(names, target:GetFullName())
			end
		end
		t.expect(table.find(names, "ServerStorage.Arcade.Wallet") ~= nil).toBe(true)
		t.expect(table.find(names, "ServerStorage.Arcade.Receipts") ~= nil).toBe(true)
		t.expect(table.find(names, "ServerScriptService.Server.Invites") ~= nil).toBe(true)
	end)

	it("the server's Main boots Plays", function()
		local main = SSS:FindFirstChild("Server"):FindFirstChild("Main")
		t.expect(boots(main, "./" .. "Plays")).toBe(true)
	end)

	it(
		"PlayButtons is in the player's scripts; the client's Main boots it and the test purchase screen",
		function()
			local m = client:FindFirstChild("PlayButtons")
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			local main = client:FindFirstChild("Main")
			t.expect(boots(main, "./" .. "PlayButtons")).toBe(true)
			local test = "@game/ReplicatedStorage/Arcade/" .. "TestPurchase"
			t.expect(table.find(place.requireSpecs(main.Source), test) ~= nil).toBe(true)
			local screen = place.resolveRequire(main, test)
			t.expect(screen ~= nil and screen:GetFullName()).toBe("ReplicatedStorage.Arcade.TestPurchase")
			local specs = place.requireSpecs(main.Source)
			local first, buttons = table.find(specs, test), table.find(specs, "./" .. "PlayButtons")
			t.expect(first ~= nil and buttons ~= nil and first < buttons).toBe(true)
		end
	)

	it("nothing a client can read requires a server module", function()
		local bad = {}
		local SS = game:GetService("ServerStorage")
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

	it("portal's architecture map declares the play buttons and the edge Play -> Card", function()
		local md = fs.readFile(".tracker/architecture.md")
		t.expect(string.find(md, "### Play buttons (f0208)", 1, true) ~= nil).toBe(true)
		local block = string.match(md, "```deps\n(.-)```") or ""
		local edges = {}
		for line in string.gmatch(block, "[^\n]+") do
			local consumer, provider = string.match(line, "^%s*(%w+)%s*%->%s*(%w+)")
			if consumer ~= nil then
				table.insert(edges, `{consumer} -> {provider}`)
			end
		end
		t.expect(table.find(edges, "Play -> Card") ~= nil).toBe(true)
	end)

	it("portal's tests/inputs.tsv declares that this spec reads the architecture map", function()
		local inputs, err = sel.parseInputs(fs.readFile("tests/inputs.tsv"), "portal/")
		t.expect(err).toBe(nil)
		local key = "portal/tests/" .. "acceptance/" .. renamed.id("f0208") .. "/place.spec.luau"
		local list = (inputs :: any)[key] or {}
		t.expect(table.find(list, "portal/.tracker/architecture.md") ~= nil).toBe(true)
	end)
end)
