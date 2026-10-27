--!strict
-- R0056 code reviews 001 F1 and 002: Main hands the walls' state to MazeView and the danger radar on every frame,
-- not only when something else changes. f0109's place case finds the calls' text; this one pins where they run in
-- the frame handler (`snapshots.OnClientEvent:Connect(function(frame …)`): exactly one `MazeView.edible(` call,
-- `MazeView.edible(model, View.edible(frame.play))`, inside nothing but `if model then`; exactly one
-- `DangerHud.wallState(` call, `DangerHud.wallState(overlay.flash, View.edible(frame.play))`, at the handler's top
-- level; and no `return` in the handler before them. Main is read from the built place (`place.load()`), so the
-- affected selector picks this spec whenever src/ changes, with comments and string literals removed, so a call
-- inside `--[[ ]]` or a `[[ ]]` string is not counted. Blocks are read by indentation (one tab per block, as stylua
-- writes it); a refactor that moves the calls into a helper called every frame updates this case. A behaviour case
-- on f0126's Main harness is to replace it (c0164).
local graph = require("@znile/lib/graph")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local HANDLER = "snapshots.OnClientEvent:Connect(function(frame: Session.Frame)"

-- the code with comments and string literals removed (each literal becomes "" and keeps its line breaks)
local function code(src: string): string
	src = graph.stripComments((string.gsub(src, "\r\n", "\n")))
	local out: { string } = {}
	local i, n = 1, #src
	while i <= n do
		local c = string.sub(src, i, i)
		local eq = if c == "[" then string.match(src, "^%[(=*)%[", i) else nil
		if eq then
			local _, close = string.find(src, "]" .. eq .. "]", i + #eq + 2, true)
			local body = string.sub(src, i, close or n)
			table.insert(out, '""' .. string.rep("\n", select(2, string.gsub(body, "\n", ""))))
			i = (close or n) + 1
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c or d == "\n" then
					break
				else
					j += 1
				end
			end
			table.insert(out, '""')
			i = j + 1
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

local function lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

local function indent(line: string): number
	return #(string.match(line, "^\t*") :: string)
end

local function trim(line: string): string
	return string.match(line, "^%s*(.-)%s*$") :: string
end

-- the openers (trimmed) of the blocks around line `at`, innermost first, and the top-level line that opens them
local function enclosing(src: { string }, at: number): ({ string }, string?, number?)
	local out: { string } = {}
	local level = indent(src[at])
	for i = at - 1, 1, -1 do
		local line = src[i]
		if string.match(line, "%S") and indent(line) < level then
			level = indent(line)
			if level == 0 then
				return out, trim(line), i
			end
			table.insert(out, trim(line))
		end
	end
	return out, nil, nil
end

-- the lines that call `prefix` (a call by any arguments)
local function calls(src: { string }, prefix: string): { number }
	local at: { number } = {}
	for i, line in src do
		if string.find(line, prefix, 1, true) then
			table.insert(at, i)
		end
	end
	return at
end

-- no `return` between the handler's opener and line `at`
local function noReturnBefore(src: { string }, from: number, at: number): boolean
	for i = from + 1, at - 1 do
		if string.match(src[i], "^%s*return%f[%W]") or string.find(src[i], "%f[%w_]return%f[%W]") then
			return false
		end
	end
	return true
end

-- Main's code (or a variant of it) checked against the rule; nil when it holds, else what breaks it
local function broken(source: string): string?
	local src = lines(code(source))
	local edible = calls(src, "MazeView.edible(")
	if #edible ~= 1 then
		return `{#edible} MazeView.edible calls`
	end
	if trim(src[edible[1]]) ~= "MazeView.edible(model, View.edible(frame.play))" then
		return `MazeView.edible is called as {trim(src[edible[1]])}`
	end
	local blocks, handler, from = enclosing(src, edible[1])
	if handler ~= HANDLER or #blocks ~= 1 or blocks[1] ~= "if model then" then
		return `MazeView.edible runs inside {table.concat(blocks, " / ")} of {handler}`
	end
	if not noReturnBefore(src, from :: number, edible[1]) then
		return "a return before MazeView.edible"
	end
	local radar = calls(src, "DangerHud.wallState(")
	if #radar ~= 1 then
		return `{#radar} DangerHud.wallState calls`
	end
	if trim(src[radar[1]]) ~= "DangerHud.wallState(overlay.flash, View.edible(frame.play))" then
		return `DangerHud.wallState is called as {trim(src[radar[1]])}`
	end
	local around, top, start = enclosing(src, radar[1])
	if top ~= HANDLER or #around ~= 0 then
		return `DangerHud.wallState runs inside {table.concat(around, " / ")} of {top}`
	end
	if not noReturnBefore(src, start :: number, radar[1]) then
		return "a return before DangerHud.wallState"
	end
	return nil
end

local function main(): string
	local node = game
	for _, n in { "StarterPlayer", "StarterPlayerScripts", "Client", "Main" } do
		node = node and node:FindFirstChild(n)
	end
	t.expect(node ~= nil).toBe(true)
	return node.Source
end

local function swap(src: string, old: string, new: string): string
	local at = string.find(src, old, 1, true)
	assert(at ~= nil, `no "{old}" in Main`)
	return string.sub(src, 1, at - 1) .. new .. string.sub(src, at + #old)
end

return t.spec("R0056 Main hands the walls' state over on every frame", function(it)
	it(
		"Main calls MazeView.edible inside nothing but `if model then`, and DangerHud.wallState at the top",
		function()
			t.expect(broken(main())).toBe(nil)
		end
	)

	it(
		"the rule names each hole: a call folded into the flash block, guarded, hidden, doubled or returned past",
		function()
			local src = main()
			local block = "\tif model then\n\t\tMazeView.edible(model, View.edible(frame.play))\n\tend\n"
			local radar = "\tDangerHud.wallState(overlay.flash, View.edible(frame.play))\n"
			local h = HANDLER
			local variants: { { src: string, says: string } } = {
				{
					src = swap(
						src,
						"\tif model then\n\t\tMazeView.edible(",
						"\tif model and false then\n\t\tMazeView.edible("
					),
					says = `MazeView.edible runs inside if model and false then of {h}`,
				},
				{ src = swap(src, block, "\t--[[\n" .. block .. "\t]]\n"), says = "0 MazeView.edible calls" },
				{
					src = swap(src, radar, "\tlocal _ = [[\n" .. radar .. "\t]]\n"),
					says = "0 DangerHud.wallState calls",
				},
				{
					src = swap(src, block, "\tif not model then\n\t\treturn\n\tend\n" .. block),
					says = "a return before MazeView.edible",
				},
				{
					src = swap(src, block, block .. "\tMazeView.edible(model, false)\n"),
					says = "2 MazeView.edible calls",
				},
				{
					src = swap(src, radar, "\tif overlay.flash then\n\t" .. radar .. "\tend\n"),
					says = `DangerHud.wallState runs inside if overlay.flash then of {h}`,
				},
				{ src = swap(src, radar, radar .. radar), says = "2 DangerHud.wallState calls" },
			}
			for _, variant in variants do
				t.expect(broken(variant.src)).toBe(variant.says)
			end
			-- and a call mentioned in a line comment or a quoted string is not a call: the rule still holds
			local mentioned: { string } = {
				swap(src, radar, radar .. "\t-- " .. string.sub(radar, 2)),
				swap(src, radar, radar .. '\tlocal _ = "' .. string.sub(radar, 2, -2) .. '"\n'),
				swap(src, block, block .. "\t-- MazeView.edible(model, false)\n"),
				swap(src, block, block .. "\tlocal _ = 'MazeView.edible(model, false)'\n"),
			}
			for _, variant in mentioned do
				t.expect(broken(variant)).toBe(nil)
			end
		end
	)
end)
