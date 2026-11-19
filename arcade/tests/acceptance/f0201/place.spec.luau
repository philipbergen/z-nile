--!strict
-- f0201 AC6: where paid play sits in the built library place, and what may reach it. PaidPlay is a Logic leaf in
-- ReplicatedStorage.Arcade.Logic, Prices and TestPurchase are shared modules, and Wallet, Receipts and Catalog are
-- server-only modules in ServerStorage.Arcade, which never replicates; nothing a client can load requires them. The
-- library's architecture declares the feature. (That the server adapters read no join data and hear only the test
-- screen's answer is pinned by spies in wallet.spec and receipts.spec.)
local fs = require("@lune/fs")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local function at(service: string, path: { string }): any
	local n = (built :: any):GetService(service):FindFirstChild("Arcade")
	for _, part in path do
		n = n and n:FindFirstChild(part)
	end
	return n
end

return t.spec("f0201 paid play in the library place", function(it)
	it(
		"PaidPlay is a Logic feature, Prices and TestPurchase shared modules, in ReplicatedStorage.Arcade",
		function()
			t.expect(at("ReplicatedStorage", { "Logic", "PaidPlay" }).ClassName).toBe("ModuleScript")
			t.expect(at("ReplicatedStorage", { "Prices" }).ClassName).toBe("ModuleScript")
			t.expect(at("ReplicatedStorage", { "TestPurchase" }).ClassName).toBe("ModuleScript")
		end
	)

	it(
		"Wallet, Receipts and Catalog are server-only modules in ServerStorage.Arcade, not in ReplicatedStorage",
		function()
			for _, name in { "Wallet", "Receipts", "Catalog" } do
				t.expect(at("ServerStorage", { name }).ClassName).toBe("ModuleScript")
				t.expect(at("ReplicatedStorage", { name })).toBe(nil)
			end
		end
	)

	it("PaidPlay is a leaf: it requires nothing", function()
		local src = at("ReplicatedStorage", { "Logic", "PaidPlay" }).Source
		t.expect(place.requireSpecs(src)).toEqual({})
	end)

	it("nothing in ReplicatedStorage.Arcade requires a server module", function()
		local bad = {}
		for _, s in place.scripts(built) do
			if string.match(s:GetFullName(), "^ReplicatedStorage%.") then
				for _, spec in place.requireSpecs(s.Source) do
					local target = place.resolveRequire(s, spec)
					if target == nil or not string.match(target:GetFullName(), "^ReplicatedStorage%.") then
						table.insert(bad, `{s:GetFullName()}: {spec}`)
					end
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it(
		"the library's architecture declares PaidPlay and Receipts in every place, and PaidPlay as a leaf",
		function()
			local doc = fs.readFile(".tracker/architecture.md")
			t.expect(string.find(doc, "### PaidPlay and Receipts (f0201)", 1, true) ~= nil).toBe(true)
			t.expect(string.find(doc, "installed by **every place**", 1, true) ~= nil).toBe(true)
			local deps = string.match(doc, "```deps\n(.-)```") or ""
			t.expect((string.find(deps, "PaidPlay ->", 1, true))).toBe(nil)
		end
	)
end)
