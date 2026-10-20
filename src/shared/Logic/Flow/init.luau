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

export type RankView = {
	over: number, -- runs ended so far: the run whose overlay is up, or was last up
	rank: number?, -- that run's all-time rank, only while its overlay is up
	pending: number?, -- the next run's rank, heard before its overlay
	pendingRun: number?,
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

-- The extra line at the end of a run for an all-time rank the server sent. Flow does not know the board size.
function Flow.rankLine(rank: number?): string?
	if type(rank) ~= "number" or rank < 1 or rank ~= math.floor(rank) or rank == math.huge then
		return nil
	end
	return `ALL-TIME #{string.format("%d", rank)}`
end

-- Follow the end-of-run overlay. A new end of run (the edge) is the next run; its rank is the one heard early for
-- exactly that run, never the previous run's. Closing the overlay drops the shown rank and keeps what is pending.
function Flow.follow(view: RankView, gameOver: boolean, wasOver: boolean): (RankView, boolean)
	if gameOver == wasOver then
		return view, gameOver
	end
	if gameOver then
		local over = view.over + 1
		local rank = if view.pendingRun == over then view.pending else nil
		return { over = over, rank = rank, pending = nil, pendingRun = nil }, true
	end
	return { over = view.over, rank = nil, pending = view.pending, pendingRun = view.pendingRun }, false
end

-- A rank arrived for `run`. For the run whose overlay is up it shows; for the next run it waits; for any other
-- run (a closed one, or too far ahead) it is dropped.
function Flow.hearRank(view: RankView, run: number, rank: number?, gameOver: boolean): RankView
	if Flow.rankLine(rank) == nil then
		return view
	end
	if run == view.over and view.over >= 1 then
		if not gameOver then
			return view
		end
		return { over = view.over, rank = rank, pending = view.pending, pendingRun = view.pendingRun }
	elseif run == view.over + 1 then
		return { over = view.over, rank = view.rank, pending = rank, pendingRun = run }
	end
	return view
end

function Flow.shownRank(view: RankView, gameOver: boolean): string?
	if not gameOver then
		return nil
	end
	return Flow.rankLine(view.rank)
end

function Flow.isPlayAgainKey(keyName: string): boolean
	return table.find(Flow.PLAY_AGAIN_KEYS, keyName) ~= nil
end

return Flow
