--!strict
-- c0231 AC5: a Monitor command may run `yes` (c0191 Decision 2: follows pass there); a background call judges it as
-- before (a head-fed one is still not bounded by its own means; a bare one is refused as a follow).
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local function expectOk(commands: { string }, ctx: boundcmd.Context?)
	for _, command in commands do
		local v = boundcmd.check(command, ctx)
		t.expect(`{command}: {if v.ok then "ok" else tostring(v.rule)}`).toBe(`{command}: ok`)
	end
end

return t.spec("c0231 yes in a Monitor and a background call", function(it)
	it("AC5: a Monitor command may run yes; a background call judges yes as before", function()
		expectOk({ "yes", "yes | cat", "yes > /dev/null" }, { monitor = true })
		-- a background call: a head-fed yes is still not bounded by its own means (c0191's background rule), and a bare one
		-- is refused by the first rule that sees it
		local piped = boundcmd.check("yes | head -3", { background = true })
		t.expect(if piped.ok then "ok" else tostring(piped.rule)).toBe("background")
		local bare = boundcmd.check("yes", { background = true })
		t.expect(if bare.ok then "ok" else tostring(bare.rule)).toBe("follow")
	end)
end)
