--!strict
-- c0165 AC1, AC2, AC9: one predicate (`select.isInput`) decides both which specs a change selects and what enters a
-- spec's fingerprint, so the two can never disagree; the selection rules moved out of affected.luau keep their
-- outcomes; `inputs.tsv` adds inputs and refuses a malformed file whole. Pure: the graph is built by hand (a Graph is
-- plain data), the blob map is invented, nothing is read from disk. The "exactly when" property holds for specs
-- without a `ref:` entry: such a spec is selected by every change set and its fingerprint (which holds the ref) decides.
-- The moved rules include c0185's (c0165 depends on it): any `*.project.json` directly in a home forces that home's run,
-- and a place spec's inputs are the home's project files and every folder they map (the arcade library's included).
local fingerprint = require("@znile/lib/fingerprint")
local projects = require("@znile/engine/projects")
local select = require("@znile/lib/select")
local t = require("@tests/lib/t")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local TOOLS = "Darwin arm64 | lune 0.11.1 | rojo 7.7.0"
local GIT: fingerprint.GitState = {
	head = string.rep("1", 40),
	refs = { ["refs/heads/main"] = string.rep("1", 40) },
}
local function of(
	ctx: select.Context,
	spec: string,
	blobs: fingerprint.Blobs,
	tools: string,
	mode: "affected" | "full",
	git: fingerprint.GitState?
): string
	return fingerprint.of(ctx, spec, blobs, tools, mode, git or GIT)
end

local MAZE = "pickman/src/shared/Logic/Maze.luau"
local GHOST = "pickman/src/shared/Logic/Ghost.luau"
local UNUSED = "pickman/src/shared/Logic/Unused.luau"
local PLACE = "pickman/tests/lib/place.luau"
local MAZE_SPEC = "pickman/tests/unit/Maze.spec.luau"
local GHOST_SPEC = "pickman/tests/unit/Ghost.spec.luau"
local BOOT_SPEC = "pickman/tests/place/Boot.spec.luau"
local TEXT_SPEC = "pickman/tests/acceptance/x/narrowed.spec.luau"
local DATA = "pickman/tests/fixtures/data/levels.json"
local OTHER_PROJECT = "pickman/other.project.json" -- c0185: any project file directly in a home is a place's
local SUB_PROJECT = "pickman/sub/x.project.json" -- a project file in a sub-folder is no place of the home
local LIB_SHARED = "arcade/src/shared/Info.luau" -- mapped by the home's project file (c0185)
local LIB_SERVER = "arcade/src/server/Boot.luau" -- the library's server folder, mapped only when the file says so
local LIB_TESTS = "arcade/tests/unit/Info.spec.luau" -- the library's tests are in no place
-- graph.placeInputs("pickman/") as c0185 defines it: the project files and every folder they map, collapsed
local PLACE_INPUTS = {
	"pickman/default.project.json",
	"pickman/lobby.project.json",
	"pickman/src",
	"arcade/src/shared",
}
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

local function ctxWith(inputs: select.Inputs, places: { string }?): select.Context
	local reg = projects.parse(REGISTRY) :: projects.Registry
	return {
		rules = select.rules(reg),
		graph = graphOf(),
		inputs = inputs,
		places = { ["pickman/"] = places or PLACE_INPUTS },
	}
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
			OTHER_PROJECT,
			SUB_PROJECT,
			LIB_SHARED,
			LIB_SERVER,
			LIB_TESTS,
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
	{ kind = "modified", path = OTHER_PROJECT }, -- c0185: any project file directly in the home: HOME_FULL
	{ kind = "modified", path = SUB_PROJECT }, -- a project file in a sub-folder: nothing
	{ kind = "modified", path = LIB_SHARED }, -- a folder a project file maps: the home's place specs
	{ kind = "modified", path = LIB_SERVER }, -- a library folder no project file maps: nothing
	{ kind = "modified", path = LIB_TESTS }, -- the library's tests are in no place
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
					local changedFp = of(ctx, spec, before, TOOLS, "affected")
						~= of(ctx, spec, after, TOOLS, "affected")
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
		-- root infrastructure forces every project; tooling infrastructure forces z-nile alone
		for _, p in { "zn", ".luaurc" } do
			t.expect(sel({ p }, nil)).toBe("ALL")
			t.expect(sel({ p }, "pickman")).toBe("ALL")
			t.expect(sel({ p }, "z-nile")).toBe("ALL")
		end
		for _, p in
			{
				"z-nile/lib/graph.luau",
				"z-nile/tests/run.luau",
				"z-nile/tests/lib/t.luau",
				"z-nile/engine/main.luau",
			}
		do
			t.expect(sel({ p }, nil)).toBe("ALL")
			t.expect(sel({ p }, "pickman")).toEqual({})
			t.expect(sel({ p }, "z-nile")).toBe("ALL")
		end
		-- documentation and skills force no suite; declared inputs and require edges still apply
		for _, p in
			{
				"z-nile/engine/design.md",
				"z-nile/skills/zz-test/SKILL.md",
				"z-nile/skills/zz-test/lessons/x.txt",
			}
		do
			t.expect(sel({ p }, nil)).toEqual({})
			t.expect(sel({ p }, "z-nile")).toEqual({})
		end
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

	it(
		"AC1: c0185's rules are in select.luau: any project file of a home, and the library a place maps",
		function()
			local ctx = ctxWith({})
			local function sel(paths: { string }, only: string?): any
				return select.affected(ctx, paths, only)
			end
			-- HOME_FULL: any *.project.json directly in the home forces that home's run, not another's, not a sub-folder's
			t.expect(sel({ OTHER_PROJECT }, "pickman")).toBe("ALL")
			t.expect(sel({ "pickman/default.project.json" }, "pickman")).toBe("ALL")
			t.expect(sel({ OTHER_PROJECT }, "z-nile")).toEqual({})
			t.expect(sel({ OTHER_PROJECT }, nil)).toBe("ALL")
			t.expect(sel({ SUB_PROJECT }, "pickman")).toEqual({})
			-- the place rule: a folder the home's project files map selects its place specs (those whose closure holds the
			-- home's place library), and no other
			t.expect(sel({ LIB_SHARED }, "pickman")).toEqual({ "tests/place/Boot.spec.luau" })
			t.expect(sel({ "pickman/src/shared/Logic/Maze.luau" }, "pickman"))
				.toEqual({ "tests/place/Boot.spec.luau", "tests/unit/Ghost.spec.luau", "tests/unit/Maze.spec.luau" })
			-- a library folder no project file maps is in no place; the library's tests are in none either
			t.expect(sel({ LIB_SERVER }, "pickman")).toEqual({})
			t.expect(sel({ LIB_TESTS }, "pickman")).toEqual({})
			-- a project file that maps the server folder makes it a place input (the rule reads the mapping, not a name)
			local mapped = ctxWith({}, { "pickman/default.project.json", "pickman/src", "arcade/src/server" })
			t.expect(select.affected(mapped, { LIB_SERVER }, "pickman"))
				.toEqual({ "tests/place/Boot.spec.luau" })
			t.expect(select.affected(mapped, { LIB_SHARED }, "pickman")).toEqual({})
			-- a home with no entry in places has no place inputs: its place specs are selected by their own closure only
			local bare: select.Context = { rules = ctx.rules, graph = ctx.graph, inputs = {}, places = {} }
			t.expect(select.affected(bare, { LIB_SHARED }, "pickman")).toEqual({})
		end
	)

	it("AC2: each kind of input changes the fingerprint, and nothing else does", function()
		local ctx = ctxWith(DECLARED)
		local base = tree()
		local function moves(spec: string, path: string): boolean
			return of(ctx, spec, base, TOOLS, "affected")
				~= of(ctx, spec, apply(base, { kind = "modified", path = path }), TOOLS, "affected")
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
		t.expect(of(ctx, MAZE_SPEC, base, TOOLS, "affected") ~= of(ctx, MAZE_SPEC, base, TOOLS, "full"))
			.toBe(true)
		-- the tools line, and a new declared entry, change it too
		t.expect(
			of(ctx, MAZE_SPEC, base, TOOLS, "affected")
				~= of(ctx, MAZE_SPEC, base, TOOLS .. " | git 2", "affected")
		).toBe(true)
		local declared = ctxWith({ [MAZE_SPEC] = { DATA } })
		t.expect(
			of(ctx, MAZE_SPEC, base, TOOLS, "affected") ~= of(declared, MAZE_SPEC, base, TOOLS, "affected")
		)
			.toBe(true)
		-- a file input (not a folder) matches only itself
		t.expect(select.isInput(declared, MAZE_SPEC, DATA)).toBe(true)
		t.expect(select.isInput(declared, MAZE_SPEC, "pickman/tests/fixtures/data/levels.json.bak"))
			.toBe(false)
		-- the same inputs, in any order of the blob map, give the same fingerprint (no time, no pid, no order)
		t.expect(of(ctx, MAZE_SPEC, base, TOOLS, "affected"))
			.toBe(of(ctx, MAZE_SPEC, tree(), TOOLS, "affected"))
		t.expect(#of(ctx, MAZE_SPEC, base, TOOLS, "affected")).toBe(64)
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
			t.expect(of(wide, MAZE_SPEC, apply(base, { kind = "modified", path = doc }), TOOLS, "affected"))
				.toBe(of(wide, MAZE_SPEC, base, TOOLS, "affected"))
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

	it("AC9: a * entry parses, and makes every same-suite path an input of its spec alone", function()
		local inputs, err = select.parseInputs("tests/unit/Maze.spec.luau\t*\n", "pickman/")
		t.expect(err).toBe(nil)
		t.expect((inputs :: select.Inputs)[MAZE_SPEC]).toEqual({ "*" })
		local ctx = ctxWith(inputs :: select.Inputs)
		for _, p in
			{
				"AGENTS.md",
				"pickman/.tracker/issues/f0001/f0001.md",
				"pickman/.tracker/issues/f0001/spend.md",
			}
		do
			t.expect(select.isInput(ctx, MAZE_SPEC, p)).toBe(true)
			t.expect(select.isInput(ctx, GHOST_SPEC, p)).toBe(false)
		end
		t.expect(select.isInput(ctx, MAZE_SPEC, "z-nile/engine/main.luau")).toBe(false)
		t.expect(select.isInput(ctx, TOOL_SPEC, MAZE)).toBe(false)
	end)

	it("AC2: a spec with a ref: entry is selected by an empty change set, and no other spec is", function()
		local declared = ctxWith(
			select.parseInputs("tests/unit/Ghost.spec.luau\tref:refs/remotes/origin/main\n", "pickman/") :: select.Inputs
		)
		t.expect(select.affected(declared, {}, "pickman")).toEqual({ "tests/unit/Ghost.spec.luau" })
		t.expect(select.affected(declared, { "AGENTS.md" }, "pickman"))
			.toEqual({ "tests/unit/Ghost.spec.luau" })
		t.expect(select.affected(ctxWith({}), {}, "pickman")).toEqual({})
		-- only its own project's run gets it: another project's runner could not load the path (design review 006 F4)
		t.expect(select.affected(declared, {}, "z-nile")).toEqual({})
		t.expect(select.affected(declared, { "AGENTS.md" }, "z-nile")).toEqual({})
		-- without --project the path is repository-relative, like every other answer
		t.expect(select.affected(declared, {}, nil)).toEqual({ GHOST_SPEC })
		t.expect(select.affected(declared, { "pickman/unrelated.luau" }, nil)).toEqual({ GHOST_SPEC })
		t.expect(select.affected(declared, { "z-nile/skills/zz-test/SKILL.md" }, nil)).toEqual({})
	end)

	it(
		"AC2: HEAD does not move a * spec, unrelated refs do not, and a declared ref moves its spec",
		function()
			local starred =
				ctxWith(select.parseInputs("tests/unit/Maze.spec.luau\t*\n", "pickman/") :: select.Inputs)
			local declared = ctxWith(
				select.parseInputs("tests/unit/Ghost.spec.luau\tref:refs/remotes/origin/main\n", "pickman/") :: select.Inputs
			)
			local plain = ctxWith({})
			local blobs = tree()
			local movedHead: fingerprint.GitState = { head = string.rep("2", 40), refs = GIT.refs }
			local movedRef: fingerprint.GitState = {
				head = GIT.head,
				refs = { ["refs/heads/main"] = string.rep("3", 40) },
			}
			t.expect(of(starred, MAZE_SPEC, blobs, TOOLS, "affected", movedHead))
				.toBe(of(starred, MAZE_SPEC, blobs, TOOLS, "affected"))
			t.expect(of(starred, MAZE_SPEC, blobs, TOOLS, "affected", movedRef))
				.toBe(of(starred, MAZE_SPEC, blobs, TOOLS, "affected"))
			t.expect(of(plain, GHOST_SPEC, blobs, TOOLS, "affected", movedHead))
				.toBe(of(plain, GHOST_SPEC, blobs, TOOLS, "affected"))
			t.expect(fingerprint.refs(declared, GHOST_SPEC)).toEqual({ "refs/remotes/origin/main" })
			local withRef = table.clone(GIT)
			withRef.refs = { ["refs/remotes/origin/main"] = string.rep("4", 40) }
			local movedDeclared = table.clone(withRef)
			movedDeclared.refs = { ["refs/remotes/origin/main"] = string.rep("5", 40) }
			t.expect(
				of(declared, GHOST_SPEC, blobs, TOOLS, "affected", movedDeclared)
					~= of(declared, GHOST_SPEC, blobs, TOOLS, "affected", withRef)
			).toBe(true)
		end
	)

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
				"tests/unit/Maze.spec.luau\tref:\n", -- empty ref
				"tests/unit/Maze.spec.luau\tref:main\n", -- not a full ref
				"tests/unit/Maze.spec.luau\tref:refs/heads/a..b\n", -- malformed ref
				"tests/unit/Maze.spec.luau\tref:refs/heads/a b\n", -- whitespace in a ref
				"tests/unit/Maze.spec.luau\t\n", -- empty input
				"tests/unit/Maze.spec.luau\ta\tb\n", -- three fields
			}
		do
			local inputs, err = select.parseInputs(good .. bad, "pickman/")
			if inputs ~= nil or err == nil then
				error(`accepted a malformed line: {bad}`)
			end
			-- the Design's form: `line N: <reason>`, N the first malformed line (the good line is line 1)
			t.expect(string.sub(err :: string, 1, 7)).toBe("line 2:")
		end
	end)
end)
