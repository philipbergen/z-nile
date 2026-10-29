--!strict
-- c0166 AC3: today's exact area rows. Run by check.sh. Not promoted: a later area change must not turn the gate red.
local fs = require("@lune/fs")
local lessonareas = require("@znile/engine/lessonareas")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local areas = lessonareas :: any
local SKILL = "@skill"
local ENGINE = { "z-nile/engine" }
local LOGIC = { "pickman/src/shared/Logic" }
local FENCE = { "z-nile/lib/fence.sh" }
local SKILLS = { "pickman/skills", "z-nile/skills" }

local NAMED: { [string]: { string } } = {
	acceptance = { "@item", "pickman/tests/acceptance", "z-nile/tests/acceptance" },
	adapters = { "pickman/src" },
	audit = ENGINE,
	authority = { "pickman/src/server", "pickman/src/shared/Logic" },
	capture = { "z-nile/engine/trail.luau" },
	["check-sh"] = { "@item", "z-nile/lib/ac.sh" },
	checks = { "@item", "z-nile/lib/ac.sh" },
	claim = ENGINE,
	claims = ENGINE,
	cli = { "z-nile/engine/main.luau", "zn" },
	colour = { "pickman/src" },
	commands = { "z-nile/engine/main.luau", "zn" },
	compaction = ENGINE,
	concurrency = { "z-nile/lib/par.sh", "z-nile/tests/run.luau" },
	conflicts = ENGINE,
	controls = { "pickman/src/client", "pickman/src/shared" },
	coverage = { "pickman/tests", "z-nile/affected.luau", "z-nile/tests" },
	dispatch = { "z-nile/engine/dispatch.luau" },
	docs = { "AGENTS.md", "pickman/skills", "z-nile/skills" },
	documents = SKILLS,
	["execution-window"] = { "z-nile/skills/z-design" },
	["fail-closed"] = FENCE,
	fence = { "z-nile/lib/fence.sh", "z-nile/tests/lib/fence.luau" },
	fixtures = { "@item", "pickman/tests", "z-nile/tests" },
	frames = LOGIC,
	gate = { "z-nile/affected.luau", "z-nile/check.sh" },
	gates = { "z-nile/check.sh" },
	git = { "z-nile/lib/fence.sh", "z-nile/lib/git-hooks" },
	github = { "z-nile/ci-verify.sh" },
	guards = {
		"z-nile/lib/fence.sh",
		"z-nile/lib/git-hooks",
		"z-nile/tests/lib/fence.luau",
		"z-nile/tests/tooling/repo-fence.spec.luau",
	},
	headless = { "z-nile/engine/dispatch.luau" },
	hooks = { "z-nile/lib/git-hooks" },
	hud = { "pickman/src/client" },
	ids = ENGINE,
	input = { "pickman/src/client", "pickman/src/shared" },
	jail = { "z-nile/lib/fence.sh", "z-nile/tests/lib/fence.luau" },
	layout = { "pickman/src", "z-nile/engine" },
	lessons = { "z-nile/engine/lessonareas.luau", "z-nile/engine/lessons.luau", "z-nile/engine/main.luau" },
	locks = { "z-nile/lib/fence.sh", "z-nile/tests/run.luau" },
	merge = ENGINE,
	merges = ENGINE,
	migration = { "pickman/skills", "z-nile/engine", "z-nile/skills" },
	mutants = { "@item", "pickman/tests", "z-nile/tests" },
	mutation = { "@item", "pickman/tests", "z-nile/tests" },
	numbering = ENGINE,
	paths = { "z-nile/engine/main.luau", "z-nile/lib/ac.sh" },
	publish = { "z-nile/engine/publish.luau" },
	raft = ENGINE,
	rafts = ENGINE,
	regression = { "pickman/tests/acceptance", "z-nile/tests/acceptance" },
	registry = { "z-nile/engine/projects.luau", "z-nile/projects.toml" },
	renames = SKILLS,
	replication = { "pickman/src/server", "pickman/src/shared" },
	["repository-safety"] = { "z-nile/lib/fence.sh", "z-nile/tests/tooling/repo-fence.spec.luau" },
	sandbox = FENCE,
	sandboxes = FENCE,
	security = { "z-nile/lib/fence.sh", "z-nile/lib/git-hooks", "z-nile/tests/tooling/repo-fence.spec.luau" },
	server = { "pickman/src/server" },
	["shared-state"] = ENGINE,
	skills = SKILLS,
	specs = { "@item", "pickman/tests", "z-nile/tests" },
	["stale-text"] = { "AGENTS.md", "pickman/skills", "z-nile/skills" },
	["stub-engine"] = { "pickman/src", "pickman/tests/lib/fakeengine.luau" },
	subprocesses = { "z-nile/tests/run.luau" },
	ticks = LOGIC,
	touch = { "pickman/src/client" },
	touched = ENGINE,
	tracker = ENGINE,
	tuning = LOGIC,
	ui = { "pickman/src/client" },
	worktrees = ENGINE,
}

local function sorted(list: { string }): { string }
	local copy = table.clone(list)
	table.sort(copy)
	return copy
end

return t.spec("c0166 named areas", function(it)
	it("the area file matches the named rows", function()
		local text = fs.readFile(`{TOP}/z-nile/lesson-areas.md`)
		local parsed = areas.parse(text)
		t.expect(sorted(parsed.core)).toEqual(sorted({ "process", "review", "scope", "sequestration" }))
		t.expect(sorted(parsed.exercised.design)).toEqual(sorted({ "z-design", "zz-review", "zz-test" }))
		t.expect(sorted(parsed.exercised.raft)).toEqual(sorted({ "z-design", "z-raft", "zz-review" }))
		t.expect(sorted(parsed.skills["zz-arch"])).toEqual(sorted({
			"scripts",
			"z-nile/affected.luau",
			"z-nile/check.sh",
			"z-nile/ci-verify.sh",
			"z-nile/engine",
			"z-nile/lib",
			"z-nile/skills",
			"z-nile/templates",
			"z-nile/tests",
			"zn",
		}))
		t.expect(sorted(parsed.skills["pickman-arch"])).toEqual({ "pickman/src" })
		t.expect(sorted(parsed.skills["pickman-test"])).toEqual({ "pickman/tests" })
		t.expect(#parsed.problems).toBe(0)
		t.expect(sorted(parsed.exercised.code)).toEqual(sorted({ "zz-execute", "zz-review", "zz-test" }))
		t.expect(sorted(parsed.exercised.stream)).toEqual(sorted({ "zz-execute", "zz-review", "zz-test" }))
		for tag, prefixes in NAMED do
			t.expect(sorted(parsed.areas[tag])).toEqual(sorted(prefixes))
		end
		t.expect(sorted(parsed.areas.wiring)).toEqual({ SKILL })
		t.expect(sorted(parsed.areas.lifetimes)).toEqual({ SKILL })
		t.expect(sorted(parsed.areas.demo)).toEqual({ SKILL })
		for tag, prefixes in parsed.areas do
			if NAMED[tag] == nil then
				t.expect(prefixes).toEqual({ SKILL })
			end
		end
		local skillNames = {}
		for name in parsed.skills do
			table.insert(skillNames, name)
		end
		t.expect(sorted(skillNames)).toEqual({ "pickman-arch", "pickman-test", "zz-arch" })
		local modeNames = {}
		for name in parsed.exercised do
			table.insert(modeNames, name)
		end
		t.expect(sorted(modeNames)).toEqual({ "code", "design", "raft", "stream" })
	end)
end)
