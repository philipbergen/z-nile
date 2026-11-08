--!strict
-- c0239 AC5: `./zn land` (a capture's merge) still runs the full gate. Pinned in the engine's text.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0239 land keeps the full gate", function(it)
	it("AC5: land's default gate is the full gate", function()
		local main = fs.readFile(`{root}/z-nile/engine/main.luau`)
		t.expect(string.find(main, 'local gate = override or "z-nile/check.sh --full"', 1, true) ~= nil)
			.toBe(true)
	end)
end)
