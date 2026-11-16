--!strict
-- c0291 AC1: a note to a lesson is a file of its own (`lessons/<slug>/<YYYY-MM-DD>-<label>.md`). The pure layer:
-- the note's name, the lesson's whole text (its file, then its notes in name order), and what `check` refuses.
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")

local GOOD = "---\ntitle: A lesson\nwhen: design\ntags: [merge]\ncheck: Is it merged?\n---\nThe rule.\n"

local function tree(notes: { [string]: { lessons.Note } }?, extra: { [string]: string }?): lessons.Tree
	local ls: { [string]: string } = { ["zz-test/a-lesson"] = GOOD }
	local more: { [string]: string } = extra or {}
	for id, text in more do
		ls[id] = text
	end
	return {
		lessons = ls,
		notes = notes,
		found = { c0010 = true },
		skills = { ["zz-test"] = true },
		folders = { ["zz-test"] = "z-nile/skills/zz-test" },
		owners = { ["zz-test"] = "z-nile" },
		items = {
			{ id = "c0010", reviews = {}, harvest = "- note a source: zz-test/a-lesson\n" },
		},
		problems = {},
	}
end

local function has(list: { string }, needle: string): boolean
	for _, p in list do
		if string.find(p, needle, 1, true) then
			return true
		end
	end
	return false
end

return t.spec("c0291 lesson notes", function(it)
	it(
		"AC1: a note's name is <YYYY-MM-DD>-<label>.md with a real date and a lowercase kebab label",
		function()
			local date, label = lessons.noteName("2026-11-09-c0279-design-review-002-f3.md")
			t.expect(date).toBe("2026-11-09")
			t.expect(label).toBe("c0279-design-review-002-f3")
			for _, bad in
				{
					"2026-11-09.md", -- no label
					"2026-11-09-.md",
					"2026-13-01-a.md", -- no month 13
					"2026-11-32-a.md",
					"2026-11-09-Upper.md",
					"2026-11-09-a-.md", -- a trailing dash
					"2026-11-09-a--b.md",
					"2026-11-09-a.txt",
					"2026-11-09-a.md.bak",
					"note-2026-11-09-a.md", -- the date first
					"26-11-09-a.md",
				}
			do
				local d, l = lessons.noteName(bad)
				if d ~= nil or l ~= nil then
					error(`{bad} was taken for a note name`)
				end
			end
		end
	)

	it(
		"AC1: with no notes a lesson's text is its file byte for byte, whether the tree has a notes map or not",
		function()
			t.expect(lessons.compose(GOOD, {})).toBe(GOOD)
			t.expect(lessons.compose("no newline", {})).toBe("no newline")
			t.expect(lessons.text(tree(nil), "zz-test/a-lesson")).toBe(GOOD)
			t.expect(lessons.text(tree({}), "zz-test/a-lesson")).toBe(GOOD)
			t.expect(lessons.text(tree(nil), "zz-test/no-such")).toBe(nil)
		end
	)

	it(
		"AC1: the notes follow the file in name order, each after one blank line, whatever order they were read in",
		function()
			local older = { name = "2026-11-02-c0200-design-review-001-f1.md", text = "Older note.\n" }
			local newer = { name = "2026-11-09-c0279-design-review-002-f3.md", text = "Newer note.\n" }
			local same = { name = "2026-11-09-c0280-review-001-f2.md", text = "Same day, later label.\n" }
			local want = GOOD .. "\nOlder note.\n\nNewer note.\n\nSame day, later label.\n"
			t.expect(lessons.compose(GOOD, { same, newer, older })).toBe(want)
			t.expect(lessons.compose(GOOD, { older, newer, same })).toBe(want)
			t.expect(
				lessons.text(tree({ ["zz-test/a-lesson"] = { newer, same, older } }), "zz-test/a-lesson")
			)
				.toBe(want)
		end
	)

	it(
		"AC1: a file or a note with no final newline gets one, so the next note still starts after a blank line",
		function()
			local n1 = { name = "2026-11-02-a.md", text = "One." }
			local n2 = { name = "2026-11-03-b.md", text = "Two." }
			t.expect(lessons.compose("Body.", { n2, n1 })).toBe("Body.\n\nOne.\n\nTwo.\n")
		end
	)

	it("AC1: the parsed lesson's body carries its notes, after the file's own body", function()
		local n = { name = "2026-11-09-c0279-design-review-002-f3.md", text = "A note word: zebrafinch.\n" }
		local text = lessons.text(tree({ ["zz-test/a-lesson"] = { n } }), "zz-test/a-lesson") :: string
		local l = lessons.parse("zz-test/a-lesson", text)
		t.expect(l ~= nil).toBe(true)
		local body = (l :: lessons.Lesson).body
		t.expect(body).toBe("The rule.\n\nA note word: zebrafinch.\n")
		t.expect(#lessons.select({ l :: lessons.Lesson }, {}, { words = { "zebrafinch" } })).toBe(1)
	end)

	it("AC1: check passes a lesson with well-named notes, and a tree with no notes map", function()
		local n = { name = "2026-11-09-c0279-design-review-002-f3.md", text = "A note.\n" }
		t.expect(lessons.check(tree({ ["zz-test/a-lesson"] = { n } }))).toEqual({})
		t.expect(lessons.check(tree(nil))).toEqual({})
		t.expect(lessons.check(tree({ ["zz-test/a-lesson"] = {} }))).toEqual({})
	end)

	it("AC1: check refuses a notes folder with no lesson, naming the folder", function()
		local n = { name = "2026-11-09-a.md", text = "A note.\n" }
		local problems = lessons.check(tree({ ["zz-test/gone"] = { n } }))
		t.expect(problems).toEqual({ "z-nile/skills/zz-test/lessons/gone/: notes with no lesson gone.md" })
	end)

	it("AC1: check refuses a file in a notes folder that is not named as a note, naming the file", function()
		local good = { name = "2026-11-09-a.md", text = "A note.\n" }
		local bad = { name = "also.md", text = "**Also:** a note.\n" }
		local problems = lessons.check(tree({ ["zz-test/a-lesson"] = { good, bad } }))
		t.expect(problems).toEqual({
			"z-nile/skills/zz-test/lessons/a-lesson/also.md: not a note file (a note is <YYYY-MM-DD>-<label>.md)",
		})
	end)

	it("AC1: check refuses an empty note, naming the file", function()
		local blank = { name = "2026-11-09-a.md", text = " \n\n" }
		local problems = lessons.check(tree({ ["zz-test/a-lesson"] = { blank } }))
		t.expect(problems)
			.toEqual({ "z-nile/skills/zz-test/lessons/a-lesson/2026-11-09-a.md: the note is empty" })
	end)

	it("AC1: check judges the lesson's own file: an empty body with a note is still refused", function()
		local n = { name = "2026-11-09-a.md", text = "A note.\n" }
		local bare = "---\ntitle: A lesson\nwhen: design\ntags: [merge]\ncheck: Is it merged?\n---\n\n"
		local problems =
			lessons.check(tree({ ["zz-test/a-lesson"] = { n } }, { ["zz-test/a-lesson"] = bare }))
		t.expect(problems).toEqual({ "zz-test/a-lesson: the body is empty" })
	end)

	it("AC1: a notes folder's problems leave the other lessons' checks as they were", function()
		local bad = { name = "x.md", text = "x\n" }
		local problems =
			lessons.check(tree({ ["zz-test/a-lesson"] = { bad } }, { ["zz-test/unsourced"] = GOOD }))
		t.expect(has(problems, "zz-test/unsourced: no source")).toBe(true)
		t.expect(has(problems, "a-lesson/x.md: not a note file")).toBe(true)
		t.expect(#problems).toBe(2)
	end)
end)
