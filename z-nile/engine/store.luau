--!strict
-- Tracker storage: locating items, reading/writing their documents, allocating IDs.
-- Layout: <root>/{issues,rafts}/[active/|done/]<ID>/<ID>.md (+ check.sh, spend.md, reviews), for every project root in
-- z-nile/projects.toml (c0114). An id is unique across every root: one counter numbers them all.
local fs = require("@lune/fs")
local projects = require("./projects")
local statusLib = require("./status")

export type State = string -- "backlog" | "active" | "done"
export type Kind = string -- "issue" | "raft"
export type Item = {
	id: string,
	kind: Kind,
	state: State,
	dir: string, -- repo-relative directory
	doc: string, -- repo-relative path of <ID>.md
	slug: string,
	root: string, -- the project root holding it (z-nile/.tracker, tracker, ...)
}

local store = {}

store.TYPES = { f = "feature", d = "defect", c = "chore" } :: { [string]: string }
store.PREFIX = { feature = "f", defect = "d", chore = "c" } :: { [string]: string }
local STATE_DIRS: { [State]: string } = { backlog = "", active = "active/", done = "done/" }
local STATE_ORDER: { State } = { "backlog", "active", "done" }

function store.isIssueId(id: string): boolean
	return string.match(id, "^[fdc]%d%d%d%d$") ~= nil
end

function store.isRaftId(id: string): boolean
	return string.match(id, "^R%d%d%d%d$") ~= nil
end

local function kindOf(id: string): Kind
	if store.isRaftId(id) then
		return "raft"
	elseif store.isIssueId(id) then
		return "issue"
	end
	error(`not a tracker id: {id} (expected f0010, d0020, c0030 or R0010)`, 0)
end

-- The working tree's project roots, in registry order.
function store.roots(): { string }
	return projects.roots(projects.load())
end

function store.kindDir(kind: Kind, root: string): string
	return if kind == "raft" then `{root}/rafts` else `{root}/issues`
end

function store.dirFor(kind: Kind, state: State, id: string, root: string): string
	return `{store.kindDir(kind, root)}/{STATE_DIRS[state]}{id}`
end

local function docIn(dir: string, id: string): string
	local doc = `{dir}/{id}.md`
	if fs.isFile(doc) then
		return doc
	end
	for _, name in fs.readDir(dir) do
		if string.match(name, `^{id}%-.+%.md$`) then
			error(`{dir}: {name} uses the legacy document name; run ./zn migrate`, 0)
		end
	end
	error(`{dir} has no {id}.md`, 0)
end

-- The item with this id in any project root. One id in two folders, in one root or in two, is an error.
function store.find(id: string): Item?
	local kind = kindOf(id)
	local found: { { dir: string, state: State, root: string } } = {}
	for _, root in store.roots() do
		for _, state in STATE_ORDER do
			local d = store.dirFor(kind, state, id, root)
			if fs.isDir(d) then
				table.insert(found, { dir = d, state = state, root = root })
			end
		end
	end
	if #found > 1 then
		local dirs: { string } = {}
		for _, f in found do
			table.insert(dirs, f.dir)
		end
		error(`duplicate id {id}: {table.concat(dirs, ", ")}`, 0)
	end
	local f = found[1]
	if not f then
		return nil
	end
	local doc = docIn(f.dir, id)
	local slug = store.readFront(doc).slug
	if not slug or slug == "" then
		error(`{doc} has no slug: in its frontmatter; add slug: <kebab-case-words>`, 0)
	end
	local item: Item =
		{ id = id, kind = kind, state = f.state, dir = f.dir, doc = doc, slug = slug, root = f.root }
	return item
end

function store.get(id: string): Item
	local item = store.find(id)
	if not item then
		error(`no such tracker item: {id}`, 0)
	end
	return item
end

function store.all(kind: Kind): { Item }
	local out: { Item } = {}
	for _, root in store.roots() do
		for _, state in STATE_ORDER do
			local base = `{store.kindDir(kind, root)}/{STATE_DIRS[state]}`
			if fs.isDir(base) then
				for _, name in fs.readDir(base) do
					local isId = if kind == "raft" then store.isRaftId(name) else store.isIssueId(name)
					if isId and fs.isDir(base .. name) then
						local item = store.find(name)
						if item then
							table.insert(out, item)
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Next free number: the next multiple of 10 above the highest number in use.
-- The next number for `kind` above every local id and every id in `extra` (origin's, when known).
function store.nextNumber(kind: Kind, extra: { string }?): number
	local ids: { string } = table.clone(extra or {})
	for _, item in store.all(kind) do
		table.insert(ids, item.id)
	end
	return statusLib.nextNumber(ids)
end

-- Number-space rule for `renumber`: one above the highest number of `kind` in the local tree (read through
-- `store.all`, so it fails like `tracker.sh list` on a malformed tree) and in `otherIds` (ids seen elsewhere,
-- such as origin/main). Ids of the other kind are ignored.
function store.nextAbove(kind: Kind, otherIds: { string }): number
	local max = 0
	for _, item in store.all(kind) do
		max = math.max(max, tonumber(string.sub(item.id, 2)) :: number)
	end
	for _, id in otherIds do
		local ok = if kind == "raft" then store.isRaftId(id) else store.isIssueId(id)
		if ok then
			max = math.max(max, tonumber(string.sub(id, 2)) :: number)
		end
	end
	return max + 1
end

function store.formatId(prefix: string, n: number): string
	return string.format("%s%04d", prefix, n)
end

-- Frontmatter: simple `key: value` lines between leading `---` fences.
function store.readFront(path: string): { [string]: string }
	return store.parseFront(fs.readFile(path))
end

-- The same over a text (a document read from git).
function store.parseFront(text: string): { [string]: string }
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	local out: { [string]: string } = {}
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

-- `text` with frontmatter key `key` set to `value` (added as the last key when missing), or nil when the text
-- has no frontmatter. Anchored at a line start: a title that mentions `status:` must not absorb the new value.
function store.withFront(text: string, key: string, value: string): string?
	local head, block, rest = string.match(text, "^(%-%-%-\n)(.-\n)(%-%-%-.*)$")
	if not head or not block or not rest then
		return nil
	end
	local replaced, n = string.gsub("\n" .. block, `\n{key}:[^\n]*\n`, function()
		return `\n{key}: {value}\n`
	end, 1)
	if n == 0 then
		replaced = "\n" .. block .. `{key}: {value}\n`
	end
	return head .. string.sub(replaced, 2) .. rest
end

function store.setFront(path: string, key: string, value: string)
	local text = store.withFront(fs.readFile(path), key, value)
	if not text then
		error(`{path} has no frontmatter`, 0)
	end
	fs.writeFile(path, text)
end

function store.typeOf(item: Item): string
	if item.kind == "issue" then
		return store.TYPES[string.sub(item.id, 1, 1)]
	end
	return store.readFront(item.doc).type or "?"
end

-- Issues whose frontmatter `raft:` names this raft.
function store.members(raftId: string): { Item }
	local out: { Item } = {}
	for _, issue in store.all("issue") do
		if store.readFront(issue.doc).raft == raftId then
			table.insert(out, issue)
		end
	end
	return out
end

-- IDs listed in a frontmatter value like "[f0010, f0020]".
function store.idList(value: string?): { string }
	local out: { string } = {}
	for id in string.gmatch(value or "", "[fdcR]%d%d%d%d") do
		table.insert(out, id)
	end
	return out
end

return store
