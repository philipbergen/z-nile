--!strict
-- f0065 AC1: at game over the overlay shows the results and a prompt that says what a tap does now: go back to
-- the lobby, wait for the trip, try again in a moment, or nothing while the lobby is not set up. A tap asks only
-- at game over, only while nothing is under way and only when the lobby is set up. The mouse is free at game over.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Session = require("@logic/Session")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local RULES = Game.CLASSIC_CONFIG

local function play(over: { [string]: any }?): Session.PlayFrame
	local p: any = { phase = "playing", level = 1, score = 0, lives = 3, timer = 0, frightened = 0 }
	local changes: { [string]: any } = over or {}
	for k, v in changes do
		p[k] = v
	end
	return p
end

local OVER = { phase = "gameover", score = 12340, level = 3, lives = 0 }
local PHASES: { any } = { "idle", "going", "cooling" }

local function trip(phase: any, configured: boolean): Flow.Trip
	return { phase = phase, configured = configured }
end

return t.spec("f0065 results and the way back", function(it)
	it("the constants: the prompts, and Return and KeypadEnter continue", function()
		t.expect(Flow.PROMPT.idle).toBe("TAP TO RETURN TO THE LOBBY")
		t.expect(Flow.PROMPT.going).toBe("RETURNING TO THE LOBBY...")
		t.expect(Flow.PROMPT.cooling).toBe("Could not return. Try again in a moment.")
		t.expect(Flow.PROMPT.unset).toBe("The lobby is not set up yet.")
		t.expect(Flow.CONTINUE_KEYS).toEqual({ "Return", "KeypadEnter" })
	end)

	it("Return and KeypadEnter are the continue keys, and no movement key is one", function()
		t.expect(Flow.isContinueKey("Return")).toBe(true)
		t.expect(Flow.isContinueKey("KeypadEnter")).toBe(true)
		for _, key in { "Space", "W", "S", "Up", "return", "", "Escape", "ButtonA" } do
			t.expect(Flow.isContinueKey(key)).toBe(false)
		end
		for _, key in Flow.CONTINUE_KEYS do
			t.expect(View.action(key)).toBe(nil)
		end
	end)

	it("game over shows the results, the way back and a free mouse, and a tap asks", function()
		t.expect(Flow.overlay(play(OVER), RULES, trip("idle", true))).toEqual({
			banner = "GAME OVER",
			detail = "SCORE 12340   LEVEL 3",
			fade = 0.6,
			flash = false,
			prompt = "TAP TO RETURN TO THE LOBBY",
			tap = true,
			cursor = true,
		})
	end)

	it("before the server has reported anything, game over offers the way back", function()
		t.expect(Flow.overlay(play(OVER), RULES)).toEqual(Flow.overlay(play(OVER), RULES, trip("idle", true)))
		t.expect(Flow.overlay(play(OVER), RULES, nil).tap).toBe(true)
	end)

	it(
		"while the trip is under way the results stay, the prompt says so, and a tap does not ask again",
		function()
			local o = Flow.overlay(play(OVER), RULES, trip("going", true))
			t.expect(o.banner).toBe("GAME OVER")
			t.expect(o.detail).toBe("SCORE 12340   LEVEL 3")
			t.expect(o.prompt).toBe("RETURNING TO THE LOBBY...")
			t.expect(o.tap).toBe(false)
			t.expect(o.cursor).toBe(true)
		end
	)

	it("after a failed trip the prompt says to try again, and a tap waits for the cool-down", function()
		local o = Flow.overlay(play(OVER), RULES, trip("cooling", true))
		t.expect(o.banner).toBe("GAME OVER")
		t.expect(o.prompt).toBe("Could not return. Try again in a moment.")
		t.expect(o.tap).toBe(false)
		t.expect(o.cursor).toBe(true)
	end)

	it("with no lobby set up the prompt says so in every trip phase, and a tap never asks", function()
		for _, phase in PHASES do
			local o = Flow.overlay(play(OVER), RULES, trip(phase, false))
			t.expect(o.banner).toBe("GAME OVER")
			t.expect(o.prompt).toBe("The lobby is not set up yet.")
			t.expect(o.tap).toBe(false)
			t.expect(o.cursor).toBe(true)
		end
	end)

	it(
		"only game over has a prompt, asks on a tap or frees the mouse, whatever the server reported",
		function()
			for _, phase in { "ready", "playing", "dying", "levelclear" } do
				for _, report in
					{ trip("idle", true), trip("going", true), trip("cooling", true), trip("idle", false) }
				do
					local o = Flow.overlay(play({ phase = phase, timer = 10 }), RULES, report)
					t.expect(o.prompt).toBe(nil)
					t.expect(o.tap).toBe(false)
					t.expect(o.cursor).toBe(false)
				end
				local o = Flow.overlay(play({ phase = phase, timer = 10 }), RULES)
				t.expect(o.prompt).toBe(nil)
				t.expect(o.tap).toBe(false)
				t.expect(o.cursor).toBe(false)
			end
		end
	)

	it("a ready pause and play show exactly what they did, with no prompt", function()
		t.expect(Flow.overlay(play({ phase = "ready", timer = 30, level = 2 }), RULES, trip("idle", true)))
			.toEqual({
				banner = "READY!",
				detail = "LEVEL 2",
				fade = 0,
				flash = false,
				tap = false,
				cursor = false,
			})
		t.expect(Flow.overlay(play({ phase = "playing", score = 990 }), RULES, trip("idle", true))).toEqual({
			fade = 0,
			flash = false,
			tap = false,
			cursor = false,
		})
	end)

	it("no prompt mentions playing again", function()
		for _, text in { Flow.PROMPT.idle, Flow.PROMPT.going, Flow.PROMPT.cooling, Flow.PROMPT.unset } do
			t.expect((string.find(string.upper(text), "PLAY", 1, true))).toBe(nil)
		end
	end)

	it("leaves the record and the report unchanged", function()
		local p = play(OVER)
		local report = trip("cooling", true)
		local before, reported = table.clone(p), table.clone(report)
		Flow.overlay(p, RULES, report)
		t.expect(p).toEqual(before)
		t.expect(report).toEqual(reported)
	end)
end)
