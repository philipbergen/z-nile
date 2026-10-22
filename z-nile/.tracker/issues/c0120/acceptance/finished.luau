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
local world = rewrites.world(TOP, pre :: string)
local reg = projects.load(TOP, true)

-- c0120's own item folder changes after the move only through its prep (Guess 17's decision came that way). Its files
-- are judged against the prep commit a reviewer recorded (decided with the user, 2026-10-21: "Reviewer-pinned commit"):
-- a `Prep reference: <sha>` line in the newest approved review file (a code review's review-NNN.md before a design
-- review's design-review-NNN.md, the higher number first), which only a reviewer writes. Never a branch ref: its author
-- can move one (code review 004 F1). No recorded sha, or one the branch doesn't contain, refuses.
local OWN = if fs.isDir(`{TOP}/z-nile/.tracker/issues/c0120`)
	then "z-nile/.tracker/issues/c0120/"
	else "z-nile/.tracker/issues/done/c0120/"
local function recorded(): (string?, string)
	local best: { rank: number, file: string, sha: string }? = nil
	for _, name in fs.readDir(`{TOP}/{OWN}`) do
		local code = string.match(name, "^review%-(%d+)%.md$")
		local n = code or string.match(name, "^design%-review%-(%d+)%.md$")
		if n then
			-- the verdict is the last `Verdict:` line (an earlier one may quote the format, code review 005 F5); a second
			-- `Prep reference:` line is ambiguous and refuses
			local verdict: string? = nil
			local refs: { string } = {}
			for line in string.gmatch(fs.readFile(`{TOP}/{OWN}{name}`), "[^\n]+") do
				local v = string.match(line, "^Verdict: (.-)%s*$")
				if v then
					verdict = v
				end
				local r = string.match(line, "^Prep reference: (%x+)%s*$")
				if r then
					table.insert(refs, r)
				end
			end
			if #refs > 1 then
				return nil, `{name} records {#refs} Prep reference lines`
			end
			local sha = refs[1]
			if sha and verdict == "approve" then
				local rank = (if code then 100000 else 0) + (tonumber(n) :: number)
				if not best or rank > (best :: any).rank then
					best = { rank = rank, file = name, sha = sha }
				end
			end
		end
	end
	if not best then
		return nil, `no approved review in {OWN} records a "Prep reference: <sha>"`
	end
	local b = best :: { rank: number, file: string, sha: string }
	local okV, full = git({ "rev-parse", "--verify", "-q", b.sha .. "^{commit}" })
	full = string.gsub(full, "%s+$", "")
	if not okV or full == "" then
		return nil, `{b.file}'s Prep reference {b.sha} is no commit here`
	end
	if not git({ "merge-base", "--is-ancestor", full, "HEAD" }) then
		return nil, `{b.file}'s Prep reference {b.sha} is not in this branch`
	end
	return full, b.file
end
local ownBase, from = recorded()
if not ownBase then
	print(`finished: {from}: refusing`)
	process.exit(1)
end

-- Every sequestered file, keyed by its item and its path inside the item's folder (code review 005 F1): an item's
-- folder moves between state folders (active/, done/) and roots (tracker/ to pickman/.tracker/), so a path is no
-- identity. `listing` is `git ls-files` (HEAD's index) or `git ls-tree` of a commit; `roots` that tree's project roots.
type Entry = { id: string, path: string }
local function sequestered(listing: string, roots: { string }): { [string]: Entry }
	local out: { [string]: Entry } = {}
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
						out[`{id}|{inner}`] = { id = id, path = path }
					end
				end
			end
		end
	end
	return out
end
local function rootsAt(rev: string): { string }
	local at = projects.at(rev, TOP)
	return if at then projects.roots(at) else { projects.LEGACY }
end
local function tree(rev: string): string
	local ok, listing = git({ "ls-tree", "-r", "--name-only", rev })
	assert(ok, `git ls-tree {rev} failed`)
	return listing
end
local OWN_ID = "c0120"
-- the reference set: every item's files before the move, c0120's own as the review recorded them
local base: { [string]: Entry & { rev: string } } = {}
for key, e in sequestered(tree(pre :: string), rootsAt(pre :: string)) do
	if e.id ~= OWN_ID then
		base[key] = { id = e.id, path = e.path, rev = pre :: string }
	end
end
for key, e in sequestered(tree(ownBase :: string), rootsAt(ownBase :: string)) do
	if e.id == OWN_ID then
		base[key] = { id = e.id, path = e.path, rev = ownBase :: string }
	end
end
local okL, headListing = git({ "ls-files" })
assert(okL, "git ls-files failed")
local head = sequestered(headListing, projects.roots(reg))
local known: { [string]: boolean } = {}
for _, e in base do
	known[e.id] = true
end

local bad: { string } = {}
local judged = 0
for key, b in base do
	local h = head[key]
	if not h or not fs.isFile(`{TOP}/{h.path}`) then
		table.insert(bad, `{b.path}: deleted (no {string.match(key, "|(.*)$")} in {b.id}'s folder now)`)
		continue
	end
	judged += 1
	local okOld, old = git({ "show", `{b.rev}:{b.path}` })
	assert(okOld, `git show {b.rev}:{b.path} failed`)
	local now = fs.readFile(`{TOP}/{h.path}`)
	local isCheck = string.match(key, "|check%.sh$") ~= nil
	local finished = b.id ~= OWN_ID
		and (
			string.match(h.path, "^[^/]+/%.tracker/[a-z]+/done/") ~= nil
			or string.match(h.path, "^[^/]+/[^/]+/%.tracker/[a-z]+/done/") ~= nil
		)
	local want = if finished and isCheck
		then rewrites.rewrite(old, projects.homeOf(reg, h.path), world)
		else old
	-- the deleted criteria (Guess 17): exactly those check statements go, after the rewrite
	local deleted = rewrites.DELETED[h.path]
	if deleted then
		want = rewrites.deleteCriteria(want, deleted) or `cannot delete {table.concat(deleted, ", ")}`
	end
	if now ~= want then
		table.insert(
			bad,
			if finished and isCheck
				then `{h.path}: not its text with exactly the rewrite{if deleted
					then " and the deleted criteria"
					else ""}`
				else `{h.path}: changed`
		)
	end
end
-- a file in the folder of an item the reference holds, which the reference doesn't: added (a capture since the move
-- is a new item, and not judged)
for key, h in head do
	if not base[key] and known[h.id] then
		table.insert(
			bad,
			`{h.path}: added (not in {h.id}'s folder {if h.id == OWN_ID
				then "as reviewed"
				else "before the move"})`
		)
	end
end
table.sort(bad)
if #bad > 0 then
	print(table.concat(bad, "\n"))
	print(
		`finished: {#bad} of {judged} sequestered files differ from their text before the move ({pre}; c0120's own from {from})`
	)
	process.exit(1)
end
print(
	`finished: {judged} sequestered files are their text before the move, finished check.sh files rewritten ({pre}; c0120's own as {from} records them)`
)
