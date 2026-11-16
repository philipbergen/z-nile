--!strict
-- c0202 AC6: Pickman's paid play is the arcade library's, with no copy of its own. Both places map the library
-- (ReplicatedStorage.Arcade and ServerStorage.Arcade); pickman's Logic/Pay, Shared/Purchases and Shared/TestPurchase
-- are gone and nothing in pickman's src names them, its own DataStores or pass map, or sets ProcessReceipt (one
-- setter per server: the library's Receipts); the servers' adapters wire the library's Wallet and Receipts and start
-- Receipts, and the clients boot the library's test screen. architecture.md no longer declares Pay, and
-- game-design.md states that Pickman runs on the arcade's paid play and what its arrival takes. Source pins are read
-- with comments removed; what they leave to the running cases: everything the adapters do (AC1 to AC5).
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()
local lobbyPlace = place.load("lobby.project.json")

local function node(root: any, path: { string }): any
	local n = root
	for _, part in path do
		n = n and n:FindFirstChild(part)
	end
	return n
end

local function source(root: any, path: { string }): string
	local n = node(root, path)
	assert(n, `no {table.concat(path, ".")}`)
	return (string.gsub(n.Source, "%-%-[^\n]*", ""))
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- every .luau file under a folder, with its text (comments removed)
local function files(dir: string, out: { [string]: string }?): { [string]: string }
	local found = out or {}
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			files(path, found)
		elseif string.sub(name, -5) == ".luau" then
			found[path] = (string.gsub(fs.readFile(path), "%-%-[^\n]*", ""))
		end
	end
	return found
end

local REQ = "req" .. "uire" -- spelled apart: a literal call in a string would read as a real one
local function requires(text: string, target: string): boolean
	return string.find(text, REQ .. '%(%s*"' .. string.gsub(target, "%p", "%%%0") .. '"%s*%)') ~= nil
end

return t.spec("c0202 Pickman's paid play is the arcade library's", function(it)
	it(
		"both places map the library: its Logic and test screen shared, its Wallet and Receipts server-only",
		function()
			for _, root in { gamePlace, lobbyPlace } do
				t.expect(node(root, { "ReplicatedStorage", "Arcade", "Logic", "PaidPlay" }) ~= nil).toBe(true)
				t.expect(node(root, { "ReplicatedStorage", "Arcade", "TestPurchase" }) ~= nil).toBe(true)
				t.expect(node(root, { "ReplicatedStorage", "Arcade", "Prices" }) ~= nil).toBe(true)
				t.expect(node(root, { "ServerStorage", "Arcade", "Wallet" }) ~= nil).toBe(true)
				t.expect(node(root, { "ServerStorage", "Arcade", "Receipts" }) ~= nil).toBe(true)
				t.expect(node(root, { "ReplicatedStorage", "Arcade", "Wallet" })).toBe(nil)
			end
		end
	)

	it(
		"pickman keeps no copy: its Pay, Purchases and TestPurchase are gone and nothing names them",
		function()
			t.expect(fs.isDir("src/shared/Logic/Pay")).toBe(false)
			t.expect(fs.isDir("tests/unit/Pay")).toBe(false)
			t.expect(fs.isFile("src/shared/Purchases.luau")).toBe(false)
			t.expect(fs.isFile("src/shared/TestPurchase.luau")).toBe(false)
			for _, root in { gamePlace, lobbyPlace } do
				t.expect(node(root, { "ReplicatedStorage", "Shared", "Logic", "Pay" })).toBe(nil)
				t.expect(node(root, { "ReplicatedStorage", "Shared", "Purchases" })).toBe(nil)
				t.expect(node(root, { "ReplicatedStorage", "Shared", "TestPurchase" })).toBe(nil)
			end
			for path, text in files("src") do
				for _, needle in { "Logic/Pay", "Shared/Purchases", "Shared/TestPurchase", "ProcessReceipt" } do
					if has(text, needle) then
						error(`{path} names {needle}`)
					end
				end
				for _, needle in { "GetDataStore", "GetHashMap", "PromptProductPurchase", "PaidPlayPass" } do
					if has(text, needle) and (has(text, "PaidPlay") or has(text, "Product")) then
						error(`{path} reaches paid play's stores or products itself ({needle})`)
					end
				end
			end
		end
	)

	it(
		"the servers wire the library's Wallet and Receipts and start Receipts; Pickman is the title pickman",
		function()
			for _, spot in
				{
					{ gamePlace, { "ServerScriptService", "Server", "Continues" } },
					{ lobbyPlace, { "ServerScriptService", "Lobby", "Paid" } },
				} :: { any }
			do
				local text = source(spot[1], spot[2])
				t.expect(requires(text, "@game/ServerStorage/Arcade/Wallet")).toBe(true)
				t.expect(requires(text, "@game/ServerStorage/Arcade/Receipts")).toBe(true)
				t.expect(string.find(text, "Receipts%.start%(") ~= nil).toBe(true)
				t.expect(has(text, '"pickman"')).toBe(true)
			end
		end
	)

	it("both clients boot the library's test screen", function()
		for _, spot in
			{
				{ gamePlace, { "StarterPlayer", "StarterPlayerScripts", "Client", "OfferView" } },
				{ lobbyPlace, { "StarterPlayer", "StarterPlayerScripts", "Lobby", "PayView" } },
			} :: { any }
		do
			local text = source(spot[1], spot[2])
			t.expect(requires(text, "@game/ReplicatedStorage/Arcade/TestPurchase")).toBe(true)
			t.expect(string.find(text, "TestPurchase%.start%(%)") ~= nil).toBe(true)
		end
	end)

	it(
		"architecture.md no longer declares Pay; game-design.md states the arcade's paid play and the arrival",
		function()
			local arch = fs.readFile(".tracker/architecture.md")
			local deps = "\n" .. (string.match(arch, "```deps\n(.-)```") or "")
			t.expect(has(deps, "-> Pay\n")).toBe(false)
			t.expect(has(arch, "\n| Pay |")).toBe(false)
			t.expect(has(arch, "c0202")).toBe(true)
			local design = fs.readFile(".tracker/game-design.md")
			for _, phrase in
				{
					"**On the arcade's paid play (c0202)**",
					"`PaidPlay` and `PaidPlayTest`",
					"the test purchase screen is the library's",
					"the portal's Pickman card",
					"plays at once",
				}
			do
				if not has(design, phrase) then
					error(`game-design.md lacks: {phrase}`)
				end
			end
		end
	)
end)
