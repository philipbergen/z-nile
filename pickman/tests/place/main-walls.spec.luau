--!strict
-- R0056 code review 001 F1: Main hands the walls' state to MazeView and the danger radar on every frame, not only
-- when something else changes. f0109's place case finds the calls' text; this one pins where they run in the frame
-- handler (`snapshots.OnClientEvent:Connect(function(frame …)`): `MazeView.edible(model, View.edible(frame.play))`
-- inside nothing but `if model then`, and `DangerHud.wallState(overlay.flash, View.edible(frame.play))` at the
-- handler's top level. So a merge that folds either call into the flash block (`if model and overlay.flash ~= lit`)
-- or guards it with anything else turns this red. It reads Main's source by its indentation (one tab per block, as
-- stylua writes it); a refactor that moves the calls into a helper called every frame updates this case.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local MAIN = "src/client/Main.client.luau"

local function lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(string.gsub(text, "\r\n", "\n") .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

local function indent(line: string): number
	return #(string.match(line, "^\t*") :: string)
end

-- the openers (trimmed) of the blocks around line `at`, innermost first, up to the frame handler's opener
local function enclosing(src: { string }, at: number): ({ string }, string?)
	local out: { string } = {}
	local level = indent(src[at])
	for i = at - 1, 1, -1 do
		local line = src[i]
		if string.match(line, "%S") and indent(line) < level then
			level = indent(line)
			local opener = string.match(line, "^\t*(.-)%s*$") :: string
			if level == 0 then
				return out, opener
			end
			table.insert(out, opener)
		end
	end
	return out, nil
end

local function find(src: { string }, call: string): { number }
	local at: { number } = {}
	for i, line in src do
		if string.find(line, call, 1, true) and not string.match(line, "^%s*%-%-") then
			table.insert(at, i)
		end
	end
	return at
end

local HANDLER = "snapshots.OnClientEvent:Connect(function(frame: Session.Frame)"

return t.spec("R0056 Main hands the walls' state over on every frame", function(it)
	it("MazeView.edible runs once per frame, inside nothing but `if model then`", function()
		local src = lines(fs.readFile(MAIN))
		local at = find(src, "MazeView.edible(model, View.edible(frame.play))")
		t.expect(#at).toBe(1)
		local blocks, handler = enclosing(src, at[1])
		t.expect(handler).toBe(HANDLER)
		t.expect(blocks).toEqual({ "if model then" })
	end)

	it("DangerHud.wallState runs once per frame, at the handler's top level", function()
		local src = lines(fs.readFile(MAIN))
		local at = find(src, "DangerHud.wallState(overlay.flash, View.edible(frame.play))")
		t.expect(#at).toBe(1)
		local blocks, handler = enclosing(src, at[1])
		t.expect(handler).toBe(HANDLER)
		t.expect(blocks).toEqual({})
	end)

	it("the reader sees a call folded into the flash block, or guarded, as nested", function()
		local folded = lines(
			"x:Connect(function(frame)\n\tif model and overlay.flash ~= lit then\n\t\tlit = overlay.flash\n\t\tMazeView.edible(model, View.edible(frame.play))\n\tend\nend)"
		)
		local blocks = enclosing(folded, 4)
		t.expect(blocks).toEqual({ "if model and overlay.flash ~= lit then" })
		local guarded =
			lines("x:Connect(function(frame)\n\tif model and false then\n\t\tMazeView.edible(m)\n\tend\nend)")
		t.expect((enclosing(guarded, 3))).toEqual({ "if model and false then" })
	end)
end)
