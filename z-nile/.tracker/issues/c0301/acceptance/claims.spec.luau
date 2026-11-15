--!strict
-- c0301: the "None." of an empty `### Judged` or `### Observed` subsection is no claim. Pure: claims and the check
-- run over texts, as tests/tooling/trace.spec does.
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local CAPTURED =
	"---\nid: c0010\n---\n\n# c0010: Alpha\n\n## Problem\nAlpha is missing.\n\n## Solution\n<!-- x -->\n"
local DOC_PATH = "pickman/.tracker/issues/active/c0010/c0010.md"
local CHECK_PATH = "pickman/.tracker/issues/active/c0010/check.sh"

local function issue(acSection: string): trace.IssueDoc
	return {
		id = "c0010",
		docPath = DOC_PATH,
		checkPath = CHECK_PATH,
		dirPath = "pickman/.tracker/issues/active/c0010",
		home = "pickman",
		capturedText = CAPTURED,
		docText = CAPTURED
			.. "\n## Design\nDo it.\n\n## Acceptance criteria\n"
			.. acSection
			.. "\n## Implementation steps\n1. Go.\n",
		checkText = nil,
		resultsPath = "pickman/.tracker/issues/active/c0010/results.txt",
		resultsText = "",
	}
end

local function acIds(acSection: string): { string }
	local claims, errs = trace.deriveClaims({ issue(acSection) })
	t.expect(errs).toEqual({})
	local out: { string } = {}
	for _, c in claims do
		if c.kind == "AC" then
			table.insert(out, `{c.id}={c.text}`)
		end
	end
	return out
end

local CHECKED = "### Checked\n- AC1: Alpha shows.\n- AC2: Alpha persists.\n\n"
local JUDGED_TEMPLATE =
	"### Judged\n<!-- Only if genuinely subjective. JCn: statement + rubric (what pass/fail looks like).\n     Ruled on by the adversarial code reviewer. -->\n"

return t.spec("c0301: an empty Judged or Observed subsection derives no claim", function(it)
	it("AC1: a Judged or Observed body of only None. derives no claim, in each spelling", function()
		local spellings = { "None.", "None", "none.", "NONE", "(none)", "- None.", "* None." }
		for _, word in spellings do
			local ids = acIds(CHECKED .. `### Judged\n{word}\n\n### Observed\n{word}\n`)
			t.expect(ids).toEqual({ "c0010:AC1=Alpha shows.", "c0010:AC2=Alpha persists." })
		end
		-- the template's comment above the None. is not part of the body
		t.expect(acIds(CHECKED .. JUDGED_TEMPLATE .. "None.\n\n### Observed\n<!-- steps -->\nNone.\n"))
			.toEqual({
				"c0010:AC1=Alpha shows.",
				"c0010:AC2=Alpha persists.",
			})
		-- each heading on its own: Judged empty, Observed real; Observed empty, Judged real
		t.expect(acIds(CHECKED .. "### Judged\nNone.\n\n### Observed\n- OC1: Open Studio and look.\n"))
			.toEqual({
				"c0010:AC1=Alpha shows.",
				"c0010:AC2=Alpha persists.",
				"c0010:AC4=OC1: Open Studio and look.",
			})
		t.expect(acIds(CHECKED .. "### Judged\n- JC1: It reads well.\n\n### Observed\nNone.\n")).toEqual({
			"c0010:AC1=Alpha shows.",
			"c0010:AC2=Alpha persists.",
			"c0010:AC3=JC1: It reads well.",
		})
	end)

	it(
		"AC1: every other claim keeps the number it had before, so no row of an old table moves to another claim",
		function()
			-- AC3 (the Judged None.) is gone; the Observed criterion keeps AC4, it is not renumbered AC3
			local ids = acIds(CHECKED .. "### Judged\nNone.\n\n### Observed\n- Walk the maze.\n")
			t.expect(ids)
				.toEqual({ "c0010:AC1=Alpha shows.", "c0010:AC2=Alpha persists.", "c0010:AC4=Walk the maze." })
		end
	)

	it(
		"AC1: a None. that is not the whole body of a Judged or Observed subsection is still a claim",
		function()
			-- under Checked
			t.expect(acIds("### Checked\n- AC1: Alpha shows.\n\nNone.\n\n### Judged\nNone.\n")).toEqual({
				"c0010:AC1=Alpha shows.",
				"c0010:AC2=None.",
			})
			t.expect(acIds("### Checked\nNone.\n\n### Observed\n- OC1: Look.\n")).toEqual({
				"c0010:AC1=None.",
				"c0010:AC2=OC1: Look.",
			})
			-- with a reason after it
			t.expect(acIds(CHECKED .. "### Judged\nNone. The playtest is f0029 OC1.\n")).toEqual({
				"c0010:AC1=Alpha shows.",
				"c0010:AC2=Alpha persists.",
				"c0010:AC3=None. The playtest is f0029 OC1.",
			})
			t.expect(acIds(CHECKED .. "### Observed\nNone: no runtime change.\n")).toEqual({
				"c0010:AC1=Alpha shows.",
				"c0010:AC2=Alpha persists.",
				"c0010:AC3=None: no runtime change.",
			})
			-- beside another paragraph in the same subsection
			t.expect(acIds(CHECKED .. "### Observed\nNone.\n\nOpen Studio and look.\n")).toEqual({
				"c0010:AC1=Alpha shows.",
				"c0010:AC2=Alpha persists.",
				"c0010:AC3=None.",
				"c0010:AC4=Open Studio and look.",
			})
			-- under a heading that only starts like one of the two
			t.expect(acIds(CHECKED .. "### Judged criteria\nNone.\n")).toEqual({
				"c0010:AC1=Alpha shows.",
				"c0010:AC2=Alpha persists.",
				"c0010:AC3=None.",
			})
		end
	)

	it(
		"AC1: a ticket whose only criteria are empty Judged and Observed subsections is refused as having none",
		function()
			local _, errs =
				trace.deriveClaims({ issue("### Checked\n\n### Judged\nNone.\n\n### Observed\nNone.\n") })
			t.expect(has(errs, "ticket c0010 is missing ## Acceptance criteria")).toBe(true)
		end
	)

	it("AC1: extractAcs reads the criteria deriveClaims makes claims of", function()
		local section = CHECKED .. "### Judged\nNone.\n\n### Observed\n- OC1: Look.\n"
		t.expect(trace.extractAcs(section))
			.toEqual({ "AC1: Alpha shows.", "AC2: Alpha persists.", "OC1: Look." })
		t.expect(trace.extractAcs("### Judged\nNone.\n\n### Observed\nNone.\n")).toEqual({})
	end)

	it("AC1: the check wants no row for a None. and refuses one that names it", function()
		local doc = issue(CHECKED .. "### Judged\nNone.\n\n### Observed\nNone.\n")
		doc.checkText = 'source "ac.sh"\ncheck "AC1: Alpha shows" true\nfinish\n'
		local files: { [string]: trace.FileMeta } = {
			[DOC_PATH] = { lines = trace.splitLines(doc.docText) },
			[CHECK_PATH] = { lines = trace.splitLines(doc.checkText :: string) },
		}
		local rows = {
			`| c0010:P1 | {DOC_PATH}:7 | {CHECK_PATH}:2 | none |`,
			`| c0010:AC1 | {DOC_PATH}:7 | {CHECK_PATH}:2 | none |`,
			`| c0010:AC2 | {DOC_PATH}:7 | {CHECK_PATH}:2 | none |`,
		}
		local function tableOf(extra: { string }): string
			local lines = {
				"# Trace: R0010",
				"",
				"Commit: abc",
				"",
				"## Claims",
				"",
				"| claim | design | test | code |",
				"|---|---|---|---|",
			}
			for _, r in rows do
				table.insert(lines, r)
			end
			for _, r in extra do
				table.insert(lines, r)
			end
			for _, r in { "", "## Source files", "", "| file | claims |", "|---|---|", "" } do
				table.insert(lines, r)
			end
			return table.concat(lines, "\n")
		end
		local function check(text: string): { string }
			return trace.check({
				tableText = text,
				expectedCommit = "abc",
				finishedIssues = { c0010 = true },
				issues = { doc },
				raftDocText = "",
				changedSources = {},
				filesAtCommit = files,
			})
		end
		t.expect(check(tableOf({}))).toEqual({})
		local named = check(tableOf({ `| c0010:AC3: None. | {DOC_PATH}:7 | {CHECK_PATH}:2 | none |` }))
		t.expect(named).toEqual({ "row c0010:AC3, claim: unknown claim c0010:AC3" })
	end)
end)
