--!strict
-- c0111 AC1: a lesson file (.claude/skills/<skill>/lessons/<slug>.md) parses into its fields, and every bad
-- field is named, with the lesson's id, in the one problem parse returns.
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

local GOOD = "---\ntitle: Run the promoted specs\nwhen: design\ntags: [regression, overrides]\n"
	.. "check: Does every promoted spec still pass?\n---\nThe rule.\n\n**Why:** it bit R0039.\n"

-- GOOD with one frontmatter line replaced (or removed, when `line` is "")
local function with(key: string, line: string): string
	local out = string.gsub(GOOD, `\n{key}:[^\n]*`, if line == "" then "" else "\n" .. line, 1)
	return out
end

local function problem(id: string, text: string): string
	local l, err = lessons.parse(id, text)
	if l or not err then
		error(`expected a problem for {id}, got a lesson`, 2)
	end
	return err
end

local function has(text: string, ...: string)
	for _, needle in { ... } do
		if not string.find(text, needle, 1, true) then
			error(`{needle} not in: {text}`, 2)
		end
	end
end

return t.spec("c0111 lesson format", function(it)
	it("a full lesson parses into every field", function()
		local l, err = lessons.parse("ticket-prep/promoted-specs", GOOD)
		t.expect(err).toBe(nil)
		local lesson = l :: lessons.Lesson
		t.expect(lesson.id).toBe("ticket-prep/promoted-specs")
		t.expect(lesson.skill).toBe("ticket-prep")
		t.expect(lesson.slug).toBe("promoted-specs")
		t.expect(lesson.title).toBe("Run the promoted specs")
		t.expect(lesson.when).toBe("design")
		t.expect(lesson.tags).toEqual({ "regression", "overrides" })
		t.expect(lesson.check).toBe("Does every promoted spec still pass?")
		t.expect(lesson.from).toBe(nil)
		t.expect(string.find(lesson.body, "The rule.", 1, true) ~= nil).toBe(true)
		local withFrom, _ =
			lessons.parse("review/x", with("check", "check: Is it?\nfrom: user 2026-10-20: said so"))
		t.expect((withFrom :: lessons.Lesson).from).toBe("user 2026-10-20: said so")
		for _, w in { "build", "both" } do
			local lw, e = lessons.parse("review/x", with("when", `when: {w}`))
			t.expect(e).toBe(nil)
			t.expect((lw :: lessons.Lesson).when).toBe(w)
		end
	end)

	it("each missing or bad field is named with the lesson's id", function()
		has(problem("a/x", with("title", "")), "a/x", "title")
		has(problem("a/x", with("title", "title:   ")), "a/x", "title")
		has(problem("a/x", with("when", "")), "a/x", "when")
		has(problem("a/x", with("when", "when: sometimes")), "a/x", "when")
		has(problem("a/x", with("tags", "")), "a/x", "tags")
		has(problem("a/x", with("tags", "tags: []")), "a/x", "tags")
		has(problem("a/x", with("tags", "tags: [Bad_Tag]")), "a/x", "tags")
		has(problem("a/x", with("tags", "tags: regression")), "a/x", "tags")
		has(problem("a/x", with("tags", "tags: [wiring, wiring]")), "a/x", "wiring", "repeated")
		has(problem("a/x", with("check", "")), "a/x", "check")
		has(problem("a/x", with("title", "title: T\nowner: me")), "a/x", "owner")
		has(problem("a/x", (string.gsub(GOOD, "\n%-%-%-\n.*$", "\n---\n  \n"))), "a/x", "body")
		has(problem("a/x", with("when", "when: design\nwhen: build")), "a/x", "when", "repeated")
		has(problem("a/x", with("check", "check: Is it?\nfrom: one\nfrom: two")), "a/x", "from", "repeated")
		has(problem("a/x", "no frontmatter at all\n"), "a/x")
		has(problem("a/Bad_Slug", GOOD), "a/Bad_Slug", "slug")
		has(problem("a/x-", GOOD), "a/x-", "slug")
		has(problem("noslash", GOOD), "noslash")
		has(problem("a/b/c", GOOD), "a/b/c")
	end)

	it("check must be one line ending in ?", function()
		has(problem("a/x", with("check", "check: Every promoted spec still passes.")), "a/x", "check")
		local l, err = lessons.parse("a/x", with("check", "check: Does it?"))
		t.expect(err).toBe(nil)
		t.expect((l :: lessons.Lesson).check).toBe("Does it?")
	end)
end)
