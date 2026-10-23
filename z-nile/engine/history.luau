--!strict
-- State spells and close days from `git log` of item documents. parse is pure; read is the only I/O.
-- A parsed log is cached under .cache keyed by HEAD: ten times today's history parses in 0.78 s, over the 0.5 s budget.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./projects")
local serde = require("@lune/serde")
local sh = require("../lib/sh")
local stats = require("./stats")

local history = {}

export type Spell = stats.Spell
export type Parsed = { closed: { [string]: string }, spells: { [string]: { Spell } }, today: string? }

-- The log of every item document under `roots` (every root that ever held items, c0114). A move between roots is a
-- delete plus an add in one commit, which `apply` reads as no change of state.
function history.logArgs(roots: { string }): { string }
	local args = { "log", "--reverse", "--format=@@C %cI", "-p", "--unified=0", "--no-renames", "--" }
	for _, r in roots do
		table.insert(args, `:(glob){r}/issues/**/[fdc][0-9][0-9][0-9][0-9]*.md`)
		table.insert(args, `:(glob){r}/rafts/**/R[0-9][0-9][0-9][0-9]*.md`)
	end
	return args
end

-- The log of a tree with the legacy root alone.
history.LOG_ARGS = history.logArgs({ projects.LEGACY })

type Area = "backlog" | "active" | "done"
type Touch = { area: Area, added: boolean, plus: string? }
type Item = {
	stamp: string?,
	loc: Area?,
	open: Spell?,
	spells: { Spell },
	closed: string?,
	seen: boolean,
}
type File = { path: string, added: boolean, deleted: boolean, plus: string? }

local function stateOf(value: string): string
	return string.match(value, "^([^-]+)") :: string
end

-- id and area for an item document under one of `roots`, legacy `<ID>-<slug>.md` names included. Raft documents are
-- ignored.
local function classify(path: string, roots: { string }): (string?, Area?)
	local _, rest = projects.rootOf(path, roots)
	if not rest then
		return nil, nil
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

-- `roots`: the roots the log covers (default: the legacy `tracker` alone, as history.LOG_ARGS reads).
function history.parse(log: string, roots: { string }?): Parsed
	local within = roots or { projects.LEGACY }
	local items: { [string]: Item } = {}
	local pending: { [string]: { Touch } } = {}
	local when: string? = nil
	local day: string? = nil
	local today: string? = nil
	local cur: File? = nil

	local function flushFile()
		local file = cur
		cur = nil
		if not file or file.deleted then
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
		table.insert(bag, { area = area, added = file.added, plus = file.plus })
	end

	local function flushCommit()
		flushFile()
		local at, on = when, day
		if at and on then
			for id, touches in pending do
				local item = items[id]
				if not item then
					item = { spells = {}, seen = false }
					items[id] = item
				end
				apply(item, touches, at, on)
			end
		end
		pending = {}
	end

	for line in string.gmatch(log .. "\n", "(.-)\n") do
		local ts = string.match(line, "^@@C%s+(%S+)")
		if ts then
			flushCommit()
			when = ts
			day = string.sub(ts, 1, 10)
			today = day
		elseif when then
			local path = string.match(line, "^diff %-%-git a/.- b/(.+)$")
			if path then
				flushFile()
				cur = { path = path, added = false, deleted = false, plus = nil }
			elseif cur then
				if string.sub(line, 1, 13) == "new file mode" or line == "--- /dev/null" then
					cur.added = true
				elseif string.sub(line, 1, 17) == "deleted file mode" or line == "+++ /dev/null" then
					cur.deleted = true
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
	for id, item in items do
		if item.closed then
			closed[id] = item.closed
		end
		spells[id] = item.spells
	end
	return { closed = closed, spells = spells, today = today }
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
function history.read(root: string?): Parsed?
	local dir = root or "."
	local top = process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = dir })
	if not top.ok then
		return nil
	end
	local shallow = process.exec("git", { "rev-parse", "--is-shallow-repository" }, { cwd = dir })
	if not shallow.ok or sh.trim(shallow.stdout) == "true" then
		return nil
	end
	local topPhys = physical(sh.trim(top.stdout))
	local rootPhys = physical(dir)
	if not topPhys or not rootPhys or topPhys ~= rootPhys then
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
	local sha = sh.trim(shaRun.stdout) .. " " .. table.concat(roots, ",")
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
	local parsed = history.parse(sh.trim(log.stdout), roots)
	if path then
		storeCache(path, sha, parsed)
	end
	return parsed
end

return history
