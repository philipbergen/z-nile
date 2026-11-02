--!strict
-- Flow: what the screen shows over the maze in each phase of a run, engine-free. The client draws it;
-- only the server moves a run from phase to phase, and only the server sends a player back to the lobby.
local Game = require("./Game")
local Session = require("./Session")
local Travel = require("./Travel")

-- How the way back to the lobby stands, as the server last reported it.
export type Trip = { phase: Travel.Phase, configured: boolean }

export type Overlay = {
	banner: string?, -- "READY!" or "GAME OVER"
	detail: string?, -- the line under the banner
	fade: number, -- 0..FADE_MAX: how dark the screen is
	flash: boolean, -- the walls are lit in this frame
	prompt: string?, -- under the results: what a tap does now, or why it does nothing
	tap: boolean, -- a tap, a click or a continue key asks the server for the lobby now
	cursor: boolean, -- the mouse is free and shown
}

export type RankView = {
	over: number, -- runs ended so far: the run whose overlay is up, or was last up
	rank: number?, -- that run's all-time rank, only while its overlay is up
	pending: number?, -- the next run's rank, heard before its overlay
	pendingRun: number?,
	missed: number?, -- that run missed the all-time top `missed`, only while its overlay is up
	pendingMissed: number?, -- the next run missed the top `pendingMissed`, heard before its overlay
}

local Flow = {}
Flow.FADE_MAX = 0.6
Flow.FLASH_TICKS = 6
Flow.CONTINUE_KEYS = table.freeze({ "Return", "KeypadEnter" })
Flow.PROMPT = table.freeze({
	idle = "TAP TO RETURN TO THE LOBBY",
	going = "RETURNING TO THE LOBBY...",
	cooling = "Could not return. Try again in a moment.",
	unset = "The lobby is not set up yet.",
})
-- before the server has said anything: the request may go, and the server answers with the truth
Flow.NO_REPORT = table.freeze({ phase = "idle", configured = true } :: Trip)

local function prompt(trip: Trip): string
	if not trip.configured then
		return Flow.PROMPT.unset
	end
	return Flow.PROMPT[trip.phase]
end

function Flow.overlay(play: Session.PlayFrame, rules: Game.Config, trip: Trip?): Overlay
	local phase = play.phase
	if phase == "ready" then
		return {
			banner = "READY!",
			detail = `LEVEL {play.level}`,
			fade = 0,
			flash = false,
			tap = false,
			cursor = false,
		}
	elseif phase == "dying" then
		-- from nothing at the moment of death to FADE_MAX at the end of the pause
		local total = rules.dyingTicks
		local fade = if total > 0
			then Flow.FADE_MAX * math.clamp((total - play.timer) / total, 0, 1)
			else Flow.FADE_MAX
		return { fade = fade, flash = false, tap = false, cursor = false }
	elseif phase == "levelclear" then
		return { fade = 0, flash = (play.timer // Flow.FLASH_TICKS) % 2 == 1, tap = false, cursor = false }
	elseif phase == "gameover" then
		local now = trip or Flow.NO_REPORT
		return {
			banner = "GAME OVER",
			detail = `SCORE {string.format("%d", play.score)}   LEVEL {play.level}`,
			fade = Flow.FADE_MAX,
			flash = false,
			prompt = prompt(now),
			tap = now.configured and now.phase == "idle",
			cursor = true,
		}
	end
	return { fade = 0, flash = false, tap = false, cursor = false }
end

-- The extra line at the end of a run for an all-time rank the server sent. Flow does not know the board size.
function Flow.rankLine(rank: number?): string?
	if type(rank) ~= "number" or rank < 1 or rank ~= math.floor(rank) or rank == math.huge then
		return nil
	end
	return `ALL-TIME #{string.format("%d", rank)}`
end

-- The extra line at the end of a run that did not make the all-time top `top` the server sent.
function Flow.missLine(top: number?): string?
	if type(top) ~= "number" or top < 1 or top ~= math.floor(top) or top == math.huge then
		return nil
	end
	return `NOT IN THE ALL-TIME TOP {string.format("%d", top)}`
end

-- Follow the end-of-run overlay. A new end of run (the edge) is the next run; its rank is the one heard early for
-- exactly that run, never the previous run's. Closing the overlay drops the shown rank and keeps what is pending.
function Flow.follow(view: RankView, gameOver: boolean, wasOver: boolean): (RankView, boolean)
	if gameOver == wasOver then
		return view, gameOver
	end
	if gameOver then
		local over = view.over + 1
		local mine = view.pendingRun == over
		return {
			over = over,
			rank = if mine then view.pending else nil,
			missed = if mine then view.pendingMissed else nil,
			pending = nil,
			pendingRun = nil,
			pendingMissed = nil,
		},
			true
	end
	return {
		over = view.over,
		rank = nil,
		missed = nil,
		pending = view.pending,
		pendingRun = view.pendingRun,
		pendingMissed = view.pendingMissed,
	},
		false
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
		return {
			over = view.over,
			rank = rank,
			missed = nil,
			pending = view.pending,
			pendingRun = view.pendingRun,
			pendingMissed = view.pendingMissed,
		}
	elseif run == view.over + 1 then
		return {
			over = view.over,
			rank = view.rank,
			missed = view.missed,
			pending = rank,
			pendingRun = run,
			pendingMissed = nil,
		}
	end
	return view
end

-- The server said `run` missed the all-time top `top`. Kept, shown and dropped exactly as hearRank keeps a rank;
-- a run has a rank or a miss, and the later one heard replaces the other.
function Flow.hearMiss(view: RankView, run: number, top: number?, gameOver: boolean): RankView
	if Flow.missLine(top) == nil then
		return view
	end
	if run == view.over and view.over >= 1 then
		if not gameOver then
			return view
		end
		return {
			over = view.over,
			rank = nil,
			missed = top,
			pending = view.pending,
			pendingRun = view.pendingRun,
			pendingMissed = view.pendingMissed,
		}
	elseif run == view.over + 1 then
		return {
			over = view.over,
			rank = view.rank,
			missed = view.missed,
			pending = nil,
			pendingRun = run,
			pendingMissed = top,
		}
	end
	return view
end

function Flow.shownRank(view: RankView, gameOver: boolean): string?
	if not gameOver then
		return nil
	end
	return Flow.rankLine(view.rank) or Flow.missLine(view.missed)
end

function Flow.isContinueKey(keyName: string): boolean
	return table.find(Flow.CONTINUE_KEYS, keyName) ~= nil
end

return Flow
