--!strict
-- z-raft's no-argument policy (c0116): which prepared, raftless issues go into which raft. Pure: the caller reads the
-- tree and hands over plain records, so the same backlog always gives the same plan, whatever order it is read in.
--   * one type per raft, one project per raft, backlog only: a raft that is not prepared in the backlog (new,
--     preparing, active, done) is never folded into, and a `single: true` raft never takes another issue;
--   * defects fold into the lowest open prepared defect raft that still fits under the cap, chores the same way;
--   * features group only when they share a surface (a Touched path that overlaps), as connected components; an
--     issue with no Touched modules overlaps nothing;
--   * a raft that would pass the cap of changed lines (the members' `size:`) starts another; an issue over the cap
--     is a raft by itself and is never split; an issue with no `size:` is skipped and named;
--   * a `solo: true` issue is always a raft by itself (a recorded user decision), and so is an over-cap one.
local raftplan = {}

export type Issue = {
	id: string,
	type: string, -- feature | defect | chore
	root: string, -- the project root it is filed under
	state: string, -- backlog | active | done
	status: string, -- effective status
	design: string?,
	raft: string, -- "" when it has none
	size: number?, -- the designer's estimate of changed lines; nil when missing or not a number
	solo: boolean,
	touched: { string }?,
}
export type Raft = {
	id: string,
	type: string,
	root: string,
	state: string,
	status: string,
	single: boolean,
	members: { string },
}
-- `fold` puts `issues` into the existing `raft`; `new` makes a raft of them (`single` for a solo or over-cap issue)
export type Op = {
	kind: string,
	raft: string?,
	type: string,
	root: string,
	issues: { string },
	single: boolean,
}
export type Skip = { id: string, reason: string }

raftplan.CAP = 1500
local TYPE_ORDER = { feature = 1, defect = 2, chore = 3 }

-- Two paths overlap when they are equal or one is a parent directory of the other, by whole components.
function raftplan.overlaps(a: string, b: string): boolean
	return a == b or string.sub(a, 1, #b + 1) == b .. "/" or string.sub(b, 1, #a + 1) == a .. "/"
end

-- Two Touched lists share a surface when any path of one overlaps any of the other. A missing or empty list shares
-- nothing (unlike `workstreams`, where an issue with none overlaps everything: there it is the safe direction).
function raftplan.touches(a: { string }?, b: { string }?): boolean
	if not a or not b then
		return false
	end
	for _, p in a do
		for _, q in b do
			if raftplan.overlaps(p, q) then
				return true
			end
		end
	end
	return false
end

-- A `size:` value as a number of lines: a positive whole number, else nil.
function raftplan.parseSize(value: string?): number?
	if not value or not string.match(value, "^%d+$") then
		return nil
	end
	local n = tonumber(value) :: number
	return if n > 0 then n else nil
end

local function isCandidate(i: Issue): boolean
	return i.state == "backlog" and i.status == "prepared" and i.design == "ready" and i.raft == ""
end

local function byId<T>(list: { T }, key: (T) -> string): { T }
	local out = table.clone(list)
	table.sort(out, function(a, b)
		return key(a) < key(b)
	end)
	return out
end

type Bin = { op: Op, size: number }

-- Fills `bins` (existing rafts first, lowest id first, then the plan's own new rafts in the order made) with each
-- issue, opening a new bin when none fits under the cap.
local function fill(issues: { Issue }, bins: { Bin }, ops: { Op }, cap: number, kind: string, root: string)
	for _, i in issues do
		local size = i.size :: number
		local placed = false
		for _, b in bins do
			if b.size + size <= cap then
				table.insert(b.op.issues, i.id)
				b.size += size
				placed = true
				break
			end
		end
		if not placed then
			local op: Op =
				{ kind = "new", raft = nil, type = kind, root = root, issues = { i.id }, single = false }
			table.insert(ops, op)
			table.insert(bins, { op = op, size = size })
		end
	end
end

function raftplan.plan(issues: { Issue }, rafts: { Raft }, cap: number?): ({ Op }, { Skip })
	local limit = cap or raftplan.CAP
	local skips: { Skip } = {}
	local sizeOf: { [string]: number } = {}
	for _, i in issues do
		if i.size then
			sizeOf[i.id] = i.size
		end
	end
	-- candidates by project and type
	local groups: { [string]: { Issue } } = {}
	local keys: { string } = {}
	local ops: { Op } = {}
	for _, i in
		byId(issues, function(x: Issue): string
			return x.id
		end)
	do
		if not isCandidate(i) then
			continue
		end
		if i.size == nil then
			table.insert(
				skips,
				{ id = i.id, reason = "no size: (z-design records its estimate of changed lines)" }
			)
			continue
		end
		if not TYPE_ORDER[i.type] then
			table.insert(skips, { id = i.id, reason = `unknown type {i.type}` })
			continue
		end
		if i.solo or (i.size :: number) > limit then
			table.insert(
				ops,
				{ kind = "new", raft = nil, type = i.type, root = i.root, issues = { i.id }, single = true }
			)
			continue
		end
		local key = `{i.root}|{i.type}`
		if not groups[key] then
			groups[key] = {}
			table.insert(keys, key)
		end
		table.insert(groups[key], i)
	end
	-- open rafts that may take more: prepared in the backlog, not single, every member sized
	local sizeless: { [string]: { Skip } } = {}
	local open: { [string]: { Bin } } = {}
	local openRafts: { [string]: { Raft } } = {}
	for _, r in
		byId(rafts, function(x: Raft): string
			return x.id
		end)
	do
		if r.state == "backlog" and r.status == "prepared" and not r.single then
			local key = `{r.root}|{r.type}`
			-- review 001 F3: a member with no size: makes the raft's size unknown, so the cap can't be kept: such a
			-- raft takes nothing without an argument, and the plan says so where it would have been considered
			local size, unknown = 0, nil :: string?
			for _, m in r.members do
				local n = sizeOf[m]
				if n == nil then
					unknown = unknown or m
				else
					size += n
				end
			end
			if unknown then
				sizeless[key] = sizeless[key] or {}
				table.insert(sizeless[key], {
					id = r.id,
					reason = `{unknown} has no size:, so its raft's size is unknown (not folded into)`,
				})
				continue
			end
			open[key] = open[key] or {}
			openRafts[key] = openRafts[key] or {}
			table.insert(open[key], {
				op = { kind = "fold", raft = r.id, type = r.type, root = r.root, issues = {}, single = false },
				size = size,
			})
			table.insert(openRafts[key], r)
		end
	end
	local touchedOf: { [string]: { string }? } = {}
	for _, i in issues do
		touchedOf[i.id] = i.touched
	end
	for _, key in keys do
		local closed: { Skip } = sizeless[key] or {}
		for _, sk in closed do
			table.insert(skips, sk)
		end
		local list = groups[key]
		local root, kind = string.match(key, "^(.*)|(.*)$")
		local bins: { Bin } = open[key] or {}
		if kind ~= "feature" then
			fill(list, bins, ops, limit, kind :: string, root :: string)
			for _, b in bins do
				if b.op.kind == "fold" and #b.op.issues > 0 then
					table.insert(ops, b.op)
				end
			end
			continue
		end
		-- features: connected components over shared surfaces, rafts included
		local rlist: { Raft } = openRafts[key] or {}
		local n = #list + #rlist
		local parent: { number } = {}
		for k = 1, n do
			parent[k] = k
		end
		local function find(k: number): number
			while parent[k] ~= k do
				parent[k] = parent[parent[k]]
				k = parent[k]
			end
			return k
		end
		local function surface(k: number): { { string }? }
			if k <= #list then
				return { list[k].touched }
			end
			local out: { { string }? } = {}
			for _, m in rlist[k - #list].members do
				table.insert(out, touchedOf[m])
			end
			return out
		end
		for a = 1, n do
			for b = a + 1, n do
				local hit = false
				for _, x in surface(a) do
					for _, y in surface(b) do
						if raftplan.touches(x, y) then
							hit = true
						end
					end
				end
				if hit then
					parent[find(a)] = find(b)
				end
			end
		end
		local seen: { [number]: boolean } = {}
		for k = 1, #list do -- components in the order of their lowest issue id
			local c = find(k)
			if seen[c] then
				continue
			end
			seen[c] = true
			local members: { Issue } = {}
			for j = 1, #list do
				if find(j) == c then
					table.insert(members, list[j])
				end
			end
			local cbins: { Bin } = {}
			for j = 1, #rlist do
				if find(#list + j) == c then
					table.insert(cbins, bins[j])
				end
			end
			fill(members, cbins, ops, limit, "feature", root :: string)
			for _, b in cbins do
				if b.op.kind == "fold" and #b.op.issues > 0 then
					table.insert(ops, b.op)
				end
			end
		end
	end
	-- one order for the output: project, type, then the op's first issue
	table.sort(ops, function(a, b)
		if a.root ~= b.root then
			return a.root < b.root
		end
		if a.type ~= b.type then
			return TYPE_ORDER[a.type] < TYPE_ORDER[b.type]
		end
		return a.issues[1] < b.issues[1]
	end)
	return ops, skips
end

-- c0116 (review 002 F1): what z-raft grouped. A raft records, for each prepared member it grouped, a hash of that
-- member's document as it was then (`grouped: [c0013@1a2b3c4d5e6f, …]`), so a redesign landed inside the rafting window
-- is noticed by the carried move and by `ready`. The hash leaves out `status:` and `raft:`, the two lines ready, stop
-- and the rafting PR itself change.
local serde = require("@lune/serde")

-- The commands that carry out a plan, one argument list per op (`fold <R> <ids…>`, `new raft <type> <slug> <ids…>
-- [--single] --project <name>`), a new raft's slug its first issue's, or that slug with `-2`, `-3`, … when a raft in
-- `taken` (every raft's slug, from audit.sluggedLocal: c0135, a slug names one raft) or an earlier op of the plan
-- has it. `projectName` gives a root's project name in the registry. A root it doesn't name refuses the whole
-- plan, so nothing is printed or run (design review 006 F1).
function raftplan.commands(
	ops: { Op },
	slugOf: { [string]: string },
	projectName: (root: string) -> string?,
	taken: { [string]: boolean }?
): ({ { string } }?, string?)
	local runs: { { string } } = {}
	local used: { [string]: boolean } = table.clone(taken or {})
	for _, op in ops do
		local args: { string }
		if op.kind == "fold" then
			args = { "fold", op.raft :: string }
		else
			local base = slugOf[op.issues[1]]
			local slug, n = base, 2
			while used[slug] do
				slug = `{base}-{n}`
				n += 1
			end
			used[slug] = true
			args = { "new", "raft", op.type, slug }
		end
		for _, id in op.issues do
			table.insert(args, id)
		end
		if op.kind == "new" then
			if op.single then
				table.insert(args, "--single")
			end
			local name = projectName(op.root)
			if not name then
				return nil,
					`{op.root} is no project's root in z-nile/projects.toml: raft-plan prints and runs nothing`
			end
			table.insert(args, "--project")
			table.insert(args, name)
		end
		table.insert(runs, args)
	end
	return runs, nil
end

function raftplan.designHash(text: string): string
	local kept: { string } = {}
	local inFront, seen = false, 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if line == "---" and seen < 2 then
			seen += 1
			inFront = seen == 1
			table.insert(kept, line)
		elseif inFront and (string.match(line, "^status:") or string.match(line, "^raft:")) then
			continue
		else
			table.insert(kept, line)
		end
	end
	return string.sub(serde.hash("sha256", table.concat(kept, "\n")), 1, 12)
end

-- c0116 (review 003 F1): the files a member's reviewed design is made of, relative to its folder: its document,
-- `check.sh`, everything under `acceptance/`, and z-design's design-review, design-refute and harvest files. Not
-- `spend.md`, `prompt.md` or `experiments/`, which change for other reasons. The one list of what the record covers.
function raftplan.isDesignFile(rel: string, id: string): boolean
	return rel == `{id}.md`
		or rel == "check.sh"
		or string.sub(rel, 1, #"acceptance/") == "acceptance/"
		or string.match(rel, "^design%-review%-%d+%.md$") ~= nil
		or string.match(rel, "^design%-refute%-%d+%.md$") ~= nil
		or rel == "harvest.md"
end

-- The record of a member: one hash over its design files (`files`: path relative to its folder -> text), sorted by
-- path, each path with its length and bytes; the document is hashed without its `status:` and `raft:` lines.
function raftplan.recordHash(id: string, files: { [string]: string }): string
	local rels: { string } = {}
	for rel in files do
		if raftplan.isDesignFile(rel, id) then
			table.insert(rels, rel)
		end
	end
	table.sort(rels)
	local parts: { string } = {}
	for _, rel in rels do
		local text = if rel == `{id}.md` then raftplan.designHash(files[rel]) else files[rel]
		table.insert(parts, `{rel}\0{#text}\0{text}`)
	end
	return string.sub(serde.hash("sha256", table.concat(parts, "\0")), 1, 12)
end

-- `grouped:`'s value as id -> hash. A malformed entry, or an id twice, is a problem (lesson parsers-refuse-ambiguity).
function raftplan.parseGrouped(value: string?): ({ [string]: string }, string?)
	local out: { [string]: string } = {}
	if not value or value == "" then
		return out, nil
	end
	local inner = string.match(value, "^%[(.*)%]$")
	if not inner then
		return out, `grouped: is not a list: {value}`
	end
	for entry in string.gmatch(inner, "[^,]+") do
		local e = (string.gsub(entry, "^%s*(.-)%s*$", "%1"))
		if e ~= "" then
			local id, hash = string.match(e, "^([fdc]%d%d%d%d)@(%x+)$")
			if not id then
				return out, `grouped: entry is not <id>@<hash>: {e}`
			end
			if out[id :: string] then
				return out, `grouped: names {id} twice`
			end
			out[id :: string] = hash :: string
		end
	end
	return out, nil
end

function raftplan.renderGrouped(map: { [string]: string }): string
	local ids: { string } = {}
	for id in map do
		table.insert(ids, id)
	end
	table.sort(ids)
	local parts: { string } = {}
	for _, id in ids do
		table.insert(parts, `{id}@{map[id]}`)
	end
	return `[{table.concat(parts, ", ")}]`
end

return raftplan
