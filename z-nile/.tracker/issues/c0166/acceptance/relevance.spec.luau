--!strict
-- c0166 AC1: core, paths:, tag area and skill folder, whole components, nil paths, and phase.
local lessonareas = require("@znile/engine/lessonareas")
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")

local api = lessons :: any
local areas = lessonareas :: any

local function lesson(id: string, when: string, tags: { string }, paths: { string }?): any
	local skill, slug = string.match(id, "^([^/]+)/(.+)$")
	return {
		id = id,
		skill = skill,
		slug = slug,
		title = "T",
		when = when,
		tags = tags,
		check = "Is it pinned?",
		from = nil,
		body = "Body.",
		paths = paths,
	}
end

local TABLE_TEXT = "core: process, review, scope, sequestration\n"
	.. "mode design: z-design, zz-review, zz-test\n"
	.. "mode code: zz-execute, zz-review, zz-test\n"
	.. "skill zz-arch: z-nile/engine, z-nile/lib\n"
	.. "acceptance: @item\nfence: z-nile/lib/fence.sh\ntracker: z-nile/engine\nwiring: @skill\n"
local TABLE = areas.parse(TABLE_TEXT)

local function rel(one: any, paths: { string }, folder: string?): boolean
	return api.relevant(one, paths, folder, TABLE)
end

local folders = {
	["zz-review"] = "z-nile/skills/zz-review",
	["zz-test"] = "z-nile/skills/zz-test",
	["zz-arch"] = "z-nile/skills/zz-arch",
	["z-design"] = "z-nile/skills/z-design",
	["zz-execute"] = "z-nile/skills/zz-execute",
}

local core = lesson("zz-review/core", "both", { "review" })
local coreDesign = lesson("z-design/coredesign", "design", { "review" })
local wire = lesson("zz-test/wire", "build", { "wiring" })
local fence = lesson("zz-arch/fence", "build", { "fence" })
local published = lesson("zz-arch/published", "build", { "fence" }, { "z-nile/engine/publish.luau" })
local tracked = lesson("zz-arch/tracked", "build", { "tracker" })

local function ids(list: { any }): { string }
	local out = {}
	for _, l in list do
		table.insert(out, l.id)
	end
	table.sort(out)
	return out
end

local function choose(all: { any }, q: any): { string }
	return ids(api.select(all, {}, q, folders, TABLE))
end

return t.spec("c0166 relevance", function(it)
	it("exports the selector", function()
		t.expect(api.relevant ~= nil).toBe(true)
		t.expect(api.select ~= nil).toBe(true)
		t.expect(areas.overlap ~= nil).toBe(true)
	end)

	it("core matches an unrelated path", function()
		local maze = { "pickman/src/shared/Logic/Maze" }
		t.expect(rel(core, maze, folders["zz-review"])).toBe(true)
		t.expect(rel(wire, maze, folders["zz-test"])).toBe(false)
	end)

	it("paths replace tags", function()
		t.expect(rel(published, { "z-nile/lib/fence.sh" }, folders["zz-arch"])).toBe(false)
		t.expect(rel(published, { "z-nile/engine/publish.luau" }, folders["zz-arch"])).toBe(true)
	end)

	it("engine-extra does not match engine", function()
		t.expect(areas.overlap("z-nile/engine", "z-nile/engine/main.luau")).toBe(true)
		t.expect(areas.overlap("z-nile/engine", "z-nile/engine-extra")).toBe(false)
		t.expect(areas.overlap("z-nile/lib/fence.sh", "z-nile/lib/fence.sh-extra")).toBe(false)
		t.expect(rel(tracked, { "z-nile/engine/main.luau" }, nil)).toBe(true)
		t.expect(rel(tracked, { "z-nile/engine-extra/x.luau" }, nil)).toBe(false)
		t.expect(rel(fence, { "z-nile/lib/fence.sh" }, nil)).toBe(true)
		t.expect(rel(fence, { "z-nile/lib/fence.sh-extra" }, nil)).toBe(false)
	end)

	it("a skill folder matches a lesson whose tags are only @skill", function()
		t.expect(rel(wire, { "z-nile/skills/zz-test/SKILL.md" }, folders["zz-test"])).toBe(true)
		t.expect(rel(wire, { "z-nile/lib/fence.sh" }, folders["zz-test"])).toBe(false)
	end)

	it("nil paths keeps a non-core build lesson", function()
		local only = lesson("z-design/only", "design", { "fence" })
		local all = { core, only, wire, fence }
		t.expect(choose(all, { when = "build" }))
			.toEqual({ "zz-arch/fence", "zz-review/core", "zz-test/wire" })
	end)

	it("an empty path list keeps only core", function()
		local all = { core, wire, fence }
		t.expect(choose(all, { when = "build", paths = {} })).toEqual({ "zz-review/core" })
	end)

	it("a design-mode query keeps a non-core z-design lesson", function()
		local shape = lesson("z-design/shape", "design", { "wiring" })
		local all = { core, shape, wire }
		t.expect(choose(all, {
			when = "design",
			paths = { "pickman/src/shared/Logic/Maze" },
			exercised = { "z-design", "zz-review", "zz-test" },
		})).toEqual({ "z-design/shape", "zz-review/core" })
	end)

	it("a build-mode query keeps a non-core zz-execute lesson", function()
		local steps = lesson("zz-execute/steps", "build", { "wiring" })
		local all = { core, steps, fence }
		t.expect(choose(all, {
			when = "build",
			paths = { "pickman/src/shared/Logic/Maze" },
			exercised = { "zz-execute", "zz-review", "zz-test" },
		})).toEqual({ "zz-execute/steps", "zz-review/core" })
	end)

	it("an acceptance lesson matches the item folder", function()
		local acc = lesson("zz-arch/acc", "design", { "acceptance" })
		t.expect(rel(acc, { "pickman/.tracker/issues/f0001/acceptance/x.spec.luau" }, nil)).toBe(true)
		t.expect(rel(acc, { "pickman/src/shared/Logic/Maze" }, nil)).toBe(false)
	end)

	it("a design lesson is absent for build", function()
		local all = { core, coreDesign, fence }
		t.expect(choose(all, { when = "build", paths = { "pickman/src/shared/Logic/Maze" } })).toEqual({
			"zz-review/core",
		})
		t.expect(choose(all, { when = "design", paths = { "pickman/src/shared/Logic/Maze" } })).toEqual({
			"z-design/coredesign",
			"zz-review/core",
		})
	end)

	it("two tables disagree", function()
		local onFence = areas.parse("core: review\nfence: z-nile/lib/fence.sh\n")
		local onLogic = areas.parse("core: review\nfence: pickman/src\n")
		t.expect(api.relevant(fence, { "z-nile/lib/fence.sh" }, nil, onFence)).toBe(true)
		t.expect(api.relevant(fence, { "z-nile/lib/fence.sh" }, nil, onLogic)).toBe(false)
	end)

	it("an engine path keeps a zz-arch lesson a maze path drops", function()
		local parsers = lesson("zz-arch/parsers", "design", { "wiring" })
		local maze = {
			when = "design",
			paths = { "pickman/src/shared/Logic/Maze" },
			exercised = { "z-design", "zz-review", "zz-test" },
		}
		local engine = {
			when = "design",
			paths = { "z-nile/engine/lessons.luau" },
			exercised = { "z-design", "zz-review", "zz-test" },
		}
		t.expect(choose({ parsers, core }, engine)).toEqual({ "zz-arch/parsers", "zz-review/core" })
		t.expect(choose({ parsers, core }, maze)).toEqual({ "zz-review/core" })
	end)
end)
