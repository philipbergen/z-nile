--!strict
-- c0112 AC3 and the conflict rule: `sources-kept.luau` compares lessons and sources as sets. Strict (no option, what
-- check.sh AC3 runs) a lesson gone from the current tree is a loss; with `--merges` (the zz-rules sentence for a
-- harvest.md conflict, and a c0181-style consolidation) it is kept only when exactly one current lesson of the same
-- skill holds every source the base gave it. This spec outlives the migration: the rule must hold for every later branch
-- that consolidates. Hand-made trees under .cache/c0112-sources; nothing else is read or written.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the script sits beside this spec, in the issue's acceptance/ folder before `done` and in tests/acceptance/c0112/ after
local SCRIPT = (string.match(debug.info(1, "s"), "^(.*)/[^/]+$") :: string) .. "/sources-kept.luau"
local ROOT = ".cache/c0112-sources"

local LESSON = "---\ntitle: T\nwhen: both\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nBody.\n"
local REVIEW = "# Review 001: R0010 (design mode)\nInputs: abc\n\n### F1 [low] a\nWhere: x\n\n### F2 [low] b\nWhere: y\n"
	.. "\n### F3 [low] c\nWhere: z\n\n### F4 [low] d\nWhere: w\n"

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

-- a tree with 100 filler lessons (the script refuses a base with fewer: a base it could not have read), the given
-- lessons, and one item whose ledger is `ledger`
local function build(name: string, ids: { string }, ledger: string): string
	local root = `{ROOT}/{name}`
	write(
		`{root}/z-nile/projects.toml`,
		'retired = []\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n'
	)
	for _, skill in { "z-design", "zz-test" } do
		write(`{root}/z-nile/skills/{skill}/SKILL.md`, `---\nname: {skill}\ndescription: d\n---\n`)
	end
	for i = 1, 100 do
		write(`{root}/z-nile/skills/z-design/lessons/filler-{i}.md`, LESSON)
	end
	for _, id in ids do
		write(`{root}/z-nile/skills/{id}.md`, LESSON)
	end
	write(`{root}/pickman/.tracker/rafts/done/R0010/design-review-001.md`, REVIEW)
	write(`{root}/pickman/.tracker/rafts/done/R0010/harvest.md`, `# Harvest: R0010\n\n{ledger}`)
	return root
end
-- the lesson files live at <skill>/lessons/<slug>.md: map "zz-test/from" to that path
local function lessonIds(ids: { string }): { string }
	local out: { string } = {}
	for _, id in ids do
		local skill, slug = string.match(id, "^([^/]+)/(.+)$")
		table.insert(out, `{skill}/lessons/{slug}`)
	end
	return out
end

local function run(base: string, cur: string, merges: boolean): (number, string)
	local args = { "run", SCRIPT, "--" }
	if merges then
		table.insert(args, "--merges")
	end
	table.insert(args, base)
	table.insert(args, cur)
	local r = process.exec("lune", args)
	return r.code, r.stdout .. r.stderr
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local BASE_IDS = { "zz-test/from", "zz-test/into", "z-design/other" }
-- from holds F1 and F4, into holds F2, other holds F3
local BASE_LEDGER = "- design-review-001 F1: zz-test/from\n- design-review-001 F2: zz-test/into\n"
	.. "- design-review-001 F3: z-design/other\n- design-review-001 F4: zz-test/from\n"

return t.spec("c0112 sources-kept compares sources, strict or across a lesson merge", function(it)
	if fs.isDir(ROOT) then
		fs.removeDir(ROOT)
	end
	local base = build("base", lessonIds(BASE_IDS), BASE_LEDGER)

	it("identical trees keep every source, strict or with --merges", function()
		local same = build("same", lessonIds(BASE_IDS), BASE_LEDGER)
		for _, merges in { false, true } do
			local code, out = run(base, same, merges)
			t.expect(code).toBe(0)
			t.expect(has(out, "every source kept")).toBe(true)
		end
	end)

	it("a source dropped while another is added to the same lesson is lost, in both modes", function()
		-- F4 leaves zz-test/from, F2 also goes to zz-test/from: the count is unchanged
		local swapped = build(
			"swapped",
			lessonIds(BASE_IDS),
			"- design-review-001 F1: zz-test/from\n- design-review-001 F2: zz-test/into, zz-test/from\n"
				.. "- design-review-001 F3: z-design/other\n- design-review-001 F4: one-off: x\n"
		)
		for _, merges in { false, true } do
			local code, out = run(base, swapped, merges)
			t.expect(code).toBe(1)
			t.expect(has(out, "lesson zz-test/from lost the source: R0010 design-review-001 F4")).toBe(true)
		end
	end)

	local merged = { "zz-test/into", "z-design/other" }
	local mergedLedger = "- design-review-001 F1: zz-test/into\n- design-review-001 F2: zz-test/into\n"
		.. "- design-review-001 F3: z-design/other\n- design-review-001 F4: zz-test/into\n"

	it(
		"a lesson merged into one lesson that holds all its sources is a loss strict and kept with --merges",
		function()
			local cur = build("merged", lessonIds(merged), mergedLedger)
			local strictCode, strictOut = run(base, cur, false)
			t.expect(strictCode).toBe(1)
			t.expect(has(strictOut, "lesson zz-test/from is gone")).toBe(true)
			local code, out = run(base, cur, true)
			t.expect(code).toBe(0)
			t.expect(has(out, "lesson zz-test/from merged into zz-test/into")).toBe(true)
		end
	)

	it(
		"--merges keeps a deleted lesson whose sources went to lessons of its skill, and refuses one whose sources did not",
		function()
			-- two lessons of its skill hold all of from's sources (a ledger line may name another lesson beside it): kept, both named
			local twoIds = { "zz-test/into", "zz-test/extra", "z-design/other" }
			local two = build(
				"two",
				lessonIds(twoIds),
				"- design-review-001 F1: zz-test/into, zz-test/extra\n- design-review-001 F2: zz-test/into\n"
					.. "- design-review-001 F3: z-design/other\n- design-review-001 F4: zz-test/into, zz-test/extra\n"
			)
			local code, out = run(base, two, true)
			t.expect(code).toBe(0)
			t.expect(has(out, "lesson zz-test/from merged into zz-test/extra, zz-test/into")).toBe(true)
			-- the survivor is in another skill
			local other = build(
				"other",
				lessonIds(merged),
				"- design-review-001 F1: z-design/other\n- design-review-001 F2: zz-test/into\n"
					.. "- design-review-001 F3: z-design/other\n- design-review-001 F4: z-design/other\n"
			)
			code, out = run(base, other, true)
			t.expect(code).toBe(1)
			t.expect(has(out, "lesson zz-test/from is gone, and no lesson of zz-test holds all its sources"))
				.toBe(true)
			-- one source of the deleted lesson (F4) is missing from the survivor
			local missing = build(
				"missing",
				lessonIds(merged),
				"- design-review-001 F1: zz-test/into\n- design-review-001 F2: zz-test/into\n"
					.. "- design-review-001 F3: z-design/other\n- design-review-001 F4: one-off: x\n"
			)
			code, out = run(base, missing, true)
			t.expect(code).toBe(1)
			t.expect(has(out, "lesson zz-test/from is gone, and no lesson of zz-test holds all its sources"))
				.toBe(true)
		end
	)
end)
