--!strict
-- c0181 AC3: a lesson fully enforced by a check is one line and is not asked of a step (`--when` hides it; the build
-- index of a raft prompt is that selection); a partly enforced lesson stays with its remaining question; `--enforced`
-- lists the enforced ones; `--codified` reports the share. Lessons without the new keys list exactly as before.
-- The selection is `lessons.select`, which `./zn lessons` and the raft prompt's build index both call, so a pure case
-- pins the prompt's list too. Runs ./zn in a tracker fixture (tests/lib/trackerfix) and only reads.
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function skill(name: string): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n`
end
local function lesson(title: string, when: string, check: string, state: string): string
	return `---\ntitle: {title}\nwhen: {when}\ntags: [wiring]\ncheck: {check}\n{state}from: test\n---\nThe rule.\n`
end

local SEED: { [string]: string } = {
	["z-nile/skills/zz-test/SKILL.md"] = skill("zz-test"),
	["z-nile/skills/zz-arch/SKILL.md"] = skill("zz-arch"),
	["z-nile/skills/zz-test/lessons/a-full.md"] = lesson(
		"Conflict markers stay out",
		"both",
		"Is a marker left?",
		"enforced_by: z-nile/lints/markers.luau\nenforced: full\n"
	),
	["z-nile/skills/zz-test/lessons/b-part.md"] = lesson(
		"Pin the call site",
		"build",
		"Which argument is still unpinned?",
		"enforced_by: z-nile/tests/meta/x.spec.luau\nenforced: part\n"
	),
	["z-nile/skills/zz-test/lessons/c-judged.md"] = lesson(
		"Read the design twice",
		"both",
		"Did I read it twice?",
		"not_codifiable: needs a human to judge the design\n"
	),
	["z-nile/lints/markers.luau"] = 'return { lesson = "zz-test/a-full" }\n',
	-- a finished item whose ledger says a-full is not codifiable, though it is enforced now: history, not a problem
	["pickman/.tracker/issues/done/c0020/review-001.md"] = "# Review 001\n\n### F1 [low] claim\nEvidence: x\n\nVerdict: changes\n",
	["pickman/.tracker/issues/done/c0020/harvest.md"] = "- review-001 F1: one-off: planted for the codify-line case\n"
		.. "- codify zz-test/a-full: not codifiable: needs a human to judge the design\n",
	["z-nile/skills/zz-arch/lessons/d-judged.md"] = lesson(
		"Name the owner",
		"build",
		"Who owns it?",
		"not_codifiable: needs a human to judge the design\n"
	),
}

local f: trackerfix.Fixture
local function run(args: { string }): (number, string)
	local argv = { "lessons" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = trackerfix.tr(f, f.main, argv)
	return r.code, r.stdout
end
local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

return t.spec("c0181 lessons listing of enforced lessons", function(it)
	it("sets up a fixture with four lessons", function()
		f = trackerfix.new("codify-listing", SEED, { noLessons = true })
	end)

	it(
		"select leaves a fully enforced lesson out of a step's reading (the prompt's build index) and nowhere else",
		function()
			local all: { lessons.Lesson } = {}
			for path, text in SEED do
				local skillName, slug = string.match(path, "skills/([^/]+)/lessons/([^/]+)%.md$")
				if skillName then
					local l = lessons.parse(`{skillName}/{slug}`, text)
					table.insert(all, l :: lessons.Lesson)
				end
			end
			local function ids(list: { lessons.Lesson }): { string }
				local out = {}
				for _, l in list do
					table.insert(out, l.id)
				end
				table.sort(out)
				return out
			end
			t.expect(ids(lessons.select(all, {}, { when = "build" })))
				.toEqual({ "zz-arch/d-judged", "zz-test/b-part", "zz-test/c-judged" })
			t.expect(#lessons.select(all, {}, {})).toBe(4)
			t.expect(ids(lessons.select(all, {}, { enforced = "only" }))).toEqual({ "zz-test/a-full" })
		end
	)

	it("lists an enforced lesson as one line, a partly enforced one with its question", function()
		local code, out = run({})
		t.expect(code).toBe(0)
		t.expect(lines(out)).toEqual({
			"- zz-arch/d-judged (build, 1 source): Who owns it?",
			"- zz-test/a-full (enforced by z-nile/lints/markers.luau, 1 source): Conflict markers stay out",
			"- zz-test/b-part (build, 1 source, partly enforced): Which argument is still unpinned?",
			"- zz-test/c-judged (both, 1 source): Did I read it twice?",
		})
	end)

	it("--when hides the fully enforced lesson and keeps the partly enforced one", function()
		local _, build = run({ "--when", "build" })
		t.expect(lines(build)).toEqual({
			"- zz-arch/d-judged (build, 1 source): Who owns it?",
			"- zz-test/b-part (build, 1 source, partly enforced): Which argument is still unpinned?",
			"- zz-test/c-judged (both, 1 source): Did I read it twice?",
		})
		local _, design = run({ "--when", "design" })
		t.expect(lines(design)).toEqual({ "- zz-test/c-judged (both, 1 source): Did I read it twice?" })
	end)

	it("--enforced lists only the fully enforced lessons, also under --when", function()
		local _, plain = run({ "--enforced" })
		t.expect(#lines(plain)).toBe(1)
		t.expect(string.find(plain, "zz-test/a-full", 1, true) ~= nil).toBe(true)
		local _, build = run({ "--enforced", "--when", "build" })
		t.expect(string.find(build, "zz-test/a-full", 1, true) ~= nil).toBe(true)
	end)

	it("--full still prints an enforced lesson's file", function()
		local _, out = run({ "--full", "a-full" })
		t.expect(string.find(out, "enforced_by: z-nile/lints/markers.luau", 1, true) ~= nil).toBe(true)
	end)

	it(
		"--check --policy leaves a finished item's codify line alone; --item compares it and checks its id",
		function()
			local gate = trackerfix.tr(f, f.main, { "lessons", "--check", "--policy" })
			t.expect((string.find(gate.stdout .. gate.stderr, "c0020", 1, true))).toBe(nil)
			local item = trackerfix.tr(f, f.main, { "lessons", "--check", "--policy", "--item", "c0020" })
			t.expect(item.code).toBe(1)
			t.expect(
				string.find(item.stdout .. item.stderr, "c0020/harvest.md: codify zz-test/a-full", 1, true)
					~= nil
			).toBe(true)
			t.expect(trackerfix.tr(f, f.main, { "lessons", "--check", "--policy", "--item", "c9999" }).code)
				.toBe(2)
			t.expect(trackerfix.tr(f, f.main, { "lessons", "--policy" }).code).toBe(2)
			t.expect(trackerfix.tr(f, f.main, { "lessons", "--item", "c0020" }).code).toBe(2)
		end
	)

	it("--codified reports the share, and takes no other option", function()
		local code, out = run({ "--codified" })
		t.expect(code).toBe(0)
		for _, needle in { "4 lessons", "1 enforced", "1 partly", "2 not codifiable", "50%" } do
			t.expect(string.find(out, needle, 1, true) ~= nil).toBe(true)
		end
		local bad = run({ "--codified", "--full" })
		t.expect(bad).toBe(2)
	end)
end)
