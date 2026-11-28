--!strict
-- c0458 AC1-AC4 (pure): the round caps, the review modes, the activities and the final-review table. Texts in, results out.
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local rounds = require("@znile/engine/rounds")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(list: { string }, name: string): boolean
	return table.find(list, name) ~= nil
end

return t.spec("c0458: collapsed reviews and tightened caps", function(it)
	it(
		"AC1: the default caps are idea 1, design and code 1/2/3, and no [rounds] table is added to the root file",
		function()
			t.expect(rounds.DEFAULT.idea).toBe(1)
			for _, level in { "easy", "normal", "risky" } do
				local want = if level == "easy" then 1 elseif level == "normal" then 2 else 3
				t.expect(rounds.max(rounds.DEFAULT, "design", level)).toBe(want)
				t.expect(rounds.max(rounds.DEFAULT, "code", level)).toBe(want)
			end
			local text = fs.readFile(`{TOP}/.models.toml`)
			t.expect((string.find(text, "[rounds", 1, true))).toBe(nil)
		end
	)

	it("AC2: only design, raft and final are review modes; code and stream are refused", function()
		t.expect(dispatch.REVIEW_MODES.code).toBe(nil)
		t.expect(dispatch.REVIEW_MODES.stream).toBe(nil)
		for _, mode in { "design", "raft", "final" } do
			t.expect(dispatch.REVIEW_MODES[mode] ~= nil).toBe(true)
		end
		for _, mode in { "code", "stream" } do
			local ok = pcall(dispatch.lessonsOf, "zz-review", mode)
			t.expect(ok).toBe(false)
			t.expect(models.activityFor("zz-review", mode)).toBe(nil)
			t.expect(models.roleFor("zz-review", mode)).toBe(nil)
		end
		t.expect(models.activityFor("zz-review", "final")).toBe("final-review")
		t.expect(models.activityFor("zz-review", "design")).toBe("design-review")
		t.expect(models.activityFor("zz-review", "raft")).toBe("raft-review")
	end)

	it(
		"AC3: code-review and code-answer are no activity; final-answer still is the writer's; the spend phase stays",
		function()
			t.expect(has(models.ACTIVITIES, "code-review")).toBe(false)
			t.expect(models.isActivity("code-review")).toBe(false)
			t.expect(models.isActivity("code-answer")).toBe(false)
			t.expect(models.isActivity("final-answer")).toBe(true)
			t.expect(models.isActivity("final-review")).toBe(true)
			for _, pair in models.PAIRS do
				t.expect(pair[2] ~= "code-review").toBe(true)
			end
			t.expect(has(ledger.PHASES, "code-review")).toBe(true)
			local text = fs.readFile(`{TOP}/.models.toml`)
			t.expect((string.find(text, "[activities.code-review]", 1, true))).toBe(nil)
			t.expect((string.find(text, "[roles.code-review]", 1, true))).toBe(nil)
		end
	)

	it("AC4: final-review is set per level: easy light, normal heavy, risky ultra", function()
		local layer = models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml")
		local a = layer.activities["final-review"]
		t.expect(a.easy.alias).toBe("light")
		t.expect(a.normal.alias).toBe("heavy")
		t.expect(a.risky.alias).toBe("ultra")
		t.expect(a.all).toBe(nil)
		-- the raft's level is its highest member's, and that level picks heavy and the cap of 2
		local level = rounds.forMembers({ "easy", "normal", "normal" }, 0)
		t.expect(level).toBe("normal")
		t.expect(a[level :: string].alias).toBe("heavy")
		t.expect(rounds.max(rounds.DEFAULT, "code", level :: string)).toBe(2)
		t.expect((rounds.forMembers({ "easy", "risky", "normal" }, 0))).toBe("risky")
		t.expect((rounds.forMembers({ "easy", "easy" }, 1))).toBe("normal") -- an unreadable member is at least normal
		-- work.activityOf reads that level for the final review of a raft whose first member is easy
		local decision: work.Decision =
			{ raft = "R0305", layer = "", ticket = "", action = "final-review", why = "" }
		local rf: any = {
			id = "R0305",
			title = "R0305",
			where = "active",
			status = "active",
			designReady = true,
			depsMet = true,
			questions = false,
			issues = { "c0010", "c0011" },
			layers = {},
			holder = "",
			since = "",
			stacked = true,
			finalReview = "none",
			trace = true,
			traceOk = false,
			root = "z-nile/.tracker",
			level = "risky",
		}
		local function member(id: string, risk: string): work.IssueFact
			return {
				id = id,
				root = "z-nile/.tracker",
				status = "active",
				raft = "R0305",
				designReady = true,
				sized = true,
				deps = {},
				draftBlock = "",
				level = risk,
			} :: any
		end
		local issues = { member("c0010", "easy"), member("c0011", "normal") }
		local _, _, got = work.activityOf({ rafts = { rf :: work.RaftFact }, issues = issues }, decision)
		t.expect(got).toBe("risky") -- the raft's level (its highest member), not the default, the first member (easy) or the second (normal)
	end)
end)
