--!strict
-- f0421 slice 3, AC28: nothing changes for a table that does not use slice 3's keys. The root `.models.toml` as origin/main
-- held it at 5e8f5eaa4 (tests/fixtures/models/root-5e8f5eaa4.models.toml) resolves every activity, the answers, trace and fix
-- included, at easy, normal and risky, for all five CLIs, for no session and for each model a session may name, and gives the
-- same can-lists, deliverers, needs, waiting lines, aliases, builder guesses and refusals as the engine gave before slice 3
-- (tests/fixtures/models/models-pin.expected.txt, captured from that engine and committed before any engine change).
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local modelspin = require("@tests/lib/modelspin")
local t = require("@tests/lib/t")

local FIXTURES = "tests/fixtures/models"

local function expected(): { string }
	local out: { string } = {}
	for line in string.gmatch(fs.readFile(`{FIXTURES}/models-pin.expected.txt`), "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

return t.spec("f0421 slice 3: every answer for today's root table is pinned", function(it)
	it("the frozen root table gives every pinned answer, line for line", function()
		local layers = { models.parse(fs.readFile(`{FIXTURES}/root-5e8f5eaa4.models.toml`), ".models.toml") }
		local now = modelspin.lines(layers)
		local want = expected()
		-- the first line that differs, so a red run names the answer that changed
		local first = 0
		for i = 1, math.max(#now, #want) do
			if now[i] ~= want[i] then
				first = i
				break
			end
		end
		t.expect(
			if first == 0
				then ""
				else `line {first}: got {tostring(now[first])}; want {tostring(want[first])}`
		)
			.toBe("")
		t.expect(#now).toBe(#want)
	end)

	it(
		"the pin covers what it says: five CLIs, agy's five session models and the answer activities",
		function()
			local want = table.concat(expected(), "\n")
			for _, cli in models.CLIS do
				t.expect(string.find(want, `cli {cli} `, 1, true) ~= nil).toBe(true)
			end
			for _, m in
				{
					"gemini-4-argon-high",
					"gemini-4-argon-medium",
					"gemini-4-neon-high",
					"gemini-4-neon-low",
					"gemini-4-neon-medium",
				}
			do
				t.expect(string.find(want, `  session {m}\n`, 1, true) ~= nil).toBe(true)
			end
			for _, act in { "design-answer", "code-answer", "final-answer", "trace", "fix" } do
				t.expect(string.find(want, `    {act}/risky `, 1, true) ~= nil).toBe(true)
			end
			t.expect(
				string.find(want, "  normal waiting=final-review/normal (ultra: claude)", 1, true) ~= nil
			)
				.toBe(true)
		end
	)
end)
