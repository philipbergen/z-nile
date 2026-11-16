--!strict
-- c0231 AC6: the refusal of a yes names the rule, the head that would end it and the wrapper, and the hook entry refuses
-- a bare yes from the tool call's JSON with exit 2 while a head-fed one passes silently.
local boundcmd = require("@znile/engine/boundcmd")
local serde = require("@lune/serde")
local sh = require("@znile/lib/sh")
local t = require("@tests/lib/t")

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local function hook(command: string): sh.Result
	local payload = serde.encode("json", { tool_name = "Bash", tool_input = { command = command } })
	return sh.run("env", { "ZN_CHECKOUT=/Users/me/code/pickman", "lune", "run", "guard-bash" }, payload)
end

return t.spec("c0231 the refusal of a yes", function(it)
	it("AC6: the refusal names the follow rule, the head that ends yes and the checkout's wrapper", function()
		local v = boundcmd.check("cd d && yes n", { zn = "/Users/me/code/pickman/zn" })
		t.expect(v.rule).toBe("follow")
		t.expect(v.command).toBe("yes n")
		local say = boundcmd.explain(v)
		t.expect(has(say, "refused by z-nile (follow)")).toBe(true)
		t.expect(has(say, "`yes | head -3`")).toBe(true)
		t.expect(has(say, "/Users/me/code/pickman/zn run --time <seconds> -- sh -c '<pipeline>'")).toBe(true)
	end)

	it("AC6: the hook entry refuses a bare yes with exit 2 and lets a head-fed one through", function()
		local bare = hook("yes > /dev/null")
		t.expect(bare.code).toBe(2)
		t.expect(has(bare.stderr, "(follow)")).toBe(true)
		t.expect(has(bare.stderr, "/Users/me/code/pickman/zn run --time")).toBe(true)
		t.expect(bare.stdout).toBe("")
		local fed = hook("yes | head -3")
		t.expect(fed.code).toBe(0)
		t.expect(fed.stdout .. fed.stderr).toBe("")
	end)
end)
