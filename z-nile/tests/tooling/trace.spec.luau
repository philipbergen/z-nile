--!strict
-- Pure checks for `./zn trace`: claim names, the stale rule, and the table.
-- The real git landing (finish, a second clone, done) is tests/tooling/trace-land.spec.luau.
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("trace derives claims and checks the table", function(it)
	it(
		"derives stable P, S and AC claims from captured idea and acceptance criteria, and fails on vacuous tickets",
		function()
			local captured1 = table.concat({
				"---",
				"id: c0010",
				"---",
				"",
				"# c0010: Alpha",
				"",
				"## Problem",
				"- Alpha is missing from the score HUD.",
				"- High score resets on reload.",
				"Scope decision (user, 2026-10-01): keep reload behavior local.",
				"",
				"## Solution",
				"Compute alpha in `alpha.luau` and persist it across reloads.",
			}, "\n")
			local doc1 = captured1
				.. "\n\n## Design\nRender alpha.\n\n## Acceptance criteria\n- AC1: Alpha renders.\n- AC2: High score persists.\n"
			local baseIssue: trace.IssueDoc = {
				id = "c0010",
				docPath = "pickman/.tracker/issues/active/c0010/c0010.md",
				checkPath = "pickman/.tracker/issues/active/c0010/check.sh",
				dirPath = "pickman/.tracker/issues/active/c0010",
				home = "pickman",
				capturedText = captured1,
				docText = doc1,
				checkText = nil,
				resultsPath = "pickman/.tracker/issues/active/c0010/results.txt",
				resultsText = "",
			}
			local claims, errs = trace.deriveClaims({ baseIssue })
			t.expect(errs).toEqual({})
			local ids: { string } = {}
			for _, c in claims do
				table.insert(ids, c.id)
			end
			t.expect(ids).toEqual({
				"c0010:P1",
				"c0010:P2",
				"c0010:S1",
				"c0010:AC1",
				"c0010:AC2",
			})

			local noProblem = table.clone(baseIssue)
			noProblem.capturedText = "# c0010\n\n## Problem\n<!-- comment only -->\n\n## Solution\nDo it.\n"
			local _, errP = trace.deriveClaims({ noProblem })
			t.expect(#errP == 1 and has(errP[1], "ticket c0010 is missing captured ## Problem")).toBe(true)

			local noSolution = table.clone(baseIssue)
			noSolution.capturedText = "# c0010\n\n## Problem\nBroken.\n\n## Solution\n\n"
			local _, errS = trace.deriveClaims({ noSolution })
			t.expect(#errS == 1 and has(errS[1], "ticket c0010 is missing captured ## Solution")).toBe(true)

			local noAc = table.clone(baseIssue)
			noAc.docText = captured1 .. "\n\n## Acceptance criteria\n<!-- none -->\n"
			local _, errAc = trace.deriveClaims({ noAc })
			t.expect(#errAc == 1 and has(errAc[1], "ticket c0010 is missing ## Acceptance criteria"))
				.toBe(true)
		end
	)

	it(
		"pure trace.staleReason covers every layer, finish, Commit: and post-finish commit condition",
		function()
			local issues: { trace.IssueDoc } = {
				{
					id = "c0010",
					docPath = "pickman/.tracker/issues/active/c0010/c0010.md",
					checkPath = "pickman/.tracker/issues/active/c0010/check.sh",
					dirPath = "pickman/.tracker/issues/active/c0010",
					home = "pickman",
					capturedText = "",
					docText = "",
				},
				{
					id = "c0020",
					docPath = "pickman/.tracker/issues/active/c0020/c0020.md",
					checkPath = "pickman/.tracker/issues/active/c0020/check.sh",
					dirPath = "pickman/.tracker/issues/active/c0020",
					home = "pickman",
					capturedText = "",
					docText = "",
				},
			}
			local raftDir = "pickman/.tracker/rafts/active/R0010"
			local function validLayers(): { trace.LayerHistory }
				return {
					{
						name = "R0010/1/c0010",
						issue = "c0010",
						title = "alpha",
						base = "main0",
						tip = "fin1",
						stackedOnBelow = true,
						commits = {
							{
								sha = "fin1",
								parent = "main0",
								subject = "c0010: alpha",
								files = { "pickman/src/alpha.luau" },
							},
						},
					},
					{
						name = "R0010/2/c0020",
						issue = "c0020",
						title = "beta",
						base = "fin1",
						tip = "rev1",
						stackedOnBelow = true,
						commits = {
							{
								sha = "fin2",
								parent = "fin1",
								subject = "c0020: beta",
								files = { "pickman/src/beta.luau" },
							},
							{
								sha = "rev1",
								parent = "fin2",
								subject = "R0010: final-review-001",
								files = { `{raftDir}/trace.md`, `{raftDir}/final-review-001.md` },
							},
						},
					},
				}
			end

			t.expect((trace.staleReason("R0010", raftDir, issues, validLayers(), "fin2"))).toBe(nil)
			t.expect(has(trace.staleReason("R0010", raftDir, issues, {}, "fin2") or "", "no layers"))
				.toBe(true)

			local oneLayer = { validLayers()[1] }
			t.expect(
				has(trace.staleReason("R0010", raftDir, issues, oneLayer, "fin1") or "", "1 layer(s) for 2")
			)
				.toBe(true)

			local wrongIssue = validLayers()
			wrongIssue[2].issue = "c0099"
			t.expect(
				has(trace.staleReason("R0010", raftDir, issues, wrongIssue, "fin2") or "", "expected c0020")
			)
				.toBe(true)

			local noTip = validLayers()
			noTip[2].tip = nil
			t.expect(has(trace.staleReason("R0010", raftDir, issues, noTip, "fin2") or "", "has no tip"))
				.toBe(true)

			local unstacked = validLayers()
			unstacked[2].stackedOnBelow = false
			t.expect(has(trace.staleReason("R0010", raftDir, issues, unstacked, "fin2") or "", "not stacked"))
				.toBe(true)

			local notFinished = validLayers()
			notFinished[1].commits[1].subject = "wip"
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, notFinished, "fin2") or "",
					"c0010 is not finished"
				)
			).toBe(true)

			local rewrittenBase = validLayers()
			rewrittenBase[1].commits[1].parent = "other0"
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, rewrittenBase, "fin2") or "",
					"R0010/1/c0010 was rewritten"
				)
			).toBe(true)

			local extraLower = validLayers()
			table.insert(extraLower[1].commits, {
				sha = "extra1",
				parent = "fin1",
				subject = "extra",
				files = { `{raftDir}/R0010.md` },
			})
			extraLower[1].tip = "extra1"
			extraLower[2].base = "extra1"
			extraLower[2].commits[1].parent = "extra1"
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, extraLower, "fin2") or "",
					"after finish commit"
				)
			).toBe(true)

			local emptyHeader = validLayers()
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, emptyHeader, "") or "",
					"missing Commit: header"
				)
			).toBe(true)
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, emptyHeader, "wrongsha") or "",
					"names commit wrongsha, but top layer finish commit is fin2"
				)
			).toBe(true)

			local nonTrackerAfter = validLayers()
			nonTrackerAfter[2].commits[2].files = { `{raftDir}/trace.md`, "pickman/src/beta.luau" }
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, nonTrackerAfter, "fin2") or "",
					"touches non-tracker file pickman/src/beta.luau"
				)
			).toBe(true)

			local commitBeforeTrace = validLayers()
			commitBeforeTrace[2].commits[2].files = { `{raftDir}/final-review-001.md` }
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, commitBeforeTrace, "fin2") or "",
					"added to R0010/2/c0020 before trace.md"
				)
			).toBe(true)

			local emptyAfterTrace = validLayers()
			table.insert(emptyAfterTrace[2].commits, {
				sha = "emp1",
				parent = "rev1",
				subject = "empty",
				files = {},
			})
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, emptyAfterTrace, "fin2") or "",
					"commit emp1 added to R0010/2/c0020 after trace.md"
				)
			).toBe(true)

			local docAfterTrace = validLayers()
			table.insert(docAfterTrace[2].commits, {
				sha = "doc1",
				parent = "rev1",
				subject = "edit issue doc",
				files = { "pickman/.tracker/issues/active/c0020/c0020.md" },
			})
			t.expect(
				has(
					trace.staleReason("R0010", raftDir, issues, docAfterTrace, "fin2") or "",
					"commit doc1 added to R0010/2/c0020 after trace.md"
				)
			).toBe(true)
		end
	)

	it(
		"pure trace.check catches every missing link, bad file kind, unrun spec, exact case match, missing results file, missing source, none code cell, and stale commit",
		function()
			local doc = table.concat({
				"---",
				"id: c0010",
				"---",
				"# c0010",
				"## Problem",
				"Need alpha.",
				"## Solution",
				"Build alpha.",
				"## Design",
				"Alpha design line.",
				"## Acceptance criteria",
				"- AC1: Alpha works.",
			}, "\n")
			local checkSh = 'source "ac.sh"\ncheck "AC1: Alpha works" true\nfinish\n'
			local specText =
				'--!strict\nreturn t.spec("alpha", function(it)\n\tit("computes alpha", function() end)\nend)\n'
			local alphaSrc = "--!strict\nreturn { alpha = 1 }\n"
			local untouchedSrc = "--!strict\nreturn { untouched = 0 }\n"
			local raftDir = "pickman/.tracker/rafts/active/R0010"
			local issueDoc: trace.IssueDoc = {
				id = "c0010",
				docPath = "pickman/.tracker/issues/active/c0010/c0010.md",
				checkPath = "pickman/.tracker/issues/active/c0010/check.sh",
				dirPath = "pickman/.tracker/issues/active/c0010",
				home = "pickman",
				capturedText = doc,
				docText = doc,
				checkText = checkSh,
				resultsPath = "pickman/.tracker/issues/active/c0010/results.txt",
				resultsText = trace.renderResults({
					{ spec = "pickman/tests/unit/alpha.spec.luau", cases = { "computes alpha" } },
				}),
			}
			local files: { [string]: trace.FileMeta } = {
				[issueDoc.docPath] = { lines = trace.splitLines(doc) },
				[issueDoc.checkPath] = { lines = trace.splitLines(checkSh) },
				["pickman/tests/unit/alpha.spec.luau"] = { lines = trace.splitLines(specText) },
				["pickman/tests/unit/unrun.spec.luau"] = { lines = trace.splitLines(specText) },
				["pickman/src/alpha.luau"] = { lines = trace.splitLines(alphaSrc) },
				["pickman/src/untouched.luau"] = { lines = trace.splitLines(untouchedSrc) },
				[`{raftDir}/review-001.md`] = { lines = { "# Review 001", "Verdict: approve" } },
			}
			local validLayers: { trace.LayerHistory } = {
				{
					name = "R0010/1/c0010",
					issue = "c0010",
					title = "alpha",
					base = "main0",
					tip = "deadbeef",
					stackedOnBelow = true,
					commits = {
						{
							sha = "deadbeef",
							parent = "main0",
							subject = "c0010: alpha",
							files = { "pickman/src/alpha.luau" },
						},
					},
				},
			}
			local validTable = table.concat({
				"# Trace: R0010",
				"",
				"Commit: deadbeef",
				"",
				"## Claims",
				"",
				"| claim | design | test | code |",
				"|---|---|---|---|",
				`| c0010:P1 | {issueDoc.docPath}:10 | pickman/tests/unit/alpha.spec.luau:3 :: computes alpha | pickman/src/alpha.luau:2 |`,
				`| c0010:S1 | {issueDoc.docPath}:10 | {issueDoc.checkPath}:2 | pickman/src/alpha.luau:2 |`,
				`| c0010:AC1 | {issueDoc.docPath}:10 | pickman/tests/unit/alpha.spec.luau:3 :: computes alpha | pickman/src/alpha.luau:2 |`,
				"",
				"## Source files",
				"",
				"| file | claims |",
				"|---|---|",
				"| pickman/src/alpha.luau | c0010:P1, c0010:S1, c0010:AC1 |",
				"",
			}, "\n")
			local baseInput: trace.CheckInput = {
				raftId = "R0010",
				raftDir = raftDir,
				tableText = validTable,
				layers = validLayers,
				issues = { issueDoc },
				raftDocText = "# R0010\n",
				changedSources = { "pickman/src/alpha.luau" },
				filesAtCommit = files,
			}
			t.expect(trace.check(baseInput)).toEqual({})

			local missingClaim = table.clone(baseInput)
			missingClaim.tableText = (string.gsub(validTable, "| c0010:S1 [^\n]+\n", ""))
			local f1 = trace.check(missingClaim)
			t.expect(#f1 > 0 and has(f1[1], "row c0010:S1, claim: missing claim")).toBe(true)

			local badLine = table.clone(baseInput)
			badLine.tableText = (
				string.gsub(validTable, "pickman/src/alpha%.luau:2", "pickman/src/alpha.luau:99", 1)
			)
			local f2 = trace.check(badLine)
			t.expect(#f2 > 0 and has(f2[1], "row c0010:P1, code: pickman/src/alpha.luau:99")).toBe(true)

			-- Missing results.txt at commit is reported distinctly from an unrun spec
			local noResultsDoc = table.clone(issueDoc)
			noResultsDoc.resultsText = nil
			local noResultsInput = table.clone(baseInput)
			noResultsInput.issues = { noResultsDoc }
			local fNoRes = trace.check(noResultsInput)
			t.expect(
				#fNoRes > 0
					and has(
						fNoRes[1],
						"row c0010:P1, test: results file pickman/.tracker/issues/active/c0010/results.txt for ticket c0010 does not exist at commit deadbeef"
					)
			).toBe(true)

			local unrunTest = table.clone(baseInput)
			unrunTest.tableText = (
				string.gsub(
					validTable,
					"pickman/tests/unit/alpha%.spec%.luau:3",
					"pickman/tests/unit/unrun.spec.luau:3",
					1
				)
			)
			local f3 = trace.check(unrunTest)
			t.expect(
				#f3 > 0
					and has(
						f3[1],
						"row c0010:P1, test: pickman/tests/unit/unrun.spec.luau did not run green for ticket c0010"
					)
			).toBe(true)

			-- Substring case name fails (must equal a recorded case name)
			local substringCase = table.clone(baseInput)
			substringCase.tableText = (string.gsub(validTable, ":: computes alpha", ":: computes", 1))
			local fSub = trace.check(substringCase)
			t.expect(
				#fSub > 0
					and has(
						fSub[1],
						'row c0010:P1, test: case "computes" in pickman/tests/unit/alpha.spec.luau did not run green for ticket c0010'
					)
			).toBe(true)

			-- When no cases are recorded for a spec, citing a case fails even if the cited line contains the text
			local emptyCasesDoc = table.clone(issueDoc)
			emptyCasesDoc.resultsText = trace.renderResults({
				{ spec = "pickman/tests/unit/alpha.spec.luau", cases = {} },
			})
			local emptyCasesInput = table.clone(baseInput)
			emptyCasesInput.issues = { emptyCasesDoc }
			local fEmptyCases = trace.check(emptyCasesInput)
			t.expect(
				#fEmptyCases > 0
					and has(
						fEmptyCases[1],
						'row c0010:P1, test: case "computes alpha" in pickman/tests/unit/alpha.spec.luau did not run green for ticket c0010'
					)
			).toBe(true)

			local missingSource = table.clone(baseInput)
			missingSource.changedSources = { "pickman/src/alpha.luau", "pickman/src/beta.luau" }
			local f4 = trace.check(missingSource)
			t.expect(
				#f4 > 0
					and has(f4[1], "row pickman/src/beta.luau, file: changed source file missing from table")
			).toBe(true)

			local unchangedCode = table.clone(baseInput)
			unchangedCode.tableText = (
				string.gsub(validTable, "pickman/src/alpha%.luau:2", "pickman/src/untouched.luau:2", 1)
			)
			local f5 = trace.check(unchangedCode)
			t.expect(
				#f5 > 0
					and has(
						f5[1],
						"row c0010:P1, code: pickman/src/untouched.luau was not changed by this stack"
					)
			).toBe(true)

			-- Stack with no changed source files requires literal `none` in code cells, never a review file
			local noSourceTable = table.concat({
				"# Trace: R0010",
				"",
				"Commit: deadbeef",
				"",
				"## Claims",
				"",
				"| claim | design | test | code |",
				"|---|---|---|---|",
				`| c0010:P1 | {issueDoc.docPath}:10 | {issueDoc.checkPath}:2 | none |`,
				`| c0010:S1 | {issueDoc.docPath}:10 | {issueDoc.checkPath}:2 | none |`,
				`| c0010:AC1 | {issueDoc.docPath}:10 | {issueDoc.checkPath}:2 | none |`,
				"",
				"## Source files",
				"",
				"| file | claims |",
				"|---|---|",
				"",
			}, "\n")
			local noSourceInput = table.clone(baseInput)
			noSourceInput.changedSources = {}
			noSourceInput.tableText = noSourceTable
			t.expect(trace.check(noSourceInput)).toEqual({})

			local reviewAsCode = table.clone(noSourceInput)
			reviewAsCode.tableText = (
				string.gsub(noSourceTable, "| none |", `| {raftDir}/review-001.md:1 |`, 1)
			)
			local fRevCode = trace.check(reviewAsCode)
			t.expect(#fRevCode > 0 and has(fRevCode[1], 'stack changed no source file (expected "none")'))
				.toBe(true)

			local noneWhenSourceChanged = table.clone(baseInput)
			noneWhenSourceChanged.tableText = (
				string.gsub(validTable, "pickman/src/alpha%.luau:2", "none", 1)
			)
			local fNoneBad = trace.check(noneWhenSourceChanged)
			t.expect(
				#fNoneBad > 0
					and has(
						fNoneBad[1],
						'row c0010:P1, code: "none" is only valid when the stack changed no source file'
					)
			).toBe(true)

			local notMetTable = (
				string.gsub(
					validTable,
					"| c0010:S1 | [^\n]+",
					'| c0010:S1 | not met: "defer persistence to c0090" | - | - |'
				)
			)
			local unruled = table.clone(baseInput)
			unruled.tableText = notMetTable
			local f6 = trace.check(unruled)
			t.expect(
				#f6 > 0
					and has(
						f6[1],
						'row c0010:S1, design: ruling "defer persistence to c0090" is not recorded under ## Open to the human'
					)
			).toBe(true)

			local ruled = table.clone(baseInput)
			ruled.tableText = notMetTable
			ruled.raftDocText =
				"# R0010\n\n## Open to the human\n- S1: persistence. Ruled (user, 2026-11-11): defer persistence to c0090.\n"
			t.expect(trace.check(ruled)).toEqual({})

			local staleLayers = { table.clone(validLayers[1]) }
			staleLayers[1].commits = {
				validLayers[1].commits[1],
				{
					sha = "123456789abc",
					parent = "deadbeef",
					subject = "extra",
					files = { "pickman/src/alpha.luau" },
				},
			}
			local stale = table.clone(baseInput)
			stale.layers = staleLayers
			local f7 = trace.check(stale)
			t.expect(#f7 > 0 and has(f7[1], "row Commit, commit: table is stale")).toBe(true)
		end
	)
end)
