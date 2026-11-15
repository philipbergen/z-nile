--!strict
-- The tooling a fixture copies to run ./zn and the gate (c0114): the ./zn entry, scripts/ (the forwarders and the
-- game's scripts) and z-nile/ without the repository's tracker state (its .tracker/ items, the id counter and the
-- compaction map), so a fixture starts with no items and the old numbering unless it seeds them.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local images = require("@tests/lib/images")
local process = require("@lune/process")
local pruning = require("@tests/lib/pruning")
local swept = require("@tests/lib/swept")
local tally = require("@tests/lib/tally")

-- process.exec, counted (tally.started) beside the call.
local function counted(
	cmd: string,
	args: { string }?,
	options: any?
): { ok: boolean, code: number, stdout: string, stderr: string }
	tally.started(1)
	return process.exec(cmd, args, options)
end

local engine = {}

-- z-nile/ entries a fixture never copies: tracker state, and z-nile's own specs and harness (its home's tests/, c0120),
-- which no command a fixture runs needs; a fixture that runs specs copies the runner itself
engine.STATE =
	{ [".tracker"] = true, next = true, ["compaction.txt"] = true, tests = true, [".cache"] = true }
-- The checkout that holds this harness: three folders above z-nile/tests/lib/engine.luau (c0120)
engine.TOP = string.match(debug.info(1, "s"), "^(.*)/[^/]+/[^/]+/[^/]+/[^/]+$") or "."
-- The same tooling as `git ls-files` pathspecs, for specs that overlay a clone with the working tree's tooling.
engine.PATHSPECS = {
	"zn",
	"scripts",
	"z-nile",
	":(exclude)z-nile/.tracker",
	":(exclude)z-nile/next",
	":(exclude)z-nile/compaction.txt",
}
-- The layout tracker fixtures run under: the repository's own since c0120 (decided with the user, 2026-10-21: "Move
-- fixtures to new layout"): pickman's items in pickman/.tracker (its home pickman/), z-nile's in z-nile/.tracker (its home
-- z-nile/), and tracker/ retired.
engine.REGISTRY = table.concat({
	'retired = ["tracker"]',
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "pickman/.tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")
-- The fixtures' project roots (engine.REGISTRY's), and the shared counter (c0114).
engine.ROOTS = { "pickman/.tracker", "z-nile/.tracker" }
-- Every root a clone of the repository may hold items in: the fixtures' and the retired one (c0120).
engine.CLONE_ROOTS = { "tracker", "z-nile/.tracker", "pickman/.tracker" }
engine.COUNTER = "z-nile/next"
-- The skills folders engine.copy brings, with their lessons (the user's G7): the one list engine.copy, clearLessons
-- and c0115's G7 case read. A project's skills folder (pickman/skills) is not in it; a spec that needs one seeds it.
engine.COPIED_SKILLS = { "z-nile/skills" }
-- Both places the counter can be: tracker/next stays the counter until origin moves it (the first publish after c0114).
engine.COUNTERS = { "z-nile/next", "tracker/next" }

-- The repository's registry, written into the fixture tree `dest`: a tree without one refuses every tracker command
-- (c0114, decided with the user: "Missing also refuses"), so a hand-built fixture writes it like the engine copy does.
function engine.registry(dest: string)
	fs.writeDir(`{dest}/z-nile`)
	-- the fixtures' registry, the shipped one since c0120 (Guess 11); read from no folder, so it works from a home
	fs.writeFile(`{dest}/z-nile/projects.toml`, engine.REGISTRY)
end

-- Lays the tooling of the checkout `root` out in `dest`, an existing folder: ./zn, scripts/, z-nile/ without its tracker
-- state, and the registry. What an image of the tooling holds, and what a tree that is not this checkout's own is built
-- with. Raises when a copy fails.
function engine.build(root: string, dest: string)
	local function cp(from: string, to: string)
		local r = counted("cp", { "-R", from, to })
		if not r.ok then
			error(`engine.copy: cp {from} {to} failed: {r.stderr}`, 2)
		end
	end
	cp(`{root}/zn`, `{dest}/zn`)
	cp(`{root}/scripts`, `{dest}/scripts`)
	fs.writeDir(`{dest}/z-nile`)
	for _, name in fs.readDir(`{root}/z-nile`) do
		if not engine.STATE[name] and name ~= "skills" then
			cp(`{root}/z-nile/{name}`, `{dest}/z-nile/{name}`)
		end
	end
	-- the skills folders, with their lessons, from the one list (the G7 case and clearLessons read it too)
	for _, folder in engine.COPIED_SKILLS do
		if fs.isDir(`{root}/{folder}`) then
			cp(`{root}/{folder}`, `{dest}/{folder}`)
		end
	end
	fs.writeFile(`{dest}/z-nile/projects.toml`, engine.REGISTRY)
end

-- What an image of this checkout's tooling is made from and keyed by: the files engine.build copies, and the code of
-- the harness that lays them out and builds the images (images.luau, engine.luau).
local function imageSpec(name: string, build: (dest: string) -> ()): images.Spec
	local skip = {}
	for state in engine.STATE do
		table.insert(skip, `z-nile/{state}`)
	end
	table.sort(skip)
	return {
		name = name,
		root = engine.TOP,
		inputs = { "zn", "scripts", "z-nile" },
		skip = skip,
		code = { `{engine.TOP}/z-nile/tests/lib/images.luau`, `{engine.TOP}/z-nile/tests/lib/engine.luau` },
		build = build,
	}
end

-- The image of this checkout's tooling: a folder laid out as engine.build lays it out, built once per content.
function engine.image(): string
	return images.ensure(imageSpec("tooling", function(dest: string)
		engine.build(engine.TOP, dest)
	end))
end

-- The packed seed repository of this checkout's tooling (c0178): a bare repository `seed.git` in the image, one
-- commit "seed" on main holding the tooling, the empty tracker folders of every root and .gitignore; with the skills'
-- lessons, or without them (`noLessons`, trackerfix.new's option). A fixture clones it instead of building one.
function engine.seed(noLessons: boolean): string
	local spec = imageSpec(if noLessons then "seed-nolessons" else "seed", function(dest: string)
		local work = `{dest}/work`
		fs.writeDir(work)
		local init = counted("git", { "init", "-q", "-b", "main", work })
		if not init.ok then
			error(`git init {work} failed: {init.stderr}`, 2)
		end
		engine.build(engine.TOP, work)
		if noLessons then
			engine.clearLessons(work)
		end
		engine.roots(work)
		fs.writeFile(`{work}/.gitignore`, ".cache/\n.worktree/\n")
		fixture.git(work, { "add", "-A" })
		fixture.git(work, {
			"-c",
			"user.name=images",
			"-c",
			"user.email=images@example.invalid",
			"commit",
			"-q",
			"-m",
			"seed",
		})
		fixture.git(work, { "repack", "-a", "-d", "-q" })
		local bare = counted("git", { "clone", "-q", "--bare", "--no-hardlinks", work, `{dest}/seed.git` })
		if not bare.ok then
			error(`git clone --bare {work} failed: {bare.stderr}`, 2)
		end
		fixture.git(`{dest}/seed.git`, { "remote", "remove", "origin" })
		fs.removeDir(work)
	end)
	return `{images.ensure(spec)}/seed.git`
end

-- A fixture folder is swept when its spec file passes (@tests/lib/swept): the `.cache/<name>` a destination lies in,
-- when it lies in one (specs name their folder `.cache/<name>`, one per spec file); any other destination is left.
local function registerFixture(dest: string)
	local top = string.match(dest, "^(.*/%.cache/[^/]+)")
	if top ~= nil and top ~= pruning.dir() then
		pcall(swept.register, top)
	end
end

local fileCounts: { [string]: number } = {}
local function imageFiles(image: string): number
	local n = fileCounts[image]
	if n == nil then
		n = tally.count(image)
		fileCounts[image] = n
	end
	return n
end

-- Copies the tooling from the checkout `given` into `dest` (an existing folder under .cache). Raises when a copy fails.
-- A `given` with no ./zn (a project's home, where specs run since c0120) means the checkout that holds this harness.
-- This checkout's tooling comes from its image (copy-on-write where the filesystem has it): one process, nothing laid
-- out again. When `dest` already holds a repository, the seed image's packed objects go into it too, so the `git add`
-- the caller runs next writes no loose object for a file of the tooling. Any other tree is laid out directly.
function engine.copy(given: string, dest: string)
	registerFixture(dest)
	local root = if fs.isFile(`{given}/zn`) then given else engine.TOP
	if root ~= engine.TOP then
		engine.build(root, dest)
		return
	end
	local image = engine.image()
	local r = counted("cp", { "-cR", `{image}/.`, dest })
	if not r.ok then
		r = counted("cp", { "-R", `{image}/.`, dest }) -- no copy-on-write here (Linux, another volume)
	end
	if not r.ok then
		error(`engine.copy: cp {image} {dest} failed: {r.stderr}`, 2)
	end
	tally.files(imageFiles(image))
	if fs.isDir(`{dest}/.git/objects/pack`) then
		local packs = `{engine.seed(false)}/objects/pack`
		local args = {}
		for _, name in fs.readDir(packs) do
			if string.match(name, "%.pack$") or string.match(name, "%.idx$") then
				table.insert(args, `{packs}/{name}`)
			end
		end
		table.insert(args, `{dest}/.git/objects/pack/`)
		local p = counted("cp", args)
		if not p.ok then
			error(`engine.copy: cp {packs} {dest}/.git/objects/pack failed: {p.stderr}`, 2)
		end
	end
end

-- c0115: fixtures copy the skills with their lessons (the user's decision, 2026-10-21). A spec that needs an exact set
-- of lessons clears the copied ones first (trackerfix.new's `noLessons`), then seeds its own.
function engine.clearLessons(dest: string)
	for _, folder in engine.COPIED_SKILLS do
		local base = `{dest}/{folder}`
		if fs.isDir(base) then
			for _, name in fs.readDir(base) do
				if fs.isDir(`{base}/{name}/lessons`) then
					fs.removeDir(`{base}/{name}/lessons`)
				end
			end
		end
	end
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

-- A sparse clone (clone.isolated with paths) keeps the real items in its index, off disk, where the deletions above never
-- reach: they would stay in the fixture's first commit. Take them out of the index as the deletions take them out of a
-- full clone: every item folder of every root, and the counters (c0178, design review 002 F2).
local function dropFromSparseIndex(dir: string)
	if not fs.isFile(`{dir}/.git/info/sparse-checkout`) then
		return
	end
	local listed = counted("git", { "ls-files", "-z" }, { cwd = dir })
	local doomed: { string } = {}
	local seen: { [string]: boolean } = {}
	for path in string.gmatch(listed.stdout, "([^%z]+)") do
		local folder = string.match(path, "^(.-/[fdcR]%d%d%d%d)/")
		local isItemFolder = false
		if folder then
			for _, root in engine.CLONE_ROOTS do
				for _, kind in { "issues", "rafts" } do
					for _, state in { "", "active/", "done/", "retired/" } do
						if string.sub(folder, 1, #root + #kind + #state + 2) == `{root}/{kind}/{state}` then
							local rest = string.sub(folder, #root + #kind + #state + 3)
							isItemFolder = isItemFolder or string.match(rest, "^[fdcR]%d%d%d%d$") ~= nil
						end
					end
				end
			end
		end
		if isItemFolder and not seen[folder :: string] then
			seen[folder :: string] = true
			table.insert(doomed, folder :: string)
		end
	end
	for _, counter in engine.COUNTERS do
		table.insert(doomed, counter)
	end
	local args = { "rm", "-r", "-q", "--cached", "--sparse", "--ignore-unmatch", "--" }
	for _, path in doomed do
		table.insert(args, path)
	end
	fixture.git(dir, args)
end

-- A clone of the repository with no items: every item folder under every root removed, and the counter too (wherever it is) (ids
-- then follow the old rule, the next multiple of 10, c0870), on the fixtures' layout (engine.REGISTRY).
function engine.empty(dir: string)
	if fs.isDir(`{dir}/z-nile`) then
		fs.writeFile(`{dir}/z-nile/projects.toml`, engine.REGISTRY)
	end
	for _, root in engine.CLONE_ROOTS do
		for _, kind in { "issues", "rafts" } do
			-- retired/: rafts recombine retired (c0116), which keep their folders
			for _, state in { "", "active/", "done/", "retired/" } do
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
	dropFromSparseIndex(dir)
	-- the fixtures' roots, laid out (a clone's tracker/ holds only the old counter's tombstone since c0120)
	if fs.isDir(`{dir}/z-nile`) then
		engine.roots(dir)
	end
end

return engine
