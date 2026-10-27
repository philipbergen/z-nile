--!strict
-- f0145 AC4: what the screens say. During the offer Flow's overlay shows CONTINUE?, the score and level, "3 NEW LIVES"
-- and the whole seconds of real time left (rounded up), frees the cursor, asks for no tap and raises `offer` (so the
-- CONTINUE and END GAME buttons show). Flow.offerPrice says what a continue costs: a continue held, else the price,
-- and in test mode (or before the server has said anything) that nothing is charged. The lobby's line under START
-- GAME: a free start due, else the plays held, else the price and the minutes to the next free start, with the test
-- note in test mode; nothing before the server has said anything.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Lobby = require("@logic/Lobby")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local NOW = 1792108800

local function offerPlay(timer: number): Session.PlayFrame
	return { phase = "offer" :: any, level = 4, score = 12340, lives = 0, timer = timer, frightened = 0 }
end

return t.spec("f0145 the offer and the price on screen", function(it)
	it(
		"the offer's overlay: CONTINUE?, the results, three new lives and the seconds left; the buttons, no tap",
		function()
			local o = Flow.overlay(offerPlay(Game.OFFER_TICKS), Game.CLASSIC_CONFIG)
			t.expect(o.banner).toBe("CONTINUE?")
			t.expect(o.detail).toBe("SCORE 12340   LEVEL 4")
			t.expect(o.prompt).toBe(`3 NEW LIVES   {math.ceil(Game.OFFER_TICKS / Session.STEP_RATE)}`)
			t.expect(o.offer).toBe(true)
			t.expect(o.tap).toBe(false)
			t.expect(o.cursor).toBe(true)
			t.expect(o.fade).toBe(Flow.FADE_MAX)
			-- no other phase raises the offer
			for _, phase in { "ready", "playing", "dying", "levelclear", "gameover" } do
				local other = Flow.overlay(
					{ phase = phase :: any, level = 1, score = 0, lives = 1, timer = 10, frightened = 0 },
					Game.CLASSIC_CONFIG
				)
				t.expect(other.offer == true).toBe(false)
			end
		end
	)

	it("the seconds left are real seconds, rounded up, and never below zero", function()
		t.expect(Flow.offerSeconds(Session.STEP_RATE)).toBe(1)
		t.expect(Flow.offerSeconds(Session.STEP_RATE + 1)).toBe(2)
		t.expect(Flow.offerSeconds(1)).toBe(1)
		t.expect(Flow.offerSeconds(0)).toBe(0)
		t.expect(Flow.offerSeconds(-3)).toBe(0)
		t.expect(Flow.offerSeconds(0 / 0)).toBe(0)
	end)

	it(
		"the price under the buttons: a continue held, else 1 Robux; test mode and no report say nothing is charged",
		function()
			t.expect(Flow.offerPrice({ mode = "live", held = 0 })).toBe(Flow.OFFER.price)
			t.expect(Flow.offerPrice({ mode = "live", held = 2 })).toBe(Flow.OFFER.held)
			t.expect(Flow.offerPrice({ mode = "test", held = 0 })).toBe(Flow.OFFER.test)
			t.expect(Flow.offerPrice(nil)).toBe(Flow.OFFER.test)
			t.expect(string.find(Flow.OFFER.price, "1 ROBUX", 1, true) ~= nil).toBe(true)
			t.expect(string.find(Flow.OFFER.test, "NOTHING IS CHARGED", 1, true) ~= nil).toBe(true)
			t.expect(Flow.OFFER.buy).toBe("CONTINUE")
			t.expect(Flow.OFFER.no).toBe("END GAME")
		end
	)

	it(
		"the lobby's line: free, else what is held, else the price and the minutes to the next free start",
		function()
			t.expect(Lobby.payLine(nil, "live", NOW)).toBe(nil)
			t.expect(Lobby.payLine({ free = true, plays = 0, continues = 0 }, "live", NOW)).toBe("FREE GAME")
			t.expect(Lobby.payLine({ free = true, plays = 2, continues = 0 }, "live", NOW)).toBe("FREE GAME") -- used first
			t.expect(Lobby.payLine({ free = false, plays = 1, continues = 0 }, "live", NOW))
				.toBe("1 GAME YOU BOUGHT")
			t.expect(Lobby.payLine({ free = false, plays = 3, continues = 0 }, "live", NOW))
				.toBe("3 GAMES YOU BOUGHT")
			t.expect(
				Lobby.payLine(
					{ free = false, nextFree = NOW + 41 * 60 + 5, plays = 0, continues = 0 },
					"live",
					NOW
				)
			).toBe("1 ROBUX A GAME, NEXT FREE GAME IN 42 MIN")
			t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, "live", NOW))
				.toBe("1 ROBUX A GAME")
		end
	)

	it("in test mode the lobby's line says nothing is charged", function()
		t.expect(Lobby.payLine({ free = true, plays = 0, continues = 0 }, "test", NOW))
			.toBe("FREE GAME (TEST: NOTHING IS CHARGED)")
		t.expect(Lobby.payLine({ free = false, plays = 0, continues = 0 }, nil, NOW))
			.toBe("1 ROBUX A GAME (TEST: NOTHING IS CHARGED)")
	end)
end)
