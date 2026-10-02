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
export type Layout =
	{ textSize: number, margin: number, iconSize: number, barWidth: number, barHeight: number }

local Hud = {}
Hud.MIN_TEXT = 14
Hud.MAX_TEXT = 40
Hud.TEXT_SHARE = 0.045 -- of the viewport's smaller side
Hud.BAR_SHARE = 0.25 -- of its width
Hud.MAX_BAR = 400
Hud.MIN_BAR_HEIGHT = 4

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

-- Whole-pixel sizes for a viewport of `width` x `height` pixels, from its smaller side.
function Hud.layout(width: number, height: number): Layout
	local w, h = side(width), side(height)
	local text = math.clamp(round(math.min(w, h) * Hud.TEXT_SHARE), Hud.MIN_TEXT, Hud.MAX_TEXT)
	local margin = round(text / 2)
	return {
		textSize = text,
		margin = margin,
		iconSize = text,
		barWidth = math.max(0, math.min(round(w * Hud.BAR_SHARE), Hud.MAX_BAR, w - 2 * margin)),
		barHeight = math.max(Hud.MIN_BAR_HEIGHT, round(text * 0.4)),
	}
end

return Hud
