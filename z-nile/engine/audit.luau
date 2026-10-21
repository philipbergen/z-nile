--!strict
-- Whole-tree tracker audit: every problem, never just the first. Reads the tree with plain directory listings, so a
-- malformed tree (which store.find refuses) can still be described. See c0880.
local fs = require("@lune/fs")
local ids = require("./ids")

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

-- Every item folder under tracker/ (relative paths), whatever state it is in. Never throws on a malformed tree.
function audit.scan(root: string): { Found }
	local out: { Found } = {}
	for _, kind in KINDS do
		for _, state in STATES do
			local rel = `tracker/{kind.dir}/{state}`
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
	table.sort(out, function(a, b)
		return a.path < b.path
	end)
	return out
end

function audit.run(root: string): { Problem }
	local problems: { Problem } = {}
	local function add(level: Level, code: string, path: string, message: string)
		table.insert(problems, { level = level, code = code, path = path, message = message })
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
	local nextPath = `{root}/{ids.FILE}`
	if not fs.isFile(nextPath) then
		add("error", "next-missing", ids.FILE, "no counter file: ids fall back to the next multiple of 10")
	else
		local c = ids.parse(fs.readFile(nextPath))
		if not c then
			add("error", "next-malformed", ids.FILE, "expected `issue <n> <phrase>` and `raft <n> <phrase>`")
		else
			-- a counter at or below the highest number in use in its space (a warning: allocation skips used numbers)
			local function behind(space: ids.Space, n: number)
				local high = ids.highest(space, used)
				if high >= n then
					add("warning", "next-behind", ids.FILE, `{space} counter {n} is not above {high}, in use`)
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
