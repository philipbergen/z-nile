--!strict
-- Flow: what the screen shows over the maze in each phase of a run, engine-free. The client draws it;
-- only the server moves a run from phase to phase.
local Game = require("./Game")
local Session = require("./Session")

export type Overlay = {
	banner: string?, -- "READY!" or "GAME OVER"
	detail: string?, -- the line under the banner
	fade: number, -- 0..FADE_MAX: how dark the screen is
	flash: boolean, -- the walls are lit in this frame
	playAgain: boolean, -- the play-again prompt is up and its keys are live
}

local Flow = {}
Flow.FADE_MAX = 0.6
Flow.FLASH_TICKS = 6
Flow.PLAY_AGAIN_KEYS = table.freeze({ "Return", "KeypadEnter" })

function Flow.overlay(play: Session.PlayFrame, rules: Game.Config): Overlay
	local phase = play.phase
	if phase == "ready" then
		return { banner = "READY!", detail = `LEVEL {play.level}`, fade = 0, flash = false, playAgain = false }
	elseif phase == "dying" then
		-- from nothing at the moment of death to FADE_MAX at the end of the pause
		local total = rules.dyingTicks
		local fade = if total > 0
			then Flow.FADE_MAX * math.clamp((total - play.timer) / total, 0, 1)
			else Flow.FADE_MAX
		return { fade = fade, flash = false, playAgain = false }
	elseif phase == "levelclear" then
		return { fade = 0, flash = (play.timer // Flow.FLASH_TICKS) % 2 == 1, playAgain = false }
	elseif phase == "gameover" then
		return {
			banner = "GAME OVER",
			detail = `SCORE {string.format("%d", play.score)}   LEVEL {play.level}`,
			fade = Flow.FADE_MAX,
			flash = false,
			playAgain = true,
		}
	end
	return { fade = 0, flash = false, playAgain = false }
end

function Flow.isPlayAgainKey(keyName: string): boolean
	return table.find(Flow.PLAY_AGAIN_KEYS, keyName) ~= nil
end

return Flow
