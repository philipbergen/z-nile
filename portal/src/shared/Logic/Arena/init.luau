--!strict
-- Arena (f0208): which shared arena an ARENA player joins. The portal's servers share one record per title in a
-- MemoryStore hash map: the reserved server's id, how many players the portal has sent there, and when it opened.
-- An arena takes players until CAP were sent or OPEN_SECONDS passed; then the next ARENA player opens a new one.
-- Pure: the record arrives as the stored value, the clock and the fresh server id as parameters.
export type Record = { id: string, count: number, opened: number }

local Arena = {}

Arena.CAP = 24 -- players sent to one arena (snake's arena cap, f0212)
Arena.OPEN_SECONDS = 600 -- an arena takes new players this long after it opened
Arena.MAP = "PortalArenas" -- the MemoryStore hash map, key the title's name
Arena.SKEW_SECONDS = 30 -- another portal server's clock may run this far ahead of this one's

local function whole(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n == math.floor(n)
end

-- The stored arena when it still takes players at `now`: a well-formed record with fewer than CAP sent, opened less
-- than OPEN_SECONDS before `now`, and no more than SKEW_SECONDS after it (another server's clock ahead of this one's
-- counts as now). Anything else is nil.
function Arena.open(raw: any, now: number): Record?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then
		return nil
	end
	if not whole(raw.count) or raw.count < 0 or raw.count >= Arena.CAP or not whole(raw.opened) then
		return nil
	end
	if raw.opened > now + Arena.SKEW_SECONDS or now - raw.opened >= Arena.OPEN_SECONDS then
		return nil
	end
	return { id = raw.id, count = raw.count, opened = raw.opened }
end

-- The record after one more player joins: the open arena with one more sent, else a new arena `fresh` opened `now`
-- with this player. The caller sends the player to the answer's id.
function Arena.join(raw: any, fresh: string, now: number): Record
	local r = Arena.open(raw, now)
	if r ~= nil then
		return { id = r.id, count = r.count + 1, opened = r.opened }
	end
	return { id = fresh, count = 1, opened = now }
end

return table.freeze(Arena)
