--!strict
-- c0111 AC9: metrics over lessons. `lessons.tagCounts` counts harvested review findings per lesson tag, and
-- `lessons.roundsSplit` splits design review rounds at the commit that added scripts/tracker/lessons.luau.
-- `tracker.sh metrics` prints both tables, read in a tracker fixture under .cache/lessons-metrics
-- (tests/lib/trackerfix). It only reads.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local lessons = require("@scripts/tracker/lessons")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function lesson(id: string, tags: { string }): lessons.Lesson
	local skill, slug = string.match(id, "^([^/]+)/(.+)$")
	return {
		id = id,
		skill = skill :: string,
		slug = slug :: string,
		title = "x",
		when = "design",
		tags = tags,
		check = "x?",
		from = nil,
		body = "x",
	}
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function skillDoc(name: string): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n`
end

local function review(...: string): string
	local out = "# Review 001\n\n"
	for _, f in { ... } do
		out ..= `### {f} [low] claim\nEvidence: x\n\n`
	end
	return out .. "Verdict: changes\n"
end

return t.spec("c0111 metrics over lessons", function(it)
	it("counts a harvested finding once per tag, ignoring notes, one-offs and unknown lessons", function()
		local all = { lesson("testing/l1", { "a", "b" }), lesson("testing/l2", { "b" }) }
		local items: { lessons.Item } = {
			{
				id = "R0010",
				reviews = {},
				harvest = "# Harvest: R0010\n"
					.. "- design-review-001 F1: testing/l1, testing/l2\n"
					.. "- design-review-001 F2: testing/l2\n"
					.. "- design-review-001 F3: one-off: a typo\n"
					.. "- design-review-001 F4: testing/gone\n"
					.. "- note a user correction: testing/l1\n",
			},
			{ id = "R0020", reviews = {}, harvest = "# Harvest: R0020\n- review-001 F1: testing/l1\n" },
		}
		t.expect(lessons.tagCounts(all, items)).toEqual({
			{ tag = "b", findings = 3, items = 2 },
			{ tag = "a", findings = 2, items = 2 },
		})
		t.expect(lessons.tagCounts(all, {})).toEqual({})
	end)

	it(
		"splits design rounds at the cutoff, at-or-after is after, and an undated raft counts nowhere",
		function()
			local rafts: { lessons.RaftRounds } = {
				{ id = "R0010", rounds = 3, start = 100 },
				{ id = "R0020", rounds = 1, start = 200 },
				{ id = "R0030", rounds = 2, start = nil },
				{ id = "R0040", rounds = 2, start = 150 },
			}
			t.expect(lessons.roundsSplit(rafts, 150)).toEqual({
				before = { rafts = 1, rounds = 3, mean = 3 },
				after = { rafts = 2, rounds = 3, mean = 1.5 },
			})
			t.expect(lessons.roundsSplit(rafts, nil)).toEqual({
				before = { rafts = 3, rounds = 6, mean = 2 },
				after = { rafts = 0, rounds = 0, mean = 0 },
			})
		end
	)

	it("dates a YYYY-MM-DD day as days since 1970-01-01 (UTC), and refuses anything else", function()
		t.expect(lessons.day("1970-01-01")).toBe(0)
		t.expect(lessons.day("2026-10-20")).toBe(20746)
		t.expect(lessons.day("2000-03-01")).toBe(11017)
		t.expect(lessons.day("2026-1-2")).toBe(nil)
		t.expect(lessons.day("2026-13-01")).toBe(nil)
	end)

	it(
		"tracker.sh metrics prints the tag table, and dates rafts by their created day, not their history",
		function()
			local function raft(id: string, created: string): string
				return (
					string.gsub(
						trackerfix.stub(id, id, "new-a-b-c"),
						"created: [%d%-]+",
						"created: " .. created
					)
				)
			end
			local f = trackerfix.new("lessons-metrics", {
				[".claude/skills/testing/SKILL.md"] = skillDoc("testing"),
				[".claude/skills/testing/lessons/pin.md"] = "---\ntitle: Pin\nwhen: build\ntags: [wiring, seams]\n"
					.. "check: Pinned?\n---\nPin them.\n",
				["tracker/rafts/R0010/design-review-001.md"] = review("F1", "F2"),
				["tracker/rafts/R0010/design-review-002.md"] = review("F1"),
				["tracker/rafts/R0010/harvest.md"] = "# Harvest: R0010\n- design-review-001 F1: testing/pin\n"
					.. "- design-review-001 F2: one-off: x\n- design-review-002 F1: testing/pin\n",
				["tracker/rafts/R0020/design-review-001.md"] = review("F1") .. "R0020 round 1\n",
				["tracker/rafts/R0010/R0010.md"] = raft("R0010", "2030-06-01"),
				["tracker/rafts/R0020/R0020.md"] = raft("R0020", "2099-01-01"),
				-- created long before lessons existed, but every one of its commits is made today
				["tracker/rafts/R0030/R0030.md"] = raft("R0030", "2030-05-31"),
				["tracker/rafts/R0030/design-review-001.md"] = review("F1") .. "R0030 round 1\n",
				["tracker/rafts/R0030/design-review-002.md"] = review("F1") .. "R0030 round 2\n",
			})
			-- a compaction-like commit rewrites R0020's review in place: a dater that reads history would lose it
			fs.writeFile(`{f.main}/tracker/compaction.txt`, "# tracker.sh compact, test\nR0200 R0020\n")
			fs.writeFile(
				`{f.main}/tracker/rafts/R0020/design-review-001.md`,
				review("F1") .. "R0020 round 1, compacted\n"
			)
			-- lessons.luau is added on 2030-06-01, not with the seed: rafts created 2030-05-31 are before, 2030-06-01 after
			local function at(d: string): fixture.Options
				return { env = { GIT_COMMITTER_DATE = d, GIT_AUTHOR_DATE = d }, stdin = nil }
			end
			fixture.git(f.main, { "rm", "-q", "--cached", "scripts/tracker/lessons.luau" })
			fixture.git(f.main, { "commit", "-q", "--amend", "--no-edit" }, at("2020-01-01T00:00:00Z"))
			fixture.git(f.main, { "add", "scripts/tracker/lessons.luau" })
			fixture.git(f.main, { "commit", "-q", "-m", "lessons" }, at("2030-06-01T12:00:00Z"))
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-q", "-m", "tracker: compact ids" })
			local r = trackerfix.tr(f, f.main, { "metrics" })
			t.expect(r.code).toBe(0)
			t.expect(has(r.stdout, "| tag | findings | items |")).toBe(true)
			t.expect(has(r.stdout, "| seams | 2 | 1 |")).toBe(true)
			t.expect(has(r.stdout, "| wiring | 2 | 1 |")).toBe(true)
			t.expect(has(r.stdout, "| before | 1 | 2 | 2.0 |")).toBe(true)
			t.expect(has(r.stdout, "| after | 2 | 3 | 1.5 |")).toBe(true)
		end
	)

	it("the metrics skill names the two tables", function()
		local doc = fs.readFile(".claude/skills/metrics/SKILL.md")
		t.expect(has(doc, '"Findings per lesson tag"')).toBe(true)
		t.expect(has(doc, '"Design rounds before and after lessons"')).toBe(true)
	end)
end)
