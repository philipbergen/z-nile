--!strict
-- c0063 AC1: f0031's promoted specs are narrowed, not deleted. They no longer pin what f0065 replaces (the
-- PlayAgain remote and handler, the playAgain overlay field, the play-again keys, the cursor wired to that field),
-- and they still pin everything that stays true after it: READY!, the fade, the flash, the GAME OVER results, the
-- thin server, the client wiring and the whole run on screen.
-- This spec reads f0031's specs as text, so `--affected` never selects it (only `--full` runs it): any later change
-- to tests/acceptance/f0031 must update the case lists and assertion counts here.
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

-- spelled in two parts so a compaction does not rewrite it; the id is mapped through tracker/compaction.txt
local DIR = "tests/" .. "acceptance/" .. renamed.id("f0031")
local FILES = { "overlay", "adapter", "place", "presentation-run" }

local function read(name: string): string
	return fs.readFile(`{DIR}/{name}.spec.luau`)
end

-- the text without comments, so a mention in a comment proves nothing either way
local function code(name: string): string
	local src = string.gsub(read(name), "%-%-[^\n]*", "")
	return src
end

-- every case, in file order (`it("name"` or `it(` with the name on the next line), as "name = n" where n is
-- how many assertions (`t.expect(`) the case makes, so a kept case whose assertions were removed fails
local function cases(name: string): { string }
	local src = code(name)
	local starts: { number } = {}
	local names: { string } = {}
	local at = 1
	while true do
		local s, e, found = string.find(src, 'it%(%s*"([^"]*)"', at)
		if s == nil then
			break
		end
		table.insert(starts, s)
		table.insert(names, found :: string)
		at = (e :: number) + 1
	end
	local out: { string } = {}
	for i, case in names do
		local body = string.sub(src, starts[i], (starts[i + 1] or (#src + 1)) - 1)
		local _, n = string.gsub(body, "t%.expect%(", "")
		table.insert(out, `{case} = {n}`)
	end
	return out
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0063 the play-again specs, narrowed", function(it)
	it("all four specs are still there, and f0031's check.sh still runs each of them", function()
		-- c0120 override: the spec runs from its project's home after the move
		local check = fs.readFile(".tracker/issues/done/" .. renamed.id("f0031") .. "/check.sh")
		for _, name in FILES do
			t.expect(fs.isFile(`{DIR}/{name}.spec.luau`)).toBe(true)
			t.expect(has(check, `"$A/{name}.spec.luau"`)).toBe(true)
		end
	end)

	it("no spec pins the play-again surface any more", function()
		for _, name in FILES do
			local src = code(name)
			for _, gone in { "PlayAgain", "PLAY_AGAIN", "isPlayAgainKey", "PLAY AGAIN" } do
				t.expect(has(src, gone)).toBe(false)
			end
			-- the only playAgain left is Logic's Session.playAgain, which f0065 keeps
			local at = 1
			while true do
				local s = string.find(src, "playAgain", at, true)
				if s == nil then
					break
				end
				local before = string.sub(src, math.max(1, s - 9), s - 1)
				t.expect(string.sub(before, -8) == "Session." or string.sub(before, -9) == "Session%.")
					.toBe(true)
				at = s + 1
			end
		end
	end)

	it("the overlay spec keeps its cases and their assertions, narrowed to the fields that stay", function()
		t.expect(cases("overlay")).toEqual({ -- name = assertions
			"the constants: fade up to 0.6, walls flash in runs of 6 ticks = 2",
			"a ready pause shows READY! over the level, with no fade or flash = 4",
			"play shows nothing over the maze = 4",
			"the fade deepens through the dying pause, from none to FADE_MAX = 4",
			"the fade follows the rules' dying pause, not a fixed one = 1",
			"with no dying pause a dying frame is fully faded, not an error = 1",
			"dying shows no banner = 3",
			"the walls are lit when (timer // FLASH_TICKS) is odd in the level-clear pause = 6",
			"a classic level-clear pause flashes five times, six ticks each = 1",
			"the level-clear pause has no banner or fade = 2",
			"only the level-clear pause flashes = 1",
			"game over shows GAME OVER with the final score and level, fully faded = 3",
			"leaves the record unchanged = 1",
		})
		local src = code("overlay")
		for _, kept in
			{
				"t.expect(Flow.FADE_MAX).toBe(0.6)",
				"t.expect(Flow.FLASH_TICKS).toBe(6)",
				'toBe("READY!")',
				'toBe("LEVEL 3")',
				"toBeNear(0.4, 1e-9)",
				"toBeNear(0.3, 1e-9)",
				"{ 6, 6, 6, 6, 6 }",
				'toBe("GAME OVER")',
				'toBe("SCORE 12340   LEVEL 3")',
				"t.expect(o.fade).toBe(0.6)",
			}
		do
			t.expect(has(src, kept)).toBe(true)
		end
		-- ready and play still pin every field that stays, not the whole table
		t.expect(has(src, "toEqual({\n\t\t\t\tbanner")).toBe(false)
		t.expect(select(2, string.gsub(src, "t%.expect%(o%.fade%)%.toBe%(0%)", "")) >= 3).toBe(true)
	end)

	it(
		"the adapter spec keeps a thin server: any playAgain call is the sender's own, and no phase is read",
		function()
			t.expect(cases("adapter")).toEqual({
				"the place keeps its Ready, Intent and Snapshot RemoteEvents = 1",
				"any Session.playAgain call in Sessions is for the sending player's own id, and nothing the client sent = 2",
				"a handler that plays again takes only the sending player, and uses it for both the session and the id = 4",
				"Sessions leaves the decision to Logic: it never looks at the phase = 2",
			})
			local src = code("adapter")
			t.expect(has(src, "t.expect(calls <= 1).toBe(true)")).toBe(true)
			t.expect(has(src, "t.expect(found <= 1).toBe(true)")).toBe(true)
			t.expect(has(src, '"gameover", 1, true')).toBe(true)
			t.expect(has(src, '".phase", 1, true')).toBe(true)
		end
	)

	it("the place spec keeps the client wiring, with the cursor wired to some overlay field", function()
		t.expect(cases("place")).toEqual({
			"the client Main requires the FlowView module = 2",
			"Main computes Flow.overlay with the server's rules, Session.GAME_CONFIG = 3",
			"Main hands the overlay to FlowView.show, MazeView.flash and Camera.setCursor = 3",
			"MazeView can light its walls and Camera can free the mouse = 3",
			"Camera no longer locks the mouse unconditionally: the lock depends on the cursor = 2",
			"the cursor flag frees the mouse and shows the icon, never the other way round = 3",
			"Main starts every adapter before it signals Ready, so no frame meets an unbuilt view = 2",
			"FlowView uses the Flow feature and sends a request to the server = 2",
			"FlowView sends the request with no arguments: the server knows who asked = 1",
		})
		local src = read("place")
		t.expect(has(src, '"Camera%.setCursor%(%s*[%w_]+%.[%w_]+%s*%)"')).toBe(true)
		t.expect(has(src, 't.expect(call).toBe(":FireServer()")')).toBe(true)
	end)

	it("the whole run still shows the results at game over, and they stay up", function()
		t.expect(cases("presentation-run")).toEqual({
			"shows the countdown, the score, the flash, the next level, the deaths, game over and a new run = 32",
			"a play-again request outside game over changes nothing on screen = 2",
		})
		local src = code("presentation-run")
		t.expect(has(src, 't.expect(over.overlay.banner).toBe("GAME OVER")')).toBe(true)
		t.expect(has(src, 't.expect(over.overlay.detail).toBe("SCORE 70   LEVEL 2")')).toBe(true)
		t.expect(has(src, 't.expect(screen(s).overlay.banner).toBe("GAME OVER")')).toBe(true)
		t.expect(has(src, "t.expect(lit).toBe(6)")).toBe(true)
	end)
end)
