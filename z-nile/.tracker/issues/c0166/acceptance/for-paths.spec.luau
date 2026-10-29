--!strict
-- c0166 AC2: --for, --diff, --paths, the empty warning, the project filter.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local AREAS = "core: process, review, scope, sequestration\n"
	.. "mode design: z-design, zz-review, zz-test\n"
	.. "mode raft: z-design, z-raft, zz-review\n"
	.. "mode code: zz-execute, zz-review, zz-test\n"
	.. "mode stream: zz-execute, zz-review, zz-test\n"
	.. "skill pickman-arch: pickman/src\n"
	.. "skill pickman-test: pickman/tests\n"
	.. "skill zz-arch: scripts, z-nile/affected.luau, z-nile/check.sh, z-nile/ci-verify.sh, z-nile/engine, z-nile/lib, z-nile/skills, z-nile/templates, z-nile/tests, zn\n"
	.. "acceptance: @item\nfence: z-nile/lib/fence.sh\nwiring: @skill\n"

local f: trackerfix.Fixture

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function lesson(when: string, tags: string, check: string, paths: string?): string
	local line = if paths then `paths: [{paths}]\n` else ""
	return `---\ntitle: A lesson\nwhen: {when}\ntags: [{tags}]\ncheck: {check}\n{line}from: user 2026-10-26: said so\n---\nBody.\n`
end

local function skill(name: string): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n`
end

local function issue(id: string, raftId: string, touched: { string }?): string
	local doc = `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raftId}\ndepends_on: []\nemergent: false\n`
		.. `design: ready\ncreated: 2026-10-26\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
	if touched then
		doc ..= "\n## Design\n\n### Touched modules\n"
		for _, path in touched do
			doc ..= "- `" .. path .. "`\n"
		end
		doc ..= "\n## Next\n"
	end
	return doc
end

local function raft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [c0001, c0002]\n`
		.. `design: ready\ncreated: 2026-10-26\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end

local function run(args: { string })
	return trackerfix.tr(f, f.main, args)
end

local function must(args: { string }): { stdout: string, stderr: string }
	local r = run(args)
	if r.code ~= 0 then
		error(`exit {r.code}\n{r.stderr}{r.stdout}`, 2)
	end
	return { stdout = r.stdout, stderr = r.stderr }
end

return t.spec("c0166 for and paths", function(it)
	it("sets up a fixture with a z-nile lesson set and a pickman lesson", function()
		f = trackerfix.new("c0166-for", {
			["z-nile/skills/zz-test/lessons/wire.md"] = lesson("build", "wiring", "Does the wire hold?"),
			["z-nile/skills/zz-test/lessons/published.md"] = lesson(
				"build",
				"wiring",
				"Does publish match?",
				"z-nile/engine/publish.luau"
			),
			["z-nile/skills/zz-arch/lessons/fence.md"] = lesson("build", "fence", "Does the fence hold?"),
			["z-nile/skills/zz-review/lessons/core.md"] = lesson("both", "review", "Does the review apply?"),
			["z-nile/skills/z-design/lessons/only.md"] = lesson("design", "fence", "Is this design only?"),
			["z-nile/skills/z-design/lessons/shape.md"] = lesson(
				"design",
				"wiring",
				"Is the shape specific?"
			),
			["z-nile/skills/zz-execute/lessons/steps.md"] = lesson("build", "wiring", "Do the steps hold?"),
			["z-nile/skills/zz-stats/lessons/acc.md"] = lesson(
				"design",
				"acceptance",
				"Does the acceptance hold?"
			),
			["z-nile/skills/zz-arch/lessons/parsers.md"] = lesson(
				"design",
				"wiring",
				"Are the parsers specific?"
			),
			["z-nile/lesson-areas.md"] = AREAS,
			["pickman/skills/pickman-play/SKILL.md"] = skill("pickman-play"),
			["pickman/skills/pickman-play/lessons/feel.md"] = lesson("both", "review", "Does it feel fair?"),
			["z-nile/.tracker/issues/c0001/c0001.md"] = issue("c0001", "R0001", { "z-nile/lib/fence.sh" }),
			["z-nile/.tracker/issues/c0002/c0002.md"] = issue(
				"c0002",
				"R0001",
				{ "z-nile/engine/publish.luau" }
			),
			["z-nile/.tracker/issues/c0004/c0004.md"] = issue("c0004", ""),
			["z-nile/.tracker/issues/c0005/c0005.md"] = issue("c0005", "", { "src/shared/Logic/Maze" }),
			["z-nile/.tracker/issues/c0006/c0006.md"] = issue(
				"c0006",
				"",
				{ "pickman/src/shared/Logic/Maze" }
			),
			["z-nile/.tracker/issues/c0007/c0007.md"] = issue("c0007", "", { "scripts/check.sh" }),
			["pickman/.tracker/issues/c0003/c0003.md"] = issue("c0003", "", { "z-nile/lib/fence.sh" }),
			["z-nile/.tracker/rafts/R0001/R0001.md"] = raft("R0001"),
		}, { noLessons = true })
	end)

	it("a touched fence path keeps fence and core and drops wiring and design", function()
		local r = must({ "lessons", "--when", "build", "--for", "c0001" })
		t.expect(has(r.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(r.stdout, "zz-review/core")).toBe(true)
		t.expect(has(r.stdout, "zz-test/wire")).toBe(false)
		t.expect(has(r.stdout, "zz-test/published")).toBe(false)
		t.expect(has(r.stdout, "z-design/only")).toBe(false)
		t.expect(has(r.stdout, "pickman-play/feel")).toBe(false)
		t.expect(has(r.stderr, "lessons:") and has(r.stderr, "for c0001") and has(r.stderr, "core)"))
			.toBe(true)
	end)

	it("no Touched modules", function()
		local r = must({ "lessons", "--when", "build", "--for", "c0004" })
		t.expect(has(r.stderr, "warning: c0004 has no Touched modules; no path filter")).toBe(true)
		t.expect(has(r.stdout, "zz-test/wire")).toBe(true)
		t.expect(has(r.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(r.stdout, "pickman-play/feel")).toBe(false)
	end)

	it("a raft unions its members", function()
		local r = must({ "lessons", "--when", "build", "--for", "R0001" })
		t.expect(has(r.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(r.stdout, "zz-test/published")).toBe(true)
		t.expect(has(r.stdout, "zz-review/core")).toBe(true)
		t.expect(has(r.stdout, "zz-test/wire")).toBe(false)
		t.expect(has(r.stdout, "pickman-play/feel")).toBe(false)
	end)

	it("pickman lesson", function()
		local r = must({ "lessons", "--when", "build", "--for", "c0003" })
		t.expect(has(r.stdout, "pickman-play/feel")).toBe(true)
		t.expect(has(r.stdout, "zz-review/core")).toBe(true)
		t.expect(has(r.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(r.stdout, "zz-test/wire")).toBe(false)
	end)

	it("--paths filters without an item", function()
		local r = must({ "lessons", "--when", "build", "--paths", "z-nile/lib/fence.sh" })
		t.expect(has(r.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(r.stdout, "zz-review/core")).toBe(true)
		t.expect(has(r.stdout, "zz-test/wire")).toBe(false)
		t.expect(has(r.stdout, "pickman-play/feel")).toBe(true)
		t.expect(has(r.stderr, "for --paths")).toBe(true)
	end)

	it("a design mode keeps the exercised lesson the path would drop", function()
		local r = must({ "lessons", "--when", "design", "--for", "c0001", "--mode", "design" })
		t.expect(has(r.stdout, "z-design/shape")).toBe(true)
		t.expect(has(r.stdout, "zz-review/core")).toBe(true)
		t.expect(has(r.stdout, "zz-execute/steps")).toBe(false)
	end)

	it("the item folder keeps an acceptance lesson", function()
		local kept = must({ "lessons", "--when", "design", "--for", "c0001", "--mode", "design" })
		t.expect(has(kept.stdout, "zz-stats/acc")).toBe(true)
		local dropped =
			must({ "lessons", "--when", "design", "--mode", "design", "--paths", "z-nile/lib/fence.sh" })
		t.expect(has(dropped.stdout, "zz-stats/acc")).toBe(false)
	end)

	it("mode design drops a skill the path does not exercise", function()
		local r = must({ "lessons", "--when", "design", "--for", "c0006", "--mode", "design" })
		t.expect(has(r.stdout, "z-design/shape")).toBe(true)
		t.expect(has(r.stdout, "zz-arch/parsers")).toBe(false)
	end)

	it("a missing area file", function()
		fs.removeFile(`{f.main}/z-nile/lesson-areas.md`)
		local r = run({ "lessons", "--for", "c0001" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "lesson-areas.md is missing")).toBe(true)
		local paths = run({ "lessons", "--paths", "z-nile/lib/fence.sh" })
		t.expect(paths.code).toBe(1)
		t.expect(has(paths.stderr, "lesson-areas.md is missing")).toBe(true)
		local check = run({ "lessons", "--check" })
		t.expect(check.code).toBe(1)
		t.expect(has(check.stdout .. check.stderr, "lesson-areas.md is missing")).toBe(true)
		fs.writeFile(`{f.main}/z-nile/lesson-areas.md`, AREAS)
	end)

	it("an area file that does not parse", function()
		fs.writeFile(`{f.main}/z-nile/lesson-areas.md`, "core: review\ncore: process\n")
		local r = run({ "lessons", "--for", "c0001" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "does not parse")).toBe(true)
		local paths = run({ "lessons", "--paths", "z-nile/lib/fence.sh" })
		t.expect(paths.code).toBe(1)
		t.expect(has(paths.stderr, "does not parse")).toBe(true)
		local check = run({ "lessons", "--check" })
		t.expect(check.code).toBe(1)
		t.expect(has(check.stdout .. check.stderr, "does not parse")).toBe(true)
		fs.writeFile(`{f.main}/z-nile/lesson-areas.md`, AREAS)
	end)

	it("a root-level folder the area table names is repository-relative", function()
		local r = must({ "lessons", "--when", "design", "--for", "c0007" })
		t.expect(has(r.stderr, "not repository-relative")).toBe(false)
		t.expect(has(r.stdout, "zz-arch/parsers")).toBe(true)
		t.expect(has(r.stdout, "z-design/shape")).toBe(false)
	end)

	it("a branch table cannot drop a core tag", function()
		local path = `{f.main}/z-nile/lesson-areas.md`
		local saved = fs.readFile(path)
		fs.writeFile(
			path,
			(
				string.gsub(
					saved,
					"core: process, review, scope, sequestration",
					"core: process, scope, sequestration"
				)
			)
		)
		local r = must({ "lessons", "--when", "build", "--for", "c0001" })
		t.expect(has(r.stdout, "zz-review/core")).toBe(true)
		fs.writeFile(path, saved)
	end)

	it("a project-relative path warns and keeps every build lesson", function()
		local r = must({ "lessons", "--when", "build", "--for", "c0005" })
		t.expect(
			has(
				r.stderr,
				"warning: c0005 Touched path src/shared/Logic/Maze is not repository-relative; no path filter"
			)
		).toBe(true)
		t.expect(has(r.stdout, "zz-test/wire")).toBe(true)
		t.expect(has(r.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(r.stdout, "zz-execute/steps")).toBe(true)
		t.expect(has(r.stdout, "pickman-play/feel")).toBe(false)
	end)

	it("diff with no Touched modules", function()
		local path = `{f.main}/z-nile/engine/publish.luau`
		fs.writeFile(path, fs.readFile(path) .. "\n-- c0166 diff only\n")
		fixture.git(f.main, { "checkout", "-q", "-b", "c0166-diff-empty" })
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "touch publish for empty" })
		local r = must({ "lessons", "--when", "build", "--for", "c0004", "--diff" })
		t.expect(has(r.stderr, "warning: c0004 has no Touched modules; no path filter")).toBe(true)
		t.expect(has(r.stdout, "zz-test/published")).toBe(true)
		t.expect(has(r.stdout, "zz-test/wire")).toBe(false)
	end)

	it("paths needs a value", function()
		t.expect(run({ "lessons", "--paths" }).code).toBe(2)
	end)

	it("usage and an unknown id", function()
		t.expect(run({ "lessons", "--check", "--for", "c0001" }).code).toBe(2)
		t.expect(run({ "lessons", "--rounds" }).code).toBe(2)
		t.expect(run({ "lessons", "--mode", "nope" }).code).toBe(2)
		t.expect(run({ "lessons", "--mode", "design", "--mode", "raft" }).code).toBe(2)
		t.expect(run({ "lessons", "--stale", "--for", "c0001" }).code).toBe(2)
		t.expect(run({ "lessons", "--stale", "--when", "build" }).code).toBe(2)
		t.expect(run({ "lessons", "--for", "c0001", "--for", "c0004" }).code).toBe(2)
		local missing = run({ "lessons", "--for", "c9999" })
		t.expect(missing.code).toBe(1)
		t.expect(has(missing.stderr, "no item c9999")).toBe(true)
		t.expect(has(missing.stdout, "zz-test/wire")).toBe(false)
	end)

	it("diff unavailable", function()
		local path = `{f.main}/z-nile/engine/publish.luau`
		fs.writeFile(path, fs.readFile(path) .. "\n-- c0166\n")
		fixture.git(f.main, { "checkout", "-q", "-b", "c0166-diff" })
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "touch publish" })
		local shown = must({ "lessons", "--when", "build", "--for", "c0001", "--diff" })
		t.expect(has(shown.stdout, "zz-test/published")).toBe(true)
		t.expect(has(shown.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(shown.stdout, "zz-test/wire")).toBe(false)
		fixture.git(f.main, { "update-ref", "-d", "refs/remotes/origin/main" })
		local failed = must({ "lessons", "--when", "build", "--for", "c0001", "--diff" })
		t.expect(has(failed.stderr, "warning: diff unavailable; --for uses Touched modules only")).toBe(true)
		t.expect(has(failed.stdout, "zz-test/published")).toBe(false)
		t.expect(has(failed.stdout, "zz-arch/fence")).toBe(true)
		t.expect(has(failed.stdout, "zz-test/wire")).toBe(false)
	end)
end)
