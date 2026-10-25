--!strict
-- c0103 AC1: f0014's promoted key-map spec is narrowed, not deleted. It no longer pins the arrow keys, Space, the
-- exact number of keys or that Q and E are unbound (f0104 binds jump, fire and arrow look), and it still pins the
-- movement keys W, A, S and D, that other keys do nothing, and that every mapped action is a real name.
-- The narrowed file is pinned token for token (only whitespace, a trailing comma before `}` and item ids are tolerated),
-- so a case whose loops or lists were emptied cannot pass. This spec reads f0014's spec as text, so `--affected`
-- never selects it (only `--full` runs it): any later change to tests/acceptance/f0014/keys.spec.luau must update
-- the golden text here.
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

-- spelled in two parts so a compaction does not rewrite it; the id is mapped through tracker/compaction.txt
local DIR = "tests/" .. "acceptance/" .. renamed.id("f0014")
local FILE = `{DIR}/keys.spec.luau`

-- the file as one line. Exactly three things are tolerated: whitespace (collapsed), a trailing comma before a closing
-- brace (stylua may reflow a table to one line) and item ids such as f0130 (masked, so a compaction cannot break it).
-- Comments are NOT stripped: their text is pinned too, so no code can hide in one (a line comment, a long comment or
-- a string that opens a long comment). The require lines are pinned, so a stub for View or Movement must not pass.
local function normalised(): string
	local text = string.gsub(fs.readFile(FILE), "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	text = string.gsub(text, "%s+", " ")
	text = string.gsub(text, ",%s*}", " }")
	text = string.gsub(text, "^ ", "")
	text = string.gsub(text, " $", "")
	return text
end

local GOLDEN = "--!strict -- ID AC5: the key map, by Enum.KeyCode name. -- Narrowed by ID: only the moveme"
	.. "nt keys W, A, S and D are pinned. The arrow keys, Space and the number of keys -- are free"
	.. " to change, so the jump, fire and arrow-look bindings (ID) can be added without a red main"
	.. ". local Movement = requ"
	.. 'ire("@logic/Movement") local View = requ'
	.. 'ire("@logic/View") local t '
	.. "= requ"
	.. 'ire("@tests/lib/t") return t.spec("ID key map", function(it) it("maps W, A, S and D '
	.. 'to the movement intents", function() local want: { [string]: string } = { W = "Forward", A'
	.. ' = "Left", D = "Right", S = "Back" } for key, action in want do t.expect(View.action(key))'
	.. ".toBe(action) end local n = 0 for _ in View.KEYS do n += 1 end t.expect(n >= 4).toBe(true)"
	.. ' end) it("other keys do nothing", function() for _, key in { "w", "Return", "LeftShift", "'
	.. '" } do t.expect(View.action(key)).toBe(nil) end end) it("every mapped action is a name, an'
	.. 'd W, A, S and D map to movement intents", function() for _, action in View.KEYS do t.expec'
	.. 't(type(action) == "string" and action ~= "").toBe(true) end for _, key in { "W", "A", "S",'
	.. ' "D" } do t.expect(Movement.isIntent(View.action(key))).toBe(true) end end) end)'

return t.spec("c0103 the key-map spec, narrowed", function(it)
	it("the spec is still there, and f0014's check.sh still runs it", function()
		-- c0120 override: the spec runs from its project's home after the move
		local check = fs.readFile(".tracker/issues/done/" .. renamed.id("f0014") .. "/check.sh")
		t.expect(fs.isFile(FILE)).toBe(true)
		t.expect(string.find(check, '"$A/keys.spec.luau"', 1, true) ~= nil).toBe(true)
	end)

	it("the spec is exactly the narrowed one: W, A, S and D, unbound keys, the shape of the map", function()
		t.expect(normalised()).toBe(GOLDEN)
	end)
end)
