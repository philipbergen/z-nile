--!strict
-- The tracker board: reads the tracker tree into a model and renders it as one self-contained HTML page.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local store = require("./store")

local board = {}

export type Tab = "done" | "active" | "waiting"
export type Raft = {
	id: string, -- "R0040", or "none:<tab>" for a No raft entry
	kind: string, -- "raft"
	type: string, -- "feature" | "defect" | "chore" ("" for No raft)
	title: string, -- frontmatter title ("No raft" for the pseudo entries)
	state: string, -- "backlog" | "active" | "done", from the directory ("" for No raft)
	design: string, -- frontmatter design ("" if absent)
	status: string, -- "done" | "active" | "ready" | "reviewed" | "draft" ("" for No raft)
	single: boolean,
	pseudo: boolean, -- true only for No raft entries
	tab: Tab,
	issues: { string }, -- member issue ids, sorted
	dependsOn: { string }, -- raft ids, sorted
	dependents: { string }, -- raft ids, sorted
	blockedBy: { string }, -- unfinished dependencies: raft ids and raftless issue ids, sorted
	topLevel: boolean, -- #blockedBy == 0
	body: string, -- the document after its frontmatter ("" for No raft)
}
export type Issue = {
	id: string,
	kind: string, -- always "issue"
	type: string,
	title: string,
	state: string,
	design: string,
	status: string,
	raft: string?, -- frontmatter raft; nil when empty, absent or naming a raft that does not exist
	dependsOn: { string }, -- frontmatter depends_on ids, sorted, as written (even if they don't exist)
	emergent: boolean,
	body: string,
}
export type Model = {
	rafts: { Raft }, -- real rafts sorted by id, then No raft entries in done, active, waiting order
	issues: { Issue }, -- sorted by id
	tabs: { done: { string }, active: { string }, waiting: { string } },
	home: { [string]: string }, -- every raft and issue id -> the id of the entry whose pane shows it
	initialTab: Tab, -- "active" if tabs.active is non-empty, else "waiting"
}

board.MARKED_PATH = "scripts/vendor/marked.umd.js"
board.MARKED_SHA256 = "21568877a938d2c4e7d74e27f18e60da96bb73a68809610ca39216e1efebae62"
board.TEMPLATE_PATH = "scripts/tracker/board.html"

-- Errors unless the vendored marked is the pinned build.
function board.checkMarked(js: string)
	local got = serde.hash("sha256", js)
	if got ~= board.MARKED_SHA256 then
		error(
			`{board.MARKED_PATH} is not the pinned marked build (sha256 {got}, expected {board.MARKED_SHA256})`,
			0
		)
	end
end

-- marked without its trailing source-map comment, so a browser never fetches marked.umd.js.map.
function board.inlineMarked(js: string): string
	return (string.gsub(js, "\n//# sourceMappingURL=[^\n]*\n?$", "\n"))
end

local TAB_OF_STATE: { [string]: Tab } = { done = "done", active = "active", backlog = "waiting" }
local TAB_ORDER: { Tab } = { "done", "active", "waiting" }
local TYPES: { [string]: boolean } = { feature = true, defect = true, chore = true }

-- Every %w+ run of a frontmatter list like "[f0100, c0090]", sorted.
local function listOf(value: string?): { string }
	local out: { string } = {}
	for id in string.gmatch(value or "", "%w+") do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for k in set do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- The document after its frontmatter, without leading blank lines; a document without frontmatter is all body.
local function bodyOf(text: string): string
	if string.sub(text, 1, 4) ~= "---\n" then
		return text
	end
	local _, closeEnd = string.find(text, "\n%-%-%-[^\n]*", 4)
	if not closeEnd then
		return text
	end
	return (string.gsub(string.sub(text, closeEnd + 1), "^\n+", ""))
end

-- { id, state, front, body } for every item directory of one kind under root.
local function scan(
	root: string,
	kind: string
): { { id: string, state: string, front: { [string]: string }, body: string } }
	local found = {}
	local base = `{root}/{kind}`
	local isId = if kind == "rafts" then store.isRaftId else store.isIssueId
	for _, state in { "backlog", "active", "done" } do
		local dir = if state == "backlog" then base else `{base}/{state}`
		if not fs.isDir(dir) then
			continue
		end
		for _, name in fs.readDir(dir) do
			local doc = `{dir}/{name}/{name}.md`
			if isId(name) and fs.isFile(doc) then
				table.insert(
					found,
					{
						id = name,
						state = state,
						front = store.readFront(doc),
						body = bodyOf(fs.readFile(doc)),
					}
				)
			end
		end
	end
	table.sort(found, function(a, b)
		return a.id < b.id
	end)
	return found
end

local function statusOf(state: string, design: string): string
	if state == "done" or state == "active" then
		return state
	end
	if design == "ready" or design == "reviewed" then
		return design
	end
	return "draft"
end

function board.collect(root: string?): Model
	local base = root or store.ROOT
	local rawRafts, rawIssues = scan(base, "rafts"), scan(base, "issues")

	local raftIds: { [string]: boolean } = {}
	for _, r in rawRafts do
		raftIds[r.id] = true
	end

	local issues: { Issue } = {}
	local issueById: { [string]: Issue } = {}
	for _, i in rawIssues do
		local named = i.front.raft
		local issue: Issue = {
			id = i.id,
			kind = "issue",
			type = if TYPES[i.front.type or ""] then i.front.type else "",
			title = i.front.title or "",
			state = i.state,
			design = i.front.design or "",
			status = statusOf(i.state, i.front.design or ""),
			raft = if named and raftIds[named] then named else nil,
			dependsOn = listOf(i.front.depends_on),
			emergent = i.front.emergent == "true",
			body = i.body,
		}
		table.insert(issues, issue)
		issueById[i.id] = issue
	end

	local members: { [string]: { string } } = {}
	local loose: { [Tab]: { string } } = { done = {}, active = {}, waiting = {} }
	for _, issue in issues do
		if issue.raft then
			members[issue.raft] = members[issue.raft] or {}
			table.insert(members[issue.raft], issue.id)
		else
			table.insert(loose[TAB_OF_STATE[issue.state]], issue.id)
		end
	end

	local rafts: { Raft } = {}
	local raftById: { [string]: Raft } = {}
	for _, r in rawRafts do
		local raft: Raft = {
			id = r.id,
			kind = "raft",
			type = if TYPES[r.front.type or ""] then r.front.type else "",
			title = r.front.title or "",
			state = r.state,
			design = r.front.design or "",
			status = statusOf(r.state, r.front.design or ""),
			single = r.front.single == "true",
			pseudo = false,
			tab = TAB_OF_STATE[r.state],
			issues = members[r.id] or {},
			dependsOn = {},
			dependents = {},
			blockedBy = {},
			topLevel = true,
			body = r.body,
		}
		table.insert(rafts, raft)
		raftById[r.id] = raft
	end

	-- dependencies: raft -> raft through member issues, and raft -> raftless issue (blocks, never a raft dependency)
	local noRaftDependents: { [Tab]: { [string]: boolean } } = { done = {}, active = {}, waiting = {} }
	for _, raft in rafts do
		local deps: { [string]: boolean } = {}
		local blockers: { [string]: boolean } = {}
		for _, id in raft.issues do
			for _, dep in issueById[id].dependsOn do
				local target = issueById[dep]
				if not target then
					continue
				end
				if target.raft then
					if target.raft ~= raft.id then
						deps[target.raft] = true
					end
				else
					noRaftDependents[TAB_OF_STATE[target.state]][raft.id] = true
					if target.status ~= "done" then
						blockers[target.id] = true
					end
				end
			end
		end
		raft.dependsOn = sortedKeys(deps)
		for dep in deps do
			if raftById[dep].status ~= "done" then
				blockers[dep] = true
			end
		end
		raft.blockedBy = sortedKeys(blockers)
		raft.topLevel = #raft.blockedBy == 0
	end
	for _, raft in rafts do
		for _, dep in raft.dependsOn do
			table.insert(raftById[dep].dependents, raft.id)
		end
	end
	for _, raft in rafts do
		table.sort(raft.dependents)
	end

	-- tabs: Done and Active list every raft, Waiting only the top-level ones; each ends with its No raft entry
	local tabs =
		{ done = {}, active = {}, waiting = {} } :: { done: { string }, active: { string }, waiting: { string } }
	local pseudo: { Raft } = {}
	for _, raft in rafts do
		if raft.tab ~= "waiting" or raft.topLevel then
			table.insert(tabs[raft.tab], raft.id)
		end
	end
	local home: { [string]: string } = {}
	for _, raft in rafts do
		home[raft.id] = raft.id
		for _, id in raft.issues do
			home[id] = raft.id
		end
	end
	for _, tab in TAB_ORDER do
		if #loose[tab] == 0 then
			continue
		end
		local entry: Raft = {
			id = `none:{tab}`,
			kind = "raft",
			type = "",
			title = "No raft",
			state = "",
			design = "",
			status = "",
			single = false,
			pseudo = true,
			tab = tab,
			issues = loose[tab],
			dependsOn = {},
			dependents = sortedKeys(noRaftDependents[tab]),
			blockedBy = {},
			topLevel = true,
			body = "",
		}
		table.insert(pseudo, entry)
		table.insert(tabs[tab], entry.id)
		for _, id in entry.issues do
			home[id] = entry.id
		end
	end
	for _, entry in pseudo do
		table.insert(rafts, entry)
	end

	return {
		rafts = rafts,
		issues = issues,
		tabs = tabs,
		home = home,
		initialTab = if #tabs.active > 0 then "active" else "waiting",
	}
end

return board
