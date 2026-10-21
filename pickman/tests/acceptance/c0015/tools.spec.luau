--!strict
-- c0140 AC5: z-nile/setup.sh --tools installs the toolchain and stops before the gate, so the deploy
-- job doesn't run the whole gate a second time. The default (no flag) still ends with the gate.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local text = fs.readFile("../z-nile/setup.sh")

local function at(needle: string): number?
	return (string.find(text, needle, 1, true))
end

return t.spec("c0140 setup.sh --tools", function(it)
	it("has a tools-only mode that exits before the gate", function()
		local flag = at("== --tools ]]") -- the condition itself, not a mention in a comment
		local gate = at('say "gate"')
		t.expect(flag ~= nil).toBe(true)
		t.expect(gate ~= nil).toBe(true)
		t.expect((flag :: number) < (gate :: number)).toBe(true)
		local exit = string.find(text, "exit 0", flag :: number, true)
		t.expect(exit ~= nil).toBe(true)
		t.expect((exit :: number) < (gate :: number)).toBe(true)
	end)

	it("still runs the gate when called without the flag, after the tools and type definitions", function()
		local gate = at("z-nile/check.sh --full")
		t.expect(gate ~= nil).toBe(true)
		t.expect((at("lune setup") :: number) < (gate :: number)).toBe(true)
		t.expect((at("rokit install") :: number) < (gate :: number)).toBe(true)
	end)

	it("installs the tools before it can stop", function()
		t.expect((at("rokit install") :: number) < (at("== --tools ]]") :: number)).toBe(true)
		t.expect((at("lune setup") :: number) < (at("== --tools ]]") :: number)).toBe(true)
	end)

	it("refuses an argument it doesn't know instead of silently running the whole gate", function()
		t.expect(at("unknown argument") ~= nil).toBe(true)
	end)
end)
