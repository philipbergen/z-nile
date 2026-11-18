--!strict
-- Where `./zn approve <id>` acts (c0369): the one worktree under .worktree/ that holds a design of its own with no
-- matching approval, or origin/main. `choose` is pure over what `load` read; `load`, `atRev` and `inTree` are the edge.

local approval = require("./approval")
local contract = require("./contract")
local fs = require("@lune/fs")
local guesses = require("./guesses")
local layergit = require("./layergit")
local process = require("@lune/process")
local projects = require("./projects")
local readycheck = require("./readycheck")
local store = require("./store")

local approveplace = {}

-- One copy of the issue: a worktree's checkout, or a commit (origin/main, a merge-base).
export type Copy = {
	ready: boolean, -- design: ready
	slug: string, -- the issue's slug, "" when the document has none
	state: string, -- "none" | "changed" | "holds" | "bad": the last approval row against this copy's contract
	hash: string?, -- the contract's hash; nil when the contract can't be built
	active: boolean?, -- the copy is in its root's issues/active/ (readied, in a raft)
	raft: string?, -- its raft: line, "" or nil when it has none
}

-- A worktree the command may act in. Only these are ever read: the one on the branch prep-<slug>, for an issue in
-- active/ on origin/main its raft's worktree (.worktree/<R-id>, c0369 design review 002 F2, the user's ruling), the one
-- the command runs in, and the command's own detached worktree of origin/main.
export type Seen = {
	name: string, -- as printed: .worktree/<name>
	path: string, -- absolute
	here: boolean, -- the checkout the command was run in
	prep: boolean, -- its branch is prep-<the issue's slug>
	raft: boolean?, -- it is .worktree/<R-id> of the raft an issue in active/ on origin/main belongs to
	scratch: boolean, -- the command's own worktree, <main checkout>/.worktree/.approve-<id>
	copy: Copy,
	base: string?, -- the contract's hash where this worktree left origin/main (nil: the issue is not there)
	landed: boolean, -- origin/main held this contract at some commit since the worktree left it (a merged prep)
	pushed: boolean, -- its branch is on origin at this commit
}

export type Choice = {
	kind: string, -- "worktree" | "main" | "approved" | "pushed"
	path: string?, -- the worktree, for "worktree"
	name: string, -- as printed
	record: boolean, -- a new approval is recorded there; false: the one it holds is only published or pushed
}

local STATES = { "", "active/", "done/" }

local function copyOf(doc: string, parts: contract.Parts?, approvalText: string?, active: boolean): Copy
	local block = "\n" .. (string.match(doc, "^%-%-%-\n(.-)\n%-%-%-") or "") .. "\n"
	local design = string.match(block, "\ndesign:[ ]*([^\n]*)\n") or ""
	local slug = string.match(block, "\nslug:[ ]*([^\n]*)\n") or ""
	local raft = string.match(block, "\nraft:[ ]*([^\n]*)\n") or ""
	local copy: Copy = {
		ready = (string.gsub(design, "%s+$", "")) == "ready",
		slug = (string.gsub(slug, "%s+$", "")),
		state = "none",
		hash = if parts then contract.hash(parts) else nil,
		active = active,
		raft = (string.gsub(raft, "%s+$", "")),
	}
	if approvalText then
		local rows = contract.parse(approvalText)
		if not rows or #rows == 0 then
			copy.state = "bad"
			return copy
		end
		copy.state = if parts and #contract.changed(rows[#rows], parts) == 0 then "holds" else "changed"
	end
	return copy
end

-- A worktree's design is its own when its contract is neither origin/main's, nor the one it branched from, nor one
-- origin/main held since: a checkout that is only behind main, or whose prep already merged, holds a text main had
-- and is nobody's design to approve.
local function own(main: Copy?, w: Seen): boolean
	local hash = w.copy.hash
	if not w.copy.ready or hash == nil then
		return false
	end
	if main and main.ready and main.hash == hash then
		return false
	end
	return w.base ~= hash and not w.landed
end

-- A worktree that holds an approval of the very design origin/main holds unapproved: the approval is published as
-- it is, never recorded a second time.
local function forMain(main: Copy?, w: Seen): boolean
	return main ~= nil
		and main.ready
		and main.state ~= "holds"
		and w.copy.ready
		and w.copy.state == "holds"
		and w.copy.hash ~= nil
		and w.copy.hash == main.hash
end

-- The one the command runs in comes first, then the prep worktree, then the raft's, then the command's own.
local function rank(w: Seen): number
	return if w.here then 3 elseif w.prep then 2 elseif w.raft then 1 else 0
end
local function first(list: { Seen }, record: boolean): Choice?
	local best: Seen? = nil
	for _, w in list do
		if best == nil or rank(w) > rank(best) then
			best = w
		end
	end
	return if best then { kind = "worktree", path = best.path, name = best.name, record = record } else nil
end

-- The place to act in, or the refusal. `publishOnly` is `--publish`: the retry of a recorded approval. The refusal is
-- typed as a variadic tail (at most one string) so a caller may pass the whole result to a one-argument function: the
-- promoted place.spec does `t.expect(approveplace.choose(...))`, which a fixed `(Choice?, string?)` fails to type-check.
function approveplace.choose(
	id: string,
	main: Copy?,
	seen: { Seen },
	publishOnly: boolean
): (Choice?, ...string)
	-- an issue in active/ (the user's ruling of 2026-11-17 on design review 003 F1, f0399's rule): its one place is its
	-- raft's worktree; the acting run then records only on the raft's top layer with a clean tree and pushes it
	if main and main.active then
		local raftName = main.raft or ""
		local raftW: Seen? = nil
		for _, w in seen do
			if w.raft then
				raftW = w
			end
		end
		if raftW then
			local w = raftW :: Seen
			if w.copy.state == "holds" then
				if main.state == "holds" and w.copy.hash == main.hash then
					return { kind = "approved", path = nil, name = "origin/main", record = false }, nil
				end
				if not w.pushed then
					return { kind = "worktree", path = w.path, name = w.name, record = false }, nil
				end
				return { kind = "pushed", path = nil, name = w.name, record = false }, nil
			end
			if publishOnly then
				return nil, `{id} has no recorded approval to publish. Run ./zn approve {id}.`
			end
			if not w.copy.ready then
				return nil, `{id}: nothing to approve: its copy in {w.name} is not design: ready`
			end
			return { kind = "worktree", path = w.path, name = w.name, record = true }, nil
		end
		if main.state == "holds" then
			return { kind = "approved", path = nil, name = "origin/main", record = false }, nil
		end
		return nil,
			`{id} is active in {raftName}, and no worktree of {raftName} is on this machine: run ./zn worktree {raftName}, then ./zn approve {id}`
	end
	local waiting: { Seen } = {}
	local recorded: { Seen } = {}
	local pushed: { Seen } = {}
	for _, w in seen do
		local mine = own(main, w)
		if mine and w.copy.state ~= "holds" then
			table.insert(waiting, w)
		elseif forMain(main, w) then
			table.insert(recorded, w)
		elseif mine and w.copy.state == "holds" then
			table.insert(if w.pushed then pushed else recorded, w)
		end
	end
	if not publishOnly and #waiting > 0 then
		return first(waiting, true), nil
	end
	if #recorded > 0 then
		return first(recorded, false), nil
	end
	-- a worktree's own design, approved and pushed, is what its pull request brings: main's older design is not
	-- approved behind it (the capture: origin/main only when no worktree holds a newer one)
	if #pushed > 0 then
		local name = (first(pushed, false) :: Choice).name
		return { kind = "pushed", path = nil, name = name, record = false }, nil
	end
	if not publishOnly and main and main.ready and main.state ~= "holds" then
		return { kind = "main", path = nil, name = "origin/main", record = true }, nil
	end
	if main and main.ready and main.state == "holds" then
		return { kind = "approved", path = nil, name = "origin/main", record = false }, nil
	end
	if publishOnly then
		return nil, `{id} has no recorded approval to publish. Run ./zn approve {id}.`
	end
	if main and not main.ready then
		return nil,
			`{id}: nothing to approve: it is not design: ready on origin/main, and the worktree of its prep branch (prep-{main.slug}) holds no design: ready of its own.`
	end
	return nil,
		`{id}: nothing to approve: it is not on origin/main, and no worktree of its prep branch holds a design: ready of its own.`
end

local function git(cwd: string, args: { string }): string?
	local r = process.exec("git", args, { cwd = cwd })
	return if r.ok then r.stdout else nil
end

-- The issue as commit `rev` holds it, read with git in `cwd`. Nil when the commit has no such issue.
function approveplace.atRev(cwd: string, rev: string, id: string): Copy?
	local reg = projects.at(rev, cwd)
	if not reg then
		return nil
	end
	local args = { "ls-tree", "-r", "--name-only", "--full-tree", rev, "--" }
	local dirs: { { dir: string, root: string } } = {}
	for _, root in projects.roots(reg) do
		for _, state in STATES do
			local dir = `{root}/issues/{state}{id}`
			table.insert(dirs, { dir = dir, root = root })
			table.insert(args, dir)
		end
	end
	local listed = git(cwd, args)
	if not listed then
		return nil
	end
	local function show(rel: string): string?
		return git(cwd, { "show", `{rev}:{rel}` })
	end
	for _, d in dirs do
		local prefix = d.dir .. "/"
		local folder: { [string]: string } = {}
		local found = false
		for relPath in string.gmatch(listed .. "\n", "([^\n]*)\n") do
			if string.sub(relPath, 1, #prefix) == prefix then
				found = true
				local rel = string.sub(relPath, #prefix + 1)
				if
					rel == `{id}.md`
					or rel == "check.sh"
					or rel == contract.FILE
					or rel == guesses.FILE
					or string.match(rel, "^acceptance/")
				then
					folder[rel] = show(relPath) or ""
				end
			end
		end
		if found and folder[`{id}.md`] then
			local promoted: { [string]: string } = {}
			local anySpec = false
			for rel in folder do
				anySpec = anySpec or string.match(rel, "^acceptance/.+%.spec%.luau$") ~= nil
			end
			if not anySpec then
				local dest = projects.promotedDir(reg, d.root, id)
				local destPrefix = dest .. "/"
				local inDest = git(cwd, { "ls-tree", "-r", "--name-only", "--full-tree", rev, "--", dest })
					or ""
				for relPath in string.gmatch(inDest .. "\n", "([^\n]*)\n") do
					if
						string.sub(relPath, 1, #destPrefix) == destPrefix
						and string.match(relPath, "%.spec%.luau$")
					then
						promoted[string.sub(relPath, #destPrefix + 1)] = show(relPath) or ""
					end
				end
			end
			local doc = folder[`{id}.md`]
			-- guesses.md is part of the contract (f0399), as approval.collect reads it
			local parts = contract.build(
				doc,
				folder["check.sh"] or "",
				readycheck.specs(folder, promoted),
				folder[guesses.FILE]
			)
			return copyOf(
				doc,
				parts,
				folder[contract.FILE],
				string.find(d.dir, "/issues/active/", 1, true) ~= nil
			)
		end
	end
	return nil
end

-- The issue as the checkout at `root` holds it (its files, committed or not). Nil when it has no such issue.
function approveplace.inTree(root: string, id: string): Copy?
	if not fs.isFile(`{root}/{projects.FILE}`) then
		return nil
	end
	local ok, reg = pcall(projects.load, root)
	if not ok then
		return nil
	end
	for _, trackerRoot in projects.roots(reg) do
		for _, state in STATES do
			local dir = `{trackerRoot}/issues/{state}{id}`
			local doc = `{dir}/{id}.md`
			if fs.isFile(`{root}/{doc}`) then
				local item: store.Item = {
					id = id,
					kind = "issue",
					state = if state == "" then "backlog" elseif state == "active/" then "active" else "done",
					dir = dir,
					doc = doc,
					slug = "",
					root = trackerRoot,
				}
				local parts = approval.collect(root, item)
				local file = `{root}/{approval.file(item)}`
				return copyOf(
					fs.readFile(`{root}/{doc}`),
					parts,
					if fs.isFile(file) then fs.readFile(file) else nil,
					state == "active/"
				)
			end
		end
	end
	return nil
end

-- Whether origin/main held the contract `hash` at a commit after `base` that changed the issue's folder.
local function held(cwd: string, base: string, id: string, hash: string): boolean
	local reg = projects.at("origin/main", cwd)
	if not reg then
		return false
	end
	local args = { "log", "--format=%H", `{base}..origin/main`, "--" }
	for _, root in projects.roots(reg) do
		for _, state in STATES do
			table.insert(args, `{root}/issues/{state}{id}`)
		end
	end
	for sha in string.gmatch(git(cwd, args) or "", "%x+") do
		local at = approveplace.atRev(cwd, sha, id)
		if at and at.ready and at.hash == hash then
			return true
		end
	end
	return false
end

export type Tree = { path: string, branch: string? }

-- The top layer of `raft` as a ref `cwd` can read (the local branch, else origin's), or nil when it has none. Which
-- layer is the top is `layergit.layersOf`'s answer, the one the acting run records on and pushes (c0369 final review
-- 001 F2: one rule, one function); worktrees share their refs, so it is the same answer in `cwd`.
local function topLayer(cwd: string, raft: string): (string?, string?)
	local layers = layergit.layersOf(raft)
	local best = layers[#layers]
	if best == nil then
		return nil, nil
	end
	local name = best.name
	local here = git(cwd, { "rev-parse", "-q", "--verify", `refs/heads/{name}` })
	return name, if here then name else `origin/{name}`
end

-- origin/main's copy and the worktrees the command may act in. `trees` is `git worktree list`'s order: the main
-- checkout first, which is never a place. Of the others only these are read: the one on prep-<slug>, for an issue in
-- active/ on origin/main its raft's .worktree/<R-id>, the one the command runs in (`here`) and the command's own
-- (`scratch`). The merge-base and main's history are read only for
-- a worktree whose contract is not origin/main's.
function approveplace.load(id: string, here: string, scratch: string, trees: { Tree }): (Copy?, { Seen })
	local main = approveplace.atRev(here, "origin/main", id)
	local slug = if main then main.slug else ""
	if slug == "" then
		local mine = approveplace.inTree(here, id)
		slug = if mine then mine.slug else ""
	end
	local raftName = if main and main.active and main.raft then main.raft else ""
	local seen: { Seen } = {}
	local prefix = `{trees[1].path}/`
	for i, tree in trees do
		local path = tree.path
		local prep = slug ~= "" and tree.branch == `prep-{slug}`
		-- an issue in active/ on origin/main is changed on its raft's branches, in the raft's own worktree
		local raft = raftName ~= "" and path == `{trees[1].path}/.worktree/{raftName}`
		if i > 1 and (prep or raft or path == here or path == scratch) and fs.isDir(path) then
			-- the raft's worktree is judged by the raft's top layer, the one an approval is recorded on, whatever the
			-- worktree has checked out (the acting run then refuses any other branch, naming that one)
			local top, topRef = nil, nil
			if raft then
				top, topRef = topLayer(path, raftName)
			end
			local copy = if topRef
				then approveplace.atRev(path, topRef :: string, id)
				else approveplace.inTree(path, id)
			if copy then
				local w: Seen = {
					name = if string.sub(path, 1, #prefix) == prefix
						then string.sub(path, #prefix + 1)
						else path,
					path = path,
					here = path == here,
					prep = prep,
					raft = raft,
					scratch = path == scratch,
					copy = copy,
					base = nil,
					landed = false,
					pushed = false,
				}
				if top then
					local theirs = git(path, { "rev-parse", "-q", "--verify", `refs/remotes/origin/{top}` })
					w.pushed = theirs ~= nil and theirs == git(path, { "rev-parse", topRef :: string })
				elseif tree.branch then
					local theirs =
						git(path, { "rev-parse", "-q", "--verify", `refs/remotes/origin/{tree.branch}` })
					w.pushed = theirs ~= nil and theirs == git(path, { "rev-parse", "HEAD" })
				end
				if copy.ready and copy.hash and not (main and main.hash == copy.hash) then
					local base = git(path, { "merge-base", "origin/main", "HEAD" })
					local at = if base
						then approveplace.atRev(path, (string.gsub(base, "%s+$", "")), id)
						else nil
					w.base = if at and at.ready then at.hash else nil
					if base and w.base ~= copy.hash then
						w.landed = held(path, (string.gsub(base, "%s+$", "")), id, copy.hash :: string)
					end
				end
				table.insert(seen, w)
			end
		end
	end
	return main, seen
end

return approveplace
