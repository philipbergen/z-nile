--!strict
-- f0421 slice 1: the round rule (rounds.luau), the one definition of "answered" (openlist.unanswered) and the
-- [rounds] limits of .models.toml (models.parse, models.rounds). Pure: texts in, results out.
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

local function round(n: number, verdict: string?, answered: boolean, serious: boolean): rounds.Round
	return { number = n, verdict = verdict, answered = answered, serious = serious }
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

	it("AC2: no [rounds] gives the seed, and the root .models.toml sets the same seed", function()
		local got = models.rounds({})
		t.expect(got.idea).toBe(3)
		for _, stage in { "design", "code" } do
			local tbl = (got :: any)[stage] :: { [string]: number }
			t.expect(tbl.easy).toBe(2)
			t.expect(tbl.normal).toBe(5)
			t.expect(tbl.risky).toBe(9)
		end
		local fs = require("@lune/fs")
		local process = require("@lune/process")
		local top = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
		local layer = models.parse(fs.readFile(`{top}/.models.toml`), ".models.toml")
		t.expect(layer.rounds ~= nil).toBe(true)
		t.expect(models.rounds({ layer })).toEqual(rounds.DEFAULT)
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
		rejects("[rounds]\nidea = 0\n", ".models.toml: rounds.idea is a whole number, at least 1")
		rejects("[rounds]\nidea = 1.5\n", "rounds.idea is a whole number, at least 1")
		rejects("[rounds]\ncode = { easy = 0 }\n", "rounds.code.easy is a whole number, at least 1")
		rejects("[nope]\nx = 1\n", "the file has roles, fallback, dispatch and rounds; skill tables are gone")
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
		t.expect(rounds.next(nil, 5)).toEqual({ kind = "file", number = 1, max = 5 })
		-- approve settles, whatever its answers
		t.expect(rounds.next(round(2, "approve", false, true), 5))
			.toEqual({ kind = "settled", number = 2, max = 5 })
		-- not approve and unanswered waits for the author, even at the maximum
		t.expect(rounds.next(round(1, "changes", false, true), 5))
			.toEqual({ kind = "answer", number = 1, max = 5 })
		t.expect(rounds.next(round(5, nil, false, false), 5))
			.toEqual({ kind = "answer", number = 5, max = 5 })
		-- answered and serious below the maximum files the next round
		t.expect(rounds.next(round(1, "changes", true, true), 2))
			.toEqual({ kind = "file", number = 2, max = 2 })
		t.expect(rounds.next(round(4, nil, true, true), 5)).toEqual({ kind = "file", number = 5, max = 5 })
		-- answered with only low findings settles below the maximum
		t.expect(rounds.next(round(1, "changes", true, false), 5))
			.toEqual({ kind = "settled", number = 1, max = 5 })
		-- answered at the maximum settles (and above it)
		t.expect(rounds.next(round(2, "changes", true, true), 2))
			.toEqual({ kind = "settled", number = 2, max = 2 })
		t.expect(rounds.next(round(3, "changes", true, true), 2))
			.toEqual({ kind = "settled", number = 3, max = 2 })
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
		t.expect(g.answered).toBe(false)
		t.expect(g.serious).toBe(true)
		files["refute-002.md"] = "- F1: fixed b; consequences: none\n"
		t.expect((rounds.latest(files, "code", "# doc\n", NO) :: rounds.Round).answered).toBe(true)
		local f = rounds.latest(files, "final", "# doc\n", NO) :: rounds.Round
		t.expect(f.number).toBe(9)
		t.expect(f.verdict).toBe("approve")
		t.expect(rounds.latest({}, "design", "", NO) == nil).toBe(true)
		-- only low findings: not serious
		local low =
			rounds.latest({ ["design-review-001.md"] = "### F1 [low] a\n" }, "design", "", NO) :: rounds.Round
		t.expect(low.serious).toBe(false)
		-- the prefix is plain: "review-" does not match "design-review-"
		t.expect(rounds.latest({ ["design-review-001.md"] = "x" }, "code", "", NO) == nil).toBe(true)
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
		t.expect(run("Verdict: changes\n", "")).toBe("review-001.md Verdict is changes, not approve")
	end)
end)
