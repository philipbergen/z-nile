--!strict
-- c0181 AC2: `codify.policy(lessons, env)` is the codification policy `./zn lessons --check --policy` runs and the
-- gate enforces: every lesson states either `enforced_by` + `enforced` or `not_codifiable`; the body fits its cap
-- (full 500 bytes, part 1200, otherwise 2500); every check named exists where the gate runs it and is a case named
-- `[<lesson id>] …` (a spec) or a lint that names the lesson; a near-duplicate pair in one skill is merged or marked
-- `distinct_from`; a merge's marker is gone; no skill text names a lesson that is gone. `env.files` holds the text of
-- every path a lesson names (an absent path does not exist), `env.homes` the registered projects' homes, `env.docs`
-- the skills' texts and AGENTS.md. A harvest `codify` line is history: the gate checks its shape and that its lesson
-- exists (or was merged); only `codify.agree` (`--check --policy --item <id>`) compares it with the lesson. Pure.
local codify = require("@znile/engine/codify")
local consolidate = require("@znile/engine/consolidate")
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

-- not in the module yet: reached through any, so the type check of the promoted copy needs only the new modules
local parseCodify: (string, string) -> ({ any }, { string }) = (lessons :: any).parseCodify

local HOMES = { "z-nile", "pickman" }
local SKILLS = { "zz-test", "zz-arch", "z-design" } -- the skills of the tree: only these start a lesson id in a skill text
local WHY = "needs a human to judge the design's intent"
-- every fixture lesson gets its own tags and check words, so no two of them reach the overlap threshold by accident
local function lintText(id: string): string
	return `return \{ lesson = "{id}" }\n`
end
local function specText(id: string): string
	return `return t.spec("x", function(it)\n\tit(\n\t\t"[{id}] the case, with a comma",\n\t\tfunction() end\n\t)\nend)\n`
end

local function make(id: string, front: string, body: string?, tags: string?, check: string?): lessons.Lesson
	local own = string.gsub(string.match(id, "[^/]+$") :: string, "[^%w]", "")
	local text =
		`---\ntitle: {own}\nwhen: both\ntags: [{tags or own}]\ncheck: {check or `{own}?`}\n{front}---\n{body or "The rule."}\n`
	local l, err = lessons.parse(id, text)
	if not l then
		error(`bad fixture {id}: {err}`, 2)
	end
	return l
end

local function has(problems: { string }, ...: string): boolean
	for _, p in problems do
		local all = true
		for _, needle in { ... } do
			all = all and string.find(p, needle, 1, true) ~= nil
		end
		if all then
			return true
		end
	end
	return false
end

local function policy(
	all: { lessons.Lesson },
	files: { [string]: string }?,
	docs: { [string]: string }?
): { string }
	return codify.policy(all, { files = files or {}, homes = HOMES, skills = SKILLS, docs = docs or {} })
end

local function spec(id: string): string
	return `z-nile/tests/meta/{string.match(id, "[^/]+$")}.spec.luau :: "[{id}] the case, with a comma"`
end
local function filesFor(id: string): { [string]: string }
	return {
		[`z-nile/lints/{string.match(id, "[^/]+$")}.luau`] = lintText(id),
		[`z-nile/tests/meta/{string.match(id, "[^/]+$")}.spec.luau`] = specText(id),
	}
end
local function lintRef(id: string): string
	return `z-nile/lints/{string.match(id, "[^/]+$")}.luau`
end

return t.spec("c0181 codification policy", function(it)
	it("passes a tree whose lessons are enforced (lint, spec case) or not codifiable", function()
		local a = make(
			"zz-test/plain-find",
			`enforced_by: {lintRef("zz-test/plain-find")}\nenforced: full\n`,
			"Pass plain = true."
		)
		local b = make("zz-test/a-case", `enforced_by: {spec("zz-test/a-case")}\nenforced: part\n`)
		local c = make("zz-arch/judged", `not_codifiable: {WHY}\n`)
		-- the fixtures do not overlap, or this case would prove nothing about over-reporting
		t.expect(consolidate.similar(a, b) < consolidate.SOFT).toBe(true)
		local files = filesFor("zz-test/plain-find")
		for path, text in filesFor("zz-test/a-case") do
			files[path] = text
		end
		t.expect(policy({ a, b, c }, files)).toEqual({})
	end)

	it("names a lesson with no state, with both states, or with enforced and no check", function()
		local none = policy({ make("zz-test/none", "") })
		t.expect(has(none, "zz-test/none", "enforced_by", "not_codifiable")).toBe(true)
		local both = policy({
			make(
				"zz-test/both",
				`enforced_by: {lintRef("zz-test/both")}\nenforced: full\nnot_codifiable: {WHY}\n`
			),
		}, filesFor("zz-test/both"))
		t.expect(has(both, "zz-test/both", "both")).toBe(true)
		local lone = policy({ make("zz-test/lone", "enforced: full\n") })
		t.expect(has(lone, "zz-test/lone", "enforced")).toBe(true)
		local lone2 = policy(
			{ make("zz-test/lone2", `enforced_by: {lintRef("zz-test/lone2")}\n`) },
			filesFor("zz-test/lone2")
		)
		t.expect(has(lone2, "zz-test/lone2", "enforced")).toBe(true)
	end)

	it("caps the body: 500 bytes for full, 1200 for part, 2500 otherwise, the cap itself allowed", function()
		local function body(n: number): string
			return string.rep("x", n)
		end
		for _, case in
			{
				{ front = `enforced_by: {lintRef("zz-test/cap")}\nenforced: full\n`, cap = 500 },
				{ front = `enforced_by: {lintRef("zz-test/cap")}\nenforced: part\n`, cap = 1200 },
				{ front = `not_codifiable: {WHY}\n`, cap = 2500 },
			}
		do
			local files = filesFor("zz-test/cap")
			t.expect(policy({ make("zz-test/cap", case.front, body(case.cap)) }, files)).toEqual({})
			local over = policy({ make("zz-test/cap", case.front, body(case.cap + 1)) }, files)
			t.expect(has(over, "zz-test/cap", tostring(case.cap))).toBe(true)
		end
	end)

	it(
		"refuses a check that does not exist where the gate runs it, or is not a case named for the lesson",
		function()
			local id = "zz-test/ref"
			local function one(ref: string, files: { [string]: string }?): { string }
				return policy({ make(id, `enforced_by: {ref}\nenforced: full\n`) }, files or filesFor(id))
			end
			t.expect(one(lintRef(id))).toEqual({})
			t.expect(one(spec(id))).toEqual({})
			t.expect(has(one("z-nile/lints/missing.luau"), id, "z-nile/lints/missing.luau")).toBe(true)
			-- a case that does not exist, or that exists under another name
			t.expect(has(one(`z-nile/tests/meta/ref.spec.luau :: "[{id}] no such case"`), id, "no such case"))
				.toBe(true)
			-- a spec ref without a case, and a case not named for this lesson
			t.expect(has(one("z-nile/tests/meta/ref.spec.luau"), id, "case")).toBe(true)
			local other = { ["z-nile/tests/meta/ref.spec.luau"] = specText("zz-test/another") }
			t.expect(
				has(
					one(
						`z-nile/tests/meta/ref.spec.luau :: "[zz-test/another] the case, with a comma"`,
						other
					),
					id,
					`[{id}]`
				)
			).toBe(true)
			-- where the gate does not run a spec: sequestered, .cache, experiments, another folder; where it does: pickman's tests
			for _, path in
				{
					"z-nile/.tracker/issues/c0999/acceptance/ref.spec.luau",
					"z-nile/.cache/ref.spec.luau",
					"z-nile/.tracker/issues/c0999/experiments/ref.spec.luau",
					"z-nile/lints/ref.spec.luau",
				}
			do
				local files = { [path] = specText(id) }
				t.expect(has(one(`{path} :: "[{id}] the case, with a comma"`, files), id, "tests/"))
					.toBe(true)
			end
			local pick = "pickman/tests/unit/ref.spec.luau"
			t.expect(one(`{pick} :: "[{id}] the case, with a comma"`, { [pick] = specText(id) })).toEqual({})
			-- neither a lint under z-nile/lints/ nor a spec
			t.expect(has(one("z-nile/engine/lessons.luau"), id, "lint or a spec")).toBe(true)
			-- a lint file that names another lesson
			t.expect(
				has(one(lintRef(id), { [lintRef(id)] = lintText("zz-test/another") }), id, "does not name")
			)
				.toBe(true)
		end
	)

	it(
		"finds a case whose name stylua wrapped onto its own line, and not a case of a similar name",
		function()
			local id = "zz-test/wrapped"
			local ref = `z-nile/tests/meta/wrapped.spec.luau :: "[{id}] the case, with a comma"`
			local wrapped = { ["z-nile/tests/meta/wrapped.spec.luau"] = specText(id) }
			t.expect(wrapped["z-nile/tests/meta/wrapped.spec.luau"]:find("it(\n", 1, true) ~= nil).toBe(true)
			t.expect(policy({ make(id, `enforced_by: {ref}\nenforced: full\n`) }, wrapped)).toEqual({})
			local near = { ["z-nile/tests/meta/wrapped.spec.luau"] = specText(id):gsub("comma", "commas") }
			t.expect(
				has(
					policy({ make(id, `enforced_by: {ref}\nenforced: full\n`) }, near),
					id,
					"the case, with a comma"
				)
			).toBe(true)
		end
	)

	it("refuses a placeholder reason: fifteen characters and a space at least", function()
		t.expect(has(policy({ make("zz-test/n", "not_codifiable: n/a\n") }), "zz-test/n", "reason"))
			.toBe(true)
		t.expect(
			has(policy({ make("zz-test/n", "not_codifiable: judgement-only-text\n") }), "zz-test/n", "reason")
		)
			.toBe(true)
		t.expect(policy({ make("zz-test/n", "not_codifiable: a judgement call\n") })).toEqual({})
	end)

	it(
		"makes a near-duplicate pair of one skill merge or say distinct_from; another skill's pair is free",
		function()
			local tags, check = "locks, claims", "Who else can claim this item while the claim is open?"
			local a = make("zz-arch/aaa", `not_codifiable: {WHY}\n`, nil, tags, check)
			local b = make("zz-arch/bbb", `not_codifiable: {WHY}\n`, nil, tags, check)
			t.expect(has(policy({ a, b }), "zz-arch/aaa", "zz-arch/bbb", "lesson-merge", "distinct_from"))
				.toBe(true)
			local cleared =
				make("zz-arch/aaa", `not_codifiable: {WHY}\ndistinct_from: zz-arch/bbb\n`, nil, tags, check)
			t.expect(policy({ cleared, b })).toEqual({}) -- one side's mark is enough
			t.expect(policy({ a, make("zz-test/bbb", `not_codifiable: {WHY}\n`, nil, tags, check) }))
				.toEqual({})
			-- a mark naming a lesson that does not exist, or itself
			local ghost =
				make("zz-arch/ccc", `not_codifiable: {WHY}\ndistinct_from: zz-arch/ghost, zz-arch/ccc\n`)
			local bad = policy({ ghost })
			t.expect(has(bad, "zz-arch/ccc", "zz-arch/ghost")).toBe(true)
			t.expect(has(bad, "zz-arch/ccc", "itself")).toBe(true)
		end
	)

	it("refuses a lesson that still carries the lesson-merge marker", function()
		local l = make(
			"zz-test/merged",
			`not_codifiable: {WHY}\nmerged: zz-test/old\n`,
			"Rule.\n\n<!-- merged from zz-test/old: tighten -->\nMore."
		)
		local problems = policy({ l })
		t.expect(has(problems, "zz-test/merged", "merged", "tighten")).toBe(true)
		t.expect(#problems).toBe(1)
	end)

	it(
		"a skill text naming a lesson that is gone is a problem, naming the survivor when it was merged",
		function()
			local keep = make("zz-test/keep", `not_codifiable: {WHY}\nmerged: zz-test/old\n`)
			local docs = {
				["z-nile/skills/zz-arch/SKILL.md"] = "See `zz-test/old` and `zz-test/keep`, lesson zz-test/ghost, but not zz-test/keepsake or a path z-nile/skills/zz-test/lessons/x.md.\n",
				["AGENTS.md"] = "Lesson zz-test/old1 is not zz-test/old. Decoys: `origin/main`, `tests/run`, `z-nile/next`, lesson foo/bar.\n",
				["z-nile/skills/zz-test/lessons/other.md"] = "`zz-test/gone` in a lesson body is not scanned.\n",
			}
			local problems = policy({ keep }, nil, docs)
			t.expect(
				has(problems, "z-nile/skills/zz-arch/SKILL.md", "zz-test/old", "merged into zz-test/keep")
			)
				.toBe(true)
			t.expect(has(problems, "z-nile/skills/zz-arch/SKILL.md", "zz-test/ghost")).toBe(true)
			t.expect(has(problems, "AGENTS.md", "zz-test/old1")).toBe(true) -- a longer id is its own token
			t.expect(has(problems, "zz-test/keepsake")).toBe(false)
			for _, decoy in { "origin/main", "tests/run", "z-nile/next", "foo/bar" } do
				t.expect(has(problems, decoy)).toBe(false) -- a path, or a skill the tree does not have
			end
			t.expect(has(problems, "zz-test/gone")).toBe(false)
			t.expect(has(problems, "lessons/x.md")).toBe(false)
		end
	)

	it(
		"a harvest codify line is history: the gate checks its shape and its lesson, agree compares it",
		function()
			local enforced = make("zz-test/e", `enforced_by: {lintRef("zz-test/e")}\nenforced: full\n`)
			local judged = make("zz-test/j", `not_codifiable: {WHY}\n`)
			local text = `- codify zz-test/e: {lintRef("zz-test/e")}\n- codify zz-test/j: not codifiable: {WHY}\n`
				.. `- codify zz-test/e: not codifiable: {WHY}\n`
			local entries, bad = parseCodify("c0999", text)
			t.expect(bad).toEqual({})
			t.expect(#entries).toBe(3)
			t.expect(entries[1].lesson).toBe("zz-test/e")
			t.expect(entries[1].ref).toBe(lintRef("zz-test/e"))
			t.expect(entries[2].reason).toBe(WHY)
			-- a malformed line is a problem of the item
			local _, malformed = parseCodify("c0999", "- codify zz-test/e:\n- codify nonsense: x\n")
			t.expect(#malformed).toBe(2)
			-- the gate passes the line that disagrees (the lesson changed after the item was done)
			t.expect(codify.ledger({ enforced, judged }, entries)).toEqual({})
			-- an entry for a lesson that does not exist fails; one for a merged lesson passes
			local ghost = parseCodify("c0999", "- codify zz-test/ghost: not codifiable: a judgement call\n")
			t.expect(has(codify.ledger({ enforced }, ghost), "zz-test/ghost")).toBe(true)
			local survivor = make("zz-test/keep", `not_codifiable: {WHY}\nmerged: zz-test/ghost\n`)
			t.expect(codify.ledger({ survivor }, ghost)).toEqual({})
			-- the item's own check (--item) compares: the third line disagrees; a spec ref also needs its mutation record
			local problems = codify.agree({ enforced, judged }, entries)
			t.expect(#problems).toBe(1)
			t.expect(has(problems, "c0999", "zz-test/e")).toBe(true)
			local specLesson = make("zz-test/s", `enforced_by: {spec("zz-test/s")}\nenforced: full\n`)
			local noMutant = parseCodify("c0999", `- codify zz-test/s: {spec("zz-test/s")}\n`)
			t.expect(has(codify.agree({ specLesson }, noMutant), "zz-test/s", "mutant")).toBe(true)
			local withMutant = parseCodify(
				"c0999",
				`- codify zz-test/s: {spec("zz-test/s")} mutant: the loop stops at the first key\n`
			)
			t.expect(codify.agree({ specLesson }, withMutant)).toEqual({})
			-- a clause tried and given up inside an enforced lesson is recorded on the line: `part: tried <what>`
			local tried = parseCodify(
				"c0999",
				`- codify zz-test/s: {spec("zz-test/s")} mutant: a first mutant part: tried the second clause needs a run no fixture can start\n`
			)
			t.expect(tried[1].partTried).toBe("the second clause needs a run no fixture can start")
			t.expect(tried[1].mutant).toBe("a first mutant")
			-- a clause left by a recorded decision (a G6 answer, a dependency not landed) is its own field
			local decided = parseCodify(
				"c0999",
				"- codify zz-test/s: z-nile/lints/s.luau part: decided G6(d): c0117 has not landed\n"
			)
			t.expect(decided[1].partDecided).toBe("G6(d): c0117 has not landed")
			t.expect(decided[1].ref).toBe("z-nile/lints/s.luau")
		end
	)

	it("a codify line is not a source, not a finding and not a problem of the harvest reader", function()
		local text = "- codify zz-test/e: not codifiable: a judgement call\n"
		local entries, problems = lessons.parseHarvest("c0999", text)
		t.expect(#entries).toBe(0)
		t.expect(problems).toEqual({})
		local item = { id = "c0999", reviews = {}, harvest = text }
		t.expect(lessons.sources({ item })["zz-test/e"]).toBe(nil)
		t.expect(lessons.uncovered({ item })).toEqual({})
	end)
end)
