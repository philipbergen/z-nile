--!strict
-- Kimi's usage.record, from a recorded session wire: inputOther + inputCacheCreation + output.
-- inputCacheRead stays out. A step.end line repeats the same usage and is not counted again.
local adapters = require("@znile/engine/adapters")
local t = require("@tests/lib/t")

local FIRST =
	[[{"type":"usage.record","model":"kimi-code/k3.1-pro","usage":{"inputOther":2061,"output":300,"inputCacheRead":15104,"inputCacheCreation":0},"usageScope":"turn"}]]
local SECOND =
	[[{"type":"usage.record","model":"kimi-code/k3.1-pro","usage":{"inputOther":10,"output":1,"inputCacheRead":4,"inputCacheCreation":0},"usageScope":"turn"}]]
local END =
	[[{"type":"step.end","usage":{"inputOther":2061,"output":300,"inputCacheRead":15104,"inputCacheCreation":0}}]]

return t.spec("kimi-cli reads usage.record and leaves cache reads out", function(it)
	it("counts one record, sums a second, and ignores the step.end copy", function()
		local adapter = adapters.get("kimi-cli")
		local acc = adapters.newAcc()
		adapter.feed(acc, FIRST)
		t.expect(adapters.tokens(acc)).toBe(2361)
		adapter.feed(acc, SECOND)
		t.expect(adapters.tokens(acc)).toBe(2372)
		adapter.feed(acc, END)
		t.expect(adapters.tokens(acc)).toBe(2372)
	end)

	it("asks the CLI for the slashed model id", function()
		local adapter = adapters.get("kimi-cli")
		local argv = adapter.argv({
			prompt = "p",
			model = "kimi-code-k3.1-pro",
			cwd = ".",
			session = "s",
		})
		t.expect(table.find(argv, "-p") ~= nil).toBe(true)
		t.expect(table.find(argv, "--auto") ~= nil).toBe(false)
		t.expect(table.find(argv, "kimi-code/k3.1-pro") ~= nil).toBe(true)
		t.expect(table.find(argv, "stream-json") ~= nil).toBe(true)
	end)
end)
