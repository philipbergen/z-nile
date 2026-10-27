--!strict
-- c0162 AC3: the documents that show a bare `lune run tests/run` say the runner runs on rokit.toml's Lune: zz-test's
-- Running tests table, pickman-test's opening and SETUP.md's CI section each carry the sentence, naming the fix.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local SENTENCE = "The runner runs on the Lune `rokit.toml` pins (c0162)"
local FIX = '`PATH="$HOME/.rokit/bin:$PATH"`'

return t.spec("c0162 the documents say which Lune the runner runs on", function(it)
	for _, rel in { "z-nile/skills/zz-test/SKILL.md", "pickman/skills/pickman-test/SKILL.md", "SETUP.md" } do
		it(`{rel} says it, with the fix`, function()
			local text = fs.readFile(`{root}/{rel}`)
			t.expect(string.find(text, SENTENCE, 1, true) ~= nil).toBe(true)
			t.expect(string.find(text, FIX, 1, true) ~= nil).toBe(true)
		end)
	end
end)
