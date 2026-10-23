--!strict
-- The project registry (c0114): z-nile/projects.toml names every project and the tracker root that holds its issues
-- and rafts. A directory that is not listed is not a project. `parse` and the path helpers are pure; `load` reads the
-- working tree and `at` reads a commit. The publish guard reads the registry only from origin/main (publish.luau).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local projects = {}

export type Project = { name: string, root: string }
export type Registry = { projects: { Project }, retired: { string } }

projects.FILE = "z-nile/projects.toml"
-- The one root a tree had before c0114. A tree or a commit with no registry has exactly this root.
projects.LEGACY = "tracker"

local NAME = "^[a-z][a-z0-9]*$"

local function nameOk(name: string): boolean
	if string.match(name, NAME) then
		return true
	end
	return string.match(name, "^[a-z][a-z0-9%-]*[a-z0-9]$") ~= nil and string.find(name, "--", 1, true) == nil
end

-- A root has one of two shapes: the legacy `tracker`, or `<name>/.tracker` with a project name as its folder. Nothing
-- else (no `.`, `..`, absolute path, `src`, or a deeper folder) can ever be a root.
function projects.shapeOk(root: string): boolean
	if root == projects.LEGACY then
		return true
	end
	local seg = string.match(root, "^([^/]+)/%.tracker$")
	return seg ~= nil and nameOk(seg)
end

-- The registry of a tree or commit from before c0114, which has no registry file: the one root `tracker`.

-- The registry in `text`, or nil and the first problem. Every key is known, every name and root is valid and unique,
-- and a project's root is `<name>/.tracker` or the legacy `tracker` (which at most one project holds).
function projects.parse(text: string): (Registry?, string?)
	local ok, decoded = pcall(serde.decode, "toml" :: "toml", text)
	if not ok or type(decoded) ~= "table" then
		return nil, `{projects.FILE} is not valid TOML: {string.match(tostring(decoded), "[^\n]+") or ""}`
	end
	local doc = decoded :: { [string]: any }
	for k in doc do
		if k ~= "project" and k ~= "retired" then
			return nil, `{projects.FILE}: unknown key {k}`
		end
	end
	local list = doc.project
	if type(list) ~= "table" or #list == 0 then
		return nil, `{projects.FILE}: no [[project]] entries`
	end
	local out: { Project } = {}
	local names: { [string]: boolean } = {}
	local roots: { [string]: boolean } = {}
	for i, p in list do
		if type(p) ~= "table" then
			return nil, `{projects.FILE}: project {i} is not a table`
		end
		for k in p do
			if k ~= "name" and k ~= "root" then
				return nil, `{projects.FILE}: project {i} has an unknown key {k}`
			end
		end
		local name, root = p.name, p.root
		if type(name) ~= "string" or not nameOk(name) then
			return nil, `{projects.FILE}: project {i} needs a name of lowercase words joined by hyphens`
		end
		if type(root) ~= "string" or not (root == projects.LEGACY or root == `{name}/.tracker`) then
			return nil, `{projects.FILE}: {name}'s root must be "{name}/.tracker" or "{projects.LEGACY}"`
		end
		if names[name] then
			return nil, `{projects.FILE}: project {name} is listed twice`
		end
		if roots[root] then
			return nil, `{projects.FILE}: root {root} is listed twice`
		end
		names[name], roots[root] = true, true
		table.insert(out, { name = name, root = root })
	end
	local retired: { string } = {}
	local raw = doc.retired
	if raw ~= nil then
		if type(raw) ~= "table" then
			return nil, `{projects.FILE}: retired must be a list of roots`
		end
		for _, r in raw do
			if type(r) ~= "string" or not projects.shapeOk(r) then
				return nil,
					`{projects.FILE}: retired root {tostring(r)} is not "<name>/.tracker" or "{projects.LEGACY}"`
			end
			if roots[r] then
				return nil, `{projects.FILE}: {r} is both a root and retired`
			end
			roots[r] = true
			table.insert(retired, r)
		end
	end
	return { projects = out, retired = retired }, nil
end

-- The current roots, in registry order.
function projects.roots(reg: Registry): { string }
	local out: { string } = {}
	for _, p in reg.projects do
		table.insert(out, p.root)
	end
	return out
end

-- Every root that ever held items: the current ones, then the retired ones. History readers (the trail, the board's
-- history) walk these; nothing else does.
function projects.allRoots(reg: Registry): { string }
	local out = projects.roots(reg)
	for _, r in reg.retired do
		table.insert(out, r)
	end
	return out
end

-- The root of `roots` that a repo-relative `path` lies under, and the rest of the path after `<root>/`.
function projects.rootOf(path: string, roots: { string }): (string?, string?)
	for _, r in roots do
		if string.sub(path, 1, #r + 1) == r .. "/" then
			return r, string.sub(path, #r + 2)
		end
	end
	return nil, nil
end

function projects.projectOf(reg: Registry, root: string): Project?
	for _, p in reg.projects do
		if p.root == root then
			return p
		end
	end
	return nil
end

-- The project named `name`, or nil.
-- The folder a project's root sits in (`z-nile` for `z-nile/.tracker`); nil for the legacy `tracker`, whose project
-- has no folder of its own (pickman, until c0120 gives it `pickman/`).
function projects.folderOf(root: string): string?
	return string.match(root, "^([^/]+)/%.tracker$")
end

-- The project whose folder holds `dir` (a path relative to the checkout; "" is its root), or nil when none does.
function projects.inDir(reg: Registry, dir: string): Project?
	for _, p in reg.projects do
		local folder = projects.folderOf(p.root)
		if folder and (dir == folder or string.sub(dir, 1, #folder + 1) == folder .. "/") then
			return p
		end
	end
	return nil
end

function projects.named(reg: Registry, name: string): Project?
	for _, p in reg.projects do
		if p.name == name then
			return p
		end
	end
	return nil
end

local cache: { [string]: Registry } = {}

-- The working tree's registry under `dir` (default: the current directory, which tracker commands set to the
-- checkout). A missing file and a file that does not parse are both errors: the tracker never guesses which roots a
-- project has (c0114, decided with the user). A tree from before c0114 runs its own engine, which needs no registry.
function projects.load(dir: string?, fresh: boolean?): Registry
	local base = dir or "."
	local hit = if fresh then nil else cache[base]
	if hit then
		return hit
	end
	local path = `{base}/{projects.FILE}`
	if not fs.isFile(path) then
		error(`no {projects.FILE} in {base}: the tracker refuses to guess the project roots`, 0)
	end
	local parsed, err = projects.parse(fs.readFile(path))
	if not parsed then
		error(err, 0)
	end
	local reg: Registry = parsed
	cache[base] = reg
	return reg
end

-- The registry at commit `rev` (as `git show <rev>:z-nile/projects.toml` in `cwd`). Nil and the reason when the file
-- is missing (a commit from before c0114) or bad: every reader refuses then, never guessing the roots.
function projects.at(rev: string, cwd: string?): (Registry?, string?)
	local listed = process.exec("git", { "ls-tree", "--name-only", rev, "--", projects.FILE }, { cwd = cwd })
	if not listed.ok then
		return nil, `cannot read {rev}: {listed.stderr}`
	end
	if string.match(listed.stdout, "%S") == nil then
		return nil, `{rev} has no {projects.FILE}`
	end
	local shown = process.exec("git", { "show", `{rev}:{projects.FILE}` }, { cwd = cwd })
	if not shown.ok then
		return nil, `cannot read {rev}:{projects.FILE}`
	end
	return projects.parse(shown.stdout)
end

return projects
