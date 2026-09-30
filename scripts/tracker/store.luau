--!strict
-- Tracker storage: locating items, reading/writing their documents, allocating IDs.
-- Layout: tracker/{issues,rafts}/[active/|done/]<ID>/<ID>.md (+ check.sh, spend.md, reviews)
local fs = require("@lune/fs")

export type State = string -- "backlog" | "active" | "done"
export type Kind = string -- "issue" | "raft"
export type Item = {
	id: string,
	kind: Kind,
	state: State,
	dir: string, -- repo-relative directory
	doc: string, -- repo-relative path of <ID>.md
	slug: string,
}

local store = {}

store.ROOT = "tracker"
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

function store.kindDir(kind: Kind): string
	return if kind == "raft" then `{store.ROOT}/rafts` else `{store.ROOT}/issues`
end

function store.dirFor(kind: Kind, state: State, id: string): string
	return `{store.kindDir(kind)}/{STATE_DIRS[state]}{id}`
end

local function docIn(dir: string, id: string): string
	local doc = `{dir}/{id}.md`
	if fs.isFile(doc) then
		return doc
	end
	for _, name in fs.readDir(dir) do
		if string.match(name, `^{id}%-.+%.md$`) then
			error(`{dir}: {name} uses the legacy document name; run scripts/tracker.sh migrate`, 0)
		end
	end
	error(`{dir} has no {id}.md`, 0)
end

function store.find(id: string): Item?
	local kind = kindOf(id)
	local dirs: { string } = {}
	for _, state in STATE_ORDER do
		local d = store.dirFor(kind, state, id)
		if fs.isDir(d) then
			table.insert(dirs, d)
		end
	end
	if #dirs > 1 then
		error(`duplicate id {id}: {table.concat(dirs, ", ")}`, 0)
	end
	for _, state in STATE_ORDER do
		local dir = store.dirFor(kind, state, id)
		if fs.isDir(dir) then
			local doc = docIn(dir, id)
			local slug = store.readFront(doc).slug
			if not slug or slug == "" then
				error(`{doc} has no slug: in its frontmatter; add slug: <kebab-case-words>`, 0)
			end
			local item: Item = { id = id, kind = kind, state = state, dir = dir, doc = doc, slug = slug }
			return item
		end
	end
	return nil
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
	for _, state in STATE_ORDER do
		local base = `{store.kindDir(kind)}/{STATE_DIRS[state]}`
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
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Next free number: the next multiple of 10 above the highest number in use.
function store.nextNumber(kind: Kind): number
	local max = 0
	for _, item in store.all(kind) do
		max = math.max(max, tonumber(string.sub(item.id, 2)) :: number)
	end
	return (math.floor(max / 10) + 1) * 10
end

function store.formatId(prefix: string, n: number): string
	return string.format("%s%04d", prefix, n)
end

-- Frontmatter: simple `key: value` lines between leading `---` fences.
function store.readFront(path: string): { [string]: string }
	local text = fs.readFile(path)
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

function store.setFront(path: string, key: string, value: string)
	local text = fs.readFile(path)
	local head, block, rest = string.match(text, "^(%-%-%-\n)(.-\n)(%-%-%-.*)$")
	if not head or not block or not rest then
		error(`{path} has no frontmatter`, 0)
	end
	local pattern = `(\n?){key}:[^\n]*\n`
	local replaced, n = string.gsub("\n" .. block, pattern, `%1{key}: {value}\n`, 1)
	if n == 0 then
		replaced = "\n" .. block .. `{key}: {value}\n`
	end
	fs.writeFile(path, head .. string.sub(replaced, 2) .. rest)
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
