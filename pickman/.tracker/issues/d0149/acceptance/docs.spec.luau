--!strict
-- d0149 AC5: the documents say what the game now does. game-design.md's Mobile section describes the touch circles
-- (the user's decisions, 2026-10-25 and 2026-10-31) and no longer the swipes, the drag look or the snap button;
-- architecture.md declares Touch -> Pad and no longer the edges the new Touch does not use (Touch -> Hud, View).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function section(doc: string, heading: string): string
	local start = string.find(doc, "\n## " .. heading .. "\n", 1, true)
	assert(start, `no {heading} section`)
	local stop = string.find(doc, "\n## ", start + 1, true) or #doc + 1
	return string.sub(doc, start, stop - 1)
end

return t.spec("d0149 the documents", function(it)
	it("game-design.md's Mobile section states the circles, the tap, the buttons and the dead space", function()
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
	end)

	it("game-design.md's Mobile section no longer offers the swipes, the drag look or the snap button", function()
		local mobile = section(fs.readFile(".tracker/game-design.md"), "Mobile")
		for _, gone in { "**Turns:** a swipe", "drag on the right half", '"snap look to heading" button' } do
			t.expect((string.find(mobile, gone, 1, true))).toBe(nil)
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
