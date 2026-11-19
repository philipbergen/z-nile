--!strict
-- Pairing (f0208): the 2 PLAYERS waiting lines of one portal server, one per title. A player waits in at most one
-- line; the second player to join a line is paired with the first one waiting there, and both leave it. Pure: ids are
-- strings (a player's user id), and nothing mutates the queue it is given.
export type Queue = { lines: { [string]: { string } } }

local Pairing = {}

function Pairing.new(): Queue
	return { lines = {} }
end

local function without(q: Queue, id: string): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for name, line in q.lines do
		local kept = {}
		for _, other in line do
			if other ~= id then
				table.insert(kept, other)
			end
		end
		if #kept > 0 then
			out[name] = kept
		end
	end
	return out
end

-- `id` joins the line of `name`, leaving any other line first. When someone else was waiting there, the first of them
-- and `id` are the pair (in that order) and both leave the line; else `id` waits at its end.
function Pairing.join(q: Queue, name: string, id: string): (Queue, { string }?)
	local lines = without(q, id)
	local line = lines[name]
	if line ~= nil and #line > 0 then
		local first = line[1]
		local rest = table.move(line, 2, #line, 1, {})
		if #rest > 0 then
			lines[name] = rest
		else
			lines[name] = nil
		end
		return { lines = lines }, { first, id }
	end
	lines[name] = { id }
	return { lines = lines }, nil
end

-- `id` leaves whatever line it waits in.
function Pairing.leave(q: Queue, id: string): Queue
	return { lines = without(q, id) }
end

-- How many wait in the line of `name`.
function Pairing.count(q: Queue, name: string): number
	local line = q.lines[name]
	return if line == nil then 0 else #line
end

-- The title `id` waits for, nil when it waits for none.
function Pairing.line(q: Queue, id: string): string?
	for name, line in q.lines do
		if table.find(line, id) ~= nil then
			return name
		end
	end
	return nil
end

return table.freeze(Pairing)
