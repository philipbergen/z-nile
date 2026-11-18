--!strict
-- Card (f0205): what one card of the portal's carousel shows. Pure view models: the price badge for a title's state,
-- the states the server sends and the client's defensive read of them, the card's regions, and its preview's spin.
-- A title is an `Entry` (src/shared/Games.luau holds them); the badge's sale words are the arcade's Prices table,
-- passed in.
export type Shape = "Ball" | "Block" | "Cylinder"
-- one part of a preview scene, in studs around the scene's centre; colour in 0..255
export type Part = { shape: Shape, size: { number }, at: { number }, color: { number } }
export type Entry = { name: string, place: string, title: string, tagline: string, preview: { Part } }
-- a title's state for one player: is its place published, and is its free start due (nil: not known yet)
export type State = { published: boolean, free: boolean? }
export type Kind = "none" | "sale" | "free" | "soon"
-- `struck` is rich text (the struck-through price), "" when there is none
export type Badge = { kind: Kind, struck: string, text: string }
export type Prices = { struck: string, price: string, sale: string }
-- the badge's own words, besides the sale's (Prices): passed in, so they can live in any config table
export type Words = { free: string, soon: string }
export type Region = { top: number, height: number } -- of the card's height
-- the server's record of one title's free state for one player: what it knows, and the reads that failed in a row
export type Read = { free: boolean?, busy: number, down: number }
-- how long to wait before reading again: after a busy read, after the first failed one, and at most
export type Waits = { busy: number, down: number, most: number }

local Card = {}
Card.WORDS = table.freeze({ free = "FREE GAME READY", soon = "COMING SOON" }) -- the words the portal shows
Card.ORDER = table.freeze({ "Title", "Tagline", "Preview", "Badge", "Buttons", "Boards" })
Card.REGIONS = table.freeze({
	Title = table.freeze({ top = 0.02, height = 0.08 }),
	Tagline = table.freeze({ top = 0.1, height = 0.08 }),
	Preview = table.freeze({ top = 0.19, height = 0.27 }),
	Badge = table.freeze({ top = 0.47, height = 0.08 }),
	Buttons = table.freeze({ top = 0.56, height = 0.09 }), -- the play buttons (f0208)
	Boards = table.freeze({ top = 0.66, height = 0.32 }), -- the boards (f0206)
})
Card.SPIN = 0.5 -- the preview's turn, radians a second
Card.FRAME = 4 -- every preview part lies within this many studs of the centre on each axis
Card.CAMERA = table.freeze({ fov = 40, distance = 22, height = 3 }) -- the preview camera: vertical degrees, studs
Card.SHAPES = table.freeze({ "Ball", "Block", "Cylinder" })
Card.INSET = 0.05 -- each label's margin either side, of the card's width (a label is 1 - 2 INSET wide)
Card.BADGE = table.freeze({ struck = 0.4, gap = 0.02, offer = 0.58 }) -- the badge's two labels, of its width
Card.GLYPH = 0.65 -- a bold glyph's width, of its text size (the text-size model)
Card.MIN_TEXT = 12 -- pixels: the smallest text a card may show
Card.ASK_GAP = 1 -- seconds: asks closer than this are answered together, at its end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- `text` struck through, as Roblox rich text; the text's own markup characters are escaped.
function Card.strike(text: string): string
	return `<s>{escape(text)}</s>`
end

-- The badge for a title's state: nothing until the state is known; the `soon` word when its place is not published;
-- the `free` word when its free start is due; else the sale: the struck price, then the price and the sale word.
function Card.badge(state: State?, prices: Prices, words: Words): Badge
	if state == nil then
		return { kind = "none", struck = "", text = "" }
	elseif not state.published then
		return { kind = "soon", struck = "", text = words.soon }
	elseif state.free == true then
		return { kind = "free", struck = "", text = words.free }
	elseif state.free == false then
		return { kind = "sale", struck = Card.strike(prices.struck), text = `{prices.price} {prices.sale}` }
	end
	return { kind = "none", struck = "", text = "" }
end

-- Whether the entry's place is published: its place has an id in `ids` (Places.read's answer).
function Card.published(entry: Entry, ids: { [string]: number? }): boolean
	return ids[entry.place] ~= nil
end

-- What the server sends one player: each entry's state by name. A place that is not published has no free state.
function Card.states(
	entries: { Entry },
	published: { [string]: boolean },
	free: { [string]: boolean }?
): { [string]: State }
	local known: { [string]: boolean } = free or {}
	local out: { [string]: State } = {}
	for _, e in entries do
		local p = published[e.name] == true
		out[e.name] = { published = p, free = if p then known[e.name] else nil }
	end
	return out
end

-- The client's read of the server's message: each entry's state, nil where the message has none that makes sense.
function Card.parse(raw: any, entries: { Entry }): { [string]: State }
	local out: { [string]: State } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, e in entries do
		local s = raw[e.name]
		if
			type(s) == "table"
			and type(s.published) == "boolean"
			and (s.free == nil or type(s.free) == "boolean")
		then
			out[e.name] = { published = s.published, free = if s.published then s.free else nil }
		end
	end
	return out
end

-- A read's answer folded into what the server knows of one title (`read` nil: nothing yet). `due` is PaidPlay's
-- free state when the read gave a record, nil when it did not. A record: that state, and no read again. A first busy
-- answer (another read of the same record under way) keeps what was known and reads again after `waits.busy`. Any
-- other answer without a record (down, or busy twice in a row) is the sale, read again after `waits.down`, doubling
-- with each failure in a row up to `waits.most`.
function Card.answer(read: Read?, due: boolean?, reason: string?, waits: Waits): (Read, number?)
	local was: Read = read or { free = nil, busy = 0, down = 0 }
	if due ~= nil then
		return { free = due, busy = 0, down = 0 }, nil
	elseif reason == "busy" and was.busy == 0 then
		return { free = was.free, busy = 1, down = was.down }, waits.busy
	end
	local down = was.down + 1
	return { free = false, busy = 0, down = down }, math.min(waits.down * 2 ^ (down - 1), waits.most)
end

-- How long an ask at `now` waits, nil to be answered at once: at once when the last answered ask is ASK_GAP old (or
-- none, or a clock that went back), else at the end of that gap.
function Card.asked(last: number?, now: number): number?
	if last == nil or now < last or now - last >= Card.ASK_GAP then
		return nil
	end
	return Card.ASK_GAP - (now - last)
end

-- The text size a label of `width` x `height` pixels gives `text` (TextScaled), by the GLYPH model: one line, or,
-- `wrap`ped, the best of one to four lines.
function Card.textSize(text: string, width: number, height: number, wrap: boolean): number
	local n = math.max(#text, 1)
	local best = math.min(height, width / (Card.GLYPH * n))
	if wrap then
		for lines = 2, 4 do
			best = math.max(best, math.min(height / lines, width * lines / (Card.GLYPH * n)))
		end
	end
	return best
end

-- The preview's turn after `seconds`, in radians from 0 up to 2π; 0 for a time that is not a finite number.
function Card.angle(seconds: number): number
	if seconds ~= seconds or seconds == math.huge or seconds == -math.huge then
		return 0
	end
	return (seconds * Card.SPIN) % (2 * math.pi)
end

return Card
