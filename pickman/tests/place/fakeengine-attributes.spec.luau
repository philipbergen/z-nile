--!strict
-- R0056 code review 001 F2: the fake engine's `:SetAttribute` refuses what Roblox refuses, and accepts what it
-- accepts, on both sides of each rule, so a wrong adapter (a table, a function, an Instance or a bad name stored as
-- an attribute) fails on the fake as it would in Roblox, and a correct one keeps working. A name is 1–100 letters,
-- digits or underscores; a value is a string, a number, a boolean, or nil (which clears it). The fake also refuses
-- Roblox datatypes (Color3, Vector3, UDim2 …), which Roblox accepts, because they are plain tables here (its header
-- says so); no adapter stores one today.
local fake = require("@tests/lib/fakeengine")
local t = require("@tests/lib/t")

local function sets(name: any, value: any): (boolean, string)
	local node = fake.node("Folder", "Walls")
	local ok, err = pcall(function()
		node:SetAttribute(name, value)
	end)
	return ok, if ok then "" else tostring(err)
end

return t.spec("R0056 the fake engine's attributes", function(it)
	it("a name of 1 to 100 letters, digits and underscores is accepted, and read back", function()
		local node = fake.node("Folder", "Walls")
		node:SetAttribute("Lit", true)
		t.expect(node:GetAttribute("Lit")).toBe(true)
		t.expect((sets("a", 1))).toBe(true)
		t.expect((sets("Edible_2", 1))).toBe(true)
		t.expect((sets(string.rep("a", 100), 1))).toBe(true)
	end)

	it("an empty name, a 101-character name, other characters and a non-string name are refused", function()
		for _, name in { "", string.rep("a", 101), "a-b", "a b", "é" } :: { any } do
			local ok, err = sets(name, 1)
			t.expect(ok).toBe(false)
			t.expect(string.find(err, "is not a valid attribute name", 1, true) ~= nil).toBe(true)
		end
		t.expect((sets(5, 1))).toBe(false)
	end)

	it("a string, a number, a boolean and nil are accepted, and nil clears", function()
		local node = fake.node("Folder", "Walls")
		for _, value in { "x", 0, -1.5, false, true } :: { any } do
			node:SetAttribute("V", value)
			t.expect(node:GetAttribute("V")).toBe(value)
		end
		node:SetAttribute("V", nil)
		t.expect(node:GetAttribute("V")).toBe(nil)
	end)

	it("a table, a function, a thread and an Instance are refused, and say which", function()
		local cases: { { value: any, says: string } } = {
			{ value = {}, says = "type table" },
			{ value = function() end, says = "type function" },
			{ value = coroutine.create(function() end), says = "type thread" },
			{ value = fake.node("Part", "Wall"), says = "type Instance" },
		}
		for _, case in cases do
			local ok, err = sets("V", case.value)
			t.expect(ok).toBe(false)
			t.expect(string.find(err, case.says, 1, true) ~= nil).toBe(true)
		end
	end)
end)
