--!strict
-- f0205 AC2: what a card shows (Logic/Card). The price badge is nothing until the title's state is known, COMING SOON
-- when its place is not published, FREE GAME READY when its free start is due, and otherwise the sale: the arcade's
-- Prices words, "5 R$" struck through (rich text, escaped), then "1 R$ SALE". The words come from the Prices table it
-- is given, the one config table of the badge's sale text. The server's states carry, by title, whether the place is
-- published and whether the free start is due; the client's read of them keeps only what makes sense. The card's
-- regions run top to bottom without overlapping, with room kept for the play buttons and the boards; the preview turns
-- at SPIN and its camera frames every part.
local Card = require("@logic/Card")
local Prices = require("@arcade/Prices")
local t = require("@tests/lib/t")

local function entry(name: string, place: string): Card.Entry
	return { name = name, place = place, title = string.upper(name), tagline = "x", preview = {} }
end

local ENTRIES = { entry("pickman", "Pickman"), entry("snake", "Snake"), entry("invaders", "Invaders") }
local OTHER: Card.Prices = { struck = "9 X", price = "2 X", sale = "DEAL" }

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
		check(Card.badge({ published = true, free = false }, Prices), "sale", "<s>5 R$</s>", "1 R$ SALE")
	end)

	it("the sale's words come from the table it is given, never from the card", function()
		check(Card.badge({ published = true, free = false }, OTHER), "sale", "<s>9 X</s>", "2 X DEAL")
	end)

	it("a title whose free start is due shows FREE GAME READY, with nothing struck", function()
		t.expect(Card.FREE).toBe("FREE GAME READY")
		check(Card.badge({ published = true, free = true }, Prices), "free", "", "FREE GAME READY")
		check(Card.badge({ published = true, free = true }, OTHER), "free", "", "FREE GAME READY")
	end)

	it("a title whose place is not published shows COMING SOON, whatever its free state says", function()
		t.expect(Card.SOON).toBe("COMING SOON")
		for _, free in { true, false } :: { boolean? } do
			check(Card.badge({ published = false, free = free }, Prices), "soon", "", "COMING SOON")
		end
		check(Card.badge({ published = false }, Prices), "soon", "", "COMING SOON")
	end)

	it("a title whose state is not known yet shows nothing: no price and no promise", function()
		check(Card.badge(nil, Prices), "none", "", "")
		check(Card.badge({ published = true }, Prices), "none", "", "")
	end)

	it("the struck price is rich text, its own markup characters escaped", function()
		t.expect(Card.strike("5 R$")).toBe("<s>5 R$</s>")
		t.expect(Card.strike("<b>&</b>")).toBe("<s>&lt;b&gt;&amp;&lt;/b&gt;</s>")
		local odd: Card.Prices = { struck = "<5>", price = "1", sale = "&" }
		check(Card.badge({ published = true, free = false }, odd), "sale", "<s>&lt;5&gt;</s>", "1 &")
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
end)
