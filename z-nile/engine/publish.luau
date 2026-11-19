--!strict
-- Pushes a tracker-only commit to origin/main with git plumbing (mktree, no index). Never touches the caller's working
-- tree, index, HEAD or branch. See c0510.
local broker = require("./broker")
local closing = require("./closing")
local escalationLib = require("./escalation")
local ids = require("./ids")
local ledger = require("./ledger")
local pathsLib = require("./paths")
local process = require("@lune/process")
local projects = require("./projects")
local provenance = require("./provenance")
local task = require("@lune/task")

local publish = {}

export type Change = { path: string, content: string, mode: string?, from: string? }
export type Result = { ok: boolean, sha: string?, reason: string? }
-- `roots`: origin/main's project roots (its z-nile/projects.toml), the only roots this publish may write under;
-- `counter`: origin/main's live id counter, z-nile/next, or tracker/next while origin/main has no registry (c0114's
-- execution window: the branch has moved the counter, origin has not yet); `base`: the origin/main sha every read
-- names, so a build that greps the tree (close's dependents, c0278) sees the same one
export type Build = (
	paths: { string },
	read: (string) -> string?,
	roots: { string },
	counter: string,
	base: string
) -> { Change } | string

local function isIssue(id: string): boolean
	return string.match(id, "^[fdc]%d%d%d%d$") ~= nil
end

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- The project root at the start of `path` and the rest after it, by shape alone: the legacy `tracker`, or
-- `<name>/.tracker`. Whether the root is registered on origin/main is `allowed`'s question, not this one's.
local function splitRoot(path: string): (string?, string?)
	local rest = string.match(path, "^tracker/(.+)$")
	if rest then
		return "tracker", rest
	end
	local root, more = string.match(path, "^([^/]+/%.tracker)/(.+)$")
	if root and more and projects.shapeOk(root) then
		return root, more
	end
	return nil, nil
end

-- The id, the path relative to the item directory, and the root, of any file inside an item directory,
-- <root>/(issues|rafts)/[active/ | done/]<ID>/<rel>; nil for anything else. `rel` is one or more segments of
-- [%w._-] that are not `.` or `..`.
function publish.itemPath(path: string): (string?, string?, string?)
	if string.sub(path, 1, 1) == "/" then
		return nil, nil, nil
	end
	local root, under = splitRoot(path)
	if not root or not under then
		return nil, nil, nil
	end
	local kind, rest = string.match(under, "^(%a+)/(.+)$")
	if not kind or not rest or (kind ~= "issues" and kind ~= "rafts") then
		return nil, nil, nil
	end
	local stripped: string = string.match(rest, "^active/(.+)$") or string.match(rest, "^done/(.+)$") or rest
	local id, rel = string.match(stripped, "^(%w+)/(.+)$")
	if not id or not rel then
		return nil, nil, nil
	end
	local okId = if kind == "issues"
		then string.match(id, "^[fdc]%d%d%d%d$") ~= nil
		else string.match(id, "^R%d%d%d%d$") ~= nil
	if not okId then
		return nil, nil, nil
	end
	for _, seg in string.split(rel, "/") do
		if seg == "." or seg == ".." or not string.match(seg, "^[%w%._%-]+$") then
			return nil, nil, nil
		end
	end
	return id, rel, root
end

-- The live id counter of a base, from the base alone (never the working tree), and whether this publish moves it there
-- (c0114), for a base that has the registry (publish.commit refuses one without it, so before c0114 lands only the
-- main checkout's older engine numbers, on tracker/next). The branch that lands c0114 never touches the counter;
-- origin moves it once:
-- - the base has z-nile/next: that is the counter;
-- - the base has no z-nile/next, and tracker/next parses (c0114 has just landed): z-nile/next is the counter and
--   `migrate` is true: this publish writes z-nile/next from tracker/next's counters and the tombstone at tracker/next,
--   in its one lease push.
function publish.counterOf(hasNew: boolean, oldText: string?): (string, boolean)
	if hasNew then
		return ids.FILE, false
	end
	return ids.FILE, oldText ~= nil and ids.parse(oldText) ~= nil
end

-- <root>/(issues|rafts)/[active/ | done/]<ID>/(<ID>.md | check.sh), the id's prefix matching the kind, under a root
-- that `roots` (origin/main's registry, never the working tree's; no default, c0114) lists. Also the live counter
-- `counter` (default z-nile/next; publish.counterOf).
function publish.allowed(path: string, roots: { string }, counter: string?, escalation: boolean?): boolean
	local within: { string } = roots
	if path == (counter or ids.FILE) then
		return true
	end
	if path == ids.FILE or path == ids.OLD_FILE then
		return false -- the other counter file: never written
	end
	if string.find(path, "..", 1, true) or string.sub(path, 1, 1) == "/" then
		return false
	end
	local id, rel, root = publish.itemPath(path)
	if not id or not rel or not root or not table.find(within, root) then
		return false
	end
	if string.find(rel, "/", 1, true) then
		return false
	end
	-- an issue's spend.md and an item's provenance.md are published append-only, an issue's approval.md whole; a raft's summary stays on its branch
	return rel == `{id}.md`
		or rel == "check.sh"
		or rel == "provenance.md"
		or (escalation == true and (rel == "escalation.md" or string.match(rel, "^escalation%-%d%d%d%.md$") ~= nil or (not isIssue(
			id
		) and string.match(rel, "^design%-review%-%d%d%d%.md$") ~= nil)))
		or (isIssue(id) and (rel == "spend.md" or rel == "approval.md"))
end

-- The directory of an item file: `path` without its `/<rel>`.
local function itemDir(path: string, rel: string): string
	return string.sub(path, 1, #path - #rel - 1)
end

-- The document with its single `status:` frontmatter line removed, or nil when it has no well-formed
-- frontmatter. A published edit of an existing document may differ from origin's only in that line, or be exactly a
-- close (`closing.guard`, c0278).
-- `escalation` (c0250: a `blocked` or `resolve` commit) also drops the `blocked:`, `design:`, `raft:` and `issues:`
-- lines, and the Decided and Scope decision lines a resolve adds to the Problem.
local ESCALATION_KEYS = { "status", "blocked", "design", "raft", "issues", "grouped", "retired" }

local function withoutStatus(text: string, escalation: boolean?): string?
	local head, block, rest = string.match(text, "^(%-%-%-\n)(.-\n)(%-%-%-\n.*)$")
	if not head or not block or not rest then
		return nil
	end
	local kept = "\n" .. block
	local keys: { string } = if escalation then ESCALATION_KEYS else { "status" }
	for _, key in keys do
		local lines = 0
		kept = string.gsub(kept, `\n{key}:[^\n]*`, function()
			lines += 1
			return ""
		end)
		if lines > 1 then
			return nil
		end
	end
	-- c0248: `ready` marks a raft `layers: reviewed` (its layers are reviewed one by one); that line is the tool's, as
	-- the status line is
	kept = string.gsub(kept, "\nlayers: reviewed", "")
	return head .. kept .. rest
end

-- c0250 (a `blocked` or `resolve` commit): why `after` may not replace the document `before`, or nil. The front matter
-- may change only the keys in `allowed`; every line of the body is kept, in order, and the only lines added are a
-- Decided or Scope decision line inside `## Problem`.
local function escalationDocDiff(before: string, after: string, allowed: { string }): string?
	local bh, bk, br = string.match(before, "^(%-%-%-\n)(.-\n)(%-%-%-\n.*)$")
	local ah, ak, ar = string.match(after, "^(%-%-%-\n)(.-\n)(%-%-%-\n.*)$")
	if not bh or not bk or not br or not ah or not ak or not ar then
		return "the document has no well-formed front matter"
	end
	local function keyed(block: string): ({ [string]: string }, { string })
		local map: { [string]: string } = {}
		local order: { string } = {}
		for line in string.gmatch(block, "([^\n]*)\n") do
			local key, value = string.match(line, "^([%w_]+):%s?(.*)$")
			if not key or not value then
				return map, { line }
			end
			if map[key] ~= nil then
				return map, { `{key} twice` }
			end
			map[key] = value
			table.insert(order, key)
		end
		return map, order
	end
	local bm, bo = keyed(bk)
	local am, ao = keyed(ak)
	local touched: { string } = {}
	for _, key in ao do
		if bm[key] ~= am[key] then
			table.insert(touched, key)
		end
	end
	for _, key in bo do
		if am[key] == nil then
			table.insert(touched, key)
		end
	end
	for _, key in touched do
		if not table.find(allowed, key) then
			return `its {key}: line may not change here (allowed: {table.concat(allowed, ", ")})`
		end
	end
	-- the rest of the front matter keeps its order: the keys both texts hold, in their order
	local common = {}
	for _, key in bo do
		if am[key] ~= nil and not table.find(touched, key) then
			table.insert(common, key)
		end
	end
	local at = 1
	for _, key in ao do
		if common[at] == key then
			at += 1
		elseif table.find(common, key) then
			return "its front matter lines were reordered"
		end
	end
	-- the body: a subsequence rule
	local bl = string.split(br, "\n")
	local section = ""
	local i = 1
	for _, line in string.split(ar, "\n") do
		local heading = string.match(line, "^## (.-)%s*$")
		if heading then
			section = heading
		end
		if bl[i] == line then
			i += 1
		elseif
			section == "Problem"
			and (
				string.match(line, "^Decided with the user %(%d%d%d%d%-%d%d%-%d%d%), resolve [%a%-]+: ")
				or string.match(line, "^Scope decision %(user, %d%d%d%d%-%d%d%-%d%d%): ")
			)
		then
			continue -- an added line
		else
			return "only a Decided or Scope decision line inside ## Problem may be added, and no other line may change or go"
		end
	end
	if i <= #bl then
		return "a line of the document on origin/main is missing (a Decided or Scope decision line is never removed or edited)"
	end
	return nil
end

-- Why a published edit of an existing item document `existing` into `content` refuses, or nil. A closed document is
-- never published again; new content that is closed (or carries wont_do) is only ever exactly one close, as
-- closing.guard recomputes it, so a status-only edit can't stamp `closed-…` without its reason (R0115 review 001 F1);
-- anything else changes only the status: line.
function publish.existingEdit(id: string, existing: string, content: string, escalation: boolean?): string?
	if closing.closedDoc(existing) then
		return `{id} is closed on origin/main: a closed issue's document is never published again`
	end
	if closing.closedDoc(content) then
		local why = closing.guard(existing, content)
		if why then
			return `a published change to an existing document may only edit its status: line (or be one close: ./zn close): {why}`
		end
		return nil
	end
	local before, after = withoutStatus(existing, escalation), withoutStatus(content, escalation)
	if not before or not after or before ~= after then
		return "a published change to an existing document may only edit its status: line (or be one close: ./zn close)"
	end
	return nil
end

-- Why a moved item document (`old` on origin/main, `content` at its new path) refuses, or nil: a closed issue never
-- moves, a move never closes one (only ./zn close does, in place: R0115 review 001 F1), and a move changes only the
-- status: line.
function publish.movedEdit(id: string, old: string, content: string, escalation: boolean?): string?
	if closing.closedDoc(old) then
		return `{id} is closed on origin/main: a closed issue's document is never published again`
	end
	if closing.closedDoc(content) then
		return `{id}: a move never closes an issue (./zn close closes it where it is)`
	end
	local before, after = withoutStatus(old, escalation), withoutStatus(content, escalation)
	if not before or not after or before ~= after then
		return `a moved document may only change its status: line{if escalation
			then ", blocked: and design:"
			else ""}`
	end
	return nil
end

-- A coherence review changed by a resolve: only its `Grouped:` lines differ.
local function groupedOnly(before: string, after: string): boolean
	local function strip(text: string): string
		return (string.gsub(text, "\nGrouped: %[[^\n]*%]", "\nGrouped:"))
	end
	return strip("\n" .. before) == strip("\n" .. after)
end

local function git(
	cwd: string,
	args: { string },
	env: { [string]: string }?,
	stdin: string?
): process.ExecResult
	return process.exec(
		"git",
		args,
		{ cwd = cwd, env = env, stdio = if stdin then { stdin = stdin } else nil }
	)
end

local function fail(reason: string): Result
	return { ok = false, reason = reason }
end

type Node = { blob: string?, mode: string?, remove: boolean?, children: { [string]: Node } }
type Step = (args: { string }, stdin: string?) -> (string?, string?)

-- The tree `treeish` (nil for none) with `node`'s changes applied, as a new tree object; each level is one
-- `ls-tree -z` and one `mktree -z`, and only the trees on a changed path are rebuilt. A removed entry is dropped, and
-- a subtree left with no entries is dropped from its parent (the third result says the tree is empty).
local function makeTree(
	step: Step,
	treeish: string?,
	node: Node,
	prefix: string
): (string?, string?, boolean?)
	local entries: { [string]: string } = {} -- name -> "<mode> <type> <object>"
	if treeish then
		local listed, le = step({ "ls-tree", "-z", treeish })
		if not listed then
			return nil, le
		end
		for _, rec in string.split(listed, "\0") do
			if rec ~= "" then
				-- "<mode> <type> <object>\t<name>": the name may hold spaces, tabs, anything but NUL
				local meta, name = string.match(rec, "^(%d+ %a+ %x+)\t(.+)$")
				if not meta or not name then
					return nil, `cannot read the tree at {prefix}: {rec}`
				end
				entries[name] = meta
			end
		end
	end
	for name, child in node.children do
		if child.remove then
			entries[name] = nil
		elseif child.blob then
			entries[name] = `{child.mode} blob {child.blob}`
		else
			local existing = entries[name]
			local sub = if existing then string.match(existing, "^040000 tree (%x+)$") else nil
			if existing and not sub then
				return nil, `{prefix}{name} is a file on origin/main, not a folder`
			end
			local made, me, emptied = makeTree(step, sub, child, `{prefix}{name}/`)
			if not made then
				return nil, me
			end
			if emptied then
				entries[name] = nil
			else
				entries[name] = `040000 tree {made}`
			end
		end
	end
	local input: { string } = {}
	for name, meta in entries do
		table.insert(input, `{meta}\t{name}\0`)
	end
	local tree, te = step({ "mktree", "-z" }, table.concat(input))
	tree = if tree then trim(tree) else nil
	if not tree or not string.match(tree, "^%x+$") then
		return nil, te or "mktree failed"
	end
	return tree, nil, #input == 0
end

-- itemPath for a move: a raft folder's `retired/` level is read as the raft's own (c0250: an emptied raft goes there)
local function movePath(path: string): (string?, string?, string?)
	local id, rel, root = publish.itemPath(path)
	if id then
		return id, rel, root
	end
	local plain = string.gsub(path, "/rafts/retired/", "/rafts/", 1)
	if plain ~= path then
		return publish.itemPath(plain)
	end
	return nil, nil, nil
end

-- Checks every move (a change with `from`) in `out` against origin: whole item directories between the backlog and
-- active/, files carried byte for byte (the document may change its status, check.sh its item paths). Returns the
-- source directories of the moves, or a reason. A move's mode is set to its source's. See c0067.
local function validateMoves(
	out: { Change },
	onOrigin: { [string]: string },
	read: (string) -> string?,
	roots: { string },
	escalation: boolean?
): ({ string }, string?)
	local sources: { string } = {}
	local targets: { [string]: boolean } = {}
	local froms: { [string]: boolean } = {}
	local dirs: { [string]: string } = {} -- every id this publish moves -> its target directory
	local srcOf: { [string]: string } = {}
	for _, c in out do
		if targets[c.path] then
			return sources, `{c.path} is written twice in one publish`
		end
		targets[c.path] = true
		local from = c.from
		if from then
			if froms[from] then
				return sources, `{from} is moved twice in one publish`
			end
			froms[from] = true
			local fid, frel, froot = movePath(from)
			local pid, prel, proot = movePath(c.path)
			if not fid or not frel or not pid or not prel then
				return sources, `{from} -> {c.path}: both sides of a move must be item files`
			end
			if not table.find(roots, froot :: string) or not table.find(roots, proot :: string) then
				return sources,
					`{from} -> {c.path}: a move stays under a project root that origin/main's registry lists`
			end
			-- c0250: a block of a readied raft that holds a resolved note keeps it, moved to its archive name
			local archived = escalation == true
				and frel == "escalation.md"
				and string.match(prel, "^escalation%-%d%d%d%.md$") ~= nil
			if fid ~= pid or (frel ~= prel and not archived) or froot ~= proot then
				return sources, `{from} -> {c.path}: a move keeps the id, the root and the relative path`
			end
			if not onOrigin[from] then
				return sources, `{from} does not exist on origin/main`
			end
			local src, dst = itemDir(from, frel), itemDir(c.path, prel)
			if src == dst then
				return sources, `{from} -> {c.path}: a move changes the directory`
			end
			-- c0250: a resolve that leaves a raft no unlanded member sends its whole folder to done/ or retired/
			local finished = escalation == true
				and string.match(fid :: string, "^R%d%d%d%d$") ~= nil
				and (string.match(dst, "/rafts/done/R%d%d%d%d$") ~= nil or string.match(
					dst,
					"/rafts/retired/R%d%d%d%d$"
				) ~= nil)
				and string.match(src, "/rafts/R%d%d%d%d$") ~= nil
			if
				not finished
				and (string.find(src .. "/", "/done/", 1, true) or string.find(dst .. "/", "/done/", 1, true))
			then
				return sources, `{from} -> {c.path}: published moves never touch done/`
			end
			if (srcOf[fid] and srcOf[fid] ~= src) or (dirs[fid] and dirs[fid] ~= dst) then
				return sources, `{fid} is moved between different directories in one publish`
			end
			srcOf[fid], dirs[fid] = src, dst
			if not table.find(sources, src) then
				table.insert(sources, src)
			end
		end
	end
	if #sources == 0 then
		return sources, nil
	end
	for _, c in out do
		local from = c.from
		if not from then
			continue
		end
		local id, rel = movePath(from)
		local _, toRel = movePath(c.path)
		local dir = itemDir(c.path, toRel :: string)
		if table.find(sources, dir) then
			return sources, `{c.path} is inside {dir}, which this publish moves away`
		end
		if onOrigin[c.path] then
			return sources, `{c.path} already exists on origin/main`
		end
		local old = read(from)
		if not old then
			return sources, `cannot read {from} on origin/main`
		end
		local want = old
		if rel == `{id}.md` then
			local why = publish.movedEdit(id :: string, old, c.content, escalation)
			if why then
				return sources, `{c.path}: {why}`
			end
			want = c.content
		elseif rel == "check.sh" then
			want = pathsLib.rewrite(old, dirs)
		elseif
			escalation
			and string.sub(c.content, 1, #old) == old
			and (
				rel == "escalation.md" -- an emptied raft's note, extended by the resolution
				or (
					rel == "provenance.md"
					and provenance.publishProblem(old, c.content, id :: string, { "unblocked" }) == nil
				)
			)
		then
			want = c.content
		end
		if c.content ~= want then
			return sources,
				`{c.path}: a moved file must equal {from} on origin/main (check.sh: with its item paths rewritten)`
		end
		local mode = onOrigin[from]
		if c.mode and c.mode ~= mode then
			return sources, `{c.path}: a move keeps the mode of {from} ({mode})`
		end
		c.mode = mode
	end
	-- whole directories: every file on origin under a source directory moves in this publish
	for _, src in sources do
		for p in onOrigin do
			if string.sub(p, 1, #src + 1) == src .. "/" and not froms[p] then
				return sources, `{src}: {p} is not moved with it (a move carries the whole directory)`
			end
		end
	end
	-- and into a new directory: nothing on origin under a target, so a move never merges into another copy
	for _, dst in dirs do
		for p in onOrigin do
			if string.sub(p, 1, #dst + 1) == dst .. "/" then
				return sources, `{dst} already holds {p} on origin/main: a move goes to a new directory`
			end
		end
	end
	return sources, nil
end

-- `escalation` (c0250): this publish is a `./zn block` or `./zn resolve` commit. It may add or append escalation.md, add
-- an archive escalation-NNN.md of the resolved note, and change the front matter's status:, blocked:, design:, raft:
-- and issues: lines and add Decided or Scope decision lines to a Problem. Every other rule is unchanged.
function publish.commit(
	cwd: string,
	build: Build,
	message: string | () -> string,
	tries: number?,
	escalation: boolean?
): Result
	local max = tries or 5
	local last = ""
	for attempt = 1, max do
		local fetched = git(cwd, { "fetch", "-q", "origin", "main" })
		if not fetched.ok then
			last = "fetch failed: " .. trim(fetched.stderr) -- a lock held by a sibling worktree: back off, retry
			task.wait(0.15 * attempt)
			continue
		end
		-- every later step names this sha, never `origin/main`: sibling worktrees share that ref
		local rev = git(cwd, { "rev-parse", "--verify", "origin/main^{commit}" })
		local base = trim(rev.stdout)
		if not rev.ok or not string.match(base, "^%x+$") then
			return fail("cannot resolve origin/main: " .. trim(rev.stderr))
		end
		local function read(p: string): string?
			local r = git(cwd, { "show", `{base}:{p}` })
			return if r.ok then r.stdout else nil
		end
		-- the roots this publish may write under come from origin/main alone: a branch that edits its own registry
		-- can't widen them (lesson zz-arch/guards-trust-only-origin). An origin/main without the registry (before
		-- c0114 lands) or with one that does not parse publishes nothing: the main checkout's engine, which predates the
		-- registry, publishes until then.
		local regText = read(projects.FILE)
		if not regText then
			return fail(
				`origin/main has no {projects.FILE} (c0114 has not landed): publish from the main checkout until it does`
			)
		end
		local reg, regErr = projects.parse(regText)
		if not reg then
			return fail(`origin/main's {regErr}`)
		end
		local roots = projects.roots(reg)
		local oldText = read(ids.OLD_FILE)
		local counter, migrate = publish.counterOf(read(ids.FILE) ~= nil, oldText)
		-- while it moves the counter, this publish reads the old counters as z-nile/next
		local buildRead = read
		if migrate then
			buildRead = function(p: string): string?
				return if p == ids.FILE then oldText else read(p)
			end
		end
		local listArgs = { "ls-tree", "-r", "-z", "--full-tree", base, "--" }
		for _, r in roots do
			table.insert(listArgs, r .. "/")
		end
		table.insert(listArgs, counter)
		local listing = git(cwd, listArgs)
		if not listing.ok then
			return fail("cannot list origin/main: " .. trim(listing.stderr))
		end
		local paths: { string } = {}
		local onOrigin: { [string]: string } = {} -- every file under the roots (and the counter) -> its mode
		for _, rec in string.split(listing.stdout, "\0") do
			local mode, p = string.match(rec, "^(%d+) %a+ %x+\t(.+)$")
			if mode and p then
				onOrigin[p] = mode
				local _, _, root = publish.itemPath(p)
				if publish.allowed(p, roots, counter) or (root and table.find(roots, root)) then
					table.insert(paths, p)
				end
			end
		end
		local out = build(paths, buildRead, roots, counter, base)
		if type(out) == "string" then
			return fail(out)
		end
		local moved, why = validateMoves(out, onOrigin, read, roots, escalation)
		if why then
			return fail(why)
		end
		-- c0250: the item of a block or resolve is the one whose note this commit writes; its members are the issues its
		-- document lists on origin/main
		local escItem: string? = nil
		local escMembers: { [string]: boolean } = {}
		if escalation then
			for _, c in out do
				local nid, nrel = movePath(c.path)
				if
					nid
					and nrel
					and (nrel == "escalation.md" or string.match(nrel, "^escalation%-%d%d%d%.md$"))
				then
					if not escItem or string.match(nid, "^R") then
						escItem = nid
					end
				end
			end
			if escItem and string.match(escItem, "^R%d%d%d%d$") then
				for p in onOrigin do
					local pid, prel = publish.itemPath(p)
					if pid == escItem and prel == `{escItem}.md` then
						local text = read(p)
						local list = text and string.match(text, "\nissues: %[([^\n]*)%]\n")
						for mid in string.gmatch(list or "", "[fdc]%d%d%d%d") do
							escMembers[mid] = true
						end
					end
				end
			end
		end
		for _, c in out do
			if c.from then
				continue -- validated above, byte for byte against origin
			end
			if not publish.allowed(c.path, roots, counter, escalation) then
				return fail(`{c.path} is not a tracker item file under a project root of origin/main`)
			end
			for _, dir in moved do
				if string.sub(c.path, 1, #dir + 1) == dir .. "/" then
					return fail(`{c.path} is inside {dir}, which this publish moves away`)
				end
			end
			local existing = buildRead(c.path)
			if existing and string.sub(c.path, -9) == "/check.sh" then
				return fail(`{c.path} already exists on origin/main: check.sh is never rewritten`)
			end
			if c.path == counter then
				-- the counter only goes up: a lower value would hand out numbers already given
				local new = ids.parse(c.content)
				local old = if existing then ids.parse(existing) else nil
				if not new then
					return fail(`{c.path}: not two counter lines (issue <n> <phrase>, raft <n> <phrase>)`)
				end
				if existing and not old then
					return fail(`{c.path} on origin/main does not parse; fix it by pull request`)
				end
				if old and (new.issue < old.issue or new.raft < old.raft) then
					return fail(`{c.path}: a published counter may only go up`)
				end
				continue
			end
			if string.find(c.content, "\r", 1, true) then
				return fail(`{c.path}: carriage returns are not allowed in a published change`)
			end
			if string.sub(c.path, -14) == "/provenance.md" then
				-- moves (c.from) already continued: a ready/stop carries the file byte for byte
				local pid = string.match(c.path, "/([fdcR]%d%d%d%d)/provenance%.md$")
				if not pid then
					return fail(`{c.path}: not an item's provenance.md`)
				end
				local doc = string.gsub(c.path, "/provenance%.md$", `/{pid}.md`)
				if not onOrigin[doc] then
					return fail(`{c.path}: no {pid}.md beside it on origin/main`)
				end
				if string.find(c.path, "/done/", 1, true) then
					return fail(
						`{c.path}: a done item's record is written in a pull request, never published`
					)
				end
				-- an active item takes `unblocked` rows only (a worker blocks while it holds a raft)
				local allowed = if string.find(c.path, "/active/", 1, true)
					then { "unblocked" }
					else provenance.PUBLISHED
				local reason = provenance.publishProblem(existing, c.content, pid, allowed)
				if reason then
					return fail(`{c.path}: {reason}`)
				end
				continue
			end
			if string.sub(c.path, -12) == "/approval.md" then
				-- an approval is not a status document. ready and work next read it from origin/main, so
				-- `./zn approve --publish` may add it or replace it. The caller checks the contract.
				local approved = string.match(c.path, "/([fdc]%d%d%d%d)/approval%.md$")
				local beside = if approved
					then string.gsub(c.path, "/approval%.md$", `/{approved}.md`)
					else ""
				if not approved or not onOrigin[beside] then
					return fail(`{c.path}: no issue document beside it on origin/main`)
				end
				continue
			end
			if string.sub(c.path, -9) == "/spend.md" then
				-- moves (c.from) already continued: a ready/stop carries the file byte for byte
				local id = string.match(c.path, "/([fdc]%d%d%d%d)/spend%.md$")
				if not id or string.find(c.path, "/active/", 1, true) then
					return fail(`{c.path}: an active item's spend.md is recorded on its raft branch`)
				end
				local doc = string.gsub(c.path, "/spend%.md$", `/{id}.md`)
				if not onOrigin[doc] then
					return fail(`{c.path}: no {id}.md beside it on origin/main`)
				end
				local reason = ledger.appendOnly(existing, c.content, id)
				if reason then
					return fail(`{c.path}: {reason}`)
				end
				continue
			end
			if escalation and string.match(c.path, "/escalation%.md$") and existing then
				-- the note is appended to (a `## Resolution` only); a note that was resolved or cannot be read is kept
				-- under its archive name first
				if string.sub(c.content, 1, #existing) == existing then
					local added = string.sub(c.content, #existing + 1)
					local headings = 0
					for _ in string.gmatch("\n" .. added, "\n## ") do
						headings += 1
					end
					if
						string.find(existing, "\n## Resolution\n", 1, true)
						or not string.match(added, "^\n+## Resolution\n")
						or headings ~= 1
					then
						return fail(
							`{c.path}: the note on origin/main is only appended to, by one ## Resolution, and only while unresolved`
						)
					end
				else
					local dir = string.match(c.path, "^(.*)/escalation%.md$") :: string
					local kept = false
					for _, other in out do
						if
							string.match(
								other.path,
								"^" .. string.gsub(dir, "%p", "%%%0") .. "/escalation%-%d%d%d%.md$"
							) and other.content == existing
						then
							kept = true
						end
					end
					local readable = escalationLib.parse(existing)
					if
						not (kept and (not readable or string.find(existing, "\n## Resolution\n", 1, true)))
					then
						return fail(
							`{c.path}: the note on origin/main is only appended to, or kept as escalation-NNN.md once resolved`
						)
					end
					if not escalationLib.parse(c.content) then
						return fail(`{c.path}: not an escalation note that parses`)
					end
				end
				continue
			end
			if escalation and string.match(c.path, "/escalation%-%d%d%d%.md$") then
				if existing then
					return fail(`{c.path} already exists on origin/main: an earlier note is never rewritten`)
				end
				continue
			end
			if escalation and string.match(c.path, "/escalation%.md$") then
				if not escalationLib.parse(c.content) then
					return fail(`{c.path}: not an escalation note that parses`)
				end
				continue
			end
			if existing and escalation then
				local cid, crel = publish.itemPath(c.path)
				if crel and string.match(crel, "^design%-review%-%d%d%d%.md$") then
					if not groupedOnly(existing, c.content) then
						return fail(
							`{c.path}: a resolve may change only the Grouped: lines of a coherence review`
						)
					end
					continue
				end
				-- the item and its members only; the keys by role
				local role: string? = if cid == escItem
					then "item"
					elseif escMembers[cid or ""] then "member"
					else nil
				if not role then
					return fail(
						`{c.path}: {cid} is neither the item {escItem} of this block or resolve nor one of its members`
					)
				end
				local keys = if role == "item"
					then { "status", "blocked", "design", "issues", "grouped", "retired", "layers" }
					else { "status", "blocked", "design", "raft", "layers" }
				local reason = escalationDocDiff(existing, c.content, keys)
				if reason then
					return fail(`{c.path}: {reason}`)
				end
				continue
			end
			if existing then
				-- c0278: a closed document is never published again, a status-only edit included
				local editWhy =
					publish.existingEdit(publish.itemPath(c.path) or c.path, existing, c.content, escalation)
				if editWhy then
					return fail(`{c.path}: {editWhy}`)
				end
			end
		end
		if migrate then
			-- the counter moves with this publish: z-nile/next holds tracker/next's counters (or the raise the build made
			-- of them), and tracker/next becomes the tombstone, in this one commit and lease push
			local raised = false
			for _, c in out do
				raised = raised or c.path == ids.FILE
			end
			if not raised then
				table.insert(out, { path = ids.FILE, content = oldText :: string })
			end
			table.insert(out, { path = ids.OLD_FILE, content = ids.TOMBSTONE })
		end
		if #out == 0 then
			return { ok = true }
		end
		-- The new tree is built with mktree, from the base tree down each changed path: no index at all, neither
		-- the caller's nor a private one, so nothing here names git's index variable (R0210's guards ban it).
		local function step(args: { string }, stdin: string?): (string?, string?)
			local r = git(cwd, args, nil, stdin)
			if not r.ok then
				return nil, trim(r.stderr .. r.stdout)
			end
			return r.stdout
		end
		local rootNode: Node = { children = {} }
		local err = ""
		local sha: string? = nil
		repeat
			local bad = false
			for _, c in out do
				local blob, be = step({ "hash-object", "-w", "--stdin" }, c.content)
				blob = if blob then trim(blob) else nil
				if not blob or not string.match(blob, "^%x+$") then
					err, bad = be or "hash-object failed", true
					break
				end
				local node = rootNode
				local parts = string.split(c.path, "/")
				for i = 1, #parts - 1 do
					local child = node.children[parts[i]] or { children = {} }
					node.children[parts[i]] = child
					node = child
				end
				node.children[parts[#parts]] = { blob = blob, mode = c.mode or "100644", children = {} }
				if c.from then
					local fromNode = rootNode
					local fromParts = string.split(c.from, "/")
					for i = 1, #fromParts - 1 do
						local child = fromNode.children[fromParts[i]] or { children = {} }
						fromNode.children[fromParts[i]] = child
						fromNode = child
					end
					fromNode.children[fromParts[#fromParts]] = { remove = true, children = {} }
				end
			end
			if bad then
				break
			end
			local rt = git(cwd, { "rev-parse", "--verify", base .. "^{tree}" })
			local baseTree = trim(rt.stdout)
			if not rt.ok or not string.match(baseTree, "^%x+$") then
				err = "cannot resolve origin/main's tree: " .. trim(rt.stderr)
				break
			end
			local tree, te = makeTree(step, baseTree, rootNode, "")
			if not tree then
				err = te or "mktree failed"
				break
			end
			-- the new tree differs from the base in the change's paths only: anything else is a bug that would
			-- delete or rewrite files on main
			local diff, de = step({ "diff-tree", "-r", "--no-renames", "-z", "--name-only", baseTree, tree })
			if not diff then
				err = de or "diff-tree failed"
				break
			end
			local wanted: { [string]: boolean } = {}
			for _, c in out do
				wanted[c.path] = true
				if c.from then
					wanted[c.from] = true
				end
			end
			for _, p in string.split(diff, "\0") do
				if p ~= "" and not wanted[p] then
					err, bad = `the new tree would also change {p}, which is not in the change`, true
					break
				end
			end
			if bad then
				break
			end
			if tree == baseTree then
				sha = ""
				break
			end
			local text = if type(message) == "function" then message() else message
			local made = git(cwd, { "commit-tree", tree, "-p", base, "-m", text })
			local candidate = trim(made.stdout)
			if
				not made.ok
				or not (string.match(candidate, "^%x+$") and (#candidate == 40 or #candidate == 64))
			then
				err = "commit-tree failed: " .. trim(made.stderr)
				break
			end
			sha = candidate
		until true
		if sha == nil then
			return fail(err)
		end
		if sha == "" then
			return { ok = true } -- the change was already there
		end
		local pushed
		if process.env.ZN_PUBLISH_BROKER and process.env.ZN_PUBLISH_BROKER ~= "" then
			-- inside a dispatched step the agent's credential can't push to main: the dispatcher pushes it (c0117)
			local ok, said = broker.request(
				process.env.ZN_PUBLISH_BROKER :: string,
				process.env.ZN_PUBLISH_TOKEN or "",
				sha,
				base
			)
			pushed = { ok = ok, code = if ok then 0 else 1, stdout = "", stderr = said }
		else
			pushed = git(cwd, {
				"push",
				"-q",
				`--force-with-lease=refs/heads/main:{base}`,
				"origin",
				`{sha}:refs/heads/main`,
			})
		end
		if pushed.ok then
			return { ok = true, sha = sha }
		end
		last = trim(pushed.stderr)
		task.wait(0.05 * attempt)
	end
	return fail(`push rejected after {max} tries: {last}`)
end

return publish
