--!strict
-- State spells and close days from `git log` of item documents. parse is pure; read is the only I/O.
-- A parsed log is cached under .cache keyed by HEAD: ten times today's history parses in 0.78 s, over the 0.5 s budget.
local fs = require("@lune/fs")
local ids = require("./ids")
local process = require("@lune/process")
local projects = require("./projects")
local serde = require("@lune/serde")
local sh = require("../lib/sh")
local stats = require("./stats")

local history = {}

export type Spell = stats.Spell
-- c0118: `doneAt` is the UTC instant, in epoch seconds, of each issue's and raft's first arrival in `done/` in its
-- current life, and `activeAt` its latest arrival in `active/`. A move between roots is no arrival. A compaction (a
-- commit that adds or changes a map's content; moving the map is none) ends the dated life of every id named on either
-- side of a pair in the whole map it leaves (`X Y` with X ~= Y: both X and Y now name another item); its dates start
-- again, and a re-add is no arrival. An id it keeps keeps its dates, even when its document is rewritten. A map line
-- that does not parse (ids.parseMap) ends the life of every item the commit touches, and says so in `warnings`.
-- `closed` and `spells` stay issues only, and unchanged.
export type Parsed = {
	closed: { [string]: string },
	spells: { [string]: { Spell } },
	today: string?,
	doneAt: { [string]: number }?,
	activeAt: { [string]: number }?,
	warnings: { string }?,
}

-- The log of every item document under `roots` (every root that ever held items, c0114). A move between roots is a
-- delete plus an add in one commit, which `apply` reads as no change of state.
function history.logArgs(roots: { string }): { string }
	local args = { "log", "--reverse", "--format=@@C %cI %H", "-p", "--unified=0", "--no-renames", "--" }
	for _, r in roots do
		table.insert(args, `:(glob){r}/issues/**/[fdc][0-9][0-9][0-9][0-9]*.md`)
		table.insert(args, `:(glob){r}/rafts/**/R[0-9][0-9][0-9][0-9]*.md`)
	end
	-- c0118: the compaction maps, so a commit that renumbered every item is known (its adds are no arrival)
	for _, f in ids.MAP_FILES do
		table.insert(args, f)
	end
	return args
end

-- The log of a tree with the legacy root alone.
history.LOG_ARGS = history.logArgs({ projects.LEGACY })

type Area = "backlog" | "active" | "done"
type Touch = { area: Area, added: boolean, deleted: boolean, plus: string? }
type Item = {
	stamp: string?,
	loc: Area?,
	open: Spell?,
	spells: { Spell },
	closed: string?,
	doneAt: number?,
	activeAt: number?,
	dLoc: Area?, -- where the dating sees the document (nil: absent)
	raft: boolean,
	seen: boolean,
}
type File = { path: string, added: boolean, deleted: boolean, plus: string? }

local function stateOf(value: string): string
	return string.match(value, "^([^-]+)") :: string
end

-- id and area for an item document under one of `roots`, legacy `<ID>-<slug>.md` names included. Raft documents
-- count only for `doneAt` (c0118): a retired raft's folder (`rafts/retired/`) is no area.
local function classify(path: string, roots: { string }): (string?, Area?)
	local _, rest = projects.rootOf(path, roots)
	if not rest then
		return nil, nil
	end
	local rid, rfile = string.match(rest, "^rafts/(R%d%d%d%d)/(.+%.md)$")
	if rid and rfile and string.sub(rfile, 1, #rid) == rid then
		return rid, "backlog"
	end
	local rarea, rid2, rfile2 = string.match(rest, "^rafts/([^/]+)/(R%d%d%d%d)/(.+%.md)$")
	if
		rid2
		and rfile2
		and (rarea == "active" or rarea == "done")
		and string.sub(rfile2, 1, #rid2) == rid2
	then
		return rid2, if rarea == "active" then "active" else "done"
	end
	local id, file = string.match(rest, "^issues/([fdc]%d%d%d%d)/(.+%.md)$")
	if id and file and string.sub(file, 1, #id) == id then
		return id, "backlog"
	end
	local area, id2, file2 = string.match(rest, "^issues/([^/]+)/([fdc]%d%d%d%d)/(.+%.md)$")
	if id2 and file2 and (area == "active" or area == "done") and string.sub(file2, 1, #id2) == id2 then
		return id2, if area == "active" then "active" else "done"
	end
	return nil, nil
end

local function endOpen(item: Item, at: string)
	local open = item.open
	if open then
		open.to = at
		item.open = nil
	end
end

local function startSpell(item: Item, state: string, at: string)
	local spell: Spell = { state = state, from = at }
	table.insert(item.spells, spell)
	item.open = spell
end

-- Apply one commit's surviving documents. A move is a delete plus an add (`--no-renames`); only the add remains.
-- `cut`: the commit changed a compaction map, so an item first seen in done/ there arrived under an older id, at an
-- instant this history cannot tell (zz-rules, item history never follows an id change): no doneAt.
local function apply(item: Item, touches: { Touch }, when: string, day: string)
	local add: Touch? = nil
	local modPlus: string? = nil
	for _, touch in touches do
		if touch.added then
			add = touch
		elseif touch.plus then
			modPlus = touch.plus
		end
	end
	if not item.seen then
		if not add then
			return
		elseif add.area == "done" then
			item.closed = day
			item.stamp = add.plus
			item.loc = "done"
			item.seen = true
		else
			item.seen = true
			item.loc = add.area
			item.stamp = add.plus
			if add.plus then
				startSpell(item, add.plus, when)
			end
		end
		return
	end
	if item.closed then
		if add then
			item.loc = add.area
			if add.plus then
				item.stamp = add.plus
			end
		end
		return
	end
	local loc: Area? = if add then add.area else item.loc
	local stamp: string? = if add then add.plus else modPlus
	if loc == "done" then
		-- The re-added file still carries its old status line; that is not a new spell.
		endOpen(item, when)
		item.closed = day
		item.loc = "done"
		if stamp then
			item.stamp = stamp
		end
	elseif stamp and stamp ~= item.stamp then
		endOpen(item, when)
		startSpell(item, stamp, when)
		item.stamp = stamp
		if loc then
			item.loc = loc
		end
	elseif loc == "active" and item.loc ~= "active" then
		endOpen(item, when)
		startSpell(item, "active", when)
		item.loc = "active"
	elseif loc then
		item.loc = loc
	end
end

-- c0118: the dates of one commit's touches of an item. `cut`: the commit is a compaction.
local function date(item: Item, touches: { Touch }, when: string, cut: boolean)
	local add: Touch? = nil
	local deleted = false
	for _, touch in touches do
		if touch.added then
			add = touch
		elseif touch.deleted then
			deleted = true
		end
	end
	local loc: Area? = if add then add.area elseif deleted then nil else item.dLoc
	if cut then -- a compaction gave this id to another item
		item.doneAt, item.activeAt, item.dLoc = nil, nil, loc
		return
	end
	if loc == "done" and item.dLoc ~= "done" and item.doneAt == nil then
		item.doneAt = stats.seconds(when)
	elseif loc == "active" and item.dLoc ~= "active" then
		item.activeAt = stats.seconds(when)
	end
	item.dLoc = loc
end

-- A compaction map's diff in one commit: added, deleted, or changed in place, with its added and removed lines.
type MapDiff = { path: string, added: boolean, deleted: boolean, plus: { string }, minus: { string } }

-- A compaction map's whole text as committed at a commit: `readMap(sha, path)`, nil when it can't be read.
export type ReadMap = (sha: string, path: string) -> string?

-- The ids a compaction's maps give new meaning: both sides of every pair whose sides differ, in the whole map each
-- added or changed map file holds at that commit, read whole (`readMap`, at the commit's own sha and the path the
-- diff names there; `compact` writes the whole map each time, so the diff is not the map), through ids.parseMap; nil
-- when there is no reader, a map can't be read, or a line of it does not parse (then every touched item counts).
local function renamedIds(maps: { MapDiff }, sha: string?, readMap: ReadMap?): { [string]: boolean }?
	local out: { [string]: boolean } = {}
	for _, m in maps do
		if not m.deleted then
			local text = if readMap and sha then readMap(sha, m.path) else nil
			local map = if text then ids.parseMap(text) else nil
			if not map then
				return nil
			end
			for old, new in map do
				if old ~= new then
					out[old] = true
					out[new] = true
				end
			end
		end
	end
	return out
end

-- A commit is a compaction when it changes a map in place, or adds one whose content is not a map it deletes in the
-- same commit (a move, as c0114's, is no compaction: trail.cuts reads it the same way, with renames).
local function isCut(maps: { MapDiff }): boolean
	local gone: { [string]: boolean } = {}
	for _, m in maps do
		if m.deleted then
			gone[table.concat(m.minus, "\n")] = true
		end
	end
	for _, m in maps do
		if m.added then
			if not gone[table.concat(m.plus, "\n")] then
				return true
			end
		elseif not m.deleted then
			return true
		end
	end
	return false
end

-- `roots`: the roots the log covers (default: the legacy `tracker` alone, as history.LOG_ARGS reads). `readMap` reads a
-- compaction map whole at a commit (history.read passes `git show <sha>:<path>`); without it, a compaction undates
-- every item it touches, with a warning.
function history.parse(log: string, roots: { string }?, readMap: ReadMap?): Parsed
	local within = roots or { projects.LEGACY }
	local items: { [string]: Item } = {}
	local pending: { [string]: { Touch } } = {}
	local when: string? = nil
	local day: string? = nil
	local today: string? = nil
	local cur: File? = nil
	local maps: { MapDiff } = {}
	local sha: string? = nil
	local warnings: { string } = {}
	local curMap: MapDiff? = nil
	local isMap: { [string]: boolean } = {}
	for _, f in ids.MAP_FILES do
		isMap[f] = true
	end

	local function flushFile()
		local file = cur
		cur = nil
		if file and isMap[file.path] then
			local m = curMap :: MapDiff
			m.added, m.deleted = file.added, file.deleted
			table.insert(maps, m)
			curMap = nil
			return
		end
		if not file then
			return
		end
		local id, area = classify(file.path, within)
		-- classify's area singleton is widened to string at the boundary; narrow it back.
		if not id or (area ~= "backlog" and area ~= "active" and area ~= "done") then
			return
		end
		local bag = pending[id]
		if not bag then
			bag = {}
			pending[id] = bag
		end
		table.insert(bag, { area = area, added = file.added, deleted = file.deleted, plus = file.plus })
	end

	local function flushCommit()
		flushFile()
		local at, on = when, day
		local cut = isCut(maps)
		local renamed = if cut then renamedIds(maps, sha, readMap) else nil
		if cut and renamed == nil then
			table.insert(
				warnings,
				`{at or "?"}: a compaction map could not be read or a line of it does not parse; every item the commit touches is undated`
			)
		end
		if at and on then
			for id, touches in pending do
				local item = items[id]
				if not item then
					item = { spells = {}, seen = false, raft = string.sub(id, 1, 1) == "R" }
					items[id] = item
				end
				local kept: { Touch } = {}
				for _, touch in touches do
					if not touch.deleted then
						table.insert(kept, touch)
					end
				end
				if #kept > 0 then
					apply(item, kept, at, on)
				end
				date(item, touches, at, cut and (renamed == nil or renamed[id] == true))
			end
		end
		pending = {}
		maps = {}
	end

	for line in string.gmatch(log .. "\n", "(.-)\n") do
		local ts, hash = string.match(line, "^@@C%s+(%S+)%s*(%x*)")
		if ts then
			flushCommit()
			when = ts
			sha = if hash and hash ~= "" then hash else nil
			day = string.sub(ts, 1, 10)
			today = day
		elseif when then
			local path = string.match(line, "^diff %-%-git a/.- b/(.+)$")
			if path then
				flushFile()
				cur = { path = path, added = false, deleted = false, plus = nil }
				curMap = if isMap[path]
					then { path = path, added = false, deleted = false, plus = {}, minus = {} }
					else nil
			elseif cur then
				if string.sub(line, 1, 13) == "new file mode" or line == "--- /dev/null" then
					cur.added = true
				elseif string.sub(line, 1, 17) == "deleted file mode" or line == "+++ /dev/null" then
					cur.deleted = true
				elseif curMap then
					local m = curMap :: MapDiff
					local c1 = string.sub(line, 1, 1)
					if c1 == "+" and string.sub(line, 1, 4) ~= "+++ " then
						table.insert(m.plus, string.sub(line, 2))
					elseif c1 == "-" and string.sub(line, 1, 4) ~= "--- " then
						table.insert(m.minus, string.sub(line, 2))
					end
				elseif not cur.plus then
					local plus = string.match(line, "^%+status:%s*(%S+)")
					if plus then
						cur.plus = stateOf(plus)
					end
				end
			end
		end
	end
	flushCommit()

	local closed: { [string]: string } = {}
	local spells: { [string]: { Spell } } = {}
	local doneAt: { [string]: number } = {}
	local activeAt: { [string]: number } = {}
	for id, item in items do
		if item.doneAt then
			doneAt[id] = item.doneAt
		end
		if item.activeAt then
			activeAt[id] = item.activeAt
		end
		if item.raft then
			continue
		end
		if item.closed then
			closed[id] = item.closed
		end
		spells[id] = item.spells
	end
	return {
		closed = closed,
		spells = spells,
		today = today,
		doneAt = doneAt,
		activeAt = activeAt,
		warnings = warnings,
	}
end

local function physical(path: string): string?
	local r = process.exec("pwd", { "-P" }, { cwd = path })
	if not r.ok then
		return nil
	end
	return sh.trim(r.stdout)
end

-- The cache file, or nil when its parent folder is absent (history never creates .cache).
local function cacheFile(dir: string): string?
	local path = `{dir}/.cache/tracker-history.json`
	local parent = string.match(path, "^(.*)/[^/]+$")
	if not parent or not fs.isDir(parent) then
		return nil
	end
	return path
end

local function loadCache(path: string, sha: string): Parsed?
	local readOk, text = pcall(fs.readFile, path)
	if not readOk or type(text) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(serde.decode, "json" :: "json", text)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local body = decoded :: { sha: string?, parsed: Parsed? }
	if body.sha ~= sha or type(body.parsed) ~= "table" then
		return nil
	end
	local parsed = body.parsed :: Parsed
	if type(parsed.closed) ~= "table" or type(parsed.spells) ~= "table" then
		return nil
	end
	return parsed
end

local function storeCache(path: string, sha: string, parsed: Parsed)
	local ok, payload = pcall(serde.encode, "json" :: "json", { sha = sha, parsed = parsed })
	if ok then
		pcall(sh.writeReplacing, path, payload :: string)
	end
end

-- nil when `root` has no git, is not the top of its own repository, or that repository is shallow.
-- Whether `dir` is the top level of its own git repository (c0284: the board reads the history of such a folder only,
-- never of the repository a fixture folder happens to sit in).
function history.atTop(dir: string): boolean
	local top = process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = dir })
	if not top.ok then
		return false
	end
	local topPhys = physical(sh.trim(top.stdout))
	local rootPhys = physical(dir)
	return topPhys ~= nil and rootPhys ~= nil and topPhys == rootPhys
end

function history.read(root: string?): Parsed?
	local dir = root or "."
	if not history.atTop(dir) then
		return nil
	end
	local shallow = process.exec("git", { "rev-parse", "--is-shallow-repository" }, { cwd = dir })
	if not shallow.ok or sh.trim(shallow.stdout) == "true" then
		return nil
	end
	local shaRun = process.exec("git", { "rev-parse", "HEAD" }, { cwd = dir })
	if not shaRun.ok then
		return nil
	end
	local ok, reg = pcall(projects.load, dir)
	if not ok then
		return nil
	end
	local roots = projects.allRoots(reg :: projects.Registry)
	-- keyed by HEAD and the roots read, so a cache of another root set is never reused
	local sha = "v7 " .. sh.trim(shaRun.stdout) .. " " .. table.concat(roots, ",") -- v7: doneAt, activeAt, compaction lives from the map read at each compaction (c0118)
	local path = cacheFile(dir)
	if path and fs.isFile(path) then
		local hit = loadCache(path, sha)
		if hit then
			return hit
		end
	end
	local log = process.exec("git", history.logArgs(roots), { cwd = dir })
	if not log.ok then
		return nil
	end
	local parsed = history.parse(sh.trim(log.stdout), roots, function(at: string, mapPath: string): string?
		local shown = process.exec("git", { "show", `{at}:{mapPath}` }, { cwd = dir })
		return if shown.ok then shown.stdout else nil
	end)
	if path then
		storeCache(path, sha, parsed)
	end
	return parsed
end

return history
