--!strict
-- c0284: the provenance the board shows on each item, the same entries `./zn who` prints for it. The board reads the
-- history ONCE per build, not once per item: one `git log --first-parent` over every item folder (parsed once by
-- `trail.parse`, the commits bucketed by item folder, each life cut by `trail.lifeOf` as `trail.read` cuts it), the
-- compaction cuts, one `git log` of the authors' emails, one `git cat-file --batch` for every document change of every
-- life and one `git log -1` per distinct merge commit: a few processes for any number of items (E9: 5.2 s when each
-- item was read alone). The entries come from `who.entries`, the one function `who` calls too.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./projects")
local provenance = require("./provenance")
local trail = require("./trail")
local who = require("./who")

local boardprov = {}

export type Entry = provenance.Entry
-- An item to read: its id, its kind ("issue" or "raft"), its folder as the board reads it, and its spend rows (an
-- issue's ledger; a raft's roll-up names no worker, so a raft has none).
export type Item = { id: string, kind: string, dir: string, spend: { provenance.Spend } }

-- The commits of a log of many items by the item folder they changed (the folder's name is the id). Pure.
function boardprov.bucket(commits: { trail.Commit }): { [string]: { trail.Commit } }
	local out: { [string]: { trail.Commit } } = {}
	for _, c in commits do
		local id = string.match(c.path, "([^/]+)/[^/]+$")
		if id then
			local list = out[id] or {}
			out[id] = list
			table.insert(list, c)
		end
	end
	return out
end

type Read = {
	lives: { [string]: { trail.Commit } },
	marks: { [string]: provenance.Mark },
	people: { [string]: boolean },
	fronts: { [string]: provenance.Front },
}

-- The lives of `items` on the mainline of the checkout `dir`: nil without a registry or a log. An item with no commit
-- there gets none (`who` refuses it as "no history"; the board shows its stored rows alone).
local function readLives(items: { Item }, dir: string): Read?
	local head = who.head(dir)
	local reg = projects.at(head, dir)
	if not reg then
		return nil
	end
	local roots = projects.allRoots(reg)
	local specs: { string } = {}
	for _, r in roots do
		table.insert(specs, `{r}/issues`)
		table.insert(specs, `{r}/rafts`)
	end
	local dirs: { string } = {}
	for _, item in items do
		for _, d in trail.dirs(if item.kind == "raft" then "rafts" else "issues", item.id, roots) do
			table.insert(dirs, d)
		end
	end
	local log = process.exec("git", trail.logArgs(head, specs, true), { cwd = dir })
	if not log.ok then
		return nil
	end
	local commits = trail.parse(log.stdout, dirs, who.want)
	who.sideTrailers(commits, dir)
	local cuts = trail.cuts(head, dir)
	local byId = boardprov.bucket(commits)
	local out: Read = { lives = {}, marks = {}, people = {}, fronts = {} }
	local all: { trail.Commit } = {}
	for _, item in items do
		local life, notes = trail.lifeOf(byId[item.id] or {}, item.id, cuts, who.want)
		if #life > 0 then
			out.lives[item.id] = life
			out.marks[item.id] = who.mark(notes, trail.ambiguous(life))
			for _, c in life do
				table.insert(all, c)
			end
		end
	end
	out.fronts = who.fronts(all, dir)
	out.people = who.people(head, dir)
	return out
end

-- The entries of every item that has any, keyed by id. `dir` is the checkout whose history is read; nil (no git, a
-- shallow clone: the board's `history` is false) leaves the stored rows alone. An item whose `provenance.md` does not
-- parse is named in `problems` and has no entry list; an item with neither history nor a row has none either.
function boardprov.read(items: { Item }, dir: string?, problems: { string }): { [string]: { Entry } }
	local read: Read = { lives = {}, marks = {}, people = {}, fronts = {} }
	if dir then
		read = readLives(items, dir) or read
	end
	local none: provenance.Mark = { note = "", cut = false }
	local out: { [string]: { Entry } } = {}
	for _, item in items do
		local path = `{item.dir}/provenance.md`
		local rows: { provenance.Row } = {}
		local ok = true
		if fs.isFile(path) then
			local parsed, err = provenance.parse(fs.readFile(path))
			if parsed then
				rows = parsed
			else
				ok = false
				table.insert(problems, `{path} does not parse: {err}`)
			end
		end
		if ok then
			local entries = who.entries(
				read.lives[item.id] or {},
				read.people,
				rows,
				item.spend,
				read.fronts,
				read.marks[item.id] or none
			)
			if #entries > 0 then
				out[item.id] = entries
			end
		end
	end
	return out
end

return boardprov
