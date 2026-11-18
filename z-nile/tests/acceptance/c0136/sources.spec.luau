--!strict
-- c0136 AC4: `lessons.unattributed` lists the entries that name no step, and stream and focused reviews are harvest
-- sources like a design or code round (stems, `uncovered`, `sources`, `check`) without being an item's document.
-- Pure over texts: nothing is read or written.
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local function lesson(when: string?): string
	return `---\ntitle: T\nwhen: {when or "both"}\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nBody.\n`
end

-- a review: each finding is `### F<n> [low] claim`, then the given extra lines
local function review(findings: { { id: string, lines: { string }? } }): string
	local out = "# Review 001: R0010 (design mode)\nInputs: abc\n\n"
	for _, f in findings do
		out ..= `### {f.id} [medium] a claim\nWhere: x\nEvidence: Erred: is quoted here, not a field\n`
		local extra: { string } = f.lines or {}
		for _, line in extra do
			out ..= line .. "\n"
		end
		out ..= "\n"
	end
	return out .. "Verdict: changes\n"
end

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local function tree(items: { lessons.Item }): lessons.Tree
	return {
		lessons = {
			["z-design/a"] = lesson(),
			["z-ticket/b"] = lesson(),
			["zz-test/c"] = lesson(),
			["z-design/design-only"] = lesson("design"),
			["zz-execute/build-only"] = lesson("build"),
			["z-raft/build-only"] = lesson("build"),
		},
		found = {},
		skills = {
			["z-design"] = true,
			["z-ticket"] = true,
			["z-raft"] = true,
			["zz-test"] = true,
			["zz-execute"] = true,
		},
		items = items,
		problems = {},
	}
end

return t.spec("c0136 every review kind is a harvest source", function(it)
	it(
		"unattributed lists the entries and notes that name no step, in file order, and not uncovered findings",
		function()
			-- R0020 comes first in the list and has an unattributed entry; R0010's lines are not in sorted order
			local items: { lessons.Item } = {
				{
					id = "R0020",
					reviews = { ["review-001"] = review({ { id = "F1" } }) },
					harvest = "- review-001 F1: zz-test/c\n",
				},
				{
					id = "R0010",
					reviews = {
						["design-review-001"] = review({
							{ id = "F1" },
							{ id = "F2" },
							{ id = "F3" },
							{ id = "F4" },
						}),
					},
					harvest = "- design-review-001 F3: z-design/a\n- note user said so: z-ticket/b\n"
						.. "- design-review-001 F2: z-design/a\n- design-review-001 F1 (erred z-design): z-design/a\n",
				},
			}
			t.expect(lessons.unattributed(items)).toEqual({
				"R0010 design-review-001 F3",
				"R0010 note user said so",
				"R0010 design-review-001 F2",
				"R0020 review-001 F1",
			})
			-- F4 has no entry at all: that is uncovered's list, not this one
			t.expect(lessons.uncovered(items)).toEqual({ "R0010 design-review-001 F4" })
			t.expect(lessons.unattributed({})).toEqual({})
		end
	)

	it("a stream review and a focused review are harvest sources like any other round", function()
		local items: { lessons.Item } = {
			{
				id = "R0010",
				reviews = {
					["review-001"] = review({ { id = "F1" } }),
					["stream-review-c0010-001"] = review({ { id = "F1" }, { id = "F2" } }),
					["focused-review-001"] = review({ { id = "F1" } }),
				},
				harvest = "- stream-review-c0010-001 F1 (erred zz-execute): zz-test/c\n",
			},
		}
		t.expect(lessons.uncovered(items)).toEqual({
			"R0010 focused-review-001 F1",
			"R0010 review-001 F1",
			"R0010 stream-review-c0010-001 F2",
		})
		local s = lessons.sources(items)
		t.expect(s["zz-test/c"]).toEqual({ "R0010 stream-review-c0010-001 F1" })
		local _, bad = lessons.parseHarvest(
			"R0010",
			"- stream-review-x-001 F1: zz-test/c\n- stream-review-c0010-1 F1: zz-test/c\n- focused-review-1 F1: zz-test/c\n"
		)
		t.expect(#bad).toBe(3)
		-- an entry for a review file that is not there is named, as for any other stem
		local gone = lessons.check(tree({
			{
				id = "R0010",
				reviews = {},
				harvest = "- focused-review-001 F1 (erred z-design): z-design/a\n",
			},
		}))
		t.expect(has(gone, "no focused-review-001.md in R0010")).toBe(true)
	end)

	it("a focused review is not an item's document", function()
		for _, name in { "focused-review-001.md", "focused-review-012.md", "stream-review-c0010-001.md" } do
			t.expect(trail.isDoc(name)).toBe(false)
		end
		t.expect(trail.isDoc("c0010.md")).toBe(true)
	end)
end)
