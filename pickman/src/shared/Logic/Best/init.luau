--!strict
-- Best: a player's best level reached and the start level they chose in the lobby (f0148), engine-free. The record
-- lives in a DataStore (Best.STORE, keyed by the user id) that the lobby and the place runs are played in share; this module decides
-- what it holds, what a run may start on, and the lobby's level picker.

export type Record = { best: number, next: number? }
export type Picker = { shown: boolean, level: number, down: boolean, up: boolean }

local Best = {}
Best.STORE = "PickmanBest" -- the DataStore both places use, one key per player (tostring(userId))
Best.ATTRIBUTE = "PickmanBest" -- the player attribute the lobby server sets to the stored best, for the picker

local function whole(v: any): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= 1 and v < math.huge
end

-- A stored value read back: anything that is not a record of whole levels counts as a fresh one (best 1).
function Best.decode(raw: any): Record
	if type(raw) ~= "table" or not whole(raw.best) then
		return { best = 1 }
	end
	return { best = raw.best, next = if whole(raw.next) then raw.next else nil }
end

-- A level a run may start on: a whole number in 1..best, else nil.
function Best.valid(requested: any, best: number): number?
	if whole(requested) and requested <= best then
		return requested
	end
	return nil
end

-- The record after a run reaches `level`: the best only ever rises.
function Best.reached(r: Record, level: number): Record
	local best = if whole(level) then math.max(r.best, level) else r.best
	return { best = best, next = r.next }
end

-- The record a run reaching `level` leaves, or nil when the best is already that high (nothing to write).
function Best.raise(r: Record, level: number): Record?
	local raised = Best.reached(r, level)
	return if raised.best > r.best then raised else nil
end

-- The record after the lobby's choice: the requested level when it is allowed, else level 1 (a press with no level is
-- START GAME, which the screen showed as level 1).
function Best.choose(r: Record, requested: any): Record
	return { best = r.best, next = Best.valid(requested, r.best) or 1 }
end

-- The place runs are played in takes the chosen start once: an allowed choice, else level 1; the choice is cleared.
function Best.claim(r: Record): (number, Record)
	local start = if r.next then Best.valid(r.next, r.best) else nil
	return start or 1, { best = r.best }
end

-- The lobby's picker: shown once there is a choice (best 2 or more); `chosen` nil starts on the best.
function Best.picker(best: number, chosen: number?): Picker
	local b = if whole(best) then best else 1
	local level = Best.valid(chosen, b) or b
	return { shown = b >= 2, level = level, down = level > 1, up = level < b }
end

-- One press of the picker's arrows: `delta` -1 or 1, kept within 1..best.
function Best.step(best: number, chosen: number?, delta: number): number
	local p = Best.picker(best, chosen)
	return math.clamp(p.level + (if delta < 0 then -1 elseif delta > 0 then 1 else 0), 1, math.max(1, best))
end

-- The picker's keys on a keyboard (f0148): Left a level lower, Right a level higher; any other key nothing.
Best.KEYS = table.freeze({ Left = -1, Right = 1 }) :: { [string]: number }
function Best.keyStep(keyName: any): number?
	return if type(keyName) == "string" then Best.KEYS[keyName] else nil
end

return Best
