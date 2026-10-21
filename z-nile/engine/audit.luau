--!strict
-- Whole-tree tracker audit: every problem, never just the first. Reads the tree with plain directory listings, so a
-- malformed tree (which store.find refuses) can still be described. See c0880.
local fs = require("@lune/fs")
local ids = require("./ids")
local process = require("@lune/process")
local projects = require("./projects")

export type Level = "error" | "warning"
export type Problem = { level: Level, code: string, path: string, message: string }

local audit = {}

-- The problems `list` (and every store.find caller) cannot get past.
audit.ITEM_CODES = { duplicate = true, ["no-document"] = true, ["legacy-name"] = true, ["no-slug"] = true }

local KINDS = { { dir = "issues", space = "issue" }, { dir = "rafts", space = "raft" } }
local STATES = { "", "active/", "done/" }

local function front(text: string): { [string]: string }
	local out: { [string]: string } = {}
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	if block then
		for line in string.gmatch(block, "[^\n]+") do
			local k, v = string.match(line, "^([%w_]+):%s*(.-)%s*$")
			if k and v then
				out[k] = v
			end
		end
	end
	return out
end

export type Found = { id: string, path: string, kind: string }

-- The project roots of the checkout at `root` (c0114), or the legacy root and the registry's problem.
local function rootsOf(root: string): ({ string }, string?)
	local ok, reg = pcall(projects.load, root)
	if not ok then
		return { projects.LEGACY }, tostring(reg)
	end
	return projects.roots(reg :: projects.Registry), nil
end

-- Every item folder under every project root (relative paths), whatever state it is in. Never throws on a malformed
-- tree.
function audit.scan(root: string): { Found }
	local out: { Found } = {}
	local roots = rootsOf(root)
	for _, base in roots do
		for _, kind in KINDS do
			for _, state in STATES do
				local rel = `{base}/{kind.dir}/{state}`
				local abs = `{root}/{rel}`
				if fs.isDir(abs) then
					for _, name in fs.readDir(abs) do
						if ids.spaceOf(name) and fs.isDir(abs .. name) then
							table.insert(out, { id = name, path = rel .. name, kind = kind.space })
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.path < b.path
	end)
	return out
end

-- The files under `dir` (relative to the checkout at `root`): the tracked ones when `root` is a repository, else every
-- file on disk. Relative paths.
local function filesUnder(root: string, dir: string): { string }
	local out: { string } = {}
	local ok, r = pcall(process.exec, "git", { "ls-files", "--", dir }, { cwd = root })
	if ok and r.ok then
		for line in string.gmatch(r.stdout, "[^\n]+") do
			table.insert(out, line)
		end
		return out
	end
	local function walk(rel: string)
		local abs = `{root}/{rel}`
		if fs.isDir(abs) then
			for _, name in fs.readDir(abs) do
				walk(`{rel}/{name}`)
			end
		elseif fs.isFile(abs) then
			table.insert(out, rel)
		end
	end
	walk(dir)
	return out
end

-- c0120: what a move between roots must never leave or bring back. A retired root holds nothing but the old counter's
-- tombstone (tracker/next); a promoted-spec folder (`<home>/tests/acceptance/<id>`) sits in the home of its item's
-- project, so a branch from before the move that re-adds one at the old place is an error.
function audit.leftovers(root: string, found: { Found }, reg: projects.Registry): { Problem }
	local out: { Problem } = {}
	for _, r in reg.retired do
		for _, f in filesUnder(root, r) do
			if f ~= ids.OLD_FILE then
				table.insert(out, {
					level = "error",
					code = "old-root",
					path = f,
					message = `{r} is a retired root: it holds nothing but {ids.OLD_FILE} (see {projects.FILE})`,
				})
			end
		end
	end
	local homeById: { [string]: string } = {}
	for _, f in found do
		homeById[f.id] = projects.homeOf(reg, f.path)
	end
	for _, p in reg.projects do
		local acc = if p.home == "." then "tests/acceptance" else `{p.home}/tests/acceptance`
		local abs = `{root}/{acc}`
		if fs.isDir(abs) then
			for _, name in fs.readDir(abs) do
				local home = homeById[name]
				if home and home ~= p.home and fs.isDir(`{abs}/{name}`) then
					local want = if home == "." then "tests/acceptance" else `{home}/tests/acceptance`
					table.insert(out, {
						level = "error",
						code = "misplaced-spec",
						path = `{acc}/{name}`,
						message = `{name}'s project keeps its promoted specs in {want}/{name}`,
					})
				end
			end
		end
	end
	return out
end

function audit.run(root: string): { Problem }
	local problems: { Problem } = {}
	local function add(level: Level, code: string, path: string, message: string)
		table.insert(problems, { level = level, code = code, path = path, message = message })
	end
	local _, regProblem = rootsOf(root)
	if regProblem then
		add("error", "registry", projects.FILE, regProblem)
	end
	local found = audit.scan(root)
	local byId: { [string]: { string } } = {}
	local used: { string } = {}
	for _, f in found do
		local key = f.kind .. ":" .. f.id
		byId[key] = byId[key] or {}
		table.insert(byId[key], f.path)
		table.insert(used, f.id)
		if ids.spaceOf(f.id) ~= f.kind then
			add("error", "wrong-kind", f.path, `{f.id} is not a {f.kind} id`)
		end
		local abs = `{root}/{f.path}`
		local doc = `{abs}/{f.id}.md`
		if fs.isFile(doc) then
			local fm = front(fs.readFile(doc))
			if fm.id and fm.id ~= "" and fm.id ~= f.id then
				add("error", "id-mismatch", f.path, `{f.id}.md says id: {fm.id}`)
			end
			if not fm.slug or fm.slug == "" then
				add("error", "no-slug", f.path, `{f.id}.md has no slug:`)
			end
		else
			local legacy = nil
			for _, name in fs.readDir(abs) do
				if string.match(name, `^{f.id}%-.+%.md$`) then
					legacy = name
				end
			end
			if legacy then
				add("error", "legacy-name", f.path, `{legacy} uses the legacy name; run tracker.sh migrate`)
			else
				add("error", "no-document", f.path, `no {f.id}.md`)
			end
		end
	end
	for _, paths in byId do
		if #paths > 1 then
			for _, p in paths do
				local others: { string } = {}
				for _, q in paths do
					if q ~= p then
						table.insert(others, q)
					end
				end
				add("error", "duplicate", p, `the same id is also at {table.concat(others, ", ")}`)
			end
		end
	end
	-- one number, two issue prefixes
	local byNumber: { [number]: { Found } } = {}
	local seen: { [string]: boolean } = {}
	for _, f in found do
		if ids.spaceOf(f.id) == "issue" and f.kind == "issue" and not seen[f.id] then
			seen[f.id] = true
			local n = ids.number(f.id)
			byNumber[n] = byNumber[n] or {}
			table.insert(byNumber[n], f)
		end
	end
	for _, list in byNumber do
		if #list > 1 then
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			local names: { string } = {}
			for _, f in list do
				table.insert(names, f.id)
			end
			add("warning", "shared-number", list[1].path, `one number for {table.concat(names, ", ")}`)
		end
	end
	local okReg, reg = pcall(projects.load, root)
	if okReg then
		for _, p in audit.leftovers(root, found, reg :: projects.Registry) do
			table.insert(problems, p)
		end
	end
	-- The live counter (c0114): z-nile/next once origin has moved it there, and tracker/next before. Both parsing at once
	-- is an error, because an engine from before the move would number from the old one.
	local newPath, oldPath = `{root}/{ids.FILE}`, `{root}/{ids.OLD_FILE}`
	local oldParses = fs.isFile(oldPath) and ids.parse(fs.readFile(oldPath)) ~= nil
	local livePath, liveFile = newPath, ids.FILE
	if fs.isFile(newPath) then
		if oldParses then
			add(
				"error",
				"old-counter",
				ids.OLD_FILE,
				`parses as a counter; it must stay a tombstone (the counter is {ids.FILE})`
			)
		end
	elseif oldParses then
		livePath, liveFile = oldPath, ids.OLD_FILE
		if fs.isFile(`{root}/{projects.FILE}`) then
			add(
				"warning",
				"counter-unmigrated",
				ids.OLD_FILE,
				`is still the counter: the first publish on an origin/main with {projects.FILE} moves it to {ids.FILE}`
			)
		end
	end
	if not fs.isFile(livePath) then
		add("error", "next-missing", ids.FILE, "no counter file: ids fall back to the next multiple of 10")
	else
		local c = ids.parse(fs.readFile(livePath))
		if not c then
			add("error", "next-malformed", liveFile, "expected `issue <n> <phrase>` and `raft <n> <phrase>`")
		else
			-- a counter at or below the highest number in use in its space (a warning: allocation skips used numbers)
			local function behind(space: ids.Space, n: number)
				local high = ids.highest(space, used)
				if high >= n then
					add("warning", "next-behind", liveFile, `{space} counter {n} is not above {high}, in use`)
				end
			end
			behind("issue", c.issue)
			behind("raft", c.raft)
		end
	end
	table.sort(problems, function(a, b)
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.code < b.code
	end)
	return problems
end

function audit.format(p: Problem): string
	return `{p.level} {p.code} {p.path}: {p.message}`
end

function audit.errors(problems: { Problem }): number
	local n = 0
	for _, p in problems do
		if p.level == "error" then
			n += 1
		end
	end
	return n
end

return audit
