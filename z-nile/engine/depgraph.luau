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
		local list = edges[id]
		if list then
			for _, n in list do
				if not seen[n] then
					seen[n] = true
					visit(n)
				end
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

-- f0420: what the units are, from plain nodes the caller has made out of its own facts (the board's rafts and issues, the
-- worker's RaftFact and IssueFact). A raft waits on the open raft of each of its members' dependencies that sits in a
-- raft of its own, or on that dependency itself when it is in no raft. A raftless issue waits the same way. A done raft
-- and a done issue are no units, and a wait on one is over. A dependency that is not among `issues` has landed.
export type RaftNode = {
	id: string,
	done: boolean,
	issues: { string },
	dependsOn: { string },
	after: { string }?, -- other rafts this one waits on whatever its tickets say (built on an unlanded raft)
}
export type IssueNode = { id: string, raft: string?, done: boolean, dependsOn: { string } }

local function sortedKeys(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for k in set do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- Open rafts first, in the order given, then open raftless issues in the order given; each `waitsOn` sorted.
function depgraph.units(rafts: { RaftNode }, issues: { IssueNode }): { Unit }
	local raftById: { [string]: RaftNode } = {}
	local ownerOf: { [string]: string } = {}
	for _, r in rafts do
		raftById[r.id] = r
		for _, m in r.issues do
			ownerOf[m] = r.id
		end
	end
	local issueById: { [string]: IssueNode } = {}
	for _, i in issues do
		issueById[i.id] = i
	end
	local function raftOf(issue: IssueNode): RaftNode?
		local id = if issue.raft ~= nil and issue.raft ~= "" then issue.raft else ownerOf[issue.id]
		return if id then raftById[id] else nil
	end
	local units: { Unit } = {}
	for _, r in rafts do
		if r.done then
			continue
		end
		local waits: { [string]: boolean } = {}
		for _, dep in r.dependsOn do
			local target = issueById[dep]
			if not target then
				continue
			end
			local owner = raftOf(target)
			if owner then
				if owner.id ~= r.id and not owner.done then
					waits[owner.id] = true
				end
			elseif not target.done then
				waits[target.id] = true
			end
		end
		for _, id in (r.after or {}) :: { string } do
			local other = raftById[id]
			if other and other.id ~= r.id and not other.done then
				waits[other.id] = true
			end
		end
		table.insert(units, { id = r.id, waitsOn = sortedKeys(waits) })
	end
	for _, i in issues do
		if raftOf(i) ~= nil or i.done then
			continue
		end
		local waits: { [string]: boolean } = {}
		for _, dep in i.dependsOn do
			local target = issueById[dep]
			if target and not target.done and dep ~= i.id then
				local owner = raftOf(target)
				if owner == nil then
					waits[dep] = true
				elseif not owner.done then
					waits[owner.id] = true
				end
			end
		end
		table.insert(units, { id = i.id, waitsOn = sortedKeys(waits) })
	end
	return units
end

-- `start` and every unit it waits on, directly or not, sorted. Depth first over a seen set, so a cycle ends.
function depgraph.closure(units: { Unit }, start: string): { string }
	local deps = known(units)
	if deps[start] == nil then
		return {}
	end
	local seen = reach(start, deps)
	seen[start] = true
	return sortedKeys(seen)
end

return depgraph
