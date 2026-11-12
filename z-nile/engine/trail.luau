--!strict
-- An item's trail (c0111, c0119): the commits that touched an item's files under its current id, read with
-- --no-renames so a similar file of another item never stands in for it. Identity is never inferred, and an id change
-- is never followed (the user's decision on R0042 design review 013):
-- - an item's life starts the last time its document went from absent in all of the id's folders to present (a reused
--   number is a new life; a move or a rename in one folder is not);
-- - a commit that changed the compaction map (tracker/compaction.txt, z-nile/compaction.txt since c0114) and the
--   item's document also starts its life, and `read` returns a note so `capture` marks that the history before it is
--   not followed. Moving the map (c0114) is not a compaction.
-- An item's folders are its three state folders under every project root that ever held items (c0114): an id is
-- unique across roots, so a move between roots is a move like any other, never a new life.
-- Everything here is pure over texts except `read`, which runs git and only reads.
local process = require("@lune/process")

local ids = require("./ids")
local projects = require("./projects")

local trail = {}

-- a commit that changed the compaction map, and the map file it changed
export type Cut = { sha: string, file: string }

-- `doc` is true for the item's document (`isDoc`); `id` is set by `read` to the item's current id (no id change is
-- followed)
export type Commit = {
	sha: string,
	time: number,
	subject: string,
	status: string,
	path: string,
	order: number,
	doc: boolean,
	id: string?,
}

local FOLDERS = { "", "active/", "done/" }

-- The folders an item with this id can have lived in: its three state folders under each of `roots` (no default: a
-- caller without roots gets none, never a guessed root, c0114).
function trail.dirs(kind: string, id: string, roots: { string }): { string }
	local out = {}
	local within: { string } = roots
	for _, r in within do
		for _, f in FOLDERS do
			table.insert(out, `{r}/{kind}/{f}{id}`)
		end
	end
	return out
end

-- An item's document: a Markdown file directly in its folder that is not a review, refute, ledger or prompt file.
-- A legacy document named by its slug counts too.
function trail.isDoc(name: string): boolean
	if string.sub(name, -3) ~= ".md" or string.find(name, "/", 1, true) then
		return false
	end
	if
		name == "spend.md"
		or name == "harvest.md"
		or name == "prompt.md"
		or name == "trace.md"
		or name == "provenance.md"
	then
		return false
	end
	for _, pattern in
		{
			"^design%-review%-%d+%.md$",
			"^review%-%d+%.md$",
			"^final%-review%-%d+%.md$",
			"^design%-refute%-%d+%.md$",
			"^refute%-%d+%.md$",
			"^final%-refute%-%d+%.md$",
		}
	do
		if string.match(name, pattern) then
			return false
		end
	end
	return string.match(name, "^stream%-") == nil
end

-- Parses `git log --no-renames --format=@@%H %ct %s --name-status`, keeping the changes to a file directly in one
-- of `dirs` that `want` accepts by name. `order` counts from 1 in the log's own order (newest first).
function trail.parse(log: string, dirs: { string }, want: (name: string) -> boolean): { Commit }
	local inDir: { [string]: boolean } = {}
	for _, d in dirs do
		inDir[d] = true
	end
	local out: { Commit } = {}
	local sha, time, subject = "", 0, ""
	local n = 0
	for line in string.gmatch(log, "[^\n]+") do
		local s, t, subj = string.match(line, "^@@(%x+) (%d+) ?(.*)$")
		if s then
			sha, time, subject = s, tonumber(t) :: number, subj :: string
		else
			local status, path = string.match(line, "^(%u)%d*\t([^\t]+)$")
			local dir, name = string.match(path or "", "^(.+)/([^/]+)$")
			if status and dir and inDir[dir] and want(name :: string) then
				n += 1
				table.insert(out, {
					sha = sha,
					time = time,
					subject = subject,
					status = status,
					path = path :: string,
					order = n,
					doc = trail.isDoc(name :: string),
				})
			end
		end
	end
	return out
end

local function newestFirst(commits: { Commit }): { Commit }
	local sorted = table.clone(commits)
	table.sort(sorted, function(a, b)
		if a.time ~= b.time then
			return a.time > b.time
		end
		return a.order < b.order
	end)
	return sorted
end

-- Walks `commits` oldest first, one commit at a time, applying its document deletions and additions (per id) as one
-- change, and calls `step(group, before, after, dirs)`: the documents present before and after that commit, and the
-- distinct folders holding one after it.
local function walk(
	commits: { Commit },
	step: (group: { Commit }, before: number, after: number, dirs: number) -> ()
)
	local sorted = newestFirst(commits)
	local present: { [string]: { [string]: boolean } } = {}
	local i = #sorted
	while i >= 1 do
		local sha = sorted[i].sha
		local group: { Commit } = {}
		while i >= 1 and sorted[i].sha == sha do
			table.insert(group, sorted[i])
			i -= 1
		end
		local before: { [string]: number } = {}
		for _, pass in { "D", "A" } do
			for _, c in group do
				if c.doc and c.status == pass then
					local key = c.id or ""
					local set: { [string]: boolean } = present[key] or {}
					present[key] = set
					if before[key] == nil then
						local n = 0
						for _ in set do
							n += 1
						end
						before[key] = n
					end
					set[c.path] = if pass == "A" then true else nil :: any
				end
			end
		end
		for key, b in before do
			local n, folders, k = 0, {} :: { [string]: boolean }, 0
			for path in present[key] :: { [string]: boolean } do
				n += 1
				local dir = string.match(path, "^(.+)/[^/]+$") :: string
				if not folders[dir] then
					folders[dir] = true
					k += 1
				end
			end
			step(group, b, n, k)
		end
	end
end

-- The last life of one id's commits, newest first: the commits from the last commit whose document changes took the id
-- from no document to one, and that commit. Without any document change: every commit, and nil.
function trail.life(commits: { Commit }): ({ Commit }, Commit?)
	local start: Commit? = nil
	walk(commits, function(group, before, after)
		if before == 0 and after > 0 then
			start = group[1]
		end
	end)
	local sorted = newestFirst(commits)
	if not start then
		return sorted, nil
	end
	local s = start :: Commit
	local out: { Commit } = {}
	for _, c in sorted do
		table.insert(out, c)
		if c.sha == s.sha then
			-- the rest of this commit's changes, then stop
			for _, d in sorted do
				if d.sha == s.sha and not table.find(out, d) then
					table.insert(out, d)
				end
			end
			break
		end
	end
	return out, s
end

-- Narrows a life (newest first) to start at its newest commit `starts` accepts, when that is newer than `start`.
function trail.since(lived: { Commit }, start: Commit?, starts: (c: Commit) -> boolean): ({ Commit }, Commit?)
	for i, c in lived do
		if starts(c) then
			if start and c.sha == (start :: Commit).sha then
				return lived, start
			end
			local out: { Commit } = {}
			for j = 1, #lived do
				if j <= i or lived[j].sha == c.sha then
					table.insert(out, lived[j])
				end
			end
			return out, c
		end
	end
	return lived, start
end

-- True when two items held the id at once: after some commit, documents existed in two of the id's folders (two
-- copies, the case `renumber <directory>` resolves). A move or a rename within one folder never counts.
function trail.ambiguous(commits: { Commit }): boolean
	local found = false
	walk(commits, function(_, _, _, dirs)
		if dirs > 1 then
			found = true
		end
	end)
	return found
end

-- The earliest commit that added one of the files, or nil.
function trail.oldestAdd(commits: { Commit }): Commit?
	local sorted = newestFirst(commits)
	for i = #sorted, 1, -1 do
		if sorted[i].status == "A" then
			return sorted[i]
		end
	end
	return nil
end

-- The ids a subject names after `tracker: new `: the leading run of ids (a trailing `,` or `;` dropped). `tracker: new
-- raft R0010 r` names none, and neither does a range like `c0810–c0850`.
function trail.namedIds(subject: string): { string }
	local out: { string } = {}
	local rest = string.match(subject, "^tracker: new (.*)$")
	if not rest then
		return out
	end
	for word in string.gmatch(rest, "%S+") do
		local id = string.match(word, "^([fdcR]%d%d%d%d)[,;]?$")
		if not id then
			break
		end
		table.insert(out, id)
	end
	return out
end

-- The capture: the newest commit, not a deletion, whose subject is `tracker: new` with the commit's `id` (the item's
-- current id) in its leading id list (z-ticket's landing commit and the stub's publish), or, when none is, the
-- earliest add (or, with none, the earliest commit). The second result says whether the commit is a capture commit
-- (false: the fallback).
function trail.capture(commits: { Commit }): (Commit?, boolean)
	for _, c in newestFirst(commits) do
		if c.status ~= "D" and c.id ~= nil and table.find(trail.namedIds(c.subject), c.id :: string) then
			return c, true
		end
	end
	local sorted = newestFirst(commits)
	return trail.oldestAdd(commits) or sorted[#sorted], false
end

local function git(args: { string }): string?
	local r = process.exec("git", args)
	return if r.ok then r.stdout else nil
end

local function changes(
	args: { string },
	dirs: { string },
	want: (name: string) -> boolean,
	id: string
): { Commit }
	local argv = table.clone(args)
	for _, a in { "--no-renames", "--format=@@%H %ct %s", "--name-status", "--" } do
		table.insert(argv, a)
	end
	for _, d in dirs do
		table.insert(argv, d)
	end
	local out = trail.parse(git(argv) or "", dirs, want)
	for _, c in out do
		c.id = id
	end
	return out
end

-- The commits on `head` that changed a compaction map's content: added or modified, never only moved (`-M`, so the
-- c0114 move of tracker/compaction.txt to z-nile/compaction.txt is a rename and no cut), each with the file it changed.
function trail.cuts(head: string): { [string]: string }
	local args = { "log", "-M", "--diff-filter=AM", "--format=@@%H", "--name-only", head, "--" }
	for _, f in ids.MAP_FILES do
		table.insert(args, f)
	end
	local out: { [string]: string } = {}
	local sha = ""
	for line in string.gmatch(git(args) or "", "[^\n]+") do
		local s = string.match(line, "^@@(%x+)$")
		if s then
			sha = s
		elseif sha ~= "" and not out[sha] then
			out[sha] = line
		end
	end
	return out
end

-- The item's commits on `head` under `id` that touch files `want` accepts, newest first: its last life, where a life
-- starts at the item's last appearance (`life`) or at a later commit that changed a compaction map and its document
-- (`since`). The second result lists such a start: its short sha and the map file it changed. The item's folders are
-- under every root of `roots`, by default every root `head`'s registry names, retired ones included. Nil without git,
-- `head`, or a registry that parses.
function trail.read(
	kind: string,
	id: string,
	want: (name: string) -> boolean,
	head: string,
	roots: { string }?
): ({ Commit }?, { Cut })
	local notes: { Cut } = {}
	if not git({ "rev-parse", "--verify", "-q", head }) then
		return nil, notes
	end
	local within = roots
	if not within then
		local reg = projects.at(head)
		if not reg then
			return nil, notes
		end
		within = projects.allRoots(reg)
	end
	local cuts = trail.cuts(head)
	local function keep(name: string): boolean
		return trail.isDoc(name) or want(name)
	end
	local lived, start =
		trail.life(changes({ "log", head }, trail.dirs(kind, id, within :: { string }), keep, id))
	lived, start = trail.since(lived, start, function(c: Commit): boolean
		return c.doc and cuts[c.sha] ~= nil
	end)
	if start and cuts[start.sha] then
		table.insert(notes, { sha = string.sub(start.sha, 1, 7), file = cuts[start.sha] })
	end
	local out: { Commit } = {}
	for _, c in lived do
		if want(string.match(c.path, "[^/]+$") :: string) then
			table.insert(out, c)
		end
	end
	return out, notes
end

return trail
