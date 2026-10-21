--!strict
-- The tooling a fixture copies to run ./zn and the gate (c0114): the ./zn entry, scripts/ (the forwarders and the
-- game's scripts) and z-nile/ without the repository's tracker state (its .tracker/ items, the id counter and the
-- compaction map), so a fixture starts with no items and the old numbering unless it seeds them.
local fs = require("@lune/fs")
local process = require("@lune/process")

local engine = {}

-- z-nile/ entries that are tracker state, never tooling
engine.STATE = { [".tracker"] = true, next = true, ["compaction.txt"] = true }
-- The same tooling as `git ls-files` pathspecs, for specs that overlay a clone with the working tree's tooling.
engine.PATHSPECS = {
	"zn",
	"scripts",
	"z-nile",
	":(exclude)z-nile/.tracker",
	":(exclude)z-nile/next",
	":(exclude)z-nile/compaction.txt",
}
-- The layout tracker fixtures run under: pickman's items in tracker/, run from the root, and z-nile's in
-- z-nile/.tracker (c0114's), which these specs were written for. The repository moved pickman into pickman/ (c0120);
-- c0120's own specs seed that layout, its homes and its registry themselves.
engine.REGISTRY = table.concat({
	"retired = []",
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")
-- The fixtures' project roots (engine.REGISTRY's), and the shared counter (c0114).
engine.ROOTS = { "tracker", "z-nile/.tracker" }
-- Every root a clone of the repository may hold items in: the fixtures' and the repository's own (c0120).
engine.CLONE_ROOTS = { "tracker", "z-nile/.tracker", "pickman/.tracker" }
engine.COUNTER = "z-nile/next"
-- Both places the counter can be: tracker/next stays the counter until origin moves it (the first publish after c0114).
engine.COUNTERS = { "z-nile/next", "tracker/next" }

-- Copies the tooling from the checkout `root` into `dest` (an existing folder under .cache). Raises when a copy fails.
function engine.copy(root: string, dest: string)
	local function cp(from: string, to: string)
		local r = process.exec("cp", { "-R", from, to })
		if not r.ok then
			error(`engine.copy: cp {from} {to} failed: {r.stderr}`, 2)
		end
	end
	cp(`{root}/zn`, `{dest}/zn`)
	cp(`{root}/scripts`, `{dest}/scripts`)
	fs.writeDir(`{dest}/z-nile`)
	for _, name in fs.readDir(`{root}/z-nile`) do
		if not engine.STATE[name] then
			cp(`{root}/z-nile/{name}`, `{dest}/z-nile/{name}`)
		end
	end
	fs.writeFile(`{dest}/z-nile/projects.toml`, engine.REGISTRY)
end

-- Empty tracker folders under every root of the copied registry, each kept by a .gitkeep so a commit holds them.
function engine.roots(dest: string)
	for _, root in engine.ROOTS do
		for _, dir in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			fs.writeDir(`{dest}/{root}/{dir}`)
			fs.writeFile(`{dest}/{root}/{dir}/.gitkeep`, "")
		end
	end
end

-- A clone of the repository with no items: every item folder under every root removed, and the counter too (wherever it is) (ids
-- then follow the old rule, the next multiple of 10, c0870), on the fixtures' layout (engine.REGISTRY).
function engine.empty(dir: string)
	if fs.isDir(`{dir}/z-nile`) then
		fs.writeFile(`{dir}/z-nile/projects.toml`, engine.REGISTRY)
	end
	for _, root in engine.CLONE_ROOTS do
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local base = `{dir}/{root}/{kind}/{state}`
				if fs.isDir(base) then
					for _, name in fs.readDir(base) do
						if string.match(name, "^[fdcR]%d%d%d%d$") then
							fs.removeDir(base .. name)
						end
					end
				end
			end
		end
	end
	for _, counter in engine.COUNTERS do
		if fs.isFile(`{dir}/{counter}`) then
			fs.removeFile(`{dir}/{counter}`)
		end
	end
	-- the fixtures' roots, laid out (a clone's tracker/ holds only the old counter's tombstone since c0120)
	if fs.isDir(`{dir}/z-nile`) then
		engine.roots(dir)
	end
end

return engine
