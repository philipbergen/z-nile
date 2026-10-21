--!strict
-- c0115 (E4): rewrites lesson ids from the old skill folders to the new ones, in every harvest.md under every
-- project root (backlog, active/ and done/) and in every lesson file's body. Run from the repository root, after
-- the skill folders have moved:
--   lune run "$(./zn find c0115)/experiments/rename-lesson-ids" [-- --dry-run]
-- An id `<old>/<slug>` is rewritten to `<new>/<slug>` only where that lesson file exists under its new skill, so a
-- path such as scripts/tracker/x.luau is never touched. Prints each changed file with its count, and every old id
-- it found with no lesson at the new place (exit 1). Idempotent: a second run changes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")

local NEW = {
	["make-issue"] = "z-ticket",
	["ticket-prep"] = "z-design",
	["ready-raft"] = "z-ready",
	["launch-raft"] = "z-run",
	["execute-raft"] = "z-run",
	["stop-raft"] = "z-stop",
	review = "zz-review",
	tracker = "zz-rules",
	metrics = "zz-stats",
	testing = "zz-test",
	architecture = "zz-arch", -- every architecture lesson is the tooling's (c0115 design §3)
}
local FOLDERS = { "z-nile/skills", "pickman/skills" }
local dry = table.find(process.args, "--dry-run") ~= nil

-- every lesson that exists, "<skill>/<slug>", read before any rewrite (gsub callbacks can't yield to fs)
local existing: { [string]: boolean } = {}
for _, f in FOLDERS do
	if fs.isDir(f) then
		for _, skill in fs.readDir(f) do
			local dir = `{f}/{skill}/lessons`
			if fs.isDir(dir) then
				for _, name in fs.readDir(dir) do
					local slug = string.match(name, "^(.+)%.md$")
					if slug then
						existing[`{skill}/{slug}`] = true
					end
				end
			end
		end
	end
end

local missing: { [string]: boolean } = {}

-- One pass over `text`: every `<old>/<slug>` token (at the start or after a space, comma, parenthesis or backtick)
-- whose new lesson exists becomes `<new>/<slug>`.
-- `ledger`: the text is a harvest.md, where every such token is an id, so one with no lesson is reported; in a
-- lesson body a token may be a path (tracker/next), so it is only left alone.
local function rewrite(text: string, ledger: boolean): (string, number)
	local n = 0
	local out = string.gsub(
		text,
		"([%s,(`]?)([%a-]+)/([%w][%w-]*)",
		function(pre: string, old: string, slug: string)
			local new = NEW[old]
			if not new then
				return nil
			end
			if existing[`{new}/{slug}`] then
				n += 1
				return `{pre}{new}/{slug}`
			end
			if ledger then
				missing[`{old}/{slug}`] = true
			end
			return nil
		end
	)
	return out, n
end

local function walk(dir: string, visit: (string) -> ())
	if not fs.isDir(dir) then
		return
	end
	local names = fs.readDir(dir)
	table.sort(names)
	for _, name in names do
		local p = `{dir}/{name}`
		if fs.isDir(p) then
			walk(p, visit)
		else
			visit(p)
		end
	end
end

local function roots(): { string }
	local r = process.exec("lune", { "run", "z-nile/roots" })
	if not r.ok then
		error(`lune run z-nile/roots failed: {r.stderr}`)
	end
	local out = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, line)
	end
	table.insert(out, "tracker") -- the retired root, for any ledger left there
	return out
end

local total = 0
local function fix(path: string)
	local text = fs.readFile(path)
	local out, n = rewrite(text, string.match(path, "/harvest%.md$") ~= nil)
	if n > 0 then
		total += n
		print(`{n} {path}`)
		if not dry then
			fs.writeFile(path, out)
		end
	end
end

for _, root in roots() do
	walk(root, function(p)
		if string.match(p, "/harvest%.md$") then
			fix(p)
		end
	end)
end
for _, f in FOLDERS do
	walk(f, function(p)
		if string.match(p, "/lessons/[^/]+%.md$") then
			fix(p)
		end
	end)
end
print(`{total} ids rewritten{if dry then " (dry run: nothing written)" else ""}`)
local gaps = {}
for id in missing do
	table.insert(gaps, id)
end
table.sort(gaps)
if #gaps > 0 then
	print("old ids with no lesson at the new place:\n" .. table.concat(gaps, "\n"))
	process.exit(1)
end
