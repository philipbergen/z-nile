--!strict
-- c0114 AC14, run by check.sh (never by the spec runner: it reads git): every item file that sequestration covers
-- (check.sh and acceptance/**, in every project root) is its text at `base`, the merge base of HEAD and main's tip as
-- the origin repository reports it (`git ls-remote origin refs/heads/main`, never a local ref the author can move:
-- decided with the user, 2026-10-23, "Allow the locked edit"), at its old path when it moved, unchanged for an unfinished item, and for a finished one with exactly
-- the rewrites of rewrites.luau (the user's exception: "Rewrite finished files"). c0114 and its raft are left out:
-- their prep edits them. Read-only; refuses when main's tip can't be read, isn't a local commit (fetch), or shares no
-- history with HEAD. Usage: lune run finished.luau <c0114's folder> (in the checkout to check)
local fs = require("@lune/fs")
local process = require("@lune/process")
local rewrites = require("./rewrites")

local here = process.args[1] or error("usage: finished.luau <item folder>")
local ROOTS = { "tracker", "z-nile/.tracker" }

local function git(args: { string }): (boolean, string)
	local r = process.exec("git", args)
	return r.ok, r.stdout
end
local function refuse(why: string): never
	print(`finished: {why}`)
	process.exit(1)
	error(why)
end

-- main's tip from origin itself, then the newest commit the branch shares with it
local listed, remote = git({ "ls-remote", "origin", "refs/heads/main" })
local tip = if listed then string.match(remote, "^(%x+)%s+refs/heads/main") else nil
if not tip then
	refuse("cannot read main's tip from origin (git ls-remote origin refs/heads/main)")
end
if not git({ "cat-file", "-e", (tip :: string) .. "^{commit}" }) then
	refuse(
		`origin's main is at {tip}, which this checkout doesn't have: fetch (git fetch origin main) and rerun`
	)
end
local based, mb = git({ "merge-base", "HEAD", tip :: string })
if not based or not string.match(mb, "%x") then
	refuse(`HEAD and origin's main ({tip}) share no history`)
end
local base = (string.gsub(mb, "%s+$", ""))

-- c0114 and its raft
local self = string.match(here, "([fdcR]%d%d%d%d)$") or "c0114"
local raft = string.match(fs.readFile(`{here}/{self}.md`), "\nraft:%s*(R%d%d%d%d)") or ""

local moved: { [string]: boolean } = {}
local files: { { path: string, id: string, done: boolean } } = {}
local ok, listing = git({ "ls-files", "--", table.unpack(ROOTS) })
assert(ok, "git ls-files failed")
for path in string.gmatch(listing, "[^\n]+") do
	for _, root in ROOTS do
		local rest = if string.sub(path, 1, #root + 1) == root .. "/"
			then string.sub(path, #root + 2)
			else nil
		local kind, state, id, file
		if rest then
			kind, state, id, file = string.match(rest, "^(%a+)/(%a+)/([fdcR]%d%d%d%d)/(.+)$")
			if not kind then
				kind, id, file = string.match(rest, "^(%a+)/([fdcR]%d%d%d%d)/(.+)$")
				state = ""
			end
		end
		if id and (kind == "issues" or kind == "rafts") then
			if root ~= "tracker" then
				moved[id] = true
			end
			local name = file :: string
			if
				(name == "check.sh" or string.sub(name, 1, 11) == "acceptance/")
				and id ~= self
				and id ~= raft
			then
				table.insert(files, { path = path, id = id, done = state == "done" })
			end
		end
	end
end

local bad = 0
local rewritten = 0
for _, f in files do
	local old = if string.sub(f.path, 1, 15) == "z-nile/.tracker"
		then "tracker" .. string.sub(f.path, 16)
		else f.path
	local found, text = git({ "show", `{base}:{f.path}` })
	if not found then
		found, text = git({ "show", `{base}:{old}` })
	end
	local now = fs.readFile(f.path)
	if not found then
		print(`new: {f.path} is not at {base}, at its path or at {old}`)
		bad += 1
	else
		local want = if f.done then rewrites.expected(f.path, text, moved) else text
		if now ~= want then
			print(
				`changed: {f.path} is not its text at {base}{if f.done
					then " with the listed rewrites"
					else ""}`
			)
			bad += 1
		elseif now ~= text then
			rewritten += 1
		end
	end
end
print(`{#files} sequestered files, {rewritten} finished ones rewritten, {bad} wrong`)
process.exit(if bad == 0 then 0 else 1)
