--!strict
-- c0330: a ticket captured with only the template under `## Solution` has no S claims and is not refused.
-- Pure: claims, the skeleton and the check run over texts, as tests/tooling/trace.spec does.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local STUB_SOLUTION = "## Solution\n<!-- The approach in one paragraph. -->\n"
local PROBLEM = "## Problem\n- Alpha is missing.\n- Reload resets the score.\n"
local AC = "## Acceptance criteria\n- AC1: Alpha shows.\n- AC2: Score persists.\n"

local function capture(problem: string, solution: string): string
	return `---\nid: c0010\n---\n\n# c0010: Alpha\n\n{problem}\n{solution}`
end

local function issue(captured: string, doc: string?): trace.IssueDoc
	local docText = doc or (captured .. "\n## Design\nDo it.\n\n" .. AC)
	return {
		id = "c0010",
		docPath = "pickman/.tracker/issues/active/c0010/c0010.md",
		checkPath = "pickman/.tracker/issues/active/c0010/check.sh",
		dirPath = "pickman/.tracker/issues/active/c0010",
		home = "pickman",
		capturedText = captured,
		docText = docText,
		checkText = nil,
		resultsPath = "pickman/.tracker/issues/active/c0010/results.txt",
		resultsText = "",
	}
end

local function ids(claims: { trace.Claim }): { string }
	local out: { string } = {}
	for _, c in claims do
		table.insert(out, c.id)
	end
	return out
end

return t.spec("c0330: trace takes claims from a stub capture's Problem", function(it)
	it("AC1: a Solution of only the template, empty or absent yields no S claim and no refusal", function()
		local variants = {
			capture(PROBLEM, STUB_SOLUTION),
			capture(PROBLEM, "## Solution\n\n"),
			capture(PROBLEM, "## Solution\n<!-- a comment\n     over two lines -->\n"),
			capture(PROBLEM, ""),
		}
		for _, captured in variants do
			local claims, errs = trace.deriveClaims({ issue(captured) })
			t.expect(errs).toEqual({})
			t.expect(ids(claims)).toEqual({ "c0010:P1", "c0010:P2", "c0010:AC1", "c0010:AC2" })
			t.expect(claims[1].rowLabel).toBe("c0010:P1: Alpha is missing.")
		end
	end)

	it(
		"AC2: a Solution with outcomes still gets one S claim per outcome, in a raft with a stub ticket",
		function()
			local real = issue(capture(PROBLEM, "## Solution\n- Compute alpha.\n- Persist it.\n"))
			local stub = issue(capture(PROBLEM, STUB_SOLUTION))
			stub.id = "c0020"
			stub.docText = string.gsub(stub.docText, "c0010", "c0020") :: string
			stub.capturedText = string.gsub(stub.capturedText, "c0010", "c0020") :: string
			local claims, errs = trace.deriveClaims({ real, stub })
			t.expect(errs).toEqual({})
			t.expect(ids(claims)).toEqual({
				"c0010:P1",
				"c0010:P2",
				"c0010:S1",
				"c0010:S2",
				"c0010:AC1",
				"c0010:AC2",
				"c0020:P1",
				"c0020:P2",
				"c0020:AC1",
				"c0020:AC2",
			})
		end
	)

	it(
		"AC3: a captured document with no Problem outcome, or no acceptance criteria, is still refused",
		function()
			local noProblemStub = issue(capture("## Problem\n<!-- comment only -->\n", STUB_SOLUTION))
			local _, errP = trace.deriveClaims({ noProblemStub })
			t.expect(#errP == 1 and has(errP[1], "ticket c0010 is missing captured ## Problem")).toBe(true)

			local noProblemSolution = issue(capture("## Problem\n", "## Solution\nDo it.\n"))
			local _, errPS = trace.deriveClaims({ noProblemSolution })
			t.expect(#errPS == 1 and has(errPS[1], "ticket c0010 is missing captured ## Problem")).toBe(true)

			local noAc = issue(
				capture(PROBLEM, STUB_SOLUTION),
				capture(PROBLEM, STUB_SOLUTION) .. "\n## Acceptance criteria\n"
			)
			local _, errAc = trace.deriveClaims({ noAc })
			t.expect(#errAc == 1 and has(errAc[1], "ticket c0010 is missing ## Acceptance criteria"))
				.toBe(true)
		end
	)

	it(
		"AC4: the skeleton has no S rows for a stub ticket, and the check expects none and reports no Solution refusal",
		function()
			local stub = issue(capture(PROBLEM, STUB_SOLUTION))
			local claims = trace.deriveClaims({ stub })
			local skeleton = trace.skeleton("R0010", "deadbeef", claims, {})
			t.expect(has(skeleton, "c0010:P1")).toBe(true)
			t.expect(has(skeleton, "c0010:AC2")).toBe(true)
			t.expect(has(skeleton, "c0010:S")).toBe(false)

			local spec = "pickman/tests/unit/alpha.spec.luau"
			local checkPath = stub.checkPath
			local row = function(id: string): string
				return `| {id} | {stub.docPath}:1 | {spec}:3 :: computes alpha | none |`
			end
			local tableText = table.concat({
				"# Trace: R0010",
				"",
				"Commit: deadbeef",
				"",
				"## Claims",
				"",
				"| claim | design | test | code |",
				"|---|---|---|---|",
				row("c0010:P1"),
				row("c0010:P2"),
				row("c0010:AC1"),
				row("c0010:AC2"),
				"",
				"## Source files",
				"",
				"| file | claims |",
				"|---|---|",
				"",
			}, "\n")
			local specText =
				'return t.spec("alpha", function(it)\n\tit("computes alpha", function() end)\nend)\n'
			stub.resultsText = trace.renderResults({ { spec = spec, cases = { "computes alpha" } } })
			local input: trace.CheckInput = {
				raftId = "R0010",
				raftDir = "pickman/.tracker/rafts/active/R0010",
				tableText = tableText,
				layers = {
					{
						name = "R0010/1/c0010",
						issue = "c0010",
						title = "alpha",
						base = "main0",
						tip = "deadbeef",
						stackedOnBelow = true,
						commits = {
							{ sha = "deadbeef", parent = "main0", subject = "c0010: alpha", files = {} },
						},
					},
				},
				issues = { stub },
				raftDocText = "# R0010\n",
				changedSources = {},
				filesAtCommit = {
					[stub.docPath] = { lines = trace.splitLines(stub.docText) },
					[checkPath] = { lines = { "check" } },
					[spec] = { lines = trace.splitLines(specText) },
					["pickman/.tracker/rafts/active/R0010/review-001.md"] = {
						lines = { "# Review 001", "Verdict: approve" },
					},
				},
			}
			t.expect(trace.check(input)).toEqual({})
		end
	)

	it(
		"AC5: a readied ticket takes its claims from the captured text, not from a Solution the prep wrote",
		function()
			local captured = capture(PROBLEM, STUB_SOLUTION)
			local readied = captured .. "\n## Design\nDo it.\n\n" .. AC
			readied = string.gsub(
				readied,
				"<!%-%- The approach in one paragraph%. %-%->",
				"Prep wrote this Solution paragraph."
			) :: string
			local claims, errs = trace.deriveClaims({ issue(captured, readied) })
			t.expect(errs).toEqual({})
			t.expect(ids(claims)).toEqual({ "c0010:P1", "c0010:P2", "c0010:AC1", "c0010:AC2" })
		end
	)

	it(
		"AC6: the zz-rules trace row and the engine contract state the stub rule, not the old refusal",
		function()
			local rules = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
			local row = string.match(rules, "\n(| trace |[^\n]*)") or ""
			t.expect(row ~= "").toBe(true)
			t.expect(has(row, "only the template under `## Solution`")).toBe(true)
			t.expect(has(row, "is not refused")).toBe(true)
			t.expect(has(row, "missing any fails")).toBe(false)
			local engine = fs.readFile(`{TOP}/z-nile/engine/trace.luau`)
			t.expect(has(engine, "`## Solution` is optional")).toBe(true)
			t.expect(has(engine, "a captured `## Solution`,")).toBe(false)
		end
	)

	it("AC8: a Problem that holds only a Decided-with-the-user line has that line as its claim", function()
		local line = "Decided with the user (2026-11-14): fix the trace first."
		local only = issue(capture(`## Problem\n{line}\n`, STUB_SOLUTION))
		local claims, errs = trace.deriveClaims({ only })
		t.expect(errs).toEqual({})
		t.expect(ids(claims)).toEqual({ "c0010:P1", "c0010:AC1", "c0010:AC2" })
		t.expect(has(claims[1].text, "fix the trace first")).toBe(true)

		-- with an outcome before it, the line still ends the captured part, as before
		local first =
			issue(capture(`## Problem\n- Alpha is missing.\n{line}\n- Added later.\n`, STUB_SOLUTION))
		local claims2 = trace.deriveClaims({ first })
		t.expect(ids(claims2)).toEqual({ "c0010:P1", "c0010:AC1", "c0010:AC2" })
		t.expect(claims2[1].text).toBe("Alpha is missing.")
	end)
end)
