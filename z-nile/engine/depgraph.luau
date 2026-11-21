--!strict
-- f0422: the dependency rules over open units, pure over data (no reads, no knowledge of the board): a unit's band
-- (how many steps from workable), how many units sit downstream of it, and the order that puts the most-unblocking
-- first. The board draws them; the worker will pick by them.
local depgraph = {}

-- `waitsOn` holds the ids of OPEN units this one waits on (the caller filters done ones out).
export type Unit = { id: string, waitsOn: { string } }

local function known(units: { Unit }): { [string]: { string } }
	local ids: { [string]: boolean } = {}
	for _, u in units do
		ids[u.id] = true
	end
	local out: { [string]: { string } } = {}
	for _, u in units do
		local seen: { [string]: boolean } = {}
		local deps: { string } = out[u.id] or {}
		for _, w in u.waitsOn do
			if ids[w] and not seen[w] then
				seen[w] = true
				table.insert(deps, w)
			end
		end
		out[u.id] = deps
	end
	return out
end

-- Every id reachable from `start` over `edges` (not `start` itself unless an edge path returns to it). Depth first
-- over a seen set, so a cycle ends.
local function reach(start: string, edges: { [string]: { string } }): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	local function visit(id: string)
		for _, next in edges[id] or {} do
			if not seen[next] then
				seen[next] = true
				visit(next)
			end
		end
	end
	visit(start)
	return seen
end

-- Band 0 for a unit that waits on nothing; else 1 + the highest band it waits on. A waitsOn id that is not a unit is
-- ignored. Units on or behind a dependency cycle get one past the highest acyclic band (1 when none is acyclic), and
-- the second result lists the ids that sit on a cycle, sorted.
function depgraph.bands(units: { Unit }): ({ [string]: number }, { string })
	local deps = known(units)
	local band: { [string]: number } = {}
	local highest = 0
	for _ = 1, #units + 1 do
		local progressed = false
		for _, u in units do
			if band[u.id] ~= nil then
				continue
			end
			local top, ready = -1, true
			for _, d in deps[u.id] do
				local b = band[d]
				if b == nil then
					ready = false
					break
				end
				top = math.max(top, b)
			end
			if ready then
				band[u.id] = top + 1
				highest = math.max(highest, top + 1)
				progressed = true
			end
		end
		if not progressed then
			break
		end
	end
	local cyclic: { string } = {}
	for _, u in units do
		if band[u.id] == nil then
			band[u.id] = highest + 1
			if reach(u.id, deps)[u.id] then
				table.insert(cyclic, u.id)
			end
		end
	end
	table.sort(cyclic)
	return band, cyclic
end

-- For each unit, the number of distinct units downstream of it (its dependents, theirs, and so on), itself not counted.
function depgraph.unblocks(units: { Unit }): { [string]: number }
	local deps = known(units)
	local dependents: { [string]: { string } } = {}
	for _, u in units do
		dependents[u.id] = dependents[u.id] or {}
	end
	for id, list in deps do
		for _, d in list do
			table.insert(dependents[d], id)
		end
	end
	local out: { [string]: number } = {}
	for _, u in units do
		local seen = reach(u.id, dependents)
		seen[u.id] = nil
		local n = 0
		for _ in seen do
			n += 1
		end
		out[u.id] = n
	end
	return out
end

-- The ids by unblocks count, highest first, ties by id ascending (a missing count is 0). The input is not changed.
function depgraph.order(ids: { string }, unblocks: { [string]: number }): { string }
	local out = table.clone(ids)
	table.sort(out, function(a: string, b: string): boolean
		local x, y = unblocks[a] or 0, unblocks[b] or 0
		if x ~= y then
			return x > y
		end
		return a < b
	end)
	return out
end

return depgraph
