--!strict
-- Which specs does a change affect?
--   lune run z-nile/affected                    -- changes vs origin/main (or main) + working tree
--   lune run z-nile/affected -- --base <ref>    -- changes vs <ref>
--   lune run z-nile/affected -- <file> ...      -- explicit changed files
--   ... --project <name>                         -- that project's specs only, relative to its home
--   ... --static                                 -- print the projects whose static stages the change affects
--                                                -- ("ALL", or one name per line), not the specs
-- Prints one spec path per line (repo-relative; home-relative with --project). Prints nothing when no watch
-- file names a changed path. Never prints "ALL": a full run is --full, not a fallback.
-- On a raft branch (R####-…), a change that includes a source file also selects that raft's acceptance specs.

local changes = require("./lib/changed")
local context = require("./lib/context")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./engine/projects")
local sel = require("./lib/select")
local stdio = require("@lune/stdio")
local store = require("./engine/store")
local watch = require("./lib/watch")

local base: string? = nil
local only: string? = nil
local staticOnly = false
local explicit: { string } = {}
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--base" then
		base = process.args[i + 1]
		i += 1
	elseif a == "--static" then
		staticOnly = true
	elseif a == "--project" then
		only = process.args[i + 1]
		i += 1
	elseif a ~= "--" and a ~= "--graph-only" then
		-- --graph-only is accepted so older callers still run; the require graph is not read
		table.insert(explicit, a)
	end
	i += 1
end

local reg = projects.load()
if only and not projects.named(reg, only) then
	stdio.ewrite(`affected: no project {only} in {projects.FILE}\n`)
	process.exit(2)
end
local rules = sel.rules(reg)
local files = if #explicit > 0 then explicit else changes.files(base)
if staticOnly then
	local answer = sel.staticProjects(rules, files)
	if answer == "ALL" then
		print("ALL")
	else
		for _, name in answer :: { string } do
			print(name)
		end
	end
	process.exit(0)
end

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- Acceptance specs of the raft this branch is for, and only when the change includes a source file.
-- A tracker file, a skill or a lesson adds none, so those changes select nothing on their own.
local function currentSpecs(changed: { string }): { string }
	local source = false
	for _, f in changed do
		if watch.isSource(f) then
			source = true
			break
		end
	end
	if not source then
		return {}
	end
	local branch = process.exec("git", { "rev-parse", "--abbrev-ref", "HEAD" })
	if not branch.ok then
		return {}
	end
	local raftId = string.match(trim(branch.stdout), "^(R%d%d%d%d)%-")
	if not raftId then
		return {}
	end
	local raft = store.find(raftId)
	if not raft or raft.kind ~= "raft" then
		return {}
	end
	local out: { string } = {}
	local function addDir(dir: string)
		if not fs.isDir(dir) then
			return
		end
		for _, name in fs.readDir(dir) do
			if string.sub(name, -10) == ".spec.luau" then
				table.insert(out, `{dir}/{name}`)
			end
		end
	end
	for _, m in store.members(raftId) do
		addDir(projects.promotedDir(reg, m.root, m.id))
		addDir(`{m.dir}/acceptance`)
	end
	return out
end

local built, why = context.build(reg)
if built == nil then
	stdio.ewrite(`affected: {why}\n`)
	process.exit(2)
end
local ctx = built :: sel.Context
ctx.current = currentSpecs(files)
local result = sel.affected(ctx, files, only)
for _, s in result :: { string } do
	print(s)
end
