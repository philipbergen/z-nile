--!strict
-- c0181 AC5: the gate runs the codification policy and the lints on every run (static stages, `--affected` too, and a
-- pickman-only run), and the lints and the lessons that name them are the same set. Reads the real repository.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local lint = require("@znile/lints/lib/lint")
local process = require("@lune/process")
local registry = require("@znile/lints/registry")
local t = require("@tests/lib/t")

local TOP = engine.TOP

-- A copy of the tree's layout, as c0120/gate-homes.spec builds it: `--plan` runs only there, never in the checkout, so
-- a gate that ran anyway (a plan that reaches a stage) would write the copy and fail the case, not the repository.
local copied: string? = nil
local function planTree(): string
	if copied then
		return copied :: string
	end
	local base = `{fixture.physical(".") or error("no home")}/.cache/c0181-wiring`
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
	engine.copy(TOP, base)
	for _, rel in
		{
			"pickman/src/shared",
			"pickman/tests/unit",
			"pickman/scripts",
			"z-nile/tests/tooling",
			"z-nile/.tracker",
			"pickman/.tracker",
		}
	do
		fs.writeDir(`{base}/{rel}`)
	end
	fs.writeFile(
		`{base}/pickman/default.project.json`,
		'{ "name": "g", "tree": { "$className": "DataModel" } }\n'
	)
	copied = base
	return base
end

local function plan(args: { string }): string
	local dir = planTree()
	local argv = { "z-nile/check.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	table.insert(argv, "--plan")
	local r = process.exec(
		"perl",
		{ "-e", "alarm 60; exec @ARGV", "bash", table.unpack(argv) },
		{ cwd = dir }
	)
	if not r.ok then
		error(`check.sh --plan failed ({r.code}): {r.stderr}`, 2)
	end
	-- nothing a gate run writes appeared in the copy
	t.expect(fs.isDir(`{dir}/pickman/.cache`) or fs.isFile(`{dir}/pickman/sourcemap.json`)).toBe(false)
	return r.stdout
end

return t.spec("c0181 gate wiring", function(it)
	it(
		"--plan names the policy stage and the lint stage, for a full run and for one project alone",
		function()
			for _, args in
				{ {}, { "--affected" }, { "--project", "pickman" }, { "--project", "z-nile", "--full" } }
			do
				local out = plan(args)
				t.expect(string.find(out, "lessons: ./zn lessons --check --policy", 1, true) ~= nil)
					.toBe(true)
				t.expect(string.find(out, "lints: lune run z-nile/lints", 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("check.sh starts both as static stages before the specs", function()
		local text = fs.readFile(`{TOP}/z-nile/check.sh`)
		local a = string.find(text, 'par_start "lessons (./zn lessons --check --policy)"', 1, true)
		local b = string.find(text, 'par_start "lints (lune run z-nile/lints)"', 1, true)
		local wait = string.find(text, "par_wait || exit 1", 1, true)
		t.expect(a ~= nil and b ~= nil and wait ~= nil).toBe(true)
		t.expect((a :: number) < (wait :: number) and (b :: number) < (wait :: number)).toBe(true)
	end)

	it("every registered lint passes its self-test and is named by exactly the lesson it says", function()
		local tree = lessons.load(TOP)
		t.expect(#registry > 0).toBe(true)
		local seen: { [string]: boolean } = {}
		for _, def in registry do
			t.expect(lint.selfTest(def)).toEqual({})
			seen[def.lesson] = true
			local l = lessons.parse(def.lesson, tree.lessons[def.lesson] or "")
			t.expect(l ~= nil).toBe(true)
			local named = false
			for _, ref in (l :: any).enforcedBy do
				named = named or string.find(ref, "z-nile/lints/", 1, true) == 1
			end
			t.expect(named).toBe(true)
		end
	end)

	it("every lesson that names a lint is the lesson that lint says it enforces", function()
		local tree = lessons.load(TOP)
		local byLesson: { [string]: boolean } = {}
		for _, def in registry do
			byLesson[def.lesson] = true
		end
		for id, text in tree.lessons do
			local l = lessons.parse(id, text)
			if l then
				for _, ref in (l :: any).enforcedBy do
					if string.find(ref, "z-nile/lints/", 1, true) == 1 then
						t.expect(byLesson[id]).toBe(true)
					end
				end
			end
		end
	end)

	it("the lint runner judges lint-allow.md lines against the lint ids and the rule ids", function()
		local runner = fs.readFile(`{TOP}/z-nile/lints.luau`)
		t.expect(string.find(runner, "unknownAllows", 1, true) ~= nil).toBe(true)
		t.expect(string.find(runner, "rules/registry", 1, true) ~= nil).toBe(true)
	end)
end)
