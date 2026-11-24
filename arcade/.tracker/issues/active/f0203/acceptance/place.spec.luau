--!strict
-- f0203 AC7: the library's place holds the four cores where every place's adapters require them
-- (ReplicatedStorage.Arcade.Logic.<Feature>), as ModuleScripts that a client may read.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

return t.spec("f0203 place", function(it)
	local dm = place.load()

	it("ReplicatedStorage.Arcade.Logic holds Rng, Pad, Touch and Look as ModuleScripts", function()
		local logic = dm:GetService("ReplicatedStorage"):FindFirstChild("Arcade")
		logic = logic and logic:FindFirstChild("Logic")
		t.expect(logic ~= nil).toBe(true)
		local missing = {}
		for _, name in { "Rng", "Pad", "Touch", "Look" } do
			local m = logic and logic:FindFirstChild(name)
			if m == nil or m.ClassName ~= "ModuleScript" then
				table.insert(missing, name)
			end
		end
		t.expect(table.concat(missing, ", ")).toBe("")
	end)

	it("no core is under ServerStorage, which a client cannot read", function()
		local server = dm:GetService("ServerStorage"):FindFirstChild("Arcade")
		local found = {}
		for _, name in { "Rng", "Pad", "Touch", "Look" } do
			if server and server:FindFirstChild(name, true) then
				table.insert(found, name)
			end
		end
		t.expect(table.concat(found, ", ")).toBe("")
	end)
end)
