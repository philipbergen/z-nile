--!strict
-- f0421 step 8b: what a worker's CLI can deliver, as `work` reads it. Pure over a models walk (the caller reads the file).
--   workcan.of           the Capability `work.decide` filters by: lacks(activity, level) is nil when the CLI can deliver it.
--   workcan.waitingFor   `./zn work status`: an active raft whose next activity no registered worker can deliver, and the kind
--                        of worker it waits for.
local models = require("./models")
local rounds = require("./rounds")
local work = require("./work")

local workcan = {}

local function levelOf(level: string): rounds.Level
	if level == "easy" then
		return "easy"
	elseif level == "risky" then
		return "risky"
	end
	return "normal"
end

function workcan.of(layers: { models.Layer }, cli: string): work.Capability
	return {
		cli = cli,
		lacks = function(activity: string, level: string): string?
			local lvl: rounds.Level = levelOf(level)
			local ok, can = pcall(function(): boolean
				return models.can(layers, cli, activity, lvl)
			end)
			if not ok or can then
				return nil -- a file that cannot be asked filters nothing
			end
			return models.waiting(layers, activity, lvl)
		end,
	}
end

export type Worker = { id: string, cli: string, can: { string } }

-- One line per active raft whose next action needs a model that no registered worker delivers, naming the activity, the
-- level and the CLIs that have it. Nothing when no worker is registered (then no worker is said to be missing). `need` words
-- the need of `activity/level` (models.waiting over the walk).
function workcan.waitingFor(
	rafts: { work.RaftFact },
	workers: { Worker },
	need: (activity: string, level: rounds.Level) -> string
): { string }
	local out: { string } = {}
	if #workers == 0 then
		return out
	end
	for _, r in rafts do
		if r.where == "active" then
			local d = work.forRaft(r)
			local activity, _, level = work.activityOf({ rafts = { r } }, d)
			if activity ~= nil then
				local pair = `{activity}/{level}`
				local delivered = false
				for _, w in workers do
					if #w.can == 0 then
						delivered = true -- its capability is unknown (the file was unreadable at join): it runs unfiltered
					end
					for _, c in w.can do
						if c == pair then
							delivered = true
						end
					end
				end
				if not delivered then
					table.insert(out, `{r.id}: {work.WAITING}{need(activity, levelOf(level))}`)
				end
			end
		end
	end
	return out
end

return workcan
