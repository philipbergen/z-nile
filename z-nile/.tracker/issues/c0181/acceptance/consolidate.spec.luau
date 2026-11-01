--!strict
-- c0181 AC7: overlap between lessons is found by a pure score over two lessons' own text, so a pair's score does not
-- move when other lessons come or go: 0.65 * Jaccard(words of title + check) + 0.35 * Jaccard(tags), rounded to
-- hundredths (words: lowercase, three letters or more, not a stop word). A same-skill pair at 0.35 or more is "hard"
-- (the policy makes it merge or `distinct_from`); 0.20 or more is a candidate; a cross-skill pair is only "related".
-- `./zn lessons --consolidate [<lesson id>]` reports them, and also bodies over their cap. Read-only.
local consolidate = require("@znile/engine/consolidate")
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function make(id: string, title: string, check: string, tags: string, state: string?): lessons.Lesson
	local l, err = lessons.parse(
		id,
		`---\ntitle: {title}\nwhen: both\ntags: [{tags}]\ncheck: {check}\n{state or ""}from: test\n---\nThe rule.\n`
	)
	return l or error(err)
end
local function has(text: string, needle: string, from: number?): boolean
	return string.find(text, needle, from or 1, true) ~= nil
end
local function skill(name: string): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n`
end
local function file(title: string, check: string, tags: string): string
	return `---\ntitle: {title}\nwhen: both\ntags: [{tags}]\ncheck: {check}\nnot_codifiable: a judgement call\nfrom: test\n---\nThe rule.\n`
end

local A = make("zz-test/a", "alpha beta", "Gamma delta epsilon zeta?", "x, y")
local SAME = make("zz-test/same", "the alpha beta", "Does this gamma delta epsilon zeta?", "x, y") -- stop words differ only
local TAGS = make("zz-test/tags", "kappa lambda", "Mu nu xi omicron?", "x, y") -- same tags, no common word
local THIRD = make("zz-test/third", "kappa lambda", "Mu nu xi omicron?", "x, y, z") -- 2 of 3 tags
local WORDS = make("zz-test/words", "alpha beta", "Gamma delta epsilon zeta?", "p") -- same words, no common tag
local OTHER = make("zz-arch/same", "alpha beta", "Gamma delta epsilon zeta?", "x, y") -- another skill

local f: trackerfix.Fixture

return t.spec("c0181 consolidation", function(it)
	it("scores words and tags as specified, symmetric, in hundredths", function()
		t.expect(consolidate.HARD).toBe(0.35)
		t.expect(consolidate.SOFT).toBe(0.2)
		t.expect(consolidate.similar(A, SAME)).toBe(1)
		t.expect(consolidate.similar(SAME, A)).toBe(1)
		t.expect(consolidate.similar(A, TAGS)).toBe(0.35)
		t.expect(consolidate.similar(A, THIRD)).toBe(0.23)
		t.expect(consolidate.similar(A, WORDS)).toBe(0.65)
	end)

	it("hard pairs are same-skill at 0.35 or more and not cleared by distinct_from", function()
		local function ids(all: { lessons.Lesson }): { string }
			local out = {}
			for _, p in consolidate.hardPairs(all) do
				table.insert(out, `{p.a} {p.b}`)
			end
			table.sort(out)
			return out
		end
		t.expect(ids({ A, TAGS })).toEqual({ "zz-test/a zz-test/tags" }) -- 0.35 itself
		t.expect(ids({ A, THIRD })).toEqual({}) -- 0.23
		t.expect(ids({ A, OTHER })).toEqual({}) -- another skill is related, never hard
		local mark = "distinct_from: zz-test/tags\n"
		t.expect(ids({ make("zz-test/a", "alpha beta", "Gamma delta epsilon zeta?", "x, y", mark), TAGS }))
			.toEqual({})
		local back =
			make("zz-test/tags", "kappa lambda", "Mu nu xi omicron?", "x, y", "distinct_from: zz-test/a\n")
		t.expect(ids({ A, back })).toEqual({}) -- either side's mark clears it
	end)

	it(
		"the report lists candidates with scores, hard ones marked, cross-skill ones as related only",
		function()
			local text = consolidate.report({ A, SAME, THIRD, OTHER }, nil)
			t.expect(has(text, "zz-test/a") and has(text, "zz-test/same")).toBe(true)
			t.expect(has(text, "1.00") and has(text, "must resolve")).toBe(true)
			local related = string.find(text, "related", 1, true)
			t.expect(related ~= nil).toBe(true)
			t.expect(has(text, "zz-arch/same", related :: number)).toBe(true)
			local far = make("zz-test/far", "pi rho", "Sigma tau?", "q")
			t.expect(has(consolidate.report({ A, far }, nil), "zz-test/far")).toBe(false) -- below 0.20
		end
	)

	it(
		"with no id the report groups same-skill pairs into clusters: A-B and B-C make one, A-C below the floor or not",
		function()
			local one = make("zz-test/c1", "x1", "Alpha beta gamma delta?", "p")
			local two = make("zz-test/c2", "x2", "Gamma delta epsilon zeta?", "q")
			local three = make("zz-test/c3", "x3", "Epsilon zeta eta theta?", "r")
			t.expect(consolidate.similar(one, two) >= consolidate.SOFT).toBe(true)
			t.expect(consolidate.similar(two, three) >= consolidate.SOFT).toBe(true)
			t.expect(consolidate.similar(one, three) < consolidate.SOFT).toBe(true)
			local found = {}
			for line in string.gmatch(consolidate.report({ one, two, three }, nil), "[^\n]+") do
				if string.sub(line, 1, 8) == "cluster " then
					table.insert(found, line)
				end
			end
			t.expect(#found).toBe(1)
			t.expect(
				has(found[1], "zz-test/c1") and has(found[1], "zz-test/c2") and has(found[1], "zz-test/c3")
			)
				.toBe(true)
		end
	)

	it("naming a lesson limits the report to the pairs that name it", function()
		local far = make("zz-test/far", "pi rho", "Sigma tau?", "q")
		local text = consolidate.report({ A, SAME, THIRD, far }, "zz-test/third")
		t.expect(has(text, "zz-test/third")).toBe(true)
		t.expect(has(text, "1.00")).toBe(false) -- A and SAME overlap, but neither is the named lesson
	end)

	it("the report lists a body over its cap", function()
		local l = lessons.parse(
			"zz-test/fat",
			`---\ntitle: pi rho\nwhen: both\ntags: [q]\ncheck: Sigma tau?\nnot_codifiable: a judgement call\n---\n{string.rep(
				"x",
				2501
			)}\n`
		)
		t.expect(has(consolidate.report({ l :: lessons.Lesson }, nil), "zz-test/fat")).toBe(true)
	end)

	it("sets up a fixture with a near-duplicate pair, a far lesson and a cross-skill twin", function()
		f = trackerfix.new("codify-consolidate", {
			["z-nile/skills/zz-test/SKILL.md"] = skill("zz-test"),
			["z-nile/skills/zz-arch/SKILL.md"] = skill("zz-arch"),
			["z-nile/skills/zz-test/lessons/a.md"] = file("alpha beta", "Gamma delta epsilon zeta?", "x, y"),
			["z-nile/skills/zz-test/lessons/b.md"] = file("alpha beta", "Gamma delta epsilon zeta?", "x, y"),
			["z-nile/skills/zz-test/lessons/c.md"] = file("pi rho", "Sigma tau?", "q"),
			["z-nile/skills/zz-arch/lessons/a.md"] = file("alpha beta", "Gamma delta epsilon zeta?", "x, y"),
		}, { noLessons = true })
	end)

	it("lessons --consolidate lists candidates and exits 0; a lesson id limits it and is checked", function()
		local r = trackerfix.tr(f, f.main, { "lessons", "--consolidate" })
		t.expect(r.code).toBe(0)
		t.expect(has(r.stdout, "zz-test/a") and has(r.stdout, "zz-test/b")).toBe(true)
		t.expect(has(r.stdout, "zz-test/c")).toBe(false)
		local one = trackerfix.tr(f, f.main, { "lessons", "--consolidate", "zz-test/c" })
		t.expect(one.code).toBe(0)
		t.expect(has(one.stdout, "zz-test/a")).toBe(false)
		t.expect(trackerfix.tr(f, f.main, { "lessons", "--consolidate", "zz-test/none" }).code).toBe(2)
		t.expect(trackerfix.tr(f, f.main, { "lessons", "--consolidate", "--full" }).code).toBe(2)
	end)

	it("--check --policy names the hard pair and how to clear it", function()
		local r = trackerfix.tr(f, f.main, { "lessons", "--check", "--policy" })
		t.expect(r.code).toBe(1)
		local all = r.stdout .. r.stderr
		t.expect(has(all, "zz-test/a") and has(all, "zz-test/b")).toBe(true)
		t.expect(has(all, "lesson-merge") and has(all, "distinct_from")).toBe(true)
	end)
end)
