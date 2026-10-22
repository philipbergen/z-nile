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
			local text = "\n" .. fs.readFile(`{TOP}/{OWN}{name}`)
			local sha = string.match(text, "\nPrep reference: (%x+)")
			if sha and string.find(text, "\nVerdict: approve", 1, true) then
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

-- where a file of a current root was before the move: pickman's root was tracker/
local function before(path: string): string
	local rest = string.match(path, "^pickman/%.tracker/(.*)$")
	return if rest then `tracker/{rest}` else path
end

local bad: { string } = {}
local judged = 0
for _, root in projects.roots(reg) do
	local ok, listing = git({ "ls-files", "--", root })
	assert(ok, "git ls-files failed")
	for path in string.gmatch(listing, "[^\n]+") do
		local isCheck = string.match(path, "/check%.sh$") ~= nil
		local isSpec = string.find(path, "/acceptance/", 1, true) ~= nil
		if isCheck or isSpec then
			local own = string.sub(path, 1, #OWN) == OWN
			local okOld, old = git({ "show", `{if own then ownBase :: string else pre}:{before(path)}` })
			if okOld then
				judged += 1
				local now = fs.readFile(`{TOP}/{path}`)
				local finished = string.match(path, "^[^/]+/%.tracker/[a-z]+/done/") ~= nil
					or string.match(path, "^[^/]+/[^/]+/%.tracker/[a-z]+/done/") ~= nil
				local want = if finished and isCheck
					then rewrites.rewrite(old, projects.homeOf(reg, path), world)
					else old
				-- the deleted criteria (Guess 17): exactly those check statements go, after the rewrite
				local deleted = rewrites.DELETED[path]
				if deleted then
					want = rewrites.deleteCriteria(want, deleted)
						or `cannot delete {table.concat(deleted, ", ")}`
				end
				if now ~= want then
					table.insert(
						bad,
						if finished and isCheck
							then `{path}: not its text with exactly the rewrite{if rewrites.DELETED[path]
								then " and the deleted criteria"
								else ""}`
							else `{path}: changed`
					)
				end
			end
		end
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
