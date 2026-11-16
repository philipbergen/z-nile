--!strict
-- c0161 AC2: the pure rule behind the refusal. `status.designReviewProblem(files, record)` takes an issue folder's files
-- (path relative to the folder -> text) and the design's record now, and returns nil when the newest design review round
-- approves and quotes that record, else the problem, which names the file it is about. Only a reviewer's word counts:
-- the newest `design-review-NNN.md` has one `Verdict: approve` line and one `Design record: <hash>` line equal to the
-- record (a repeat of either is refused: a round is written once). A `changes` round is never the last, whatever sits beside it; refutes, harvest and the
-- like are not read. Pure: no fixture, no git.
local status = require("@znile/engine/status")
local t = require("@tests/lib/t")

local H = "0123456789ab"

-- a round as a reviewer leaves it
local function round(verdict: string?, hash: string?): string
	local verdictLine = if verdict then `\nVerdict: {verdict}\n` else "\n"
	local quote = if hash then `\nDesign record: {hash}\n` else ""
	return `# Review 001: c0001 (design mode)\nInputs: x\n\n### F1 [low] a claim\nWhere: a\nEvidence: b\n{verdictLine}{quote}`
end
local function problem(files: { [string]: string }, record: string?): string
	local p = status.designReviewProblem(files, record or H)
	assert(p ~= nil, "expected a problem, got none")
	return p :: string
end
local function mentions(text: string, needle: string)
	if string.find(text, needle, 1, true) == nil then
		error(`the problem lacks {needle}: {text}`, 2)
	end
end
local function passes(files: { [string]: string }, record: string?)
	local p = status.designReviewProblem(files, record or H)
	if p ~= nil then
		error(`expected no problem, got: {p}`, 2)
	end
end

return t.spec(
	"c0161 status.designReviewProblem: an issue is prepared only after a reviewer's approving round that read the design",
	function(it)
		it("an empty folder, and files that are not review rounds, have no review", function()
			mentions(problem({}), "design-review-001.md")
			mentions(problem({}), "closure")
			local others: { [string]: string } = {
				["c0001.md"] = "# c0001\n",
				["check.sh"] = "true\n",
				["design-refute-001.md"] = "- F1: fixed\n",
				["review-001.md"] = round("approve", H), -- a code-mode round is not a design round
				["design-review-1.md"] = round("approve", H),
				["design-review-0001.md"] = round("approve", H),
				["design-review-001.md.bak"] = round("approve", H),
				["old-design-review-001.md"] = round("approve", H),
				["acceptance/design-review-001.md"] = round("approve", H), -- a sub folder's file is not the folder's own
				["experiments/design-review-001.md"] = round("approve", H),
			}
			mentions(problem(others), "design-review-001.md")
		end)

		it("a round with no Verdict line is illegible and names its file", function()
			local p = problem({ ["design-review-001.md"] = round(nil, H) })
			mentions(p, "design-review-001.md")
			mentions(p, "Verdict")
		end)

		it("only `approve` is a verdict that passes, spelled exactly, at the start of a line", function()
			for _, bad in { "approved", "approve with reservations", "Approve", "ok", "" } do
				mentions(problem({ ["design-review-001.md"] = round(bad, H) }), "Verdict")
			end
			-- a Verdict mentioned inside a line, or indented, is a quotation, not the verdict
			local quoted =
				`# Review 001\n\n### F1 [low] x\nEvidence: the reviewer wrote Verdict: approve\n  Verdict: approve\nDesign record: {H}\n`
			mentions(problem({ ["design-review-001.md"] = quoted }), 'has no "Verdict: approve"')
			-- and a note mentioning a verdict inside a line does not make a second verdict line
			passes({
				["design-review-001.md"] = round("approve", H) .. "\nnote: Verdict: changes was wrong\n",
			})
		end)

		it(
			"a round that says changes is never the last: a refute beside it, or a record, does not stand in",
			function()
				local p = problem({
					["design-review-001.md"] = round("changes", H),
					["design-refute-001.md"] = `- F1: fixed: x; consequences: none\n\nDesign record: {H}\n`,
				})
				mentions(p, "design-review-001.md")
				mentions(p, "Verdict: changes")
				mentions(p, "next round")
				mentions(problem({ ["design-review-001.md"] = round("changes", H) }), "Verdict: changes")
			end
		)

		it(
			"an approving round passes alone with the record; trailing spaces, CRLF and a missing newline read",
			function()
				passes({ ["design-review-001.md"] = round("approve", H) })
				passes({ ["design-review-001.md"] = round("approve   ", H) })
				passes({ ["design-review-001.md"] = `{round("approve")}\r\nDesign record: {H}\r\n` })
				passes({ ["design-review-001.md"] = `{round("approve")}\nDesign record: {H}` })
				-- findings on an approving round need no answer file
				passes({ ["design-review-001.md"] = round("approve", H) })
			end
		)

		it("the record is quoted on a line of its own; a repeat or an annotated line is refused", function()
			mentions(problem({ ["design-review-001.md"] = round("approve", nil) }), "quotes no")
			mentions(
				problem({ ["design-review-001.md"] = round("approve") .. `\nsee Design record: {H}\n` }),
				"quotes no"
			)
			mentions(
				problem({ ["design-review-001.md"] = round("approve") .. `\n  Design record: {H}\n` }),
				"quotes no"
			)
			-- two quotes, adjacent or apart, are refused whichever comes last
			mentions(
				problem({
					["design-review-001.md"] = round("approve")
						.. `\nDesign record: {H}\nDesign record: ffffffffffff\n`,
				}),
				'two "Design record:" lines'
			)
			mentions(
				problem({
					["design-review-001.md"] = round("approve")
						.. `\nDesign record: ffffffffffff\nDesign record: {H}\n`,
				}),
				'two "Design record:" lines'
			)
			mentions(
				problem({
					["design-review-001.md"] = round("approve", H)
						.. "\n\nnote\n\nDesign record: ffffffffffff\n",
				}),
				'two "Design record:" lines'
			)
			-- a quote with anything after the hash is refused, by the same reader the re-record uses
			mentions(
				problem({
					["design-review-001.md"] = round("approve")
						.. `\nDesign record: {H} (taken before reading)\n`,
				}),
				"not just the hash"
			)
		end)

		it("a stale record names both hashes and says the design changed after the round", function()
			local p = problem({ ["design-review-001.md"] = round("approve", "ffffffffffff") })
			mentions(p, "ffffffffffff")
			mentions(p, H)
			mentions(p, "changed after this round")
			mentions(p, "needs a new round")
			mentions(p, "another checkout")
			-- the recovery (design review 006 F2): a round for this issue, in the worktree that holds the edit
			mentions(
				p,
				"design round for this issue, run in the worktree that holds the edit and landed with it"
			)
			mentions(
				p,
				"for a rafted member: unfold it with the edit and the round, land, then fold it again: z-raft 2"
			)
		end)

		it("the newest round decides, by its number: an older approval excuses nothing", function()
			local files: { [string]: string } = {
				["design-review-001.md"] = round("approve", H),
				["design-review-002.md"] = round("changes", H),
				["design-refute-001.md"] = "- F1: refuted\n",
			}
			mentions(problem(files), "design-review-002.md")
			-- an older changes round, then an approving one that read the design as it is
			passes({
				["design-review-001.md"] = round("changes", "ffffffffffff"),
				["design-refute-001.md"] = "- F1: fixed\n",
				["design-review-002.md"] = round("approve", H),
			})
			-- an older approval of an older design, then a newer round without a record
			mentions(
				problem({
					["design-review-001.md"] = round("approve", H),
					["design-review-002.md"] = round("approve", nil),
				}),
				"design-review-002.md"
			)
			-- the number decides, not the order the files are listed in or the name sorted
			local many: { [string]: string } = {}
			for n = 1, 12 do
				many[string.format("design-review-%03d.md", n)] =
					round(if n == 12 then "changes" else "approve", H)
			end
			mentions(problem(many), "design-review-012.md")
		end)

		it("a second Verdict line is refused, whichever it says", function()
			for _, pair in { { "changes", "approve" }, { "approve", "changes" }, { "approve", "approve" } } do
				local text =
					`# Review\n\nVerdict: {pair[1]}\n\n(re-read)\n\nVerdict: {pair[2]}\n\nDesign record: {H}\n`
				mentions(problem({ ["design-review-001.md"] = text }), 'two "Verdict:" lines')
			end
		end)

		it(
			"roundLines reads one verdict and one quote, and rewriteRecord changes only the exact quote line",
			function()
				local verdict, quoted, bad =
					status.roundLines(`# R\n\nVerdict: approve  \r\nDesign record: {H}\r\n`)
				t.expect(verdict).toBe("approve")
				t.expect(quoted).toBe(H)
				t.expect(bad).toBe(nil)
				local v2, q2 = status.roundLines("# R\nno lines\n")
				t.expect(v2).toBe(nil)
				t.expect(q2).toBe(nil)
				local text = `# R\n\nVerdict: approve\nsee Design record: {H}\nDesign record: {H}\n`
				local out = status.rewriteRecord(text, H, "ffffffffffff")
				t.expect(out)
					.toBe(`# R\n\nVerdict: approve\nsee Design record: {H}\nDesign record: ffffffffffff\n`)
				t.expect(status.rewriteRecord(text, "aaaaaaaaaaaa", "ffffffffffff")).toBe(text) -- another hash: unchanged
				t.expect(status.rewriteRecord("Design record: " .. H, H, "ffffffffffff"))
					.toBe("Design record: ffffffffffff")
			end
		)

		it(
			"preparedReadProblem: an issue no round of which quotes a record predates the rule and is exempt",
			function()
				t.expect(status.preparedReadProblem({}, H)).toBe(nil)
				t.expect(status.preparedReadProblem({ ["design-review-001.md"] = round("changes", nil) }, H))
					.toBe(nil)
				t.expect(status.preparedReadProblem({ ["design-review-001.md"] = round("approve", nil) }, H))
					.toBe(nil)
			end
		)

		it(
			"preparedReadProblem: once any round quotes a record, the newest must match the design as on origin",
			function()
				t.expect(status.preparedReadProblem({ ["design-review-001.md"] = round("approve", H) }, H))
					.toBe(nil)
				local stale = status.preparedReadProblem(
					{ ["design-review-001.md"] = round("approve", "ffffffffffff") },
					H
				)
				assert(stale ~= nil, "expected a problem")
				mentions(stale :: string, "prepared on origin/main")
				mentions(stale :: string, "design-review-001.md")
				mentions(stale :: string, "ffffffffffff")
				-- an older round quoted, the newest does not: not exempt
				local later = status.preparedReadProblem({
					["design-review-001.md"] = round("approve", H),
					["design-review-002.md"] = round("approve", nil),
				}, H)
				assert(later ~= nil, "expected a problem")
				mentions(later :: string, "design-review-002.md")
				-- a quote beside a repeat is still a quote, and the repeat is the problem
				local twice = status.preparedReadProblem(
					{ ["design-review-001.md"] = round("approve", H) .. `\nDesign record: {H}\n` },
					H
				)
				assert(twice ~= nil, "expected a problem")
				mentions(twice :: string, "two")
			end
		)
	end
)
