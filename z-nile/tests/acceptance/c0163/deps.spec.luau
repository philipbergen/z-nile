--!strict
-- c0163 AC4: the one deps reader (@znile/lib/deps, pure) fails closed. It reads `Consumer -> Provider` edges from an
-- architecture document's ```deps block, allows blank lines and `#` comments, and names, with the document's line,
-- every other line (a conflict marker among them) instead of skipping it; no deps block, two of them, or one never
-- closed is a problem too. pickman's architecture meta spec reads the block through it, with its own matcher gone.
-- Casts keep the spec type-legal before the module exists; a missing member fails at the call.
local deps: any = require("@znile/lib/deps")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local LT, GT, EQ = string.rep("<", 7), string.rep(">", 7), string.rep("=", 7)
local FENCE = string.rep("`", 3)

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function doc(lines: { string }): string
	return "# Architecture\n\ntext\n"
		.. FENCE
		.. "deps\n"
		.. table.concat(lines, "\n")
		.. "\n"
		.. FENCE
		.. "\nafter\n"
end

return t.spec("c0163 the deps reader fails closed", function(it)
	it("reads edges, with blank lines and # comments", function()
		local g, problems = deps.parse(doc({ "A -> B", "", "# why", "  C->D  ", "A -> E" }), "arch.md")
		t.expect(#problems).toBe(0)
		t.expect(g.A.B).toBe(true)
		t.expect(g.A.E).toBe(true)
		t.expect(g.C.D).toBe(true)
	end)

	it("a conflict inside the block is named line by line, both sides' edges aside", function()
		local _, problems = deps.parse(
			doc({ "A -> B", LT .. " HEAD", "Touch -> Hud", EQ, "Session -> Picks", GT .. " origin/main" }),
			"arch.md"
		)
		t.expect(#problems).toBe(3)
		-- the block starts on line 5 of the document: A -> B is 5, the markers 6, 8 and 10
		t.expect(has(problems[1], "arch.md:6:")).toBe(true)
		t.expect(has(problems[2], "arch.md:8:")).toBe(true)
		t.expect(has(problems[3], "arch.md:10:")).toBe(true)
	end)

	it("any other non-edge line is named too", function()
		for _, bad in { "A -> ", "A => B", "A -> B -> C", "just words", "- A -> B" } do
			local _, problems = deps.parse(doc({ "A -> B", bad }), "arch.md")
			t.expect(#problems).toBe(1)
			t.expect(has(problems[1], "arch.md:6:")).toBe(true)
		end
	end)

	it("no block, two blocks, or one never closed is a problem", function()
		local _, none = deps.parse("# nothing\n", "arch.md")
		t.expect(#none).toBe(1)
		local _, two = deps.parse(doc({ "A -> B" }) .. doc({ "C -> D" }), "arch.md")
		t.expect(#two).toBe(1)
		local _, open = deps.parse("x\n" .. FENCE .. "deps\nA -> B\n", "arch.md")
		t.expect(#open).toBe(1)
	end)

	it("pickman's architecture meta spec reads the block through it, its own matcher gone", function()
		local src = fs.readFile("../pickman/tests/meta/architecture.spec.luau")
		t.expect(has(src, 'require("@znile/lib/deps")')).toBe(true)
		t.expect(has(src, ".parse(")).toBe(true)
		t.expect(has(src, "%s*(%w+)%s*%->%s*(%w+)")).toBe(false)
	end)
end)
