--!strict
-- Hud: what the heads-up display shows and how big, engine-free. HudView draws it.
local Levels = require("./Levels")
local Session = require("./Session")

export type Model = {
	score: string, -- plain digits
	level: string, -- "LEVEL n"
	lives: number, -- lives left, the one in play included
	power: number, -- 0..1: the share of the level's frightened time still to run
}
-- Sizes in pixels, and the safe rectangle (the viewport less its inset) the HUD blocks sit in.
export type Layout = {
	textSize: number,
	margin: number,
	iconSize: number,
	barWidth: number,
	barHeight: number,
	safeX: number,
	safeY: number,
	safeW: number,
	safeH: number,
}
-- Pixels the device keeps for itself on each edge (a notch, a home indicator, the top bar).
export type Inset = { top: number, bottom: number, left: number, right: number }
-- Min/Max, the shape of an inset area. No engine types.
export type Area = { Min: { X: number, Y: number }, Max: { X: number, Y: number } }
-- Top-left of the radar in pixels. w and h are the requested size (0 when size is not a positive finite number).
export type Box = { x: number, y: number, w: number, h: number }
type JumpRow = { right: number, bottom: number, size: number }

local Hud = {}
Hud.MIN_TEXT = 14
Hud.MAX_TEXT = 40
Hud.TEXT_SHARE = 0.045 -- of the viewport's smaller side
Hud.BAR_SHARE = 0.25 -- of its width
Hud.MAX_BAR = 400
Hud.MIN_BAR_HEIGHT = 4
-- Roblox's touch jump button (PlayerModule's TouchJump), measured from the bottom-right of the frame the touch
-- GUI fills: the small set when that frame's smaller side is at most JUMP_SMALL_MAX. Legacy first, then the
-- ability-controls placement. A further placement is one more row.
Hud.JUMP_SMALL_MAX = 500
Hud.JUMP = table.freeze({
	small = table.freeze({ { right = 95, bottom = 90, size = 70 }, { right = 136, bottom = 136, size = 72 } }),
	large = table.freeze({
		{ right = 170, bottom = 210, size = 120 },
		{ right = 220, bottom = 232, size = 120 },
	}),
}) :: { small: { JumpRow }, large: { JumpRow } }

local function round(v: number): number
	return math.floor(v + 0.5)
end

-- a viewport side that is zero, negative, NaN or infinite counts as 0
local function side(v: number): number
	return if v > 0 and v < math.huge then v else 0
end

function Hud.model(play: Session.PlayFrame): Model
	local total = Levels.frightenedTicks(play.level, Session.TICK_RATE)
	return {
		score = string.format("%d", play.score),
		level = `LEVEL {play.level}`,
		lives = play.lives,
		power = if total > 0 then math.clamp(play.frightened / total, 0, 1) else 0,
	}
end

-- Whole-pixel sizes for a viewport of `width` x `height` pixels, from its smaller side, and the safe rectangle
-- left by `inset` (all zeros when nil; each component counts as 0 unless positive and finite). The text follows
-- the full viewport, so a notch does not shrink it; the bar fits the safe width.
function Hud.layout(width: number, height: number, inset: Inset?): Layout
	local w, h = side(width), side(height)
	local top = if inset then side(inset.top) else 0
	local bottom = if inset then side(inset.bottom) else 0
	local left = if inset then side(inset.left) else 0
	local right = if inset then side(inset.right) else 0
	local safeW = math.max(0, w - left - right)
	local safeH = math.max(0, h - top - bottom)
	local text = math.clamp(round(math.min(w, h) * Hud.TEXT_SHARE), Hud.MIN_TEXT, Hud.MAX_TEXT)
	local margin = round(text / 2)
	return {
		textSize = text,
		margin = margin,
		iconSize = text,
		barWidth = math.max(0, math.min(round(safeW * Hud.BAR_SHARE), Hud.MAX_BAR, safeW - 2 * margin)),
		barHeight = math.max(Hud.MIN_BAR_HEIGHT, round(text * 0.4)),
		safeX = left,
		safeY = top,
		safeW = safeW,
		safeH = safeH,
	}
end

-- The inset of the core-UI safe area (`core`) inside the full screen (`none`), both as one inset area API
-- reports them: relative to the core area's top-left, so the screen's top-left is -none.Min.
function Hud.safeInset(none: Area, core: Area): Inset
	local left, top = -none.Min.X, -none.Min.Y
	local right = (none.Max.X - none.Min.X) - (core.Max.X - core.Min.X) - left
	local bottom = (none.Max.Y - none.Min.Y) - (core.Max.Y - core.Min.Y) - top
	return { left = side(left), top = side(top), right = side(right), bottom = side(bottom) }
end

-- Roblox's touch jump button rectangles for a touch GUI filling the frame (x, y, w, h), legacy first.
function Hud.jumpButtons(x: number, y: number, w: number, h: number): { Box }
	local fw, fh = side(w), side(h)
	local rows: { JumpRow } = if math.min(fw, fh) <= Hud.JUMP_SMALL_MAX
		then Hud.JUMP.small
		else Hud.JUMP.large
	local out: { Box } = {}
	for _, row in rows do
		table.insert(out, { x = x + fw - row.right, y = y + fh - row.bottom, w = row.size, h = row.size })
	end
	return out
end

-- How far the core-UI safe area's top sits below the device safe area's (the top bar), never negative.
function Hud.bandTop(core: Area, device: Area): number
	return side(core.Min.Y - device.Min.Y)
end

-- The radar's square in the bottom-right corner, in pixels. The right edge is one layout margin in from
-- the screen. The bottom edge is one margin above the power bar, whose own top is one margin up from the
-- screen, so the inset from the bottom is the bar's height plus two margins. A size that is not a positive
-- finite number is an empty square on that same corner. Hud.layout's numbers are not changed.
-- On a touch screen (`touch` true) it is lifted to one margin above the higher jump button of the touch GUI,
-- whose frame starts `bandTop` lower (the top bar), and never into the top text band below that.
function Hud.radarBox(width: number, height: number, size: number, touch: boolean?, bandTop: number?): Box
	local l = Hud.layout(width, height)
	local s = side(size)
	local right = side(width) - l.margin
	local bottom = side(height) - (l.barHeight + 2 * l.margin)
	local y = bottom - s
	if touch == true then
		local band = side(bandTop or 0)
		local higher = math.huge
		for _, b in Hud.jumpButtons(0, band, width, math.max(0, side(height) - band)) do
			higher = math.min(higher, b.y)
		end
		y = math.max(band + l.textSize + 2 * l.margin, higher - l.margin - s)
	end
	return { x = right - s, y = y, w = s, h = s }
end

-- The blaster's shots in the lives row (f0100), in pixels from that row's top-left: after the last life's icon
-- and one margin, one bar per shot, half an icon wide, an icon tall, half a margin apart (halves rounded half up).
-- A count or a life total that is not a whole number >= 0 counts as 0 (rounded down).
function Hud.shotIcons(l: Layout, lives: number, shots: number): { Box }
	local function count(n: number): number
		return if n >= 0 and n < math.huge then math.floor(n) else 0
	end
	local w = round(l.iconSize / 2)
	local gap = round(l.margin / 2)
	local x = count(lives) * (l.iconSize + l.margin)
	local out: { Box } = {}
	for i = 1, count(shots) do
		table.insert(out, { x = x + (i - 1) * (w + gap), y = 0, w = w, h = l.iconSize })
	end
	return out
end

-- f0126: the pick under way, as a share of its time done at the shown tick (0..1), nil when there is none.
function Hud.pickProgress(pick: Session.Pick?, shownTick: number): number?
	if pick == nil or shownTick ~= shownTick then
		return nil
	end
	return math.clamp((shownTick - pick.started) / math.max(1, pick.ticks), 0, 1)
end

-- What each boon is called on the screen.
Hud.BOON_LABELS = table.freeze({
	jumps = "LONGER JUMPS",
	fastpick = "FASTER PICK",
	pill = "GHOST PILL",
	longpill = "LONG GHOST PILL",
	shot = "BLASTER SHOT",
	pellets = "PELLETS BACK",
} :: { [string]: string })
Hud.BOON_TICKS = 30 -- the banner shows for 2 s of real time at Session.STEP_RATE 15

-- The banner for the latest boon at `tick`: its label from the step it was granted for BOON_TICKS steps, else nil.
function Hud.boonBanner(boon: Session.BoonGrant?, tick: number): string?
	if boon == nil or tick < boon.tick or tick >= boon.tick + Hud.BOON_TICKS then
		return nil
	end
	return Hud.BOON_LABELS[boon.kind]
end

-- Where the pick's bar and the boon's banner go (f0126), in the same pixels as Hud.layout (screen pixels, inside its
-- safe rectangle): both centred across it, the bar a little above the middle (clear of the
-- bottom row of lives, shots, power bar, snap button and radar), the banner in the upper third (clear of the top
-- row of score and level).
Hud.PICK_BAR_AT = 0.4 -- of the safe rectangle's height, the bar's top: above the middle, so above the touch radar on a narrow phone
Hud.BOON_AT = 0.3 -- of the safe rectangle's height, the banner's middle
function Hud.pickBox(l: Layout): Box
	local w = l.barWidth
	local h = math.max(Hud.MIN_BAR_HEIGHT, l.barHeight)
	return {
		x = round(l.safeX + (l.safeW - w) / 2),
		y = round(l.safeY + l.safeH * Hud.PICK_BAR_AT),
		w = w,
		h = h,
	}
end

function Hud.boonBox(l: Layout): Box
	local h = 2 * l.textSize
	local w = math.min(math.max(0, l.safeW - 2 * l.margin), 16 * l.textSize)
	return {
		x = round(l.safeX + (l.safeW - w) / 2),
		y = round(l.safeY + l.safeH * Hud.BOON_AT - h / 2),
		w = w,
		h = h,
	}
end

return Hud
