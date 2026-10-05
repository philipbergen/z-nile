--!strict
-- f0100 AC2: parse rejects malformed maze text with a message naming the problem and where.
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local function rejects(rows: { any }, ...: string)
	local ok, err = pcall(Maze.parse, rows)
	t.expect(ok).toBe(false)
	local msg = tostring(err)
	for _, want in { ... } do
		if not string.find(msg, want, 1, true) then
			error(`expected the error to mention "{want}", got: {msg}`, 2)
		end
	end
end

return t.spec("f0100 Maze.parse validation", function(it)
	it("rejects an empty maze", function()
		rejects({}, "empty")
		rejects({ "" }, "empty")
	end)

	it("rejects rows of unequal width, naming the row", function()
		rejects({ "#####", "#P. #", "####" }, "width", "row 2")
	end)

	it("rejects an unknown character with its coordinates", function()
		rejects({ "#####", "#P.X#", "#####" }, "character", "X", "(3, 1)")
	end)

	it("requires exactly one spawn", function()
		rejects({ "#####", "#...#", "#####" }, "spawn", "found 0")
		rejects({ "#####", "#P.P#", "#####" }, "spawn", "found 2")
	end)

	it("rejects a spawn with no exit for the player", function()
		rejects({ "#####", "#P-H#", "#####" }, "spawn", "no exit")
	end)

	it("rejects an open edge: a walkable edge tile with a wall opposite", function()
		rejects({ "#####", "#P.. ", "#####" }, "open edge", "(4, 1)")
		rejects({ "##.##", "#P..#", "#####" }, "open edge", "(2, 0)")
	end)

	it("rejects a walkable tile the player cannot reach from the spawn", function()
		rejects({ "######", "#P.#.#", "######" }, "unreachable", "player", "(4, 1)")
	end)

	it("rejects a ghost-only tile that ghosts cannot reach", function()
		rejects({ "#######", "#P..#H#", "#######" }, "unreachable", "ghost", "(5, 1)")
	end)

	it("accepts the smallest valid mazes, including a wrapping corridor", function()
		t.expect(Maze.parse({ "####", "#P #", "####" }).width).toBe(4)
		t.expect(Maze.parse({ "####", " P  ", "####" }).width).toBe(4)
		t.expect(Maze.parse({ "#.#", "#P#", "#.#" }).height).toBe(3)
	end)
end)
