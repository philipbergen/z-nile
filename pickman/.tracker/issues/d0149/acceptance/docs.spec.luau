--!strict
-- d0149 AC5: the documents say what the game now does. The whole-document absence scan runs only under
-- D0149_EXACT=1 (AC5's check.sh line); the positive needles always run. game-design.md's Mobile section describes the touch circles
-- (the user's decisions, 2026-10-25 and 2026-10-31) and no longer the swipes, the drag look or the snap button;
-- architecture.md declares Touch -> Pad and no longer the edges the new Touch does not use (Touch -> Hud, View).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function section(doc: string, heading: string): string
	local start = string.find(doc, "\n## " .. heading .. "\n", 1, true)
	assert(start, `no {heading} section`)
	local stop = string.find(doc, "\n## ", start + 1, true) or #doc + 1
	return string.sub(doc, start, stop - 1)
end

return t.spec("d0149 the documents", function(it)
	it(
		"game-design.md's Mobile section states the circles, the tap, the buttons and the dead space",
		function()
			local mobile = section(fs.readFile(".tracker/game-design.md"), "Mobile")
			for _, needle in
				{
					"d0149",
					"Steer circle",
					"Look circle",
					"30% of the screen's shorter side",
					"96 to 160 px",
					"springs the view back",
					"0.25 s",
					"12 px",
					"FIRE and PICK",
					"outside the controls does nothing",
					"two quick pulls up boost",
					"480 x 320",
				}
			do
				t.expect(string.find(mobile, needle, 1, true) ~= nil).toBe(true)
			end
		end
	)

	it(
		"nowhere in game-design.md offers the swipes, the drag look, the snap button or JUMP any more",
		function()
			-- checked only when D0149_EXACT is set, which only AC5's line in d0149's check.sh does: once promoted, a
			-- later issue may use these words again (design review 005 F2, as f0158's F0158_EXACT)
			if process.env.D0149_EXACT ~= "1" then
				return
			end
			-- the Touch circles bullet names what it replaces; every other line is read (review 001 F5: f0126's and
			-- f0143's sections and the Look rule restate the touch controls too)
			local doc = fs.readFile(".tracker/game-design.md")
			local rest: { string } = {}
			for _, line in string.split(doc, "\n") do
				if string.sub(line, 1, 20) ~= "- **Touch circles** " then
					table.insert(rest, line)
				end
			end
			local text = string.lower(table.concat(rest, "\n"))
			local found: { string } = {}
			for _, gone in
				{ "swipe", "snap look to heading", "drag on the right half", "jump button", "jump control" }
			do
				if string.find(text, gone, 1, true) then
					table.insert(found, gone)
				end
			end
			t.expect(table.concat(found, ", ")).toBe("")
			t.expect((string.find(table.concat(rest, "\n"), "JUMP", 1, true))).toBe(nil)
		end
	)

	it("the Look rule, the pick and the boost say how touch does them now", function()
		local doc = fs.readFile(".tracker/game-design.md")
		for _, needle in
			{
				"on touch the look circle points the view",
				"on touch the PICK button, left of FIRE beside the look circle",
				"on touch, two quick pulls up on the steer circle",
			}
		do
			t.expect(string.find(doc, needle, 1, true) ~= nil).toBe(true)
		end
	end)

	it("architecture.md declares Touch -> Pad, and not Touch -> Hud or Touch -> View", function()
		local arch = fs.readFile(".tracker/architecture.md")
		local deps = string.match(arch, "```deps\n(.-)```") or ""
		t.expect(string.find(deps, "\nTouch -> Pad\n", 1, true) ~= nil).toBe(true)
		t.expect((string.find(deps, "\nTouch -> Hud\n", 1, true))).toBe(nil)
		t.expect((string.find(deps, "\nTouch -> View\n", 1, true))).toBe(nil)
	end)
end)
