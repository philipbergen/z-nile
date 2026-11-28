--!strict
-- c0458 AC5-AC7 (pure): no per-layer code review in the walk, no draft for an easy ticket with no design review, and
-- ready no longer refuses it. Facts in, one Decision out.
local dispatch = require("@znile/engine/dispatch")
local easy = require("@znile/engine/easy")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function raft(id: string, over: { [string]: any }?): work.RaftFact
	local r: any = {
		id = id,
		title = id,
		where = "active",
		status = "active",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010" },
		layers = {
			{
				position = 1,
				issue = "c0010",
				name = `{id}/1/c0010`,
				commits = 3,
				onlyStart = false,
				finished = true,
			},
		},
		holder = "",
		since = "",
		stacked = true,
		finalReview = "none",
		trace = true,
		traceOk = false,
		root = "z-nile/.tracker",
		codeMax = 2,
		finalMax = 2,
	}
	for k, v in (over or {}) :: { [string]: any } do
		r[k] = v
	end
	return r :: work.RaftFact
end

return t.spec("c0458: the walk and ready after the code review is gone", function(it)
	it(
		"AC5: every built raft goes from restack to trace to the final review, light or not, with the code states ignored",
		function()
			for _, light in { true, false } do
				local d =
					work.forRaft(raft("R0300", { light = light, lightWhy = "its risk is normal, not easy" }))
				t.expect(d.action).toBe("final-review")
				t.expect(has(d.why, "Run code review round")).toBe(false)
			end
			-- a raft in flight with an unanswered old review-001.md is not held by it
			for _, state in { "open", "due", "malformed", "rule" } do
				local d = work.forRaft(raft("R0301", { light = false, codeReview = state, codeRound = 1 }))
				t.expect(d.action).toBe("final-review")
			end
			t.expect(work.forRaft(raft("R0302", { trace = false })).action).toBe("trace")
			t.expect(work.forRaft(raft("R0303", { stacked = false })).action).toBe("restack")
		end
	)

	it(
		"AC6: the final brief of a raft of three tickets, light or not, names every Code check and the design judgement",
		function()
			local NAMES = {
				"Correctness",
				"Sequestration",
				"Weak tests",
				"Design adherence",
				"Architecture rules",
				"Performance",
				"Judged criteria",
				"Repository safety",
				"Everything in the first round",
				"Lessons",
				"ruling line",
				"Bounded commands",
				"Overrides",
			}
			local function judge(text: string)
				for _, name in NAMES do
					t.expect(has(text, name)).toBe(true)
				end
				t.expect(has(text, "git diff origin/main...HEAD")).toBe(true)
				t.expect(has(text, "design-review")).toBe(true) -- the design judgement of a ticket with no passing review
				t.expect(has(text, "Level:")).toBe(true)
				t.expect(has(text, "took the light path")).toBe(false)
				t.expect(has(text, "ONLY review")).toBe(false)
			end
			for _, light in { true, false } do
				local layers = {}
				for n, id in { "c0010", "c0011", "c0012" } do
					table.insert(layers, {
						position = n,
						issue = id,
						name = `R0304/{n}/{id}`,
						commits = 2,
						onlyStart = false,
						finished = true,
					})
				end
				local r =
					raft("R0304", { light = light, issues = { "c0010", "c0011", "c0012" }, layers = layers })
				judge(work.forRaft(r).why)
			end
			t.expect(type((work :: any).finalBrief)).toBe("function")
			judge((work :: any).finalBrief("R0304"))
			-- the dispatched prompt carries it for a raft that is not light
			local prompt = dispatch.prompt({
				step = "zz-review",
				id = "R0304",
				mode = "final",
				skillPath = "z-nile/skills/zz-review/SKILL.md",
				worktree = "/w/.worktree/R0304",
				stateDir = "/w/.cache/dispatch/R0304",
				light = false,
			})
			judge(prompt)
		end
	)

	it(
		"AC7: an easy ticket off the light path with no design review is not drafted and ready does not refuse it",
		function()
			local base: work.IssueFact = {
				id = "c0001",
				root = "z-nile/.tracker",
				status = "prepared",
				raft = "",
				designReady = true,
				sized = true,
				deps = {},
				draftBlock = "",
				level = "easy",
				light = false,
				lightWhy = "a dependency has not landed",
				designReviewed = false,
			}
			local sized = work.decide({ rafts = {}, issues = { base }, session = "s" })
			t.expect(sized.action).toBe("rafting")
			local unsized = table.clone(base)
			unsized.sized = false
			t.expect(work.decide({ rafts = {}, issues = { unsized }, session = "s" }).action).toBe("fix")

			local doc = "---\nid: c0001\nrisk: easy\n---\n\n## Problem\nP\n"
			local member: readycheck.Member = {
				id = "c0001",
				design = "ready",
				doc = doc,
				deps = {},
				files = { ["c0001.md"] = doc, ["check.sh"] = 'check "AC1: holds" true\n' },
				specs = {},
				approval = nil,
				approvalFile = "z-nile/.tracker/issues/c0001/approval.md",
			}
			local r: readycheck.Raft = {
				id = "R0001",
				where = "backlog",
				status = "prepared",
				dir = "z-nile/.tracker/rafts/R0001",
				design = "ready",
				doc = "---\ndesign: ready\n---\n",
				grouped = nil,
				questions = false,
				listed = { "c0001" },
				members = { member },
				files = { ["check.sh"] = 'check "RC0: ok" true\n' },
				loaded = true,
				light = nil,
			}
			t.expect((readycheck.reason(r))).toBe(nil)
			-- control: the same raft with one rule broken (a bad Level line in a review) still refuses
			local broken = table.clone(member)
			broken.files = table.clone(member.files)
			broken.files["design-review-001.md"] = "Verdict: approve\nLevel: nonsense\n"
			local r2 = table.clone(r)
			r2.members = { broken }
			t.expect((readycheck.reason(r2)) ~= nil).toBe(true)
		end
	)

	it(
		"AC9: a raise in a raft of several tickets that is not light stops the walk at release, naming each raised ticket; a bad Level line stops it",
		function()
			local layers = {}
			for n, id in { "c0010", "c0011", "c0012" } do
				table.insert(layers, {
					position = n,
					issue = id,
					name = `R0306/{n}/{id}`,
					commits = 2,
					onlyStart = false,
					finished = true,
				})
			end
			local base = {
				light = false,
				issues = { "c0010", "c0011", "c0012" },
				layers = layers,
				finalReview = "open",
				finalRound = 1,
			}
			local over = table.clone(base);
			(over :: any).raised = { c0011 = "risky", c0012 = "normal" }
			local d = work.forRaft(raft("R0306", over))
			t.expect(d.action).toBe("release")
			t.expect(has(d.why, "c0011")).toBe(true)
			t.expect(has(d.why, "risky")).toBe(true)
			t.expect(has(d.why, "c0012")).toBe(true)
			t.expect(has(d.why, "c0010")).toBe(false)
			local bad = table.clone(base);
			(bad :: any).levelProblem =
				'a review has the line "Level: nonsense": a Level line holds easy, normal or risky'
			local b = work.forRaft(raft("R0306", bad))
			t.expect(b.action).toBe("none")
			t.expect(has(b.why, "fix the review's Level line")).toBe(true)
			-- after stop empties the raft, its unraised members are prepared with no raft: the walk rafts them again
			local again = work.decide({
				rafts = {},
				issues = {
					{
						id = "c0010",
						root = "z-nile/.tracker",
						status = "prepared",
						raft = "",
						designReady = true,
						sized = true,
						deps = {},
						draftBlock = "",
					},
					{
						id = "c0012",
						root = "z-nile/.tracker",
						status = "prepared",
						raft = "",
						designReady = true,
						sized = true,
						deps = {},
						draftBlock = "",
					},
				} :: { work.IssueFact },
				session = "s",
			})
			t.expect(again.action).toBe("rafting")
		end
	)

	it(
		"AC8: a final review raises tickets by name in a raft of several; above the ticket's level, or at it only for a ticket on a short note; a bare Level line needs one ticket",
		function()
			t.expect(type((easy :: any).raisedBy)).toBe("function")
			local raisedBy = (easy :: any).raisedBy
			local levels = { c0010 = "easy", c0011 = "normal", c0012 = "normal" }
			local none: { [string]: boolean } = {}
			local by, problem =
				raisedBy({ "Verdict: changes\nLevel: c0011 risky\nLevel: c0010 normal\n" }, levels, none)
			t.expect(problem).toBe(nil)
			t.expect(by).toEqual({ c0010 = "normal", c0011 = "risky" })
			-- at the ticket's own level: nothing for a ticket with a full design, a raise for one on a short note
			t.expect((raisedBy({ "Level: c0011 normal\nLevel: c0012 easy\n" }, levels, none))).toEqual({})
			t.expect((raisedBy({ "Level: c0011 normal\n" }, levels, { c0011 = true })))
				.toEqual({ c0011 = "normal" })
			-- below it: never, short note or not (a ticket at risky given a normal line); and the highest line wins per ticket
			local high = { c0010 = "easy", c0011 = "risky", c0012 = "normal" }
			t.expect((raisedBy({ "Level: c0011 normal\n" }, high, { c0011 = true }))).toEqual({})
			t.expect((raisedBy({ "Level: c0011 normal\n" }, high, none))).toEqual({})
			t.expect((raisedBy({ "Level: c0010 risky\n", "Level: c0010 normal\n" }, high, none)))
				.toEqual({ c0010 = "risky" })
			t.expect((raisedBy({ "Level: c0010 normal\n", "Level: c0010 risky\n" }, high, none)))
				.toEqual({ c0010 = "risky" })
			t.expect((raisedBy({ "Level: c0011 easy\n" }, levels, { c0011 = true }))).toEqual({})
			local one = raisedBy({ "Level: normal\n" }, { c0010 = "easy" }, none)
			t.expect(one).toEqual({ c0010 = "normal" })
			t.expect((raisedBy({ "Level: normal\n" }, { c0010 = "normal" }, none))).toEqual({})
			t.expect((raisedBy({ "Level: normal\n" }, { c0010 = "normal" }, { c0010 = true })))
				.toEqual({ c0010 = "normal" })
			local _, bare = raisedBy({ "Level: normal\n" }, levels, none)
			t.expect(bare ~= nil).toBe(true)
			local _, unknown = raisedBy({ "Level: c0099 risky\n" }, levels, none)
			t.expect(unknown ~= nil).toBe(true)
			t.expect((raisedBy({ "Level: easy\n" }, { c0010 = "easy" }, none))).toEqual({})
		end
	)
end)
