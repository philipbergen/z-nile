--!strict
-- c0291 AC3: a prep PR may carry a note file as it may a lesson (dispatch.isLesson), each in its own shape (a lesson
-- slug, a note name), and nothing deeper.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

return t.spec("c0291 note paths", function(it)
	it(
		"AC3: a lesson and a note in its notes folder are lesson paths, in z-nile's skills and a project's",
		function()
			t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson.md")).toBe(true)
			t.expect(
				dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson/2026-11-09-c0279-review-001-f3.md")
			)
				.toBe(true)
			t.expect(dispatch.isLesson("pickman/skills/pickman-arch/lessons/a-lesson/2026-11-09-a.md"))
				.toBe(true)
		end
	)

	it("AC3: deeper paths, other files and other folders are not", function()
		t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson/deeper/2026-11-09-a.md"))
			.toBe(false)
		t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson/2026-11-09-a.txt")).toBe(false)
		t.expect(dispatch.isLesson("z-nile/skills/zz-test/SKILL.md")).toBe(false)
		t.expect(dispatch.isLesson("z-nile/skills/zz-test/notes/a-lesson/2026-11-09-a.md")).toBe(false)
		t.expect(dispatch.isLesson("z-nile/engine/lessons/a/b.md")).toBe(false)
	end)

	it(
		"AC3: a file in a notes folder not shaped as a note, or a folder not shaped as a slug, is not",
		function()
			t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson/CLAUDE.md")).toBe(false)
			t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson/AGENTS.md")).toBe(false)
			t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson/also.md")).toBe(false)
			t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a-lesson/2026-11-09.md")).toBe(false)
			t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/Upper/2026-11-09-a.md")).toBe(false)
		end
	)

	it("AC3: a lesson file whose name is not a slug's shape is not", function()
		t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/CLAUDE.md")).toBe(false)
		t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/Upper-Case.md")).toBe(false)
		t.expect(dispatch.isLesson("z-nile/skills/zz-test/lessons/a_lesson.md")).toBe(false)
	end)
end)
