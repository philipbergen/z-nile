--!strict
-- f0290 AC1: the pellets' wire format. Every pellet and power tile of the layout is a slot, in row-major
-- order; the code has one bit per slot (1 = still there), six bits to a base64url character: slot i is in
-- character (i - 1) // 6 + 1 at bit (i - 1) % 6, and unused bits of the last character are 0.
local Maze = require("@logic/Maze")
local Pellets = require("@logic/Pellets")
local t = require("@tests/lib/t")

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
-- eight slots: (2,1) power, (3..6,1) pellets, (1,2) pellet, (2,2) power, (6,2) pellet
local EIGHT = Maze.parse({ "########", "#Po....#", "#.o###.#", "########" }, "eight")

local function classic(): Maze.Maze
	return Maze.layout(Maze.DEFAULT)
end

local function slotIndex(m: Maze.Maze, x: number, y: number): number
	for i, s in Pellets.slots(m) do
		if s.x == x and s.y == y then
			return i
		end
	end
	error(`no slot at ({x}, {y})`)
end

return t.spec("f0290 pellets on the wire", function(it)
	it("slots are the layout's pellet and power tiles, row-major, with their kind", function()
		local slots = Pellets.slots(EIGHT)
		t.expect(slots).toEqual({
			{ x = 2, y = 1, kind = "power" },
			{ x = 3, y = 1, kind = "pellet" },
			{ x = 4, y = 1, kind = "pellet" },
			{ x = 5, y = 1, kind = "pellet" },
			{ x = 6, y = 1, kind = "pellet" },
			{ x = 1, y = 2, kind = "pellet" },
			{ x = 2, y = 2, kind = "power" },
			{ x = 6, y = 2, kind = "pellet" },
		})
	end)

	it("the classic maze has 244 slots, 4 of them power pellets", function()
		local slots = Pellets.slots(classic())
		t.expect(#slots).toBe(244)
		local power = 0
		for _, s in slots do
			if s.kind == "power" then
				power += 1
			end
		end
		t.expect(power).toBe(4)
	end)

	it("slots describe the layout, not what is left", function()
		local m = classic()
		local p = Pellets.new(m)
		local before = Pellets.slots(m)
		Pellets.eat(p, before[1])
		Pellets.eat(p, before[10])
		t.expect(Pellets.slots(m)).toEqual(before)
	end)

	it("slots returns a fresh list: changing it changes nothing", function()
		local m = classic()
		local first = Pellets.slots(m)
		first[1].x = 99
		first[1].kind = "power"
		table.remove(first, 2)
		local again = Pellets.slots(m)
		t.expect(#again).toBe(244)
		t.expect(again[1]).toEqual({ x = 1, y = 1, kind = "pellet" })
		t.expect(Pellets.encode(Pellets.new(m))).toBe(string.rep("_", 40) .. "P")
	end)

	it("a full classic maze encodes as forty '_' and a 'P' (bits 0-3 of the last character)", function()
		t.expect(Pellets.encode(Pellets.new(classic()))).toBe(string.rep("_", 40) .. "P")
	end)

	it("eating slot 1 clears bit 0 of the first character", function()
		local m = classic()
		local p = Pellets.new(m)
		Pellets.eat(p, Pellets.slots(m)[1])
		t.expect(Pellets.encode(p)).toBe("-" .. string.rep("_", 39) .. "P")
	end)

	it("bits follow the slot order across character boundaries", function()
		local m = classic()
		local p = Pellets.new(m)
		local slots = Pellets.slots(m)
		for _, i in { 6, 7, 244 } do
			Pellets.eat(p, slots[i])
		end
		-- slot 6 is bit 5 of character 1 (63 - 32 = 31, 'f'); slot 7 is bit 0 of character 2 ('-');
		-- slot 244 is bit 3 of character 41 (15 - 8 = 7, 'H')
		t.expect(Pellets.encode(p)).toBe("f-" .. string.rep("_", 38) .. "H")
	end)

	it("an empty maze of pellets is all zero bits, still the full length", function()
		local m = EIGHT
		local p = Pellets.new(m)
		for _, s in Pellets.slots(m) do
			Pellets.eat(p, s)
		end
		t.expect(Pellets.encode(p)).toBe("AA")
	end)

	it("uses only base64url characters, ceil(slots / 6) of them", function()
		local m = classic()
		local p = Pellets.new(m)
		for i, s in Pellets.slots(m) do
			if i % 3 == 0 then
				Pellets.eat(p, s)
			end
		end
		local code = Pellets.encode(p)
		t.expect(#code).toBe(41)
		for c in string.gmatch(code, ".") do
			t.expect(string.find(ALPHABET, c, 1, true) ~= nil).toBe(true)
		end
		t.expect(#Pellets.encode(Pellets.new(EIGHT))).toBe(2)
	end)

	it("decode gives, per slot, whether the pellet is still there", function()
		local m = classic()
		local p = Pellets.new(m)
		local gone =
			{ [slotIndex(m, 1, 1)] = true, [slotIndex(m, 26, 3)] = true, [slotIndex(m, 26, 29)] = true }
		for i in gone do
			Pellets.eat(p, Pellets.slots(m)[i])
		end
		local present = Pellets.decode(m, Pellets.encode(p))
		t.expect(#present).toBe(244)
		for i = 1, 244 do
			t.expect(present[i]).toBe(not gone[i])
		end
	end)

	it("decode after a reset shows every pellet back", function()
		local m = EIGHT
		local p = Pellets.new(m)
		Pellets.eat(p, { x = 2, y = 1 })
		Pellets.eat(p, { x = 6, y = 2 })
		Pellets.reset(p)
		t.expect(Pellets.decode(m, Pellets.encode(p)))
			.toEqual({ true, true, true, true, true, true, true, true })
	end)

	it("decode refuses a code of the wrong length", function()
		t.expect(function()
			Pellets.decode(EIGHT, "_")
		end).toThrow("pellets:")
		t.expect(function()
			Pellets.decode(EIGHT, "___")
		end).toThrow("pellets:")
		-- a valid code with a character too many, its extra bits all clear
		t.expect(function()
			Pellets.decode(EIGHT, "_DA")
		end).toThrow("pellets:")
	end)

	it("decode refuses a character outside the alphabet", function()
		t.expect(function()
			Pellets.decode(EIGHT, "_=")
		end).toThrow("pellets:")
	end)

	it("decode refuses a set bit past the last slot", function()
		-- EIGHT has 8 slots: bits 2-5 of the second character are padding
		t.expect(Pellets.decode(EIGHT, "_D")).toEqual({ true, true, true, true, true, true, true, true })
		t.expect(function()
			Pellets.decode(EIGHT, "_H")
		end).toThrow("pellets:")
	end)
end)
