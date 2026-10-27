--!strict
-- c0165 AC1, AC2, AC9: one predicate (`select.isInput`) decides both which specs a change selects and what enters a
-- spec's fingerprint, so the two can never disagree; the selection rules moved out of affected.luau keep their
-- outcomes; `inputs.tsv` adds inputs and refuses a malformed file whole. Pure: the graph is built by hand (a Graph is
-- plain data), the blob map is invented, nothing is read from disk.
local fingerprint = require("@znile/lib/fingerprint")
local projects = require("@znile/engine/projects")
local select = require("@znile/lib/select")
local t = require("@tests/lib/t")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local TOOLS = "Darwin arm64 | lune 0.11.1 | rojo 7.7.0"

local MAZE = "pickman/src/shared/Logic/Maze.luau"
local GHOST = "pickman/src/shared/Logic/Ghost.luau"
local UNUSED = "pickman/src/shared/Logic/Unused.luau"
local PLACE = "pickman/tests/lib/place.luau"
local MAZE_SPEC = "pickman/tests/unit/Maze.spec.luau"
local GHOST_SPEC = "pickman/tests/unit/Ghost.spec.luau"
local BOOT_SPEC = "pickman/tests/place/Boot.spec.luau"
local TEXT_SPEC = "pickman/tests/acceptance/x/narrowed.spec.luau"
local DATA = "pickman/tests/fixtures/data/levels.json"
local TOOL_SPEC = "z-nile/tests/tooling/a.spec.luau"
local TOOL_LIB = "z-nile/tests/tooling/helper.luau"
local SPECS = { MAZE_SPEC, GHOST_SPEC, BOOT_SPEC, TEXT_SPEC, TOOL_SPEC }

local function graphOf(): any
	return {
		files = {
			MAZE,
			GHOST,
			UNUSED,
			PLACE,
			MAZE_SPEC,
			GHOST_SPEC,
			BOOT_SPEC,
			TEXT_SPEC,
			TOOL_SPEC,
			TOOL_LIB,
		},
		deps = {
			[MAZE] = {},
			[GHOST] = { MAZE },
			[UNUSED] = {},
			[PLACE] = {},
			[MAZE_SPEC] = { MAZE },
			[GHOST_SPEC] = { GHOST },
			[BOOT_SPEC] = { PLACE },
			[TEXT_SPEC] = {},
			[TOOL_SPEC] = { TOOL_LIB },
			[TOOL_LIB] = {},
		},
		unresolved = {},
		dynamic = {},
	}
end

local function ctxWith(inputs: select.Inputs): select.Context
	local reg = projects.parse(REGISTRY) :: projects.Registry
	return { rules = select.rules(reg), graph = graphOf(), inputs = inputs }
end

local DECLARED: select.Inputs =
	{ [TEXT_SPEC] = { "pickman/tests/fixtures/data/", "pickman/.tracker/issues/f0001/" } }

-- every file the fixture tree holds, with a blob id each
local function tree(): fingerprint.Blobs
	local b: fingerprint.Blobs = {}
	for _, p in
		{
			MAZE,
			GHOST,
			UNUSED,
			PLACE,
			MAZE_SPEC,
			GHOST_SPEC,
			BOOT_SPEC,
			TEXT_SPEC,
			TOOL_SPEC,
			TOOL_LIB,
			DATA,
			"pickman/default.project.json",
			"pickman/lobby.project.json",
			"pickman/tests/meta/architecture.spec.luau",
			"pickman/scripts/check.sh",
			"pickman/tests/inputs.tsv",
			"pickman/.tracker/issues/f0001/f0001.md",
			"pickman/.tracker/issues/f0001/spend.md",
			"z-nile/.tracker/issues/c0001/c0001.md",
			"z-nile/engine/main.luau",
			"z-nile/lib/graph.luau",
			"z-nile/tests/lib/t.luau",
			"z-nile/tests/run.luau",
			"zn",
			".luaurc",
			"AGENTS.md",
		}
	do
		b[p] = "100644 " .. string.rep("a", 40)
	end
	return b
end

local function projectOf(spec: string): string
	return if string.sub(spec, 1, 8) == "pickman/" then "pickman" else "z-nile"
end
local function picks(ctx: select.Context, change: string, spec: string): boolean
	local r = select.affected(ctx, { change }, projectOf(spec))
	if r == "ALL" then
		return true
	end
	local home = projectOf(spec) .. "/"
	for _, s in r :: { string } do
		if s == spec or home .. s == spec then
			return true
		end
	end
	return false
end

type Edit = { kind: string, path: string }
-- one change of each kind the selector knows: modified, added, deleted
local function apply(b: fingerprint.Blobs, e: Edit): fingerprint.Blobs
	local out = table.clone(b)
	if e.kind == "deleted" then
		out[e.path] = nil
	else
		out[e.path] = "100644 " .. string.rep("b", 40)
	end
	return out
end

local CHANGES: { Edit } = {
	{ kind = "modified", path = MAZE }, -- in two closures
	{ kind = "modified", path = GHOST_SPEC }, -- a spec's own file
	{ kind = "modified", path = UNUSED }, -- src: the place library's specs only
	{ kind = "modified", path = "pickman/default.project.json" }, -- place project file
	{ kind = "modified", path = "pickman/tests/meta/architecture.spec.luau" }, -- HOME_FULL (pickman)
	{ kind = "modified", path = "pickman/scripts/check.sh" }, -- HOME_FULL (pickman)
	{ kind = "modified", path = "z-nile/engine/main.luau" }, -- TOOLING (z-nile only)
	{ kind = "modified", path = "z-nile/lib/graph.luau" }, -- SHARED_FULL
	{ kind = "modified", path = "z-nile/tests/run.luau" }, -- SHARED_FULL
	{ kind = "modified", path = "zn" }, -- SHARED_FULL
	{ kind = "modified", path = ".luaurc" }, -- SHARED_FULL
	{ kind = "added", path = "tests/old.luau" }, -- OLD_ROOTS (z-nile)
	{ kind = "modified", path = "pickman/.tracker/issues/f0001/f0001.md" }, -- under a root: only its declaring spec
	{ kind = "modified", path = "pickman/.tracker/issues/f0001/spend.md" }, -- spend.md: never, declared folder or not
	{ kind = "modified", path = "z-nile/.tracker/issues/c0001/c0001.md" }, -- a project root: nothing
	{ kind = "modified", path = "AGENTS.md" }, -- no rule: nothing
	{ kind = "modified", path = DATA }, -- a declared folder input
	{ kind = "added", path = "pickman/tests/fixtures/data/new.json" }, -- added under a declared folder
	{ kind = "deleted", path = MAZE }, -- a deleted closure file
	{ kind = "added", path = "pickman/src/shared/Logic/New.luau" }, -- an added src file
	{ kind = "modified", path = TOOL_LIB }, -- a z-nile tests/ helper in a closure
}

return t.spec("c0165 one rule for selection and fingerprints", function(it)
	it(
		"AC1: a change alters a spec's fingerprint exactly when it makes the selector pick that spec",
		function()
			local ctx = ctxWith(DECLARED)
			local before = tree()
			for _, e in CHANGES do
				local after = apply(before, e)
				for _, spec in SPECS do
					local changedFp = fingerprint.of(ctx, spec, before, TOOLS, "affected")
						~= fingerprint.of(ctx, spec, after, TOOLS, "affected")
					local picked = picks(ctx, e.path, spec)
					if changedFp ~= picked then
						error(
							`{e.kind} {e.path} for {spec}: fingerprint changed {changedFp}, selector picks {picked}`
						)
					end
					t.expect(select.isInput(ctx, spec, e.path)).toBe(picked)
				end
			end
		end
	)

	it("AC1: the moved rules keep their outcomes", function()
		local ctx = ctxWith({})
		local function sel(paths: { string }, only: string?): any
			return select.affected(ctx, paths, only)
		end
		-- SHARED_FULL forces every project, with or without --project
		for _, p in
			{ "z-nile/lib/graph.luau", "z-nile/tests/run.luau", "z-nile/tests/lib/t.luau", "zn", ".luaurc" }
		do
			t.expect(sel({ p }, nil)).toBe("ALL")
			t.expect(sel({ p }, "pickman")).toBe("ALL")
			t.expect(sel({ p }, "z-nile")).toBe("ALL")
		end
		-- the rest of z-nile/ forces z-nile's run only
		t.expect(sel({ "z-nile/engine/main.luau" }, "z-nile")).toBe("ALL")
		t.expect(sel({ "z-nile/engine/main.luau" }, "pickman")).toEqual({})
		t.expect(sel({ "z-nile/engine/main.luau" }, nil)).toBe("ALL")
		-- HOME_FULL forces that home's run
		t.expect(sel({ "pickman/tests/meta/architecture.spec.luau" }, "pickman")).toBe("ALL")
		t.expect(sel({ "pickman/tests/meta/architecture.spec.luau" }, "z-nile")).toEqual({})
		-- an old root forces z-nile's
		t.expect(sel({ "tests/old.luau" }, "z-nile")).toBe("ALL")
		-- project roots select nothing, even under a forcing folder's name
		t.expect(sel({ "z-nile/.tracker/issues/c0001/c0001.md" }, nil)).toEqual({})
		t.expect(sel({ "pickman/.tracker/issues/f0001/f0001.md" }, nil)).toEqual({})
		-- the graph: a closure file selects its specs, a src file the place library's, relative to the home with --project
		t.expect(sel({ MAZE }, nil)).toEqual({ BOOT_SPEC, GHOST_SPEC, MAZE_SPEC }) -- sorted
		t.expect(sel({ GHOST }, "pickman"))
			.toEqual({ "tests/place/Boot.spec.luau", "tests/unit/Ghost.spec.luau" })
		t.expect(sel({ UNUSED }, "pickman")).toEqual({ "tests/place/Boot.spec.luau" })
		t.expect(sel({ "AGENTS.md" }, nil)).toEqual({})
	end)

	it("AC2: each kind of input changes the fingerprint, and nothing else does", function()
		local ctx = ctxWith(DECLARED)
		local base = tree()
		local function moves(spec: string, path: string): boolean
			return fingerprint.of(ctx, spec, base, TOOLS, "affected")
				~= fingerprint.of(
					ctx,
					spec,
					apply(base, { kind = "modified", path = path }),
					TOOLS,
					"affected"
				)
		end
		t.expect(moves(MAZE_SPEC, MAZE_SPEC)).toBe(true) -- its own file
		t.expect(moves(GHOST_SPEC, MAZE)).toBe(true) -- a file it requires through another
		t.expect(moves(BOOT_SPEC, UNUSED)).toBe(true) -- the place library's src
		t.expect(moves(BOOT_SPEC, "pickman/lobby.project.json")).toBe(true) -- a place project file
		t.expect(moves(MAZE_SPEC, "pickman/scripts/check.sh")).toBe(true) -- a forcing file of its project
		t.expect(moves(MAZE_SPEC, "zn")).toBe(true) -- a forcing file of every project
		t.expect(moves(TEXT_SPEC, DATA)).toBe(true) -- a declared folder input
		t.expect(moves(TOOL_SPEC, "z-nile/engine/main.luau")).toBe(true) -- the tooling, for z-nile's specs
		t.expect(moves(MAZE_SPEC, "z-nile/engine/main.luau")).toBe(false) -- but not for pickman's
		t.expect(moves(MAZE_SPEC, "pickman/.tracker/issues/f0001/f0001.md")).toBe(false) -- tracker documents
		t.expect(moves(TOOL_SPEC, "z-nile/.tracker/issues/c0001/c0001.md")).toBe(false)
		t.expect(moves(MAZE_SPEC, UNUSED)).toBe(false) -- an unrelated src file, for a spec without the place library
		t.expect(moves(MAZE_SPEC, "AGENTS.md")).toBe(false)
		t.expect(moves(MAZE_SPEC, DATA)).toBe(false) -- another spec's declared input
		-- a tracker file under a declared folder (it names a path under the root) is an input; its spend.md never is
		t.expect(moves(TEXT_SPEC, "pickman/.tracker/issues/f0001/f0001.md")).toBe(true)
		t.expect(moves(TEXT_SPEC, "pickman/.tracker/issues/f0001/spend.md")).toBe(false)
		-- the gate mode is part of the fingerprint: a full run's rows never serve an affected run
		t.expect(
			fingerprint.of(ctx, MAZE_SPEC, base, TOOLS, "affected")
				~= fingerprint.of(ctx, MAZE_SPEC, base, TOOLS, "full")
		).toBe(true)
		-- the tools line, and a new declared or learned entry, change it too
		t.expect(
			fingerprint.of(ctx, MAZE_SPEC, base, TOOLS, "affected")
				~= fingerprint.of(ctx, MAZE_SPEC, base, TOOLS .. " | git 2", "affected")
		).toBe(true)
		local learned = ctxWith({ [MAZE_SPEC] = { DATA } })
		t.expect(
			fingerprint.of(ctx, MAZE_SPEC, base, TOOLS, "affected")
				~= fingerprint.of(learned, MAZE_SPEC, base, TOOLS, "affected")
		).toBe(true)
		-- a file input (not a folder) matches only itself
		t.expect(select.isInput(learned, MAZE_SPEC, DATA)).toBe(true)
		t.expect(select.isInput(learned, MAZE_SPEC, "pickman/tests/fixtures/data/levels.json.bak"))
			.toBe(false)
		-- the same inputs, in any order of the blob map, give the same fingerprint (no time, no pid, no order)
		t.expect(fingerprint.of(ctx, MAZE_SPEC, base, TOOLS, "affected"))
			.toBe(fingerprint.of(ctx, MAZE_SPEC, tree(), TOOLS, "affected"))
		t.expect(#fingerprint.of(ctx, MAZE_SPEC, base, TOOLS, "affected")).toBe(64)
		-- the inputs list is sorted and holds only isInput paths that exist
		local ins = fingerprint.inputs(ctx, GHOST_SPEC, base)
		local sorted = table.clone(ins)
		table.sort(sorted)
		t.expect(ins).toEqual(sorted)
		for _, p in ins do
			t.expect(select.isInput(ctx, GHOST_SPEC, p)).toBe(true)
			t.expect(base[p] ~= nil).toBe(true)
		end
	end)

	it(
		"AC2: a declared folder that covers a project root still never makes a tracker document an input",
		function()
			-- only isInput's own root exemption can say no here: the folder entry matches the path, and no forcing rule does
			local wide = ctxWith({ [MAZE_SPEC] = { "pickman/" } })
			local doc = "pickman/.tracker/issues/f0001/f0001.md"
			t.expect(select.isInput(wide, MAZE_SPEC, doc)).toBe(false)
			t.expect(select.isInput(wide, MAZE_SPEC, DATA)).toBe(true)
			local base = tree()
			t.expect(
				fingerprint.of(
					wide,
					MAZE_SPEC,
					apply(base, { kind = "modified", path = doc }),
					TOOLS,
					"affected"
				)
			).toBe(fingerprint.of(wide, MAZE_SPEC, base, TOOLS, "affected"))
		end
	)

	it("AC2: a home's inputs.tsv is an input of exactly the specs it names", function()
		local ctx = ctxWith(DECLARED)
		t.expect(select.isInput(ctx, TEXT_SPEC, "pickman/tests/inputs.tsv")).toBe(true)
		t.expect(select.isInput(ctx, MAZE_SPEC, "pickman/tests/inputs.tsv")).toBe(false)
		t.expect(select.isInput(ctx, TOOL_SPEC, "pickman/tests/inputs.tsv")).toBe(false)
	end)

	it("AC9: inputs.tsv parses comments, blank lines, files and folders, relative to the home", function()
		local text = "# extra inputs\n\ntests/acceptance/x/narrowed.spec.luau\tpickman/tests/fixtures/data/\n"
			.. "tests/unit/Maze.spec.luau\tpickman/tests/fixtures/data/levels.json\n"
			.. "tests/unit/Maze.spec.luau\tz-nile/templates/raft/check.sh\n"
			.. "tests/acceptance/c0063/narrowed.spec.luau\tpickman/.tracker/issues/done/f0031/acceptance/\n"
		local inputs, err = select.parseInputs(text, "pickman/")
		t.expect(err).toBe(nil)
		t.expect((inputs :: select.Inputs)[TEXT_SPEC]).toEqual({ "pickman/tests/fixtures/data/" })
		t.expect((inputs :: select.Inputs)[MAZE_SPEC]).toEqual({ DATA, "z-nile/templates/raft/check.sh" })
		-- the Design's own example: a done item's folder under the root
		t.expect((inputs :: select.Inputs)["pickman/tests/acceptance/c0063/narrowed.spec.luau"])
			.toEqual({ "pickman/.tracker/issues/done/f0031/acceptance/" })
	end)

	it("AC9: one malformed line refuses the whole file, naming its line", function()
		local good = "tests/unit/Maze.spec.luau\tpickman/tests/fixtures/data/levels.json\n"
		for _, bad in
			{
				"tests/unit/Maze.spec.luau pickman/x.json\n", -- no tab
				"tests/unit/Maze.luau\tpickman/x.json\n", -- not a spec
				"tests/unit/Maze.spec.luau\t/abs/x.json\n", -- absolute
				"tests/unit/Maze.spec.luau\tpickman/../x.json\n", -- ..
				"tests/unit/Maze.spec.luau\tpickman/.tracker\n", -- a project root itself
				"tests/unit/Maze.spec.luau\tpickman/.tracker/\n", -- the same, as a folder
				"tests/unit/Maze.spec.luau\tpickman/.tracker/issues/f0001/spend.md\n", -- a spend.md
				"tests/unit/Maze.spec.luau\t\n", -- empty input
				"tests/unit/Maze.spec.luau\ta\tb\n", -- three fields
			}
		do
			local inputs, err = select.parseInputs(good .. bad, "pickman/")
			if inputs ~= nil or err == nil then
				error(`accepted a malformed line: {bad}`)
			end
			t.expect(string.find(err :: string, "2", 1, true) ~= nil).toBe(true)
		end
	end)
end)
