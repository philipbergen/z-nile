--!strict
-- f0205 AC6: the built portal place. ReplicatedStorage.Remotes.Cards is the RemoteEvent the cards use; Carousel and
-- Card are Logic features in ReplicatedStorage.Shared.Logic whose requires stay inside it, and Games a shared config
-- module beside them that requires Card and nothing outside ReplicatedStorage.Shared; the server adapter Cards is in
-- ServerScriptService.Server, reaching the arcade's Wallet in ServerStorage.Arcade, and the server's Main starts it
-- once; the client adapter CarouselView is in the player's scripts and the client's Main starts it once; nothing a
-- client can read requires a server module; portal's architecture map names both features; and portal's
-- tests/inputs.tsv declares that this spec reads that map.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local renamed = require("@tests/lib/renamed")
local sel = require("@znile/lib/select")
local t = require("@tests/lib/t")

local game = place.load()
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
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

-- a stand-in that accepts any use: every field is a callable stand-in too
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
			return standin() -- another adapter a later issue boots
		end,
	}
	luau.load(main.Source, { debugName = main.Name, environment = env })()
	return count
end

return t.spec("f0205 place", function(it)
	it("ReplicatedStorage.Remotes.Cards is a RemoteEvent", function()
		local remotes = RS:FindFirstChild("Remotes")
		t.expect(remotes ~= nil and remotes.ClassName).toBe("Folder")
		local cards = remotes:FindFirstChild("Cards")
		t.expect(cards ~= nil and cards.ClassName).toBe("RemoteEvent")
	end)

	it(
		"Carousel and Card are Logic features whose every require stays inside ReplicatedStorage.Shared.Logic",
		function()
			local logic = RS:FindFirstChild("Shared"):FindFirstChild("Logic")
			for _, name in { "Carousel", "Card" } do
				local m = logic:FindFirstChild(name)
				t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
				for _, s in place.scripts(game) do
					if under(s, m) then
						for _, spec in place.requireSpecs(s.Source) do
							local target = place.resolveRequire(s, spec)
							t.expect(target ~= nil and under(target, logic)).toBe(true)
						end
					end
				end
			end
		end
	)

	it(
		"Games is a shared config module that requires Card and nothing outside ReplicatedStorage.Shared",
		function()
			local shared = RS:FindFirstChild("Shared")
			local m = shared:FindFirstChild("Games")
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			local card = shared:FindFirstChild("Logic"):FindFirstChild("Card")
			local found = false
			for _, spec in place.requireSpecs(m.Source) do
				local target = place.resolveRequire(m, spec)
				t.expect(target ~= nil and under(target, shared)).toBe(true)
				if target == card then
					found = true
				end
			end
			t.expect(found).toBe(true)
		end
	)

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

	it("the server's Main starts Cards once", function()
		local main = SSS:FindFirstChild("Server"):FindFirstChild("Main")
		t.expect(main ~= nil and main.ClassName).toBe("Script")
		t.expect(starts(main, "./" .. "Cards")).toBe(1)
	end)

	it(
		"the client adapter CarouselView is in the player's scripts, and the client's Main starts it once",
		function()
			local m = client:FindFirstChild("CarouselView")
			t.expect(m ~= nil and m.ClassName).toBe("ModuleScript")
			local main = client:FindFirstChild("Main")
			t.expect(main ~= nil and main.ClassName).toBe("LocalScript")
			t.expect(starts(main, "./" .. "CarouselView")).toBe(1)
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

	it("portal's architecture map names Carousel and Card", function()
		local md = fs.readFile(".tracker/architecture.md")
		t.expect(string.find(md, "### Carousel and Card (" .. renamed.id("f0205") .. ")", 1, true) ~= nil)
			.toBe(true)
	end)

	it("portal's tests/inputs.tsv declares that this spec reads the architecture map", function()
		local inputs, err = sel.parseInputs(fs.readFile("tests/inputs.tsv"), "portal/")
		t.expect(err).toBe(nil)
		local key = "portal/tests/" .. "acceptance/" .. renamed.id("f0205") .. "/place.spec.luau"
		local list = (inputs :: any)[key] or {}
		t.expect(table.find(list, "portal/.tracker/architecture.md") ~= nil).toBe(true)
	end)
end)
