--!strict
-- Carousel (f0205): which card of the portal's row is in front, how the player's inputs move it, and where each card
-- sits on the screen. Pure: inputs come in as key, wheel and swipe names and numbers, time as `now`.
export type Intent = "prev" | "next" | "play"
export type Carousel = { count: number, index: number, wheelAt: number? }
-- a card's box in the screen's safe area, in pixels from its top-left corner
export type Box = { x: number, y: number, width: number, height: number, shown: boolean, dim: number }

local KEYS: { [string]: Intent } = {
	A = "prev",
	Left = "prev",
	ButtonL1 = "prev",
	D = "next",
	Right = "next",
	ButtonR1 = "next",
	Return = "play",
	KeypadEnter = "play",
	ButtonA = "play",
}

local Carousel = {}
Carousel.KEYS = table.freeze(KEYS)
Carousel.ACTION = "PortalCarousel"
Carousel.PRIORITY = 2500 -- above the default controls (2000), below the test purchase screen (3000, f0201)
Carousel.WHEEL_GAP = 0.25 -- seconds the wheel must rest before a wheel event moves the row again
Carousel.HEIGHT = 0.9 -- the front card's height, of the safe area's
Carousel.ASPECT = 0.75 -- the front card's width over its height
Carousel.MAX_WIDTH = 0.8 -- at most this much of the safe area's width
Carousel.SIDE_SCALE = 0.8 -- a neighbour's size, of the front card's
Carousel.GAP = 0.03 -- between the front card and a neighbour, of the safe area's width
Carousel.SIDE_DIM = 0.5 -- how much a neighbour is dimmed (0 none, 1 black)

local function whole(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n == math.floor(n)
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- A row of `count` cards with the first in front.
function Carousel.new(count: number): Carousel
	if not whole(count) or count < 1 then
		error(`Carousel.new: count must be a whole number of at least 1, got {tostring(count)}`, 2)
	end
	return { count = count, index = 1, wheelAt = nil }
end

-- The row moved by `by` cards (negative: back), wrapping round at either end. A new table.
function Carousel.step(c: Carousel, by: number): Carousel
	local index = c.index
	if whole(by) then
		index = (c.index - 1 + by) % c.count + 1
	end
	return { count = c.count, index = index, wheelAt = c.wheelAt }
end

-- What a key or button does here, by its KeyCode name; nil for any other.
function Carousel.key(name: string): Intent?
	return KEYS[name]
end

-- A wheel event of `delta` (positive: rolled up, away from the player) at `now`: up is "prev", down is "next". It
-- moves the row only when the wheel rested WHEEL_GAP before it, so one roll or one trackpad flick moves one card.
-- Every wheel event, moving or not, restarts the rest.
function Carousel.wheel(c: Carousel, delta: number, now: number): (Carousel, Intent?)
	if not finite(now) then
		return c, nil
	end
	local rested = c.wheelAt == nil or now - c.wheelAt >= Carousel.WHEEL_GAP or now < c.wheelAt
	local after: Carousel = { count = c.count, index = c.index, wheelAt = now }
	if not finite(delta) or delta == 0 then
		return after, nil
	end
	if not rested then
		return after, nil
	end
	return after, if delta > 0 then "prev" else "next"
end

-- A swipe by its SwipeDirection name: a swipe to the left brings the next card in, to the right the previous one.
function Carousel.swipe(direction: string): Intent?
	if direction == "Left" then
		return "next"
	elseif direction == "Right" then
		return "prev"
	end
	return nil
end

-- Card `i`'s place relative to the front card, the short way round the row: 0 in front, -1 to its left, +1 to its
-- right. With an even count the card opposite the front one is +count/2.
function Carousel.offset(c: Carousel, i: number): number
	local d = (i - c.index) % c.count
	if d > c.count / 2 then
		d -= c.count
	end
	return d
end

-- The box of a card `offset` places from the front one, in a safe area `width` x `height` pixels: the front card
-- centred and as tall as HEIGHT allows (narrower than MAX_WIDTH), its two neighbours smaller and dimmed on either
-- side, clear of it; every other card hidden.
function Carousel.box(offset: number, width: number, height: number): Box
	local h = height * Carousel.HEIGHT
	local w = math.min(h * Carousel.ASPECT, width * Carousel.MAX_WIDTH)
	if offset == 0 then
		return { x = (width - w) / 2, y = (height - h) / 2, width = w, height = h, shown = true, dim = 0 }
	end
	local sw, sh = w * Carousel.SIDE_SCALE, h * Carousel.SIDE_SCALE
	local centre = width / 2 + (if offset < 0 then -1 else 1) * (w / 2 + width * Carousel.GAP + sw / 2)
	local x = centre - sw / 2
	local shown = (offset == 1 or offset == -1) and x < width and x + sw > 0
	return { x = x, y = (height - sh) / 2, width = sw, height = sh, shown = shown, dim = Carousel.SIDE_DIM }
end

return Carousel
