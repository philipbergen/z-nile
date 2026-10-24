--!strict
-- The tooling a fixture copies to run ./zn and the gate (c0114): the ./zn entry, scripts/ (the forwarders and the
-- game's scripts) and z-nile/ without the repository's tracker state (its .tracker/ items, the id counter and the
-- compaction map), so a fixture starts with no items and the old numbering unless it seeds them.
local fs = require("@lune/fs")
local process = require("@lune/process")

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

-- Copies the tooling from the checkout `root` into `dest` (an existing folder under .cache). Raises when a copy fails.
-- A `root` with no ./zn (a project's home, where specs run since c0120) means the checkout that holds this harness.
function engine.copy(given: string, dest: string)
	local root = if fs.isFile(`{given}/zn`) then given else engine.TOP
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
