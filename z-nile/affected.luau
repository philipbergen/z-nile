--!strict
-- Which specs does a change affect?
--   lune run z-nile/affected                    -- changes vs origin/main (or main) + working tree
--   lune run z-nile/affected -- --base <ref>    -- changes vs <ref>
--   lune run z-nile/affected -- <file> ...      -- explicit changed files
--   ... --project <name>                         -- that project's specs only, relative to its home
--   ... --static                                 -- print the projects whose static stages the change affects
--                                                -- ("ALL", or one name per line), not the specs
--   ... --touches <folder>                       -- print "yes" when the change touches a path under the folder, else
--                                                -- "no" (the gate's test for z-nile/go, f0424)
--   ... --own-acceptance                         -- also the layer's own sequestered acceptance specs (./zn finish
--                                                -- only: it records them in results.txt; the gate never passes it)
-- Prints one spec path per line (repo-relative; home-relative with --project). Prints nothing when no watch
-- file names a changed path. Never prints "ALL": a full run is --full, not a fallback.
-- On a layer branch (R0010/1/c0010), a change that includes a source file selects that ticket's
-- promoted acceptance specs (tests/acceptance/<id>/) when the ticket has no watch file yet, and only when one of its
-- watch files names the path once the watches exist. On an old raft branch (R####-…), a source change selects that
-- raft's members' promoted ones. A sequestered spec (under a project root: an item's acceptance/ or proofs/) is
-- printed only with --own-acceptance, and then only the current layer's ticket's (every member's on an old raft
-- branch) (d0297): the gate never runs one.

local changes = require("./lib/changed")
local context = require("./lib/context")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./engine/projects")
local sel = require("./lib/select")
local stack = require("./engine/stack")
local stdio = require("@lune/stdio")
local store = require("./engine/store")
local watch = require("./lib/watch")

local base: string? = nil
local only: string? = nil
local staticOnly = false
local ownAcceptance = false
local touches: string? = nil
local explicit: { string } = {}
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--base" then
		base = process.args[i + 1]
		i += 1
	elseif a == "--static" then
		staticOnly = true
	elseif a == "--touches" then
		touches = process.args[i + 1]
		i += 1
	elseif a == "--own-acceptance" then
		ownAcceptance = true
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
if touches then
	local prefix = (string.gsub(touches, "/+$", "")) .. "/"
	for _, f in files do
		if string.sub(f, 1, #prefix) == prefix then
			print("yes")
			process.exit(0)
		end
	end
	print("no")
	process.exit(0)
end
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
	local name = trim(branch.stdout)
	local out: { string } = {}
	local function addDir(dir: string)
		if not fs.isDir(dir) then
			return
		end
		for _, specName in fs.readDir(dir) do
			if string.sub(specName, -10) == ".spec.luau" then
				table.insert(out, `{dir}/{specName}`)
			end
		end
	end
	-- A watch file that exists decides. No watch file yet means the ticket is still being written.
	local function watches(dir: string): (boolean, boolean)
		if not fs.isDir(dir) then
			return false, false
		end
		local any = false
		local hit = false
		for _, specName in fs.readDir(dir) do
			if specName == "watch.txt" or string.sub(specName, -10) == ".watch.txt" then
				any = true
				local text = fs.readFile(`{dir}/{specName}`)
				for _, f in changed do
					if string.find("\n" .. text, "\n" .. f .. "\n", 1, true) then
						hit = true
					end
				end
			end
		end
		return any, hit
	end
	local layer = stack.parse(name)
	if layer then
		local m = store.find(layer.issue)
		if not m then
			return {}
		end
		local dirs = { projects.promotedDir(reg, m.root, m.id), `{m.dir}/acceptance` }
		local any, hit = false, false
		for _, dir in dirs do
			local saw, named = watches(dir)
			any = any or saw
			hit = hit or named
		end
		if not any or hit then
			for _, dir in dirs do
				addDir(dir)
			end
		end
		return out
	end
	local raftId = string.match(name, "^(R%d%d%d%d)%-")
	if not raftId then
		return {}
	end
	local raft = store.find(raftId)
	if not raft or raft.kind ~= "raft" then
		return {}
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
if ownAcceptance then
	ctx.own = ctx.current
end
local result = sel.affected(ctx, files, only)
-- A deleted spec is a changed path, and the pure selector still names it. There is nothing to run.
local homePrefix = ""
if only then
	local home = (projects.named(reg, only) :: any).home
	homePrefix = if home == "." then "" else home .. "/"
end
for _, s in result :: { string } do
	if fs.isFile(`{homePrefix}{s}`) then
		print(s)
	end
end
