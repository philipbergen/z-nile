--!strict
-- c0118 AC8 (design review 006 F3): metrics counts review rounds by the board's rule, `boardview.rounds`, not by a copy of
-- its patterns. c0116's metrics counts rounds in two functions of z-nile/engine/main.luau, `designRoundsIn(dir)` (a
-- folder's design rounds: the per-issue table, the per-raft roll-up, retired rafts) and `codeRounds(dir)` (a raft's
-- code rounds). Their outputs can't tell a copy from the shared rule (the patterns are the same), so this pins the
-- source: each function's body calls `boardview.rounds` and names no round-file pattern of its own. Other places in
-- main.luau that name review files for other purposes (z-raft's coherence review) are not metrics and are not read.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- The body of the function `name` declared in `text` (`local function <name>(` at any indent), up to the first line
-- that is that indent followed by `end`; nil when there is no such function.
local function body(text: string, name: string): string?
	local lines = string.split(text, "\n")
	for i, line in lines do
		local indent = string.match(line, `^(%s*)local function {name}%(`)
		if indent then
			local out = { line }
			for j = i + 1, #lines do
				table.insert(out, lines[j])
				if lines[j] == `{indent}end` then
					return table.concat(out, "\n")
				end
			end
			return nil
		end
	end
	return nil
end

-- a round-file pattern written in Lua pattern syntax: `design%-review%-%d`, `review%-%d`, `refute%-%d` and the like
local function ownPattern(b: string): boolean
	return string.find(b, "review%%%-%%d", 1) ~= nil or string.find(b, "review%-%d", 1, true) ~= nil
end

return t.spec("c0118 metrics rounds", function(it)
	local text = fs.readFile(`{TOP}/z-nile/engine/main.luau`)

	it("the body finder reads a nested function to its own end, and flags a copied pattern", function()
		local sample =
			'local function a(x)\n\tlocal function codeRounds(dir)\n\t\tif string.match(n, "^review%-%d+%.md$") then\n\t\tend\n\tend\n\treturn 1\nend\n'
		local b = body(sample, "codeRounds")
		t.expect(b ~= nil).toBe(true)
		t.expect(string.find(b :: string, "return 1", 1, true)).toBe(nil)
		t.expect(ownPattern(b :: string)).toBe(true)
		t.expect(ownPattern("local d, c = boardview.rounds(paths)")).toBe(false)
		t.expect(body(sample, "missing")).toBe(nil)
	end)

	for _, name in { "designRoundsIn", "codeRounds" } do
		it(`metrics' {name} counts through boardview.rounds and keeps no pattern of its own`, function()
			local b = body(text, name)
			if not b then
				error(`z-nile/engine/main.luau has no local function {name} (c0116's metrics counter)`)
			end
			t.expect(string.find(b :: string, "boardview.rounds(", 1, true) ~= nil).toBe(true)
			t.expect(ownPattern(b :: string)).toBe(false)
		end)
	end
end)
