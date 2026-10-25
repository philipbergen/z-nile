--!strict
-- c0111 AC3: select filters lessons by skill, when (both matches either), every tag and every word
-- (case-insensitive, plain), sorts by source count (from counts one) then id; index prints one line per lesson.
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

local function lesson(
	id: string,
	when: string,
	tags: string,
	check: string,
	body: string,
	from: string?
): lessons.Lesson
	local text = `---\ntitle: Title of {id}\nwhen: {when}\ntags: [{tags}]\ncheck: {check}\n`
		.. (if from then `from: {from}\n` else "")
		.. `---\n{body}\n`
	local l, err = lessons.parse(id, text)
	if not l then
		error(err, 2)
	end
	return l
end

local ALL = {
	lesson("testing/pin-inputs", "build", "wiring, seams", "Are the call site's inputs pinned?", "Pin them."),
	lesson(
		"ticket-prep/lifetimes",
		"design",
		"lifetimes",
		"Which process outlives which?",
		"Name the Owner."
	),
	lesson(
		"review/text",
		"both",
		"wiring",
		"Is the text consistent?",
		"Read it twice.",
		"user 2026-10-20: said so"
	),
	lesson("architecture/zeta", "both", "seams", "Is it pure?", "Keep Logic pure."),
}
local SOURCES: { [string]: { string } } = {
	["testing/pin-inputs"] = { "R0010 design-review-001 F1", "R0010 review-001 F2" },
	["ticket-prep/lifetimes"] = { "R0010 design-review-001 F2" },
}

local function ids(list: { lessons.Lesson }): { string }
	local out = {}
	for _, l in list do
		table.insert(out, l.id)
	end
	return out
end

local function pick(q: lessons.Query): { string }
	return ids(lessons.select(ALL, SOURCES, q))
end

return t.spec("c0111 lesson selection", function(it)
	it("filters by skill, when, every tag and every word, case-insensitively", function()
		t.expect(pick({ skills = { "testing", "review" } })).toEqual({ "testing/pin-inputs", "review/text" })
		t.expect(pick({ when = "design" }))
			.toEqual({ "review/text", "ticket-prep/lifetimes", "architecture/zeta" })
		t.expect(pick({ when = "build" }))
			.toEqual({ "testing/pin-inputs", "review/text", "architecture/zeta" })
		t.expect(pick({ tags = { "wiring" } })).toEqual({ "testing/pin-inputs", "review/text" })
		t.expect(pick({ tags = { "wiring", "seams" } })).toEqual({ "testing/pin-inputs" })
		t.expect(pick({ words = { "OWNER" } })).toEqual({ "ticket-prep/lifetimes" }) -- body, any case
		t.expect(pick({ words = { "pin", "inputs" } })).toEqual({ "testing/pin-inputs" }) -- every word
		t.expect(pick({ words = { "pin", "owner" } })).toEqual({})
		t.expect(pick({ words = { "lifetimes" } })).toEqual({ "ticket-prep/lifetimes" }) -- id and tag
		t.expect(pick({ words = { "consistent" } })).toEqual({ "review/text" }) -- check
		t.expect(pick({ words = { "title of architecture" } })).toEqual({ "architecture/zeta" }) -- title
		t.expect(pick({ words = { "f.o" } })).toEqual({}) -- plain, not a pattern
		t.expect(pick({ words = { "[" } })).toEqual({})
		t.expect(pick({ skills = { "review" }, when = "build", tags = { "wiring" } }))
			.toEqual({ "review/text" })
	end)

	it("sorts by sources (from counts one), then id; index lines and (none)", function()
		-- pin-inputs 2; review/text 1 (from); ticket-prep/lifetimes 1; architecture/zeta 0
		t.expect(pick({}))
			.toEqual({ "testing/pin-inputs", "review/text", "ticket-prep/lifetimes", "architecture/zeta" })
		local text = lessons.index(lessons.select(ALL, SOURCES, {}), SOURCES)
		t.expect(text).toBe(
			"- testing/pin-inputs (build, 2 sources): Are the call site's inputs pinned?\n"
				.. "- review/text (both, 1 source): Is the text consistent?\n"
				.. "- ticket-prep/lifetimes (design, 1 source): Which process outlives which?\n"
				.. "- architecture/zeta (both, 0 sources): Is it pure?\n"
		)
		t.expect(lessons.index({}, SOURCES)).toBe("(none)\n")
	end)

	it("a word that equals a lesson id selects exactly that lesson", function()
		local all = {
			lesson("testing/pin", "build", "wiring", "Pinned?", "Pin it."),
			lesson(
				"testing/pin-inputs",
				"build",
				"wiring",
				"Inputs pinned?",
				"Unlike testing/pin, the inputs."
			),
		}
		t.expect(ids(lessons.select(all, {}, { words = { "testing/pin" } }))).toEqual({ "testing/pin" })
		t.expect(ids(lessons.select(all, {}, { words = { "pin" } })))
			.toEqual({ "testing/pin", "testing/pin-inputs" })
		t.expect(ids(lessons.select(all, {}, { words = { "testing/pin-input" } })))
			.toEqual({ "testing/pin-inputs" })
	end)
end)
