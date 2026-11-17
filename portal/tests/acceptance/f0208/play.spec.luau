--!strict
-- f0208 AC1: what a play button does and shows (Logic/Play) and each title's buttons (Modes). The server's decision
-- from a read of the player's record: a free start due or a held play goes, in every mode; a failed read goes on the
-- portal's pass, in every mode; a busy one reads again; with nothing held a title in closed mode cannot sell, else
-- the player buys. A client's intent and the server's status are checked field by field and never raise. Each card
-- shows one button per mode with its price ("FREE", or 5 R$ struck through then 1 R$, from the arcade's Prices), a
-- note for the player's own play of that title (the buttons then show their names only), CANCEL and INVITE FRIEND while
-- waiting; every text at least Card.MIN_TEXT px on every screen; the keys sit above the default controls, below the test
-- purchase screen and clear of the carousel's.
local Card = require("@logic/Card")
local Carousel = require("@logic/Carousel")
local Games = require("@shared/Games")
local Modes = require("@shared/Modes")
local Play = require("@logic/Play")
local Prices = require("@arcade/Prices")
local t = require("@tests/lib/t")

local SALE = "<s>5 R$</s> 1 R$"
local SCREENS =
	{ { 1920, 1080 }, { 1280, 720 }, { 1024, 768 }, { 844, 390 }, { 390, 844 }, { 320, 480 }, { 2560, 1080 } }

local function kinds(view: any): { string }
	local out = {}
	for _, b in view.buttons do
		table.insert(out, b.kind)
	end
	return out
end

local function shape(view: any): { string }
	local out = {}
	for _, b in view.buttons do
		table.insert(out, `{b.kind}|{b.text}|{b.price}|{tostring(b.enabled)}`)
	end
	return out
end

return t.spec("f0208 Play", function(it)
	it("a free start due goes at once, in every mode, closed included", function()
		for _, mode in { "live", "test", "closed" } do
			t.expect(Play.decide({ free = true, plays = 0 }, nil, mode, 0)).toBe("go")
		end
	end)

	it("a held play goes at once, in every mode, closed included", function()
		for _, mode in { "live", "test", "closed" } do
			t.expect(Play.decide({ free = false, plays = 1 }, nil, mode, 0)).toBe("go")
			t.expect(Play.decide({ free = false, plays = 3 }, nil, mode, 0)).toBe("go")
		end
	end)

	it(
		"with no free start due and nothing held the player buys; in closed mode the store is unavailable",
		function()
			t.expect(Play.decide({ free = false, plays = 0 }, nil, "live", 0)).toBe("buy")
			t.expect(Play.decide({ free = false, plays = 0 }, nil, "test", 0)).toBe("buy")
			t.expect(Play.decide({ free = false, plays = 0 }, nil, "closed", 0)).toBe("closed")
		end
	)

	it("a read that failed goes on the portal's pass, in every mode; a busy read reads again", function()
		for _, mode in { "live", "test", "closed" } do
			t.expect(Play.decide(nil, "down", mode, 0)).toBe("pass")
			t.expect(Play.decide(nil, "busy", mode, 0)).toBe("busy")
		end
		t.expect(Play.decide(nil, nil, "live", 0)).toBe("pass")
	end)

	it(
		"a read still busy after CHECK_SECONDS of checking is a slow store: it goes on the pass, in every mode",
		function()
			t.expect(Play.CHECK_SECONDS > 5).toBe(true) -- more than the Wallet's WAIT_SECONDS, so the late read allows a pass
			for _, mode in { "live", "test", "closed" } do
				t.expect(Play.decide(nil, "busy", mode, Play.CHECK_SECONDS - 0.01)).toBe("busy")
				t.expect(Play.decide(nil, "busy", mode, Play.CHECK_SECONDS)).toBe("pass")
			end
			t.expect(Play.decide({ free = false, plays = 0 }, nil, "live", 60)).toBe("buy")
		end
	)

	it("a client's play names a title and one of that title's modes", function()
		t.expect(Play.intent("play", "invaders", "pair", Modes))
			.toEqual({ action = "play", name = "invaders", mode = "pair" })
		t.expect(Play.intent("play", "snake", "arena", Modes))
			.toEqual({ action = "play", name = "snake", mode = "arena" })
		t.expect(Play.intent("play", "pickman", "solo", Modes))
			.toEqual({ action = "play", name = "pickman", mode = "solo" })
		t.expect(Play.intent("play", "pickman", "arena", Modes)).toBe(nil)
		t.expect(Play.intent("play", "snake", "pair", Modes)).toBe(nil)
		t.expect(Play.intent("play", "tetris", "solo", Modes)).toBe(nil)
		t.expect(Play.intent("play", "invaders", "duo", Modes)).toBe(nil)
		t.expect(Play.intent("play", 7, "solo", Modes)).toBe(nil)
		t.expect(Play.intent("play", nil, nil, Modes)).toBe(nil)
		t.expect(Play.intent("buy", "pickman", "solo", Modes)).toBe(nil)
		t.expect(Play.intent({}, "pickman", "solo", Modes)).toBe(nil)
	end)

	it("cancel and invite carry nothing else, whatever the client adds", function()
		t.expect(Play.intent("cancel", "pickman", "solo", Modes)).toEqual({ action = "cancel" })
		t.expect(Play.intent("invite", { x = 1 }, 3, Modes)).toEqual({ action = "invite" })
	end)

	it("the client reads the server's status field by field, never raising", function()
		t.expect(Play.parse({ phase = "waiting", name = "invaders", mode = "pair" }, Modes))
			.toEqual({ phase = "waiting", name = "invaders", mode = "pair" })
		t.expect(Play.parse({ phase = "idle" }, Modes)).toEqual({ phase = "idle" })
		for _, phase in Play.PHASES do
			t.expect(Play.parse({ phase = phase, name = "pickman", mode = "solo" }, Modes) ~= nil).toBe(true)
		end
		t.expect(Play.parse({ phase = "flying", name = "pickman", mode = "solo" }, Modes)).toBe(nil)
		t.expect(Play.parse({ phase = "going", name = "pickman" }, Modes)).toBe(nil)
		t.expect(Play.parse({ phase = "going", name = "pickman", mode = "pair" }, Modes)).toBe(nil)
		t.expect(Play.parse({ phase = "going", name = 3, mode = "solo" }, Modes)).toBe(nil)
		t.expect(Play.parse("going", Modes)).toBe(nil)
		t.expect(Play.parse(nil, Modes)).toBe(nil)
	end)

	it("the phases are the seven a play passes through", function()
		t.expect(Play.PHASES)
			.toEqual({ "idle", "checking", "buying", "waiting", "going", "closed", "failed" })
	end)

	it(
		"a play's price is FREE when the free start is due, else 5 R$ struck through and 1 R$, from Prices",
		function()
			t.expect(Play.price({ published = true, free = true }, Prices)).toBe("FREE")
			t.expect(Play.price({ published = true, free = false }, Prices)).toBe(SALE)
			t.expect(
				Play.price({ published = true, free = false }, { struck = "9 X", price = "2 X", sale = "S" })
			)
				.toBe(`{Card.strike("9 X")} 2 X`)
			t.expect(Play.price({ published = true }, Prices)).toBe("")
			t.expect(Play.price(nil, Prices)).toBe("")
		end
	)

	it(
		"a card shows one button per mode, each with its label and the price, enabled once the state is known",
		function()
			local free = Play.view("snake", Modes.snake, { published = true, free = true }, nil, 0, Prices)
			t.expect(shape(free)).toEqual({ "solo|PLAY|FREE|true", "arena|ARENA|FREE|true" })
			t.expect(free.note).toBe("")
			local sale =
				Play.view("invaders", Modes.invaders, { published = true, free = false }, nil, 0, Prices)
			t.expect(shape(sale)).toEqual({ `solo|PLAY|{SALE}|true`, `pair|2 PLAYERS|{SALE}|true` })
			local pickman =
				Play.view("pickman", Modes.pickman, { published = true, free = false }, nil, 0, Prices)
			t.expect(shape(pickman)).toEqual({ `solo|PLAY|{SALE}|true` })
		end
	)

	it(
		"a card whose state is not known shows its buttons disabled, with no price; one not published shows none",
		function()
			local unknown = Play.view("snake", Modes.snake, nil, nil, 0, Prices)
			t.expect(shape(unknown)).toEqual({ "solo|PLAY||false", "arena|ARENA||false" })
			local unread = Play.view("snake", Modes.snake, { published = true }, nil, 0, Prices)
			t.expect(shape(unread)).toEqual({ "solo|PLAY||false", "arena|ARENA||false" })
			local soon = Play.view("snake", Modes.snake, { published = false }, nil, 0, Prices)
			t.expect(#soon.buttons).toBe(0)
			t.expect(soon.note).toBe("")
		end
	)

	it(
		"while the player's play of a title is checked, bought or starting, its card shows only the note",
		function()
			local state = { published = true, free = false }
			for phase, note in
				{ checking = "CHECKING...", buying = "COMPLETE THE PURCHASE", going = "STARTING..." }
			do
				local v = Play.view(
					"snake",
					Modes.snake,
					state,
					{ phase = phase :: any, name = "snake", mode = "arena" },
					0,
					Prices
				)
				t.expect(#v.buttons).toBe(0)
				t.expect(v.note).toBe(note)
			end
		end
	)

	it("a 2 PLAYERS wait shows WAITING FOR A SECOND PLAYER with CANCEL and INVITE FRIEND", function()
		local v = Play.view(
			"invaders",
			Modes.invaders,
			{ published = true, free = false },
			{ phase = "waiting", name = "invaders", mode = "pair" },
			1,
			Prices
		)
		t.expect(v.note).toBe("WAITING FOR A SECOND PLAYER")
		t.expect(shape(v)).toEqual({ "cancel|CANCEL||true", "invite|INVITE FRIEND||true" })
	end)

	it("a play that could not start, or a closed store, shows its note above the buttons", function()
		local state = { published = true, free = false }
		local failed = Play.view(
			"pickman",
			Modes.pickman,
			state,
			{ phase = "failed", name = "pickman", mode = "solo" },
			0,
			Prices
		)
		t.expect(failed.note).toBe("COULD NOT START. TRY AGAIN.")
		t.expect(shape(failed)).toEqual({ "solo|PLAY||false" }) -- resting: its cool-down
		local closed = Play.view(
			"pickman",
			Modes.pickman,
			state,
			{ phase = "closed", name = "pickman", mode = "solo" },
			0,
			Prices
		)
		t.expect(closed.note).toBe("STORE UNAVAILABLE")
		t.expect(shape(closed)).toEqual({ "solo|PLAY||true" })
	end)

	it("the player's play of one title leaves every other card as it is", function()
		local state = { published = true, free = true }
		local status = { phase = "waiting" :: any, name = "invaders", mode = "pair" :: any }
		local other = Play.view("asteroids", Modes.asteroids, state, status, 0, Prices)
		t.expect(shape(other)).toEqual(shape(Play.view("asteroids", Modes.asteroids, state, nil, 0, Prices)))
		t.expect(other.note).toBe("")
		local idle = Play.view("invaders", Modes.invaders, state, { phase = "idle" }, 0, Prices)
		t.expect(kinds(idle)).toEqual({ "solo", "pair" })
	end)

	it("another player waiting on a 2 PLAYERS card says so; a card without 2 PLAYERS says nothing", function()
		local state = { published = true, free = false }
		local other = Play.view("invaders", Modes.invaders, state, nil, 1, Prices)
		t.expect(other.note).toBe("A PLAYER IS WAITING")
		t.expect(shape(other)).toEqual({ "solo|PLAY||true", "pair|2 PLAYERS||true" })
		t.expect(Play.view("invaders", Modes.invaders, state, nil, 0, Prices).note).toBe("")
		t.expect(Play.view("snake", Modes.snake, state, nil, 1, Prices).note).toBe("")
	end)

	it(
		"the buttons sit side by side across the slot with a gap: full height, or the bottom half under a note",
		function()
			t.expect(Play.slots(1, false)).toEqual({ { x = 0, y = 0, width = 1, height = 1 } })
			local two = Play.slots(2, false)
			t.expect(two[1].x).toBe(0)
			t.expect(two[2].x + two[2].width).toBeNear(1, 1e-9)
			t.expect(two[2].x - (two[1].x + two[1].width)).toBeNear(Play.GAP, 1e-9)
			t.expect(two[1].width).toBeNear(two[2].width, 1e-9)
			t.expect(two[2].y).toBe(0)
			t.expect(two[2].height).toBe(1)
			local noted = Play.slots(2, true)
			for i = 1, 2 do
				t.expect(noted[i].x).toBeNear(two[i].x, 1e-9)
				t.expect(noted[i].width).toBeNear(two[i].width, 1e-9)
				t.expect(noted[i].y).toBe(0.5)
				t.expect(noted[i].height).toBe(0.5)
			end
			t.expect(#Play.slots(0, false)).toBe(0)
		end
	)

	it("the note takes the whole slot alone, else its top half", function()
		t.expect(Play.noteBox(0)).toEqual({ x = 0, y = 0, width = 1, height = 1 })
		t.expect(Play.noteBox(2)).toEqual({ x = 0, y = 0, width = 1, height = 0.5 })
	end)

	it("every play text on the front card is at least Card.MIN_TEXT px on every screen", function()
		local states: { any } =
			{ { published = true, free = true }, { published = true, free = false }, { published = true } }
		local statuses: { any } = { false }
		for _, phase in Play.PHASES do
			for _, mode in Play.MODES do
				table.insert(statuses, { phase = phase, mode = mode })
			end
		end
		local smallest, where = math.huge, ""
		for _, sc in SCREENS do
			local box = Carousel.box(0, sc[1], sc[2])
			local width = box.width * (1 - 2 * Card.INSET)
			local height = box.height * Card.REGIONS.Buttons.height
			for _, entry in Games.LIST do
				for _, state in states do
					for _, st in statuses do
						for others = 0, 1 do
							local status = if st
								then { phase = st.phase, name = entry.name, mode = st.mode }
								else nil
							local v = Play.view(entry.name, Modes[entry.name], state, status, others, Prices)
							local function at(size: number, text: string)
								if size < smallest then
									smallest, where = size, `{text} on {sc[1]}x{sc[2]}`
								end
							end
							if v.note ~= "" then
								local nb = Play.noteBox(#v.buttons)
								at(Card.textSize(v.note, nb.width * width, nb.height * height, true), v.note)
							end
							local places = Play.slots(#v.buttons, v.note ~= "")
							for i, b in v.buttons do
								local lines = if b.price ~= "" then 2 else 1
								local bw, bh = places[i].width * width, places[i].height * height / lines
								at(Card.textSize(b.text, bw, bh, false), b.text)
								if b.price ~= "" then
									local shown = string.gsub(b.price, "<[^>]*>", "")
									at(Card.textSize(shown, bw, bh, false), shown)
								end
							end
						end
					end
				end
			end
		end
		t.expect(where ~= "" and smallest >= Card.MIN_TEXT).toBe(true)
	end)

	it(
		"the card's other keys: 2, keypad 2 and X the second button; Backspace and B cancel; I and Y invite",
		function()
			t.expect(Play.KEYS).toEqual({
				Two = "second",
				KeypadTwo = "second",
				ButtonX = "second",
				Backspace = "cancel",
				ButtonB = "cancel",
				I = "invite",
				ButtonY = "invite",
			})
			t.expect(Play.key("ButtonX")).toBe("second")
			t.expect(Play.key("Return")).toBe(nil)
			for key in Play.KEYS do
				t.expect(Carousel.KEYS[key]).toBe(nil)
			end
		end
	)

	it(
		"the keys are bound under one action, above the default controls and below the test purchase screen",
		function()
			t.expect(Play.ACTION).toBe("PortalPlay")
			t.expect(Play.PRIORITY > 2000).toBe(true) -- above Roblox's default controls
			t.expect(Play.PRIORITY < 3000).toBe(true)
			t.expect(Play.ACTION ~= Carousel.ACTION).toBe(true)
		end
	)

	it(
		"a player's MemoryStore writes: WRITES within WRITE_SPAN seconds, the oldest freeing a place as it ages out",
		function()
			local times = {}
			local ok
			for i = 1, Play.WRITES do
				ok, times = Play.spend(times, 100 + i)
				t.expect(ok).toBe(true)
			end
			local before = table.clone(times)
			ok, times = Play.spend(times, 100 + Play.WRITES + 1)
			t.expect(ok).toBe(false)
			t.expect(#times).toBe(Play.WRITES)
			t.expect(times).toEqual(before) -- a refused write is not counted
			ok = Play.spend(times, 101 + Play.WRITE_SPAN - 0.01)
			t.expect(ok).toBe(false)
			ok, times = Play.spend(times, 101 + Play.WRITE_SPAN)
			t.expect(ok).toBe(true)
			t.expect(#times).toBe(Play.WRITES)
		end
	)

	it("spending never changes the list it is given", function()
		local times = { 1, 2 }
		Play.spend(times, 3)
		Play.spend(times, 1000)
		t.expect(times).toEqual({ 1, 2 })
	end)

	it(
		"the card's keys are clear of the boards' tab keys (f0206: W, S, Up, Down, ButtonL2, ButtonR2)",
		function()
			for _, key in { "W", "S", "Up", "Down", "ButtonL2", "ButtonR2" } do
				t.expect(Play.KEYS[key]).toBe(nil)
			end
		end
	)

	it("a card's second button is its second mode", function()
		t.expect(Play.second(Modes.snake)).toBe("arena")
		t.expect(Play.second(Modes.invaders)).toBe("pair")
		t.expect(Play.second(Modes.pickman)).toBe(nil)
	end)

	it("an invited friend's launch data names the inviter by a whole positive id, else nothing", function()
		t.expect(Play.inviter("123456")).toBe(123456)
		for _, bad in { "0", "-5", "12a", "", " 7", "1e3", "0x10", "1234567890123456", "07" } do
			t.expect(Play.inviter(bad)).toBe(nil)
		end
		t.expect(Play.inviter(123 :: any)).toBe(nil)
		t.expect(Play.inviter(nil)).toBe(nil)
	end)

	it("an invite's record holds the inviting server's job and a title", function()
		t.expect(Play.invite({ job = "j-1", name = "invaders" }, Modes))
			.toEqual({ job = "j-1", name = "invaders" })
		t.expect(Play.invite({ job = "", name = "invaders" }, Modes)).toBe(nil)
		t.expect(Play.invite({ job = "j-1", name = "tetris" }, Modes)).toBe(nil)
		t.expect(Play.invite({ job = 5, name = "invaders" }, Modes)).toBe(nil)
		t.expect(Play.invite("j-1", Modes)).toBe(nil)
	end)

	it("the waits and bounds", function()
		t.expect(Play.BUSY_SECONDS).toBe(0.25)
		t.expect(Play.CHECK_SECONDS).toBe(10)
		t.expect(Play.RECEIPT_SECONDS).toBe(30)
		t.expect(Play.BUY_SECONDS).toBe(120)
		t.expect(Play.COOL_SECONDS).toBe(3)
		t.expect(Play.WRITE_SECONDS).toBe(5)
		t.expect(Play.WRITES).toBe(6)
		t.expect(Play.WRITE_SPAN).toBe(60)
		t.expect(Play.RETRY_SECONDS).toBe(1)
	end)

	it("Modes: PLAY on every title, ARENA on Snake, 2 PLAYERS on Invaders and Asteroids, frozen", function()
		t.expect(Modes.pickman).toEqual({ "solo" })
		t.expect(Modes.snake).toEqual({ "solo", "arena" })
		t.expect(Modes.invaders).toEqual({ "solo", "pair" })
		t.expect(Modes.asteroids).toEqual({ "solo", "pair" })
		t.expect(table.isfrozen(Modes)).toBe(true)
		local names = {}
		for name, list in Modes do
			table.insert(names, name)
			t.expect(table.isfrozen(list)).toBe(true)
		end
		table.sort(names)
		local games = {}
		for _, entry in Games.LIST do
			table.insert(games, entry.name)
		end
		table.sort(games)
		t.expect(names).toEqual(games)
	end)
end)
