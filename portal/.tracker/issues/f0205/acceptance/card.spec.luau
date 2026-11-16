--!strict
-- f0205 AC2: what a card shows (Logic/Card). The price badge is nothing until the title's state is known, the `soon`
-- word (COMING SOON) when its place is not published, the `free` word (FREE GAME READY) when its free start is due, and
-- otherwise the sale: the arcade's Prices words, "5 R$" struck through (rich text, escaped), then "1 R$ SALE". Every
-- word comes from the tables it is given. The server's states carry, by title, whether the place is published and
-- whether the free start is due; the client's read of them keeps only what makes sense. A read's answer folds into
-- what the server knows: a record gives the state, a first busy answer keeps it and reads again after the busy wait, a
-- failure is the sale, read again after the down wait, doubling to the most. Asks closer than ASK_GAP are answered
-- together. The card's regions run top to bottom without overlapping, with room kept for the play buttons and the
-- boards; every text on the front card is at least MIN_TEXT pixels on every screen the carousel fits; the preview
-- turns at SPIN and its camera frames every part.
local Card = require("@logic/Card")
local Carousel = require("@logic/Carousel")
local Games = require("@shared/Games")
local Prices = require("@arcade/Prices")
local t = require("@tests/lib/t")

local function entry(name: string, place: string): Card.Entry
	return { name = name, place = place, title = string.upper(name), tagline = "x", preview = {} }
end

local ENTRIES = { entry("pickman", "Pickman"), entry("snake", "Snake"), entry("invaders", "Invaders") }
local OTHER: Card.Prices = { struck = "9 X", price = "2 X", sale = "DEAL" }
local W = Card.WORDS
local ODD: Card.Words = { free = "GO!", soon = "LATER" } -- words no card holds
local WAITS: Card.Waits = { busy = 7, down = 11, most = 50 }
local SCREENS =
	{ { 1920, 1080 }, { 1280, 720 }, { 1024, 768 }, { 844, 390 }, { 390, 844 }, { 320, 480 }, { 2560, 1080 } }

local function check(b: Card.Badge, kind: string, struck: string, text: string)
	t.expect(b.kind).toBe(kind)
	t.expect(b.struck).toBe(struck)
	t.expect(b.text).toBe(text)
end

-- the state named `name`, which must be there (a missing one fails on an assertion, not an index error)
local function of(states: { [string]: Card.State }, name: string): Card.State
	t.expect(states[name] ~= nil).toBe(true)
	return states[name]
end

return t.spec("f0205 card", function(it)
	it("the badge's sale text is the arcade's Prices: 5 R$ struck through, then 1 R$ SALE", function()
		check(Card.badge({ published = true, free = false }, Prices, W), "sale", "<s>5 R$</s>", "1 R$ SALE")
	end)

	it("the sale's words come from the table it is given, never from the card", function()
		check(Card.badge({ published = true, free = false }, OTHER, W), "sale", "<s>9 X</s>", "2 X DEAL")
	end)

	it("a title whose free start is due shows FREE GAME READY, with nothing struck", function()
		t.expect(W.free).toBe("FREE GAME READY")
		check(Card.badge({ published = true, free = true }, Prices, W), "free", "", "FREE GAME READY")
		check(Card.badge({ published = true, free = true }, OTHER, W), "free", "", "FREE GAME READY")
	end)

	it("a title whose place is not published shows COMING SOON, whatever its free state says", function()
		t.expect(W.soon).toBe("COMING SOON")
		for _, free in { true, false } :: { boolean? } do
			check(Card.badge({ published = false, free = free }, Prices, W), "soon", "", "COMING SOON")
		end
		check(Card.badge({ published = false }, Prices, W), "soon", "", "COMING SOON")
	end)

	it("a title whose state is not known yet shows nothing: no price and no promise", function()
		check(Card.badge(nil, Prices, W), "none", "", "")
		check(Card.badge({ published = true }, Prices, W), "none", "", "")
	end)

	it("the badge's own words come from the table it is given, never from the card", function()
		check(Card.badge({ published = true, free = true }, Prices, ODD), "free", "", "GO!")
		check(Card.badge({ published = false }, Prices, ODD), "soon", "", "LATER")
		t.expect(table.isfrozen(Card.WORDS)).toBe(true)
	end)

	it("the struck price is rich text, its own markup characters escaped", function()
		t.expect(Card.strike("5 R$")).toBe("<s>5 R$</s>")
		t.expect(Card.strike("<b>&</b>")).toBe("<s>&lt;b&gt;&amp;&lt;/b&gt;</s>")
		local odd: Card.Prices = { struck = "<5>", price = "1", sale = "&" }
		check(Card.badge({ published = true, free = false }, odd, W), "sale", "<s>&lt;5&gt;</s>", "1 &")
	end)

	it("a title is published when its place has an id in Places.read's answer", function()
		local pickman, snake = ENTRIES[1], ENTRIES[2]
		t.expect(Card.published(pickman, { Pickman = 77 })).toBe(true)
		t.expect(Card.published(snake, { Pickman = 77 })).toBe(false)
		t.expect(Card.published(snake, {})).toBe(false)
		t.expect(Card.published(snake, { snake = 5, SnakePlaceId = 5 } :: any)).toBe(false)
	end)

	it(
		"the server's states: each title by name, published or not, and its free state where it is published",
		function()
			local s = Card.states(
				ENTRIES,
				{ pickman = true, snake = true, invaders = false },
				{ pickman = true, snake = false, invaders = true }
			)
			t.expect(of(s, "pickman").published).toBe(true)
			t.expect(of(s, "pickman").free).toBe(true)
			t.expect(of(s, "snake").published).toBe(true)
			t.expect(of(s, "snake").free).toBe(false)
			t.expect(of(s, "invaders").published).toBe(false)
			t.expect(of(s, "invaders").free).toBe(nil)
		end
	)

	it(
		"a published title not read yet has no free state, and a title missing from published is not published",
		function()
			local s = Card.states(ENTRIES, { pickman = true }, nil)
			t.expect(of(s, "pickman").published).toBe(true)
			t.expect(of(s, "pickman").free).toBe(nil)
			t.expect(of(s, "snake").published).toBe(false)
			t.expect(of(s, "invaders").published).toBe(false)
			local only = Card.states(ENTRIES, { pickman = true, snake = true }, { snake = true })
			t.expect(of(only, "pickman").free).toBe(nil)
			t.expect(of(only, "snake").free).toBe(true)
		end
	)

	it("the server's states carry every title given, and only those", function()
		local s = Card.states(ENTRIES, { pickman = true, ghost = true }, { ghost = true })
		local names = {}
		for name in s do
			table.insert(names, name)
		end
		table.sort(names)
		t.expect(table.concat(names, " ")).toBe("invaders pickman snake")
	end)

	it("the client reads back what the server sent", function()
		local sent = Card.states(ENTRIES, { pickman = true, snake = true }, { pickman = true, snake = false })
		local s = Card.parse(sent, ENTRIES)
		t.expect(of(s, "pickman").published).toBe(true)
		t.expect(of(s, "pickman").free).toBe(true)
		t.expect(of(s, "snake").published).toBe(true)
		t.expect(of(s, "snake").free).toBe(false)
		t.expect(of(s, "invaders").published).toBe(false)
		t.expect(of(s, "invaders").free).toBe(nil)
	end)

	it(
		"the client drops a state that makes no sense, title by title, and any title it does not know",
		function()
			local s = Card.parse({
				pickman = { published = "yes", free = true },
				snake = { published = true, free = "no" },
				invaders = 5,
				ghost = { published = true, free = true },
			}, ENTRIES)
			t.expect(s.pickman).toBe(nil)
			t.expect(s.snake).toBe(nil)
			t.expect(s.invaders).toBe(nil)
			t.expect((s :: any).ghost).toBe(nil)
			for _, bad in { nil, 5, "x", true } :: { any } do
				local ok, parsed = pcall(Card.parse, bad, ENTRIES)
				t.expect(ok).toBe(true)
				t.expect(ok and next(parsed)).toBe(nil)
			end
		end
	)

	it("the client keeps no free state for a place that is not published", function()
		local s = Card.parse({ snake = { published = false, free = true } }, ENTRIES)
		t.expect(of(s, "snake").published).toBe(false)
		t.expect(of(s, "snake").free).toBe(nil)
	end)

	it("the card's regions run top to bottom inside it, without overlapping", function()
		t.expect(table.concat(Card.ORDER, " ")).toBe("Title Tagline Preview Badge Buttons Boards")
		local bottom = 0
		for _, name in Card.ORDER do
			local r = Card.REGIONS[name]
			t.expect(r ~= nil).toBe(true)
			t.expect(r.height > 0).toBe(true)
			t.expect(r.top >= bottom - 1e-9).toBe(true)
			bottom = r.top + r.height
		end
		t.expect(bottom <= 1 + 1e-9).toBe(true)
	end)

	it(
		"the preview and the boards have the most room: the preview at least a fifth, the boards at least a quarter",
		function()
			t.expect(Card.REGIONS.Preview.height >= 0.2).toBe(true)
			t.expect(Card.REGIONS.Boards.height >= 0.25).toBe(true)
			t.expect(Card.REGIONS.Buttons.height > 0).toBe(true)
		end
	)

	it("the preview turns at SPIN radians a second, from 0 up to a full turn", function()
		t.expect(Card.angle(0)).toBe(0)
		t.expect(Card.angle(2)).toBeNear(2 * Card.SPIN, 1e-12)
		local full = 2 * math.pi / Card.SPIN
		t.expect(Card.angle(full + 1)).toBeNear(Card.SPIN, 1e-9)
		for _, s in { 0.5, 10, 1000, 123456.789 } do
			local a = Card.angle(s)
			t.expect(a >= 0 and a < 2 * math.pi).toBe(true)
		end
		t.expect(Card.SPIN > 0 and Card.SPIN <= 2).toBe(true)
	end)

	it("a time that is not a finite number turns the preview to 0", function()
		for _, bad in { 0 / 0, math.huge, -math.huge } do
			t.expect(Card.angle(bad)).toBe(0)
		end
	end)

	it("the preview camera frames a whole FRAME cube turning about its centre", function()
		local cam = Card.CAMERA
		local reach = Card.FRAME * math.sqrt(3) -- the furthest corner of the cube, from its centre
		local away = math.sqrt(cam.distance ^ 2 + cam.height ^ 2)
		t.expect(away * math.sin(math.rad(cam.fov / 2)) >= reach).toBe(true)
		t.expect(away > reach).toBe(true)
		t.expect(cam.fov > 0 and cam.fov < 90).toBe(true)
	end)

	it("its constants are frozen", function()
		t.expect(table.isfrozen(Card.REGIONS)).toBe(true)
		t.expect(table.isfrozen(Card.ORDER)).toBe(true)
		t.expect(table.isfrozen(Card.CAMERA)).toBe(true)
		t.expect(table.concat(Card.SHAPES, " ")).toBe("Ball Block Cylinder")
	end)
	it(
		"a read that gave a record sets the free state and reads no more, forgetting earlier failures",
		function()
			local r, delay = Card.answer(nil, true, nil, WAITS)
			t.expect(r.free).toBe(true)
			t.expect(delay).toBe(nil)
			local failed = Card.answer(Card.answer(nil, nil, "down", WAITS), nil, "down", WAITS)
			local back, again = Card.answer(failed, false, nil, WAITS)
			t.expect(back.free).toBe(false)
			t.expect(back.down).toBe(0)
			t.expect(back.busy).toBe(0)
			t.expect(again).toBe(nil)
			-- after a record, the next failure starts the back-off again from the first wait
			local _, first = Card.answer(back, nil, "down", WAITS)
			t.expect(first).toBe(11)
		end
	)

	it("a first busy answer keeps what was known and reads again after the busy wait", function()
		local known = Card.answer(nil, true, nil, WAITS)
		local r, delay = Card.answer(known, nil, "busy", WAITS)
		t.expect(r.free).toBe(true)
		t.expect(delay).toBe(7)
		local unknown, d2 = Card.answer(nil, nil, "busy", WAITS)
		t.expect(unknown.free).toBe(nil)
		t.expect(d2).toBe(7)
	end)

	it("a second busy answer in a row is a failure: the sale, and the down wait", function()
		local r = Card.answer(Card.answer(nil, true, nil, WAITS), nil, "busy", WAITS)
		local again, delay = Card.answer(r, nil, "busy", WAITS)
		t.expect(again.free).toBe(false)
		t.expect(delay).toBe(11)
	end)

	it("a failed read is the sale, read again after the down wait, doubling to the most", function()
		local r: Card.Read? = Card.answer(nil, true, nil, WAITS)
		local delays = {}
		for _ = 1, 6 do
			local after, delay = Card.answer(r, nil, "down", WAITS)
			t.expect(after.free).toBe(false)
			table.insert(delays, delay)
			r = after
		end
		t.expect(table.concat(delays, " ")).toBe("11 22 44 50 50 50")
		local _, none = Card.answer(nil, nil, nil, WAITS) -- no record and no reason counts as down
		t.expect(none).toBe(11)
	end)

	it("an answer never changes the record it is given", function()
		local r = Card.answer(nil, true, nil, WAITS)
		Card.answer(r, nil, "down", WAITS)
		Card.answer(r, nil, "busy", WAITS)
		t.expect(r.free).toBe(true)
		t.expect(r.down).toBe(0)
		t.expect(r.busy).toBe(0)
	end)

	it(
		"asks closer than ASK_GAP are answered at the gap's end; the first, and one after the gap, at once",
		function()
			t.expect(Card.ASK_GAP).toBe(1)
			t.expect(Card.asked(nil, 10)).toBe(nil)
			t.expect(Card.asked(10, 10.25)).toBe(0.75)
			t.expect(Card.asked(10, 10)).toBe(1)
			t.expect(Card.asked(10, 11)).toBe(nil)
			t.expect(Card.asked(10, 12.5)).toBe(nil)
			t.expect(Card.asked(10, 9)).toBe(nil) -- a clock that went back
		end
	)

	it(
		"every text on the front card is at least MIN_TEXT pixels on every screen the carousel fits",
		function()
			t.expect(Card.MIN_TEXT >= 12).toBe(true)
			local inner = 1 - 2 * Card.INSET
			for _, sc in SCREENS do
				local box = Carousel.box(0, sc[1], sc[2])
				local w, h = box.width * inner, box.height
				local function size(text: string, region: string, share: number, wrap: boolean): number
					return Card.textSize(text, w * share, h * Card.REGIONS[region].height, wrap)
				end
				local texts: { { text: string, size: number } } = {}
				for _, e in Games.LIST do
					table.insert(texts, { text = e.title, size = size(e.title, "Title", 1, false) })
					table.insert(texts, { text = e.tagline, size = size(e.tagline, "Tagline", 1, true) })
				end
				table.insert(
					texts,
					{ text = Prices.struck, size = size(Prices.struck, "Badge", Card.BADGE.struck, false) }
				)
				local offers = { `{Prices.price} {Prices.sale}`, W.free, W.soon }
				for _, text in offers do
					table.insert(texts, { text = text, size = size(text, "Badge", Card.BADGE.offer, false) })
				end
				for _, x in texts do
					if x.size < Card.MIN_TEXT then
						error(
							`expected "{x.text}" at least {Card.MIN_TEXT} px on {sc[1]}x{sc[2]}, got {x.size}`
						)
					end
				end
			end
		end
	)

	it(
		"the text model: one line fills the height or the width; wrapping finds the best of up to four lines",
		function()
			t.expect(Card.textSize("ABCD", 1000, 20, false)).toBe(20)
			t.expect(Card.textSize("ABCDEFGHIJ", 65, 100, false)).toBeNear(10, 1e-9)
			-- 20 glyphs in 130 x 40: one line 10 px, two lines 20 px
			t.expect(Card.textSize(string.rep("A", 20), 130, 40, true)).toBeNear(20, 1e-9)
			t.expect(Card.textSize(string.rep("A", 20), 130, 40, false)).toBeNear(10, 1e-9)
			t.expect(Card.GLYPH).toBe(0.65)
		end
	)

	it("the badge's two labels share its width without overlapping", function()
		local b = Card.BADGE
		t.expect(b.struck > 0 and b.offer > 0 and b.gap >= 0).toBe(true)
		t.expect(b.struck + b.gap + b.offer <= 1 + 1e-9).toBe(true)
		t.expect(Card.INSET >= 0 and Card.INSET < 0.25).toBe(true)
	end)
end)
