--!strict
-- c0120 AC18, run by check.sh (never by the spec runner: it reads git): every item file that sequestration covers
-- (check.sh and acceptance/**, in every current project root) is its text before the move, read at its old place when
-- it moved (pickman's items were under tracker/): unchanged, or, for a finished item's check.sh, with exactly the
-- rewrite of rewrites.luau (the user's exception, 2026-10-21: "Rewrite them too"). A file that wasn't there before the
-- move (a capture since) is not judged; c0120's own files are judged against the prep commit a reviewer recorded
-- (below). Read-only. Usage: lune run finished.luau -- <the checkout's top>
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("./rewrites")

-- the first argument that isn't `--` (lune keeps it when the script is named by an absolute path)
local top: string? = nil
for _, a in process.args do
	if a ~= "--" and top == nil then
		top = a
	end
end
if top == nil then
	error("usage: finished.luau <the checkout's top>")
end
local TOP: string = top :: string

local function git(args: { string }): (boolean, string)
	local r = process.exec("git", args, { cwd = TOP })
	return r.ok, r.stdout
end

local pre, why = rewrites.premove(TOP)
if not pre then
	print(`finished: {why}`)
	process.exit(1)
end
local reg = projects.load(TOP, true)

-- c0120's own item folder changes after the move only through its prep (Guess 17's decision came that way). Its files
-- are judged against the prep commit a reviewer recorded (decided with the user, 2026-10-21: "Reviewer-pinned commit"):
-- a `Prep reference: <sha>` line in the newest approved review file (a code review's review-NNN.md before a design
-- review's design-review-NNN.md, the higher number first), which only a reviewer writes. Never a branch ref: its author
-- can move one (code review 004 F1). No recorded sha, or one the branch doesn't contain, refuses.
local OWN = if fs.isDir(`{TOP}/z-nile/.tracker/issues/c0120`)
	then "z-nile/.tracker/issues/c0120/"
	else "z-nile/.tracker/issues/done/c0120/"
local PINNED_MOVE: string? = nil
local PINNED_CORE: string? = nil
local function recorded(): (string?, string)
	local best: { rank: number, file: string, sha: string, move: string?, core: string? }? = nil
	for _, name in fs.readDir(`{TOP}/{OWN}`) do
		local code = string.match(name, "^review%-(%d+)%.md$")
		local n = code or string.match(name, "^design%-review%-(%d+)%.md$")
		if n then
			-- the verdict is the last `Verdict:` line (an earlier one may quote the format, code review 005 F5); a second
			-- `Prep reference:` line is ambiguous and refuses
			local verdict: string? = nil
			local refs: { string } = {}
			local moves: { string } = {}
			local cores: { string } = {}
			for line in string.gmatch(fs.readFile(`{TOP}/{OWN}{name}`), "[^\n]+") do
				local v = string.match(line, "^Verdict: (.-)%s*$")
				if v then
					verdict = v
				end
				local r = string.match(line, "^Prep reference: (%x+)%s*$")
				if r then
					table.insert(refs, r)
				end
				-- the anchors, pinned by the same reviewer (code review 010 F1): never found by searching history
				local mv = string.match(line, "^Move commit: (%x+)%s*$")
				if mv then
					table.insert(moves, mv)
				end
				local co = string.match(line, "^Core commit: (%x+)%s*$")
				if co then
					table.insert(cores, co)
				end
			end
			if #refs > 1 or #moves > 1 or #cores > 1 then
				return nil, `{name} records more than one Prep reference, Move commit or Core commit line`
			end
			local sha = refs[1]
			if sha and verdict == "approve" then
				local rank = (if code then 100000 else 0) + (tonumber(n) :: number)
				if not best or rank > (best :: any).rank then
					best = { rank = rank, file = name, sha = sha, move = moves[1], core = cores[1] }
				end
			end
		end
	end
	if not best then
		return nil, `no approved review in {OWN} records a "Prep reference: <sha>"`
	end
	local b = best :: { rank: number, file: string, sha: string, move: string?, core: string? }
	local okV, full = git({ "rev-parse", "--verify", "-q", b.sha .. "^{commit}" })
	full = string.gsub(full, "%s+$", "")
	if not okV or full == "" then
		return nil, `{b.file}'s Prep reference {b.sha} is no commit here`
	end
	if not git({ "merge-base", "--is-ancestor", full, "HEAD" }) then
		return nil, `{b.file}'s Prep reference {b.sha} is not in this branch`
	end
	if not b.move or not b.core then
		return nil,
			`{b.file} records no "Move commit: <sha>" and "Core commit: <sha>" beside its Prep reference`
	end
	PINNED_MOVE, PINNED_CORE = b.move, b.core
	return full, b.file
end
local ownBase, from = recorded()
if not ownBase then
	print(`finished: {from}: refusing`)
	process.exit(1)
end

-- Every sequestered file of a tree, keyed by its item and its path inside the item (code review 005 F1): an item's
-- folder moves between state folders and roots, and done promotes its acceptance/ to the project's
-- tests/acceptance/<id> (code review 006 F1), so a path is no identity. `listing` is `git ls-tree -r --name-only` of a
-- commit; `roots` that tree's project roots; `promotedRoots` its promoted-spec folders. A key found twice (a duplicate
-- item folder, or acceptance/ left beside its promoted copy, code review 007 F5) is ambiguous: `dups` names it.
type Entry = { id: string, path: string, promoted: boolean }
local function sequestered(
	listing: string,
	roots: { string },
	promotedRoots: { string }
): ({ [string]: Entry }, { string })
	local out: { [string]: Entry } = {}
	local dups: { string } = {}
	local function put(key: string, e: Entry)
		if out[key] then
			table.insert(dups, `{out[key].path} and {e.path}`)
		end
		out[key] = e
	end
	for path in string.gmatch(listing, "[^\n]+") do
		for _, root in roots do
			if string.sub(path, 1, #root + 1) == root .. "/" then
				local rest = string.sub(path, #root + 2)
				local inKind = string.match(rest, "^issues/(.*)$") or string.match(rest, "^rafts/(.*)$")
				if inKind then
					inKind = string.match(inKind, "^active/(.*)$")
						or string.match(inKind, "^done/(.*)$")
						or inKind
					local id, inner = string.match(inKind :: string, "^([fdcR]%d%d%d%d)/(.+)$")
					if
						id and (inner == "check.sh" or string.sub(inner :: string, 1, 11) == "acceptance/")
					then
						put(`{id}|{inner}`, { id = id, path = path, promoted = false })
					end
				end
			end
		end
		for _, dir in promotedRoots do
			if string.sub(path, 1, #dir + 1) == dir .. "/" then
				local id, rest = string.match(string.sub(path, #dir + 2), "^([fdcR]%d%d%d%d)/(.+)$")
				if id then
					put(`{id}|acceptance/{rest}`, { id = id, path = path, promoted = true })
				end
			end
		end
	end
	return out, dups
end
local function regAt(rev: string): projects.Registry?
	return projects.at(rev, TOP)
end
local function rootsOf(r: projects.Registry?): { string }
	return if r then projects.roots(r) else { projects.LEGACY }
end
local function promotedOf(r: projects.Registry?): { string }
	return if r then projects.acceptanceRoots(r) else { "tests/acceptance" }
end
local function tree(rev: string): string
	local ok, listing = git({ "ls-tree", "-r", "--name-only", rev })
	assert(ok, `git ls-tree {rev} failed`)
	return listing
end
local function show(rev: string, path: string): string
	local ok, text = git({ "show", `{rev}:{path}` })
	assert(ok, `git show {rev}:{path} failed`)
	return text
end
local function isDone(path: string): boolean
	return string.match(path, "^[^/]+/%.tracker/[a-z]+/done/") ~= nil
		or string.match(path, "^[^/]+/[^/]+/%.tracker/[a-z]+/done/") ~= nil
		or string.match(path, "^tracker/[a-z]+/done/") ~= nil
end
local function trim(x: string): string
	return (string.gsub(x, "%s+$", ""))
end
local OWN_ID = "c0120"
local bad: { string } = {}

-- The main this branch merged (code review 007 F1): AC18 judges only the branch's own changes. M is the merge-base
-- of HEAD and origin/main (as of the last fetch, as AC16 reads it); B is main as the move's base had it. A file main
-- changed between B and M is main's reviewed change (a prep, a ready, a done), and its reference is M's text; any
-- other file's is its text before the move. An origin/main that already holds the move (c0120 landed, or a ref moved
-- to this branch) leaves nothing to judge against, and refuses.
local mainBase, mainWhy = rewrites.mainBase(TOP)
if not mainBase then
	print(`finished: {mainWhy}`)
	process.exit(1)
end
local M: string = mainBase :: string
local ORIGIN = rewrites.originUrl(TOP)
local okB, mergePre = git({ "merge-base", pre :: string, M })
local B = trim(mergePre)
assert(okB and B ~= "", `git merge-base {pre} {M} failed`)

local preReg, mReg, bReg = regAt(pre :: string), regAt(M), regAt(B)
local preSet, preDups = sequestered(tree(pre :: string), rootsOf(preReg), promotedOf(preReg))
local mSet, mDups = sequestered(tree(M), rootsOf(mReg), promotedOf(mReg))
local bSet = sequestered(tree(B), rootsOf(bReg), promotedOf(bReg))
local ownSet = sequestered(tree(ownBase :: string), rootsOf(regAt(ownBase :: string)), {})
local headSet, headDups = sequestered(tree("HEAD"), projects.roots(reg), projects.acceptanceRoots(reg))
for _, d in preDups do
	table.insert(bad, `duplicate item folders before the move: {d}`)
end
for _, d in mDups do
	table.insert(bad, `duplicate item folders on main: {d}`)
end
for _, d in headDups do
	table.insert(bad, `duplicate item folders: {d}`)
end

-- A compaction merged in renumbers ids: refused, never read as deletions (code review 006 F1 (d))
local function compacted(id: string): string?
	local okC, map = git({ "show", "HEAD:z-nile/compaction.txt" })
	local okP, preMap = git({ "show", `{pre}:z-nile/compaction.txt` })
	if not okC then
		return nil
	end
	for line in string.gmatch(map, "[^\n]+") do
		local was, to = string.match(line, "^(%S+)%s+(%S+)$")
		if was == id and not (okP and string.find(preMap, line, 1, true)) then
			return to
		end
	end
	return nil
end

-- c0114's promoted specs carry c0120's overrides (Implementation step 9): their expected text is their text before the
-- move with c0114-overrides.patch applied: that file's section of the patch, applied by patch(1) to a copy in a
-- scratch folder under this home's .cache (no git, so no repository is in play)
-- The reviewed overrides patches (decided with the user, 2026-10-23: "Reviewed overrides patch"): c0114's for its
-- own promoted specs, and main-overrides.patch for every spec main promoted during c0120's window that the move must
-- override (its layout). Both are read from the prep commit the review pinned, never from HEAD: they change only in
-- prep, under the reviewer's pin.
local PATCHES: string = ""
for _, name in { "c0114-overrides.patch", "main-overrides.patch" } do
	local okP, text = git({ "show", `{ownBase}:{OWN}{name}` })
	if okP then
		PATCHES ..= text .. "\n"
	end
end
local function withOverrides(promoted: string, old: string): string?
	local text = PATCHES
	local header = `diff --git a/{promoted} b/{promoted}\n`
	local s = string.find(text, header, 1, true)
	if not s then
		return old -- the patch leaves this file as it was
	end
	local e = string.find(text, "\ndiff --git ", s + #header, true)
	if string.find(text, header, (e or #text) + 1, true) then
		return nil -- two sections for one file: ambiguous
	end
	local section = string.sub(text, s, if e then e else #text)
	local scratch = `{TOP}/z-nile/.cache/c0120-ac18-patch`
	if fs.isDir(scratch) then
		fs.removeDir(scratch)
	end
	fs.writeDir(scratch)
	fs.writeFile(`{scratch}/file`, old)
	fs.writeFile(`{scratch}/section.patch`, section)
	local r = process.exec(
		"patch",
		{ "-s", "-f", `{scratch}/file`, `{scratch}/section.patch` },
		{ cwd = scratch }
	)
	local out = if r.ok then fs.readFile(`{scratch}/file`) else nil
	fs.removeDir(scratch)
	return out
end

-- every key to judge: each item's before the move and on the merged main (c0120's own from the reviewed prep). A spec
-- already promoted before the move left sequestration then: the Overrides rule and override-markers judge it, not AC18
local keys: { [string]: boolean } = {}
local known: { [string]: boolean } = {}
local promotedBefore: { [string]: boolean } = {}
for key, e in preSet do
	if e.promoted then
		promotedBefore[key] = true
	end
end
for key, e in bSet do
	if e.promoted then
		promotedBefore[key] = true
	end
end
for key, e in preSet do
	if e.id ~= OWN_ID and not promotedBefore[key] then
		keys[key] = true
		known[e.id] = true
	end
end
for key, e in mSet do
	if e.id ~= OWN_ID and not promotedBefore[key] then
		keys[key] = true
		known[e.id] = true
	end
end
for key, e in ownSet do
	if e.id == OWN_ID then
		keys[key] = true
		known[e.id] = true
	end
end
-- an item main captured after the move's base and later removed or renamed stays known (code review 008 F5): the
-- branch must follow main there too; its files are in neither pre nor M, only in main's history between B and M
local removedOnMain: { [string]: boolean } = {}
do
	local okD, removed =
		git({ "log", "--no-renames", "--format=", "--name-only", "--diff-filter=D", `{B}..{M}` })
	if okD then
		local gone = sequestered(removed, rootsOf(mReg), promotedOf(mReg))
		for key, e in gone do
			if e.id ~= OWN_ID then
				known[e.id] = true
				removedOnMain[key] = true
			end
		end
	end
end

-- the world a finished check.sh's rewrite saw: the tree of the commit that made its text (code review 008 F4), so a
-- file committed later, at a path it names, can't change what is expected
-- The finished rewrite (JC1's group 2) ran with the hand-written core (group 4) in the working tree, so a file whose text
-- comes from group 2 or earlier is rewritten against group 4's tree: the third commit after the move on the branch's
-- first-parent line (the user decided the groups, "One PR, reviewed by commit group"; they are never rewritten).
-- Two worlds, neither chosen per file (code review 009 F2: a commit the author makes must not choose the world): group
-- 4's tree, pinned by its subject, and HEAD's. A finished check.sh's text is accepted when it equals the rewrite under
-- either.
local CORE_SUBJECT = "c0120: run each project from its home"
-- the anchors are the reviewer's (code review 010 F1): the move the search finds must be the pinned one, the pinned move
-- and core must be on HEAD's first-parent line, the core the third commit after the move there, and its subject the
-- hand-written core's (a second guard)
local function full(sha: string): string?
	local ok, out = git({ "rev-parse", "--verify", "-q", sha .. "^{commit}" })
	return if ok and trim(out) ~= "" then trim(out) else nil
end
local pinnedMove, pinnedCore = full(PINNED_MOVE :: string), full(PINNED_CORE :: string)
local okMv, moveCommit = git({ "log", "-1", "--format=%H", "--", rewrites.MARK })
if not pinnedMove or not pinnedCore or not okMv or trim(moveCommit) ~= pinnedMove then
	print(`finished: the move is not the one {from} pins ({PINNED_MOVE}): refusing`)
	process.exit(1)
end
local okFp, firstParents = git({ "rev-list", "--first-parent", "--reverse", "HEAD" })
local line: { string } = {}
for sha in string.gmatch(if okFp then firstParents else "", "%x+") do
	table.insert(line, sha)
end
local at = table.find(line, pinnedMove :: string)
local coreRev: string? = if at then line[at + 3] else nil
if coreRev ~= pinnedCore then
	print(
		`finished: the core is not the one {from} pins ({PINNED_CORE}) on HEAD's first-parent line, three after the move: refusing`
	)
	process.exit(1)
end
local coreSubject = trim(select(2, git({ "log", "-1", "--format=%s", coreRev :: string })))
if string.sub(coreSubject, 1, #CORE_SUBJECT) ~= CORE_SUBJECT then
	print(`finished: the pinned core is not the hand-written core ("{CORE_SUBJECT} …"): refusing`)
	process.exit(1)
end
local worldCore = rewrites.world(TOP, pre :: string, coreRev :: string, M)
local worldHead = rewrites.world(TOP, pre :: string, "HEAD", M)
local function finishedAtHead(id: string): boolean
	local c = headSet[`{id}|check.sh`]
	return c ~= nil and isDone(c.path)
end

local judged = 0
for key in keys do
	local idM, innerM = string.match(key, "^([^|]+)|(.*)$")
	local id: string = idM :: string
	local inner: string = innerM :: string
	-- the reference: c0120's own from the reviewed prep; else main's when main changed it after the move's base,
	-- else the text before the move; both sides changing it differently is ambiguous and refuses
	local ref: string? = nil
	local refPath: string? = nil
	local refPromoted = false
	if id == OWN_ID then
		local o = ownSet[key]
		if o then
			ref, refPath = show(ownBase :: string, o.path), o.path
		end
	else
		local p, m, b = preSet[key], mSet[key], bSet[key]
		local tP = if p then show(pre :: string, p.path) else nil
		local tM = if m then show(M, m.path) else nil
		local tB = if b then show(B, b.path) else nil
		local mainChanged = tM ~= tB
		local stackChanged = tP ~= tB
		-- the stack's change landed on main (c0114's branch merged as R0043): main's text is its newest form, and
		-- supersedes the stack's older one
		local landed = false
		if mainChanged and stackChanged and tM ~= tP and p then
			-- the stack's text reached main between B and M at this item's place: main carried it, then changed it
			-- further (Guess 18's supersede rule)
			local okO, blob = git({ "rev-parse", `{pre}:{p.path}` })
			if okO then
				-- bounded (code review 010 F2): between main's base and the merged main, at this item's own places
				local where = { p.path }
				if m then
					table.insert(where, m.path)
				end
				local argv = { "log", "-1", "--format=%H", `--find-object={trim(blob)}`, `{B}..{M}`, "--" }
				for _, w in where do
					table.insert(argv, w)
				end
				local okF, seen = git(argv)
				landed = okF and trim(seen) ~= ""
			end
		end
		if landed then
			stackChanged = false
		end
		if mainChanged and stackChanged and tM ~= tP then
			table.insert(
				bad,
				`{id}'s {inner}: changed on main ({if m then m.path else "removed"}) and before the move on this branch's base ({if p
					then p.path
					else "removed"}), differently: refusing`
			)
			continue
		end
		if mainChanged then
			ref, refPath = tM, if m then m.path else nil
			refPromoted = m ~= nil and m.promoted
		else
			ref, refPath = tP, if p then p.path else nil
		end
	end
	local h = headSet[key]
	if ref == nil then
		if h then
			table.insert(
				bad,
				if id == OWN_ID
					then `{h.path}: added (not in c0120's folder as reviewed)`
					else `{h.path}: kept, though the main it merged removed it`
			)
		end
		continue
	end
	if not h then
		local renamed = compacted(id)
		if renamed then
			table.insert(
				bad,
				`{refPath}: {id} was renumbered to {renamed} by a compaction merged in: refusing to judge it`
			)
		else
			table.insert(bad, `{refPath}: deleted (no {inner} of {id}'s at HEAD, in its folder or promoted)`)
		end
		continue
	end
	judged += 1
	-- a finished item's specs live in its promoted place (code review 008 F2): one moved back into its done/ folder
	-- keeps its text and loses its gate
	if string.sub(inner, 1, 11) == "acceptance/" and not h.promoted and finishedAtHead(id) then
		table.insert(
			bad,
			`{h.path}: not promoted ({id} is done: its specs belong in {projects.promotedDir(
				reg,
				string.match(h.path, "^(.-)/[a-z]+/done/") or "",
				id
			)})`
		)
	end
	local now = show("HEAD", h.path)
	local want: string? = ref
	if inner == "check.sh" and id ~= OWN_ID and isDone(h.path) then
		-- the move's rewrite, whoever finished it (main's done already rewrote its own item paths)
		local home = projects.homeOf(reg, h.path)
		local deletedHere = rewrites.DELETED[h.path]
		local function form(w: rewrites.World): string
			local text = rewrites.rewrite(ref :: string, home, w)
			return if deletedHere then rewrites.deleteCriteria(text, deletedHere) or "" else text
		end
		local underCore = form(worldCore)
		want = if now == underCore then underCore else form(worldHead)
	elseif h.promoted then
		-- a promoted spec: with the reviewed overrides patch's section for it, if any (c0114's own, promoted by this
		-- branch's done or main's; or one main promoted during the window, main-overrides.patch)
		want = withOverrides(h.path, ref :: string)
	end
	local deleted = rewrites.DELETED[h.path]
	if deleted and want and not (inner == "check.sh" and isDone(h.path)) then
		want = rewrites.deleteCriteria(want, deleted) or `cannot delete {table.concat(deleted, ", ")}`
	end
	if now ~= want then
		table.insert(
			bad,
			if inner == "check.sh" and isDone(h.path)
				then `{h.path}: not its text with exactly the rewrite{if deleted
					then " and the deleted criteria"
					else ""}`
				else `{h.path}: changed{if h.promoted and not refPromoted
					then ` (promoted from {refPath})`
					else ""}`
		)
	end
end
-- a file at HEAD in the folder of an item the reference holds, which the reference doesn't: added (a capture since
-- the move is a new item, and not judged)
for key, h in headSet do
	if not keys[key] and known[h.id] and not promotedBefore[key] then
		table.insert(
			bad,
			if removedOnMain[key]
				then `{h.path}: kept, though the main it merged removed it`
				else `{h.path}: added (not in {h.id}'s folder {if h.id == OWN_ID
					then "as reviewed"
					else "on the main it merged, nor before the move"})`
		)
	end
	-- a spec promoted before the move, moved back into its item's folder (code review 008 F2)
	if promotedBefore[key] and not h.promoted then
		table.insert(bad, `{h.path}: not promoted ({h.id}'s specs were promoted before the move)`)
	end
end
table.sort(bad)
if #bad > 0 then
	print(table.concat(bad, "\n"))
	print(
		`finished: {#bad} of {judged} sequestered files differ from their reference (before the move {pre}, main {M} from {ORIGIN}; c0120's own from {from})`
	)
	process.exit(1)
end
print(
	`finished: {judged} sequestered files are their reference (before the move {pre}, main {M} from {ORIGIN}), finished check.sh files rewritten; c0120's own as {from} records them`
)
