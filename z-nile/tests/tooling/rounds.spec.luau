--!strict
-- f0421 slice 1: the round rule (rounds.luau), the one definition of "answered" (openlist.unanswered) and the
-- [rounds] limits of .models.toml (models.parse, models.rounds). Pure: texts in, results out.
local dispatch = require("@znile/engine/dispatch")
local models = require("@znile/engine/models")
local openlist = require("@znile/engine/openlist")
local rounds = require("@znile/engine/rounds")
local t = require("@tests/lib/t")

local function rejects(text: string, want: string)
	local ok, err = pcall(function()
		models.parse(text, ".models.toml")
	end)
	t.expect(ok).toBe(false)
	t.expect(string.find(tostring(err), want, 1, true) ~= nil).toBe(true)
end

local function round(
	n: number,
	verdict: string?,
	responded: boolean,
	answered: boolean,
	serious: boolean,
	malformed: string?
): rounds.Round
	return {
		number = n,
		file = `review-{string.format("%03d", n)}.md`,
		verdict = verdict,
		responded = responded,
		answered = answered,
		serious = serious,
		seriousCount = if serious then 1 else 0,
		malformed = malformed,
	}
end

local NO = function(_: string): boolean
	return false
end

return t.spec("f0421: rounds, answered and [rounds] limits", function(it)
	it("AC1: [rounds] parses, and a closer file replaces only the leaves it sets", function()
		local root =
			models.parse("[rounds]\nidea = 4\ndesign = { easy = 3, normal = 6 }\ncode = { risky = 7 }\n", "a")
		local near = models.parse("[rounds]\ndesign = { normal = 8 }\n", "b")
		local got = models.rounds({ root, near })
		t.expect(got.idea).toBe(4)
		t.expect(got.design.easy).toBe(3)
		t.expect(got.design.normal).toBe(8)
		t.expect(got.design.risky).toBe(9)
		t.expect(got.code.risky).toBe(7)
		t.expect(got.code.normal).toBe(5)
	end)

	it("AC2: no [rounds] gives the defaults, and the root .models.toml names no [rounds]", function()
		local got = models.rounds({})
		t.expect(got.idea).toBe(3)
		for _, stage in { "design", "code" } do
			local tbl = (got :: any)[stage] :: { [string]: number }
			t.expect(tbl.easy).toBe(2)
			t.expect(tbl.normal).toBe(5)
			t.expect(tbl.risky).toBe(9)
		end
		t.expect(got).toEqual(rounds.DEFAULT)
		local fs = require("@lune/fs")
		local process = require("@lune/process")
		local top = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
		local layer = models.parse(fs.readFile(`{top}/.models.toml`), ".models.toml")
		t.expect(layer.rounds == nil).toBe(true) -- an older worktree's engine rejects an unknown table: none on main
	end)

	it("AC3: a bad [rounds] is refused naming the file and the key", function()
		rejects("rounds = 3\n", ".models.toml: [rounds] is a table")
		rejects("[rounds]\nfoo = 1\n", ".models.toml: rounds.foo is not a setting (idea, design, code)")
		rejects(
			"[rounds]\ndesign = 2\n",
			".models.toml: rounds.design is a table of levels (easy, normal, risky)"
		)
		rejects(
			"[rounds]\ndesign = { huge = 2 }\n",
			".models.toml: rounds.design.huge is not a level (easy, normal, risky)"
		)
		rejects("[rounds]\nidea = 0\n", ".models.toml: rounds.idea is a whole number, 1 to 99")
		rejects("[rounds]\nidea = 1.5\n", "rounds.idea is a whole number, 1 to 99")
		rejects("[rounds]\nidea = 100\n", "rounds.idea is a whole number, 1 to 99")
		rejects("[rounds]\nidea = inf\n", "rounds.idea is a whole number, 1 to 99")
		rejects("[rounds]\nidea = nan\n", "rounds.idea is a whole number, 1 to 99")
		rejects("[rounds]\ncode = { easy = 0 }\n", "rounds.code.easy is a whole number, 1 to 99")
		rejects(
			"[nope]\nx = 1\n",
			"the file has catalog, clis, activities, roles, fallback, dispatch and rounds; skill tables are gone"
		)
	end)

	it("AC4: level and highest", function()
		t.expect((rounds.level(nil))).toBe("normal")
		t.expect((rounds.level(""))).toBe("normal")
		for _, v in { "easy", "normal", "risky" } do
			t.expect((rounds.level(v))).toBe(v)
		end
		local lvl, problem = rounds.level("high")
		t.expect(lvl == nil).toBe(true)
		t.expect(problem).toBe("risk is high: easy, normal or risky")
		t.expect(rounds.highest({})).toBe("normal")
		t.expect(rounds.highest({ "easy", "risky", "normal" })).toBe("risky")
		t.expect(rounds.highest({ "easy", "normal" })).toBe("normal")
		t.expect(rounds.highest({ "easy" })).toBe("easy")
		t.expect(rounds.max(rounds.DEFAULT, "idea", "risky")).toBe(3)
		t.expect(rounds.max(rounds.DEFAULT, "code", "easy")).toBe(2)
		t.expect(rounds.max(rounds.DEFAULT, "design", "risky")).toBe(9)
	end)

	it("AC5: next follows every row of the table", function()
		local function step(k: string, n: number, max: number, extra: { [string]: any }?): rounds.Step
			local out: any = { kind = k, number = n, max = max }
			local more: { [string]: any } = extra or {}
			for key, v in more do
				out[key] = v
			end
			return out
		end
		t.expect(rounds.next(nil, 5)).toEqual(step("file", 1, 5))
		-- approve settles, whatever its answers
		t.expect(rounds.next(round(2, "approve", false, false, true), 5)).toEqual(step("settled", 2, 5))
		-- not approve and not responded waits for the author, even at the maximum
		t.expect(rounds.next(round(1, "changes", false, false, true), 5)).toEqual(step("answer", 1, 5))
		t.expect(rounds.next(round(5, nil, false, false, false), 5)).toEqual(step("answer", 5, 5))
		-- responded and serious below the maximum files the next round: no rulings are needed
		t.expect(rounds.next(round(1, "changes", true, false, true), 2)).toEqual(step("file", 2, 2))
		t.expect(rounds.next(round(4, nil, true, true, true), 5)).toEqual(step("file", 5, 5))
		-- responded with only low findings settles below the maximum once answered, and otherwise asks for the rule
		t.expect(rounds.next(round(1, "changes", true, true, false), 5)).toEqual(step("settled", 1, 5))
		local rule = rounds.next(round(1, "changes", true, false, false), 5)
		t.expect(rule.kind).toBe("rule")
		t.expect(
			string.find(
				rule.reason or "",
				"list what is refuted or still open under ## Open to the human",
				1,
				true
			) ~= nil
		).toBe(true)
		-- at the maximum: settled when answered (with the serious count), the rule otherwise
		t.expect(rounds.next(round(2, "changes", true, true, true), 2))
			.toEqual(step("settled", 2, 2, { atMaximum = 1 }))
		t.expect(rounds.next(round(3, "changes", true, true, true), 2))
			.toEqual(step("settled", 3, 2, { atMaximum = 1 }))
		t.expect(rounds.next(round(2, "changes", true, false, true), 2).kind).toBe("rule")
		-- a malformed latest round is neither settled nor answered
		local bad = rounds.next(round(1, nil, true, true, false, "review-001.md has no Verdict line"), 5)
		t.expect(bad.kind).toBe("malformed")
		t.expect(bad.reason).toBe("review-001.md has no Verdict line")
	end)

	it("forMembers: an unreadable member never lowers the level below normal", function()
		t.expect((rounds.forMembers({ "easy" }, 0))).toBe("easy")
		t.expect((rounds.forMembers({ "easy" }, 1))).toBe("normal")
		t.expect((rounds.forMembers({ "easy", "risky" }, 1))).toBe("risky")
		t.expect((rounds.forMembers({}, 1))).toBe("normal")
		t.expect((rounds.forMembers({}, 0))).toBe("normal")
		local lvl, problem = rounds.forMembers({ "easy", "high" }, 0)
		t.expect(lvl == nil).toBe(true)
		t.expect(problem).toBe("risk is high: easy, normal or risky")
	end)

	it("verdict is the one Verdict reader", function()
		t.expect(rounds.verdict("x\nVerdict: approve\n")).toBe("approve")
		t.expect(rounds.verdict("x\nverdict: changes\n")).toBe("changes")
		t.expect(rounds.verdict("no verdict here") == nil).toBe(true)
	end)

	it("latest takes the highest round, its refute file, and reads severity through openlist", function()
		local r1 = "### F1 [low] a\n\nVerdict: changes\n"
		local r2 = "### F1 [medium] b\n\nVerdict: changes\n"
		local files = {
			["review-001.md"] = r1,
			["review-002.md"] = r2,
			["refute-001.md"] = "- F1: fixed a; consequences: none\n",
			["final-review-009.md"] = "Verdict: approve\n",
			["review-003.md.bak"] = "Verdict: approve\n",
		}
		local got = rounds.latest(files, "code", "# doc\n", NO)
		t.expect(got ~= nil).toBe(true)
		local g = got :: rounds.Round
		t.expect(g.number).toBe(2)
		t.expect(g.verdict).toBe("changes")
		t.expect(g.responded).toBe(false)
		t.expect(g.answered).toBe(false)
		t.expect(g.serious).toBe(true)
		t.expect(g.malformed == nil).toBe(true)
		files["refute-002.md"] = "- F1: fixed b; consequences: none\n"
		t.expect((rounds.latest(files, "code", "# doc\n", NO) :: rounds.Round).answered).toBe(true)
		t.expect((rounds.latest(files, "code", "# doc\n", NO) :: rounds.Round).responded).toBe(true)
		local f = rounds.latest(files, "final", "# doc\n", NO) :: rounds.Round
		t.expect(f.number).toBe(9)
		t.expect(f.verdict).toBe("approve")
		t.expect(rounds.latest({}, "design", "", NO) == nil).toBe(true)
		-- only low findings: not serious
		local low =
			rounds.latest({ ["design-review-001.md"] = "### F1 [low] a\n" }, "design", "", NO) :: rounds.Round
		t.expect(low.serious).toBe(false)
		-- a finding with no severity tag is unknown, so it is serious
		local unrated = rounds.latest(
			{ ["design-review-001.md"] = "### F1 an untagged finding\n" },
			"design",
			"",
			NO
		) :: rounds.Round
		t.expect(unrated.serious).toBe(true)
		-- the prefix is plain: "review-" does not match "design-review-"
		t.expect(rounds.latest({ ["design-review-001.md"] = "x" }, "code", "", NO) == nil).toBe(true)
	end)

	it(
		"F3: a review with no verdict and no findings, or a changes verdict and no findings, is malformed",
		function()
			local function latest(text: string): rounds.Round
				return rounds.latest({ ["review-001.md"] = text }, "code", "", NO) :: rounds.Round
			end
			t.expect(latest("# Review\n\nnothing\n").malformed)
				.toBe("review-001.md has no Verdict line and no findings: fix the file or redo the round")
			t.expect(latest("# Review\n\nVerdict: changes\n").malformed)
				.toBe("review-001.md has a changes verdict and no findings: fix the file or redo the round")
			t.expect(latest("# Review\n\nVerdict: approve\n").malformed == nil).toBe(true)
			t.expect(latest("# Review\n\n### F1 [low] a\n\nVerdict: changes\n").malformed == nil).toBe(true)
			t.expect(latest("# Review\n\nJudged\n- JC1: fail\n\nVerdict: changes\n").malformed == nil)
				.toBe(true)
			-- done refuses a review that has no verdict and no findings, as it already refused a changes verdict with none
			local function done(text: string): string?
				return openlist.unanswered({
					review = text,
					refute = "",
					doc = "",
					reviewName = "review-001.md",
					refuteName = "refute-001.md",
					isBacklog = NO,
				})
			end
			t.expect(done("# Review\n\nnothing\n")).toBe("review-001.md has no Verdict line and no findings")
			t.expect(done("# Review\n\nVerdict: changes\n"))
				.toBe("review-001.md Verdict is changes, not approve")
		end
	)

	it("F4: a refuted finding needs its ruling only at the settling round", function()
		local review = "### F1 [low] a\n\nVerdict: changes\n"
		local refuted = { ["review-001.md"] = review, ["refute-001.md"] = "- F1: refuted: shown\n" }
		local got = rounds.latest(refuted, "code", "# doc\n", NO) :: rounds.Round
		t.expect(got.responded).toBe(true)
		t.expect(got.answered).toBe(false)
		t.expect(rounds.next(got, 5).kind).toBe("rule") -- low only: this round settles, so it needs its ruling
		-- the same refutation of a medium finding below the maximum files round 2 with no ruling at all
		local serious = {
			["review-001.md"] = "### F1 [medium] a\n\nVerdict: changes\n",
			["refute-001.md"] = "- F1: refuted: shown\n",
		}
		local again = rounds.latest(serious, "code", "# doc\n", NO) :: rounds.Round
		t.expect(again.responded).toBe(true)
		t.expect(rounds.next(again, 5)).toEqual({ kind = "file", number = 2, max = 5 })
		-- at the maximum it needs the ruling, qualified by its file after round 1
		local second = {
			["review-002.md"] = "### F1 [medium] a\n\nVerdict: changes\n",
			["refute-002.md"] = "- F1: refuted: shown\n",
		}
		t.expect(rounds.next(rounds.latest(second, "code", "# doc\n", NO), 2).kind).toBe("rule")
		local ruled =
			"## Open to the human\n- review-002 F1: a. Answer: shown. Decision: accept. Ruled (user, 2026-11-20): ok.\n"
		t.expect(rounds.next(rounds.latest(second, "code", ruled, NO), 2).kind).toBe("settled")
	end)

	it("F1: a ruling on an earlier round's F1 never answers a later round's F1", function()
		local function judge(doc: string, reviewName: string): string?
			return openlist.problem(
				"### F1 [medium] a\n\nVerdict: changes\n",
				"- F1: refuted: shown\n",
				doc,
				reviewName
			)
		end
		local round1 =
			"## Open to the human\n- F1: a. Answer: shown. Decision: accept. Ruled (user, 2026-11-20): ok.\n"
		-- round 1 (and today's unqualified bullets) keep their meaning
		t.expect(judge(round1, "review-001.md") == nil).toBe(true)
		t.expect(judge(round1, "final-review-001.md") == nil).toBe(true) -- today's behaviour: round 1 of any kind
		-- round 2 is not answered by round 1's bullet, qualified or not
		t.expect(judge(round1, "review-002.md")).toBe(
			"open to the human (review-002 F1): record each under ## Open to the human with Ruled (user, YYYY-MM-DD):"
		)
		local qualified = round1
			.. "- review-002 F1: b. Answer: shown. Decision: accept. Ruled (user, 2026-11-20): ok.\n"
		t.expect(judge(qualified, "review-002.md") == nil).toBe(true)
		-- a code review's qualified ruling does not answer a final review's finding of the same number
		t.expect(judge(qualified, "final-review-002.md")).toBe(
			"open to the human (final-review-002 F1): record each under ## Open to the human with Ruled (user, YYYY-MM-DD):"
		)
		-- an unruled qualified bullet is still waiting
		local waiting = "## Open to the human\n- review-002 F1: b. Answer: shown. Decision: accept.\n"
		t.expect(judge(waiting, "review-002.md") ~= nil).toBe(true)
		-- pending reads the qualified bullet as its own key
		t.expect(openlist.pending(waiting)).toEqual({ "review-002 F1" })
		-- and unanswered honours it too
		local function unanswered(doc: string, name: string): string?
			return openlist.unanswered({
				review = "### F1 [low] a\n\nVerdict: changes\n",
				refute = "- F1: refuted: shown\n",
				doc = doc,
				reviewName = name,
				refuteName = "refute-002.md",
				isBacklog = NO,
			})
		end
		t.expect(unanswered(round1, "review-002.md") ~= nil).toBe(true)
		t.expect(unanswered(qualified, "review-002.md") == nil).toBe(true)
	end)

	it("N1: a review file name must have exactly three digits to be a round", function()
		local ok = "### F1 [low] a\n\nVerdict: changes\n"
		-- an unpadded name is no round; with a padded one present it is ignored
		local got =
			rounds.latest({ ["review-001.md"] = ok, ["review-2.md"] = ok }, "code", "", NO) :: rounds.Round
		t.expect(got.number).toBe(1)
		-- alone, it is a malformed review, not "no review"
		local alone = rounds.latest({ ["review-2.md"] = ok }, "code", "", NO) :: rounds.Round
		t.expect(alone.malformed ~= nil).toBe(true)
		t.expect(
			string.find(
				alone.malformed or "",
				"review-2.md is not named review-NNN.md with three digits",
				1,
				true
			) ~= nil
		).toBe(true)
		t.expect(rounds.next(alone, 5).kind).toBe("malformed")
		t.expect(rounds.latest({ ["review-0002.md"] = ok }, "code", "", NO) ~= nil).toBe(true)
		-- no round at all is still no review
		t.expect(rounds.latest({ ["notes.md"] = ok }, "code", "", NO) == nil).toBe(true)
	end)

	it("AC6: unanswered returns nil for an answered review and each refusal word for word", function()
		local function run(rev: string, ref: string, doc: string?): string?
			return openlist.unanswered({
				review = rev,
				refute = ref,
				doc = doc or "# raft\n",
				reviewName = "review-001.md",
				refuteName = "refute-001.md",
				isBacklog = function(id: string): boolean
					return id == "c0020"
				end,
			})
		end
		local rev = "### F1 [medium] a\n\n### F2 [high] b\n\nVerdict: changes\n"
		t.expect(run(rev, "- F1: fixed a; consequences: none\n- F2: fixed b; consequences: none\n") == nil)
			.toBe(true)
		t.expect(run(rev, "- F1: fixed a; consequences: none\n"))
			.toBe("review-001.md findings not answered in refute-001.md: F2")
		t.expect(run(rev, "- F1: fixed a\n- F2: fixed b; consequences: none\n")).toBe(
			'refute-001.md: F1: a fixed answer needs "; consequences: <what the fix could break, and how that was checked, or none>"'
		)
		t.expect(run(rev, "- F1: deferred c0020: later\n- F2: fixed b; consequences: none\n") == nil)
			.toBe(true)
		t.expect(run(rev, "- F1: deferred c0999: later\n- F2: fixed b; consequences: none\n"))
			.toBe("refute-001.md: F1: c0999 is not a backlog issue")
		t.expect(run(rev, "- F1: fixed a; consequences: none\n- F2: deferred c0020: x\n"))
			.toBe("refute-001.md: F2 is high: only a medium or low finding can be deferred")
		t.expect(run(rev, "- F1: deferred later\n- F2: fixed b; consequences: none\n"))
			.toBe('refute-001.md: F1: deferred needs "<issue id>: <why>"')
		t.expect(run(rev, "- F1: fixed a; consequences: none\n- F2: refuted: no\n")).toBe(
			"review-001.md open to the human (F2): record each under ## Open to the human with Ruled (user, YYYY-MM-DD):"
		)
		t.expect(run("Verdict: changes\n", "") ~= nil).toBe(true)
		t.expect(run("nothing\n", "")).toBe("review-001.md has no Verdict line and no findings")
		t.expect(run("Verdict: changes\n", "")).toBe("review-001.md Verdict is changes, not approve")
	end)
	it(
		"AC9: filing with a step files, refuses answer and settled; with no step, or in raft or stream mode, as before",
		function()
			local function input(mode: string?, step: rounds.Step?): dispatch.FilingInput
				return {
					mode = mode,
					dir = "pickman/.tracker/issues/c0010",
					prefix = "design-review-",
					raftId = "c0010",
					reviews = { ["design-review-001.md"] = "Verdict: changes\n" },
					step = step,
				}
			end
			local filed = dispatch.filing(input("design", { kind = "file", number = 2, max = 5 }))
			t.expect(filed.number).toBe(2)
			t.expect(filed.refusal == nil).toBe(true)
			local open = dispatch.filing(input("design", { kind = "answer", number = 1, max = 5 }))
			t.expect(open.number == nil).toBe(true)
			t.expect(open.refusal).toBe(
				"pickman/.tracker/issues/c0010/design-review-001.md is not answered: answer every finding in its refute file before round 2"
			)
			local last = dispatch.filing(input("code", { kind = "answer", number = 2, max = 2 }))
			t.expect(last.refusal).toBe(
				"pickman/.tracker/issues/c0010/design-review-002.md is not answered: it is round 2 of 2, the last; what stays open goes to the human"
			)
			local settled = dispatch.filing(input("final", { kind = "settled", number = 3, max = 9 }))
			t.expect(settled.refusal).toBe(
				"pickman/.tracker/issues/c0010/design-review-003.md settled the review (approve, or answered at round 3 of 9): there is no further round"
			)
			-- no step: one round, today's words
			local old = dispatch.filing(input("design", nil))
			t.expect(old.refusal).toBe(
				"pickman/.tracker/issues/c0010 already has design-review-001.md: one round, then the author answers it; there is no second round"
			)
			-- stream mode ignores a step
			local stream = dispatch.filing(input("stream", { kind = "file", number = 7, max = 9 }))
			t.expect(stream.refusal ~= nil).toBe(true)
			-- raft mode with no record is one round, whatever step it is given
			local raft = dispatch.filing(input("raft", { kind = "file", number = 7, max = 9 }))
			t.expect(raft.refusal == old.refusal).toBe(true)
		end
	)

	it(
		"F6: a dispatched reviewer of round 2 or later is told the round, the previous files and the rule",
		function()
			local function prompt(mode: string, which: number?): string
				return dispatch.prompt({
					step = "zz-review",
					id = "c0010",
					mode = mode,
					skillPath = "z-nile/skills/zz-review/SKILL.md",
					worktree = "/w",
					stateDir = "/s",
					round = which,
				})
			end
			local function has(text: string, needle: string): boolean
				return string.find(text, needle, 1, true) ~= nil
			end
			local second = prompt("design", 2)
			t.expect(has(second, "This is round 2, not round 1.")).toBe(true)
			t.expect(has(second, "Read design-review-001.md and design-refute-001.md")).toBe(true)
			t.expect(has(second, "accept or re-raise each refutation")).toBe(true)
			t.expect(has(second, "this round only checks the answers")).toBe(true)
			t.expect(has(prompt("code", 3), "Read review-002.md and refute-002.md")).toBe(true)
			t.expect(has(prompt("final", 2), "Read final-review-001.md and final-refute-001.md")).toBe(true)
			t.expect(has(prompt("design", 1), "only checks the answers")).toBe(false)
			t.expect(has(prompt("design", nil), "only checks the answers")).toBe(false)
			t.expect(has(second, "- review-002 F2")).toBe(true)
		end
	)

	it("F5: ./zn rounds prints the step in one line", function()
		local roundscmd = require("@znile/engine/roundscmd")
		local function has(text: string, needle: string): boolean
			return string.find(text, needle, 1, true) ~= nil
		end
		local files = {
			["design-review-001.md"] = "### F1 [medium] a\n\nVerdict: changes\n",
			["design-refute-001.md"] = "- F1: fixed a; consequences: none\n",
		}
		local latest = rounds.latest(files, "design", "", NO)
		t.expect(roundscmd.line("f0421", "design", rounds.next(latest, 5), latest))
			.toBe("f0421 design: round 1 answered; run design review round 2 of at most 5")
		t.expect(roundscmd.line("f0421", "design", rounds.next(nil, 5), nil))
			.toBe("f0421 design: no review yet; run design review round 1 of at most 5")
		files["design-refute-001.md"] = ""
		latest = rounds.latest(files, "design", "", NO)
		t.expect(roundscmd.line("f0421", "design", rounds.next(latest, 5), latest))
			.toBe("f0421 design: answer design-review-001.md in design-refute-001.md (every finding gets a line)")
		local low = {
			["design-review-001.md"] = "### F1 [low] a\n\nVerdict: changes\n",
			["design-refute-001.md"] = "- F1: fixed a; consequences: none\n",
		}
		latest = rounds.latest(low, "design", "", NO)
		t.expect(roundscmd.line("f0421", "design", rounds.next(latest, 5), latest))
			.toBe("f0421 design: settled at round 1")
		local maxed = {
			["design-review-002.md"] = "### F1 [high] a\n\nVerdict: changes\n",
			["design-refute-002.md"] = "- F1: fixed a; consequences: none\n",
		}
		latest = rounds.latest(maxed, "design", "", NO)
		t.expect(roundscmd.line("f0421", "design", rounds.next(latest, 2), latest)).toBe(
			"f0421 design: design-review-002.md settled at the maximum (round 2 of 2) with 1 serious findings answered: record it as a guess (./zn guess f0421 --step design) so the owner sees it at approval"
		)
		latest = rounds.latest({ ["design-review-001.md"] = "nothing\n" }, "design", "", NO)
		t.expect(
			has(
				roundscmd.line("f0421", "design", rounds.next(latest, 5), latest),
				"has no Verdict line and no findings"
			)
		).toBe(true)
	end)
end)
