--!strict
-- Server adapter: turns a session's game over into one hiscore submit. Sessions hands it every step's events;
-- Hiscores.onStep decides what counts, and HiscoreStore.submit (which returns at once) writes it. The only dedupe
-- is each session's own run state. A closing server is held until the runs and writes in flight are done.
local HiscoreStore = require("./HiscoreStore")
local Hiscores = require("@game/ReplicatedStorage/Shared/Logic/Hiscores")

type Held = { state: Hiscores.RunState, userId: string, name: string }

local Submits = {}

local held: { [any]: Held } = {}
local count = 0

-- A session was made on Ready: its first run, and who it is, captured now.
function Submits.ready(s: any, player: Player)
	local display = player.DisplayName
	local name =
		Hiscores.cleanName(if type(display) == "string" and display ~= "" then display else player.Name)
	if held[s] == nil then
		count += 1
	end
	held[s] = { state = Hiscores.newRun(), userId = tostring(player.UserId), name = name }
end

-- Session.playAgain accepted: the next run.
function Submits.again(s: any)
	local h = held[s]
	if h then
		h.state = Hiscores.onAgain(h.state, true)
	end
end

-- Hears one step's events. False tells Sessions to let a parked session go.
function Submits.step(s: any, events: { any }, here: boolean): boolean
	local h = held[s]
	if h == nil then
		return false
	end
	local nextState, submission = Hiscores.onStep(h.state, events, here)
	h.state = nextState
	if submission then
		HiscoreStore.submit(h.userId, h.name, submission.score, submission.level, submission.run)
	end
	if nextState.drop then
		held[s] = nil
		count -= 1
		return false
	end
	return true
end

-- Runs held: made on Ready, released when `step` says to let the session go.
function Submits.pending(): number
	return count
end

-- Holds a closing server while a run or a write is pending, for at most Hiscores.CLOSE_WAIT seconds. The engine
-- keeps stepping while this waits, so a parked run reaches its game over and submits.
function Submits.close()
	local waited = 0
	while Hiscores.holdClose(Submits.pending(), HiscoreStore.pending(), waited) do
		waited += task.wait(0.25)
	end
end

game:BindToClose(Submits.close)

return Submits
