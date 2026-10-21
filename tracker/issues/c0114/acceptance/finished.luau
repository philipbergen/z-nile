--!strict
-- c0114 AC14, run by check.sh (never by the spec runner: it reads git): every item file that sequestration covers
-- (check.sh and acceptance/**, in every project root) is its text at `base` (the newest commit of origin/main the
-- branch holds), at its old path when it moved, unchanged for an unfinished item, and for a finished one with exactly
-- the rewrites of rewrites.luau (the user's exception: "Rewrite finished files"). c0114 and its raft are left out:
-- their prep edits them. Read-only. Usage: lune run finished.luau <base> <c0114's folder>
local fs = require("@lune/fs")
local process = require("@lune/process")
local rewrites = require("./rewrites")

local base = process.args[1] or error("usage: finished.luau <base> <item folder>")
local here = process.args[2] or error("usage: finished.luau <base> <item folder>")
local ROOTS = { "tracker", "z-nile/.tracker" }

local function git(args: { string }): (boolean, string)
	local r = process.exec("git", args)
	return r.ok, r.stdout
end

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
		local want = if f.done then rewrites.expected(f.id, text, moved) else text
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
