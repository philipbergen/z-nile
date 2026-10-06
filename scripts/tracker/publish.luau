--!strict
-- Pushes a tracker-only commit to origin/main with git plumbing (mktree, no index). Never touches the caller's working
-- tree, index, HEAD or branch. See c0510.
local ids = require("./ids")
local pathsLib = require("./paths")
local process = require("@lune/process")
local task = require("@lune/task")

local publish = {}

export type Change = { path: string, content: string, mode: string?, from: string? }
export type Result = { ok: boolean, sha: string?, reason: string? }
export type Build = (paths: { string }, read: (string) -> string?) -> { Change } | string

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- tracker/(issues|rafts)/[active/ | done/]<ID>/(<ID>.md | check.sh), the id's prefix matching the kind.
-- Also the counter file, tracker/next (c0870).
function publish.allowed(path: string): boolean
	if path == ids.FILE then
		return true
	end
	if string.find(path, "..", 1, true) or string.sub(path, 1, 1) == "/" then
		return false
	end
	local kind, rest = string.match(path, "^tracker/(%a+)/(.+)$")
	if not kind or not rest then
		return false
	end
	local stripped: string = string.match(rest, "^active/(.+)$") or string.match(rest, "^done/(.+)$") or rest
	local id, file = string.match(stripped, "^(%w+)/([%w%.]+)$")
	if not id then
		return false
	end
	local okId = if kind == "issues"
		then string.match(id, "^[fdc]%d%d%d%d$") ~= nil
		else (kind == "rafts" and string.match(id, "^R%d%d%d%d$") ~= nil)
	return okId and (file == `{id}.md` or file == "check.sh")
end

-- The id and the path relative to the item directory of any file inside an item directory,
-- tracker/(issues|rafts)/[active/ | done/]<ID>/<rel>; nil for anything else. `rel` is one or more segments of
-- [%w._-] that are not `.` or `..`.
function publish.itemPath(path: string): (string?, string?)
	if string.sub(path, 1, 1) == "/" then
		return nil, nil
	end
	local kind, rest = string.match(path, "^tracker/(%a+)/(.+)$")
	if not kind or not rest or (kind ~= "issues" and kind ~= "rafts") then
		return nil, nil
	end
	local stripped: string = string.match(rest, "^active/(.+)$") or string.match(rest, "^done/(.+)$") or rest
	local id, rel = string.match(stripped, "^(%w+)/(.+)$")
	if not id or not rel then
		return nil, nil
	end
	local okId = if kind == "issues"
		then string.match(id, "^[fdc]%d%d%d%d$") ~= nil
		else string.match(id, "^R%d%d%d%d$") ~= nil
	if not okId then
		return nil, nil
	end
	for _, seg in string.split(rel, "/") do
		if seg == "." or seg == ".." or not string.match(seg, "^[%w%._%-]+$") then
			return nil, nil
		end
	end
	return id, rel
end

-- The directory of an item file: `path` without its `/<rel>`.
local function itemDir(path: string, rel: string): string
	return string.sub(path, 1, #path - #rel - 1)
end

-- The document with its single `status:` frontmatter line removed, or nil when it has no well-formed
-- frontmatter. A published edit of an existing document may differ from origin's only in that line.
local function withoutStatus(text: string): string?
	local head, block, rest = string.match(text, "^(%-%-%-\n)(.-\n)(%-%-%-\n.*)$")
	if not head or not block or not rest then
		return nil
	end
	local lines = 0
	local kept = string.gsub("\n" .. block, "\nstatus:[^\n]*", function()
		lines += 1
		return ""
	end)
	if lines > 1 then
		return nil
	end
	return head .. kept .. rest
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

-- Checks every move (a change with `from`) in `out` against origin: whole item directories between the backlog and
-- active/, files carried byte for byte (the document may change its status, check.sh its item paths). Returns the
-- source directories of the moves, or a reason. A move's mode is set to its source's. See c0067.
local function validateMoves(
	out: { Change },
	onOrigin: { [string]: string },
	read: (string) -> string?
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
			local fid, frel = publish.itemPath(from)
			local pid, prel = publish.itemPath(c.path)
			if not fid or not frel or not pid or not prel then
				return sources, `{from} -> {c.path}: both sides of a move must be item files`
			end
			if fid ~= pid or frel ~= prel then
				return sources, `{from} -> {c.path}: a move keeps the id and the relative path`
			end
			if not onOrigin[from] then
				return sources, `{from} does not exist on origin/main`
			end
			local src, dst = itemDir(from, frel), itemDir(c.path, prel)
			if src == dst then
				return sources, `{from} -> {c.path}: a move changes the directory`
			end
			if string.find(src .. "/", "/done/", 1, true) or string.find(dst .. "/", "/done/", 1, true) then
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
		local id, rel = publish.itemPath(from)
		local dir = itemDir(c.path, rel :: string)
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
			local before, after = withoutStatus(old), withoutStatus(c.content)
			if not before or not after or before ~= after then
				return sources, `{c.path}: a moved document may only change its status: line`
			end
			want = c.content
		elseif rel == "check.sh" then
			want = pathsLib.rewrite(old, dirs)
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

function publish.commit(cwd: string, build: Build, message: string | () -> string, tries: number?): Result
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
		local listing = git(cwd, { "ls-tree", "-r", "-z", "--full-tree", base, "tracker/" })
		if not listing.ok then
			return fail("cannot list origin/main: " .. trim(listing.stderr))
		end
		local paths: { string } = {}
		local onOrigin: { [string]: string } = {} -- every file under tracker/ -> its mode
		for _, rec in string.split(listing.stdout, "\0") do
			local mode, p = string.match(rec, "^(%d+) %a+ %x+\t(.+)$")
			if mode and p then
				onOrigin[p] = mode
				if publish.allowed(p) or publish.itemPath(p) then
					table.insert(paths, p)
				end
			end
		end
		local function read(p: string): string?
			local r = git(cwd, { "show", `{base}:{p}` })
			return if r.ok then r.stdout else nil
		end
		local out = build(paths, read)
		if type(out) == "string" then
			return fail(out)
		end
		local moved, why = validateMoves(out, onOrigin, read)
		if why then
			return fail(why)
		end
		for _, c in out do
			if c.from then
				continue -- validated above, byte for byte against origin
			end
			if not publish.allowed(c.path) then
				return fail(`{c.path} is not a tracker item file`)
			end
			for _, dir in moved do
				if string.sub(c.path, 1, #dir + 1) == dir .. "/" then
					return fail(`{c.path} is inside {dir}, which this publish moves away`)
				end
			end
			local existing = read(c.path)
			if existing and string.sub(c.path, -9) == "/check.sh" then
				return fail(`{c.path} already exists on origin/main: check.sh is never rewritten`)
			end
			if c.path == ids.FILE then
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
			if existing then
				local before, after = withoutStatus(existing), withoutStatus(c.content)
				if not before or not after or before ~= after then
					return fail(
						`{c.path}: a published change to an existing document may only edit its status: line`
					)
				end
			end
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
		local pushed = git(
			cwd,
			{ "push", "-q", `--force-with-lease=refs/heads/main:{base}`, "origin", `{sha}:refs/heads/main` }
		)
		if pushed.ok then
			return { ok = true, sha = sha }
		end
		last = trim(pushed.stderr)
		task.wait(0.05 * attempt)
	end
	return fail(`push rejected after {max} tries: {last}`)
end

return publish
