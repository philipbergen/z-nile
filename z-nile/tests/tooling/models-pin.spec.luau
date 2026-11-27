--!strict
-- f0421 slice 3, AC28: nothing changes for a table that does not use slice 3's keys. The root `.models.toml` as origin/main
-- held it at 5e8f5eaa4 (tests/fixtures/models/root-5e8f5eaa4.models.toml) resolves every activity, the answers, trace and fix
-- included, at easy, normal and risky, for all five CLIs, for no session and for each model a session may name, and gives the
-- same can-lists, deliverers, needs, waiting lines, aliases, builder guesses and refusals as the engine gave before slice 3
-- (tests/fixtures/models/models-pin.expected.txt, captured from that engine and committed before any engine change). The
-- real root file is tied to tests/fixtures/models/models-pin-agy-ultra.expected.txt (and, with agy's ultra line stripped, to
-- models-pin.expected.txt) while it has no [catalog] (S1b's seed retires that case). Outside the pin: what the
-- identity change makes one model (`-fast`, `none`, `minimal`; the pin's authors carry none of them), which
-- tests/tooling/models-identity.spec.luau covers.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local modelspin = require("@tests/lib/modelspin")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local FIXTURES = "tests/fixtures/models"

local function expected(): { string }
	local out: { string } = {}
	for line in string.gmatch(fs.readFile(`{FIXTURES}/models-pin.expected.txt`), "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function frozen(): { models.Layer }
	return { models.parse(fs.readFile(`{FIXTURES}/root-5e8f5eaa4.models.toml`), ".models.toml") }
end

return t.spec("f0421 slice 3: every answer for today's root table is pinned", function(it)
	it("the frozen root table gives every pinned answer, line for line", function()
		local now = modelspin.lines(frozen())
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
			-- computed by the engine, so this case fails when the engine cannot answer (review-005 F11)
			local now = table.concat(modelspin.lines(frozen()), "\n")
			for _, cli in models.CLIS do
				t.expect(string.find(now, `cli {cli} `, 1, true) ~= nil).toBe(true)
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
				t.expect(string.find(now, `  session {m}\n`, 1, true) ~= nil).toBe(true)
			end
			for _, act in { "design-answer", "code-answer", "final-answer", "trace", "fix" } do
				t.expect(string.find(now, `    {act}/risky `, 1, true) ~= nil).toBe(true)
			end
			t.expect(string.find(now, "  normal waiting=final-review/normal (ultra: claude)", 1, true) ~= nil)
				.toBe(true)
		end
	)

	it(
		"the real root file is the pinned copy plus agy's ultra while it has no [catalog] (S1b's seed retires this case)",
		function()
			local top = (
				string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
			)
			local raw = fs.readFile(`{top}/.models.toml`)
			local layers = { models.parse(raw, ".models.toml") }
			if layers[1].catalog ~= nil then
				return -- S1b seeded the root file: its answers are AC32's to pin
			end
			local ultra = models.resolveAlias(layers, "agy", "ultra")
			t.expect(ultra ~= nil and ultra.model).toBe("gemini-4-carbon-high")
			local stripped, count = string.gsub(raw, '\nultra = { model = "gemini%-4%-carbon%-high" }', "")
			t.expect(count).toBe(1)
			t.expect(modelspin.lines({ models.parse(stripped, ".models.toml") })).toEqual(expected())
			local wantUltra: { string } = {}
			for line in string.gmatch(fs.readFile(`{FIXTURES}/models-pin-agy-ultra.expected.txt`), "[^\n]+") do
				table.insert(wantUltra, line)
			end
			t.expect(modelspin.lines(layers)).toEqual(wantUltra)
		end
	)
end)
