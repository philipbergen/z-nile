--!strict
-- c0120 AC18, run by check.sh (never by the spec runner: it reads git): every item file that sequestration covers
-- (check.sh and acceptance/**, in every current project root) is its text before the move, read at its old place when
-- it moved (pickman's items were under tracker/): unchanged, or, for a finished item's check.sh, with exactly the
-- rewrite of rewrites.luau (the user's exception, 2026-10-21: "Rewrite them too"). A file that wasn't there before the
-- move (a capture since) is not judged; c0120's own files are judged against its prep (below). Read-only. Usage: lune run finished.luau -- <the checkout's top>
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

-- c0120's own item folder is its prep's: it changes after the move only by merging prep-c0120 (Guess 17's decision came
-- that way), so its files are judged against the newest prep commit merged into HEAD, else the tree before the move
local OWN = "z-nile/.tracker/issues/c0120/"
local ownBase: string = pre :: string
for _, ref in { "origin/prep-c0120", "prep-c0120" } do
	local okB, base = git({ "merge-base", "HEAD", ref })
	base = string.gsub(base, "%s+$", "")
	if okB and base ~= "" then
		ownBase = base
		break
	end
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
			local okOld, old = git({ "show", `{if own then ownBase else pre}:{before(path)}` })
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
	print(`finished: {#bad} of {judged} sequestered files differ from their text before the move ({pre})`)
	process.exit(1)
end
print(
	`finished: {judged} sequestered files are their text before the move, finished check.sh files rewritten ({pre})`
)
