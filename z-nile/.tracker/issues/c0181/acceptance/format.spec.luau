--!strict
-- c0181 AC1: a lesson file may carry its codification state: `enforced_by` (checks) with `enforced` (full or part),
-- or `not_codifiable` (the reason), plus `distinct_from` and `merged` (lesson ids). A lesson with none of them
-- parses as it does today (the policy, not the format, makes the state mandatory). Pure over texts.
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")

local function lesson(extra: string): string
	return "---\ntitle: A lesson\nwhen: both\ntags: [wiring]\ncheck: Is it pinned?\n"
		.. extra
		.. "---\nThe rule.\n"
end

local function problem(extra: string): string
	local l, err = lessons.parse("zz-test/a-lesson", lesson(extra))
	if l or not err then
		error(`expected a problem for {extra}`, 2)
	end
	return err
end

return t.spec("c0181 lesson codification keys", function(it)
	it("reads enforced_by (two checks, one with a case), enforced, distinct_from and merged", function()
		local l, err = lessons.parse(
			"zz-test/a-lesson",
			lesson(
				'enforced_by: z-nile/lints/plain-find.luau, z-nile/tests/meta/x.spec.luau :: "the case, with a comma"\n'
					.. "enforced: part\ndistinct_from: zz-test/other, zz-arch/third\nmerged: zz-test/old-one\n"
			)
		)
		t.expect(err).toBe(nil)
		local got = l :: any
		t.expect(got.enforcedBy)
			.toEqual({ "z-nile/lints/plain-find.luau", 'z-nile/tests/meta/x.spec.luau :: "the case, with a comma"' })
		t.expect(got.enforced).toBe("part")
		t.expect(got.distinct).toEqual({ "zz-test/other", "zz-arch/third" })
		t.expect(got.merged).toEqual({ "zz-test/old-one" })
		t.expect(got.notCodifiable).toBe(nil)
	end)

	it("reads not_codifiable as one line of text", function()
		local l = lessons.parse(
			"zz-test/a-lesson",
			lesson("not_codifiable: needs a human to judge the design's intent\n")
		)
		t.expect((l :: any).notCodifiable).toBe("needs a human to judge the design's intent")
		t.expect((l :: any).enforced).toBe(nil)
	end)

	it("a lesson with none of the keys parses as before, with empty lists", function()
		local l, err = lessons.parse("zz-test/a-lesson", lesson(""))
		t.expect(err).toBe(nil)
		t.expect((l :: any).enforcedBy).toEqual({})
		t.expect((l :: any).distinct).toEqual({})
		t.expect((l :: any).merged).toEqual({})
		t.expect((l :: any).enforced).toBe(nil)
		t.expect((l :: any).notCodifiable).toBe(nil)
	end)

	it(
		"refuses a bad enforced value, a repeated key, an empty list item and an empty reason, naming the lesson",
		function()
			for _, bad in
				{
					"enforced_by: z-nile/lints/a.luau\nenforced: maybe\n",
					"enforced_by: z-nile/lints/a.luau\nenforced_by: z-nile/lints/b.luau\n",
					"enforced_by: z-nile/lints/a.luau,\n",
					'enforced_by: z-nile/tests/x.spec.luau :: "unterminated\n',
					"not_codifiable:\n",
					"distinct_from: zz-test/x,, zz-test/y\n",
					"merged: not an id\n",
				}
			do
				local err = problem(bad)
				t.expect(string.find(err, "zz-test/a-lesson", 1, true) ~= nil).toBe(true)
			end
		end
	)
end)
