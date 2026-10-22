--!strict
-- Travel: whether a player may be sent to another place right now. Pure state per player: one request at a
-- time, a timeout when nothing happens after the engine call has returned, a cap for a call that never
-- returns, and a short cool-down after a failure. Time comes in as `now` (seconds); the adapter owns the
-- engine call and reports how it went.
export type Phase = "idle" | "going" | "cooling"
export type Config = { goingSeconds: number, coolSeconds: number, capSeconds: number }
export type Entry = { phase: Phase, deadline: number, cap: number, ticket: number }
export type Travel = { config: Config, entries: { [string]: Entry }, serial: number }

export type Answer = "go" | "busy" | "cooling"

local Travel = {}
Travel.DEFAULT = table.freeze({ goingSeconds = 15, coolSeconds = 3, capSeconds = 60 } :: Config)
Travel.MAX_PLACE_ID = 2 ^ 53 - 1

function Travel.new(config: Config?): Travel
	return { config = config or Travel.DEFAULT, entries = {}, serial = 0 }
end

-- A place id from configuration (an attribute, a number or text): a whole number from 1 to MAX_PLACE_ID,
-- else nil. 0 and anything else mean "not configured".
function Travel.destination(raw: any): number?
	local n: any = raw
	if type(raw) == "string" then
		if not string.match(raw, "^%d+$") then
			return nil
		end
		n = tonumber(raw)
	end
	if type(n) ~= "number" or n ~= n or n < 1 or n > Travel.MAX_PLACE_ID or n ~= math.floor(n) then
		return nil
	end
	return n
end

-- idle, going (a request is in flight and not timed out) or cooling (a failure is being waited out)
function Travel.status(t: Travel, id: string, now: number): Phase
	local e = t.entries[id]
	if e == nil then
		return "idle"
	end
	if now >= e.deadline then
		if e.phase == "going" then
			-- the engine never answered: that is a failure
			e.phase, e.deadline = "cooling", now + t.config.coolSeconds
			return "cooling"
		end
		t.entries[id] = nil
		return "idle"
	end
	return e.phase
end

-- A player asks to go. "go" means start the engine call now (it is recorded, with a ticket that names this
-- request); the other answers say why not.
function Travel.request(t: Travel, id: string, now: number): (Answer, number?)
	local phase = Travel.status(t, id, now)
	if phase == "idle" then
		-- until the engine call returns the player stays going, up to the cap
		local cap = now + t.config.capSeconds
		t.serial += 1
		t.entries[id] = { phase = "going", deadline = cap, cap = cap, ticket = t.serial }
		return "go", t.serial
	end
	local answer: Answer = if phase == "going" then "busy" else "cooling"
	return answer, nil
end

-- A report belongs to the player's current request when it names its ticket (or names none: some engine
-- reports carry no request id).
local function current(t: Travel, id: string, now: number, ticket: number?): Entry?
	if Travel.status(t, id, now) ~= "going" then
		return nil
	end
	local e = t.entries[id]
	if ticket ~= nil and ticket ~= e.ticket then
		return nil
	end
	return e
end

-- The engine call returned without an error: the player is still going, but nothing may be waiting any more,
-- so the timeout now counts from here (never past the cap). Nothing for a player who is not going, or for a
-- request that is not the current one.
function Travel.answered(t: Travel, id: string, now: number, ticket: number?)
	local e = current(t, id, now, ticket)
	if e then
		e.deadline = math.min(e.cap, now + t.config.goingSeconds)
	end
end

-- The engine said the call failed. Only the current request of a player who is going can fail: a late report
-- for a request that already timed out, an older one, or nobody, changes nothing.
function Travel.failed(t: Travel, id: string, now: number, ticket: number?)
	if current(t, id, now, ticket) then
		local coolEnd = now + t.config.coolSeconds
		t.entries[id] = { phase = "cooling", deadline = coolEnd, cap = coolEnd, ticket = 0 }
	end
end

-- The player is gone (left, or the teleport took them).
function Travel.left(t: Travel, id: string)
	t.entries[id] = nil
end

return Travel
