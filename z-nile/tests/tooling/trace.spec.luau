--!strict
-- Pure unit tests and a real two-ticket stacked-raft fixture for `./zn trace <R-id> [--check]`,
-- final review (`final-review-NNN.md`), and `./zn done` landing with the trace table.
-- Fixture under .cache/trace-e2e-github.com.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local R = "req" .. "uire"
local PREPARED = "prepared-quiet-copper-falcon"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

return t.spec("trace derives claims, checks the table, and gates done", function(it)
	it("derives stable P, S and AC claims from captured idea and acceptance criteria", function()
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
		local claims = trace.deriveClaims({
			{
				id = "c0010",
				docPath = "pickman/.tracker/issues/active/c0010/c0010.md",
				checkPath = "pickman/.tracker/issues/active/c0010/check.sh",
				dirPath = "pickman/.tracker/issues/active/c0010",
				home = "pickman",
				capturedText = captured1,
				docText = doc1,
				checkText = nil,
			},
		})
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
	end)

	it(
		"pure trace.check catches every missing link, bad file kind, unrun spec, missing source, and stale commit",
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
			local issueDoc: trace.IssueDoc = {
				id = "c0010",
				docPath = "pickman/.tracker/issues/active/c0010/c0010.md",
				checkPath = "pickman/.tracker/issues/active/c0010/check.sh",
				dirPath = "pickman/.tracker/issues/active/c0010",
				home = "pickman",
				capturedText = doc,
				docText = doc,
				checkText = checkSh,
			}
			local files: { [string]: trace.FileMeta } = {
				[issueDoc.docPath] = { lines = trace.splitLines(doc) },
				[issueDoc.checkPath] = { lines = trace.splitLines(checkSh) },
				["pickman/tests/unit/alpha.spec.luau"] = { lines = trace.splitLines(specText) },
				["pickman/tests/unit/unrun.spec.luau"] = { lines = trace.splitLines(specText) },
				["pickman/src/alpha.luau"] = { lines = trace.splitLines(alphaSrc) },
				["pickman/src/untouched.luau"] = { lines = trace.splitLines(untouchedSrc) },
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
				tableText = validTable,
				expectedCommit = "deadbeef",
				staleReason = nil,
				issues = { issueDoc },
				raftDocText = "# R0010\n",
				changedSources = { "pickman/src/alpha.luau" },
				changedSpecs = {
					["pickman/tests/unit/alpha.spec.luau"] = true,
					["pickman/tests/unit/unrun.spec.luau"] = true,
				},
				filesAtCommit = files,
				greenSpecs = {
					["pickman/tests/unit/alpha.spec.luau"] = {
						passed = true,
						cases = { ["computes alpha"] = true },
					},
				},
				finishedIssues = { c0010 = true },
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
						"row c0010:P1, test: pickman/tests/unit/unrun.spec.luau did not run green for this stack"
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

			local stale = table.clone(baseInput)
			stale.staleReason = "commit 123456789abc added to R0010/1/c0010 after trace.md"
			local f7 = trace.check(stale)
			t.expect(#f7 > 0 and has(f7[1], "row Commit, commit: table is stale")).toBe(true)
		end
	)

	it("drives a two-ticket raft through trace, --check failure modes, final review and done", function()
		local checkC0010 = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. 'check "AC1: alpha module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
		local checkC0020 = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. 'check "AC1: beta module exists" test -f "$ZN_ROOT/pickman/src/beta.luau"\nfinish\n'
		local checkRaft = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. 'check "RC1: both modules exist" test -f "$ZN_ROOT/pickman/src/alpha.luau" -a -f "$ZN_ROOT/pickman/src/beta.luau"\nfinish\n'
		local alphaSpec = "--!strict\nlocal t = "
			.. R
			.. '("@tests/lib/t")\nreturn t.spec("alpha", function(it)\n\tit("computes alpha", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		local betaSpec = "--!strict\nlocal t = "
			.. R
			.. '("@tests/lib/t")\nreturn t.spec("beta", function(it)\n\tit("computes beta", function()\n\t\tt.expect(2).toBe(2)\n\tend)\nend)\n'

		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/src/untouched.luau"] = "--!strict\nreturn { untouched = true }\n",
		}
		local f = trackerfix.new("trace-e2e-github.com", seed)
		local function copy(rel: string)
			local parent = string.match(rel, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{f.main}/{parent}`)
			end
			local copied = process.exec("cp", { "-R", `{TOP}/{rel}`, `{f.main}/{rel}` })
			if not copied.ok then
				error(`cp {rel}: {copied.stderr}`)
			end
		end
		for _, rel in
			{
				".luaurc",
				"pickman/.luaurc",
				"pickman/tests/run.luau",
				"pickman/tests/lib",
				"z-nile/tests/run.luau",
				"z-nile/tests/lib",
			}
		do
			copy(rel)
		end

		-- Capture commit on origin/main so `./zn capture` reads the captured Problem and Solution
		local capC0010 = table.concat({
			"---",
			"id: c0010",
			"type: chore",
			"title: alpha module",
			"slug: c0010",
			"raft: ",
			"depends_on: []",
			"emergent: false",
			"design: draft",
			"created: 2026-11-11",
			"status: new-quiet-copper-falcon",
			"---",
			"",
			"# c0010: alpha module",
			"",
			"## Problem",
			"Alpha value is not computed.",
			"",
			"## Solution",
			"Add `pickman/src/alpha.luau` returning the alpha table.",
			"",
		}, "\n")
		local capC0020 = table.concat({
			"---",
			"id: c0020",
			"type: chore",
			"title: beta module",
			"slug: c0020",
			"raft: ",
			"depends_on: [c0010]",
			"emergent: false",
			"design: draft",
			"created: 2026-11-11",
			"status: new-quiet-copper-falcon",
			"---",
			"",
			"# c0020: beta module",
			"",
			"## Problem",
			"- Beta step is missing.",
			"- Optional telemetry hook is not wired.",
			"",
			"## Solution",
			"Add `pickman/src/beta.luau` returning the beta table.",
			"",
		}, "\n")
		write(f.main, "pickman/.tracker/issues/c0010/c0010.md", capC0010)
		write(f.main, "pickman/.tracker/issues/c0020/c0020.md", capC0020)
		git(f.main, { "add", "-A" })
		git(f.main, { "commit", "-qm", "tracker: new (c0010, c0020)" })

		-- Prep and raft on origin/main
		local readyC0010 = table.concat({
			"---",
			"id: c0010",
			"type: chore",
			"title: alpha module",
			"slug: c0010",
			"raft: R0010",
			"depends_on: []",
			"emergent: false",
			"design: ready",
			"created: 2026-11-11",
			`status: {PREPARED}`,
			"---",
			"",
			"# c0010: alpha module",
			"",
			"## Problem",
			"Alpha value is not computed.",
			"",
			"## Solution",
			"Add `pickman/src/alpha.luau` returning the alpha table.",
			"",
			"## Design",
			"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
			"",
			"## Acceptance criteria",
			"- AC1: alpha module exists",
			"",
		}, "\n")
		local readyC0020 = table.concat({
			"---",
			"id: c0020",
			"type: chore",
			"title: beta module",
			"slug: c0020",
			"raft: R0010",
			"depends_on: [c0010]",
			"emergent: false",
			"design: ready",
			"created: 2026-11-11",
			`status: {PREPARED}`,
			"---",
			"",
			"# c0020: beta module",
			"",
			"## Problem",
			"- Beta step is missing.",
			"- Optional telemetry hook is not wired.",
			"",
			"## Solution",
			"Add `pickman/src/beta.luau` returning the beta table.",
			"",
			"## Design",
			"Export `{ beta = 2 }` from `pickman/src/beta.luau`.",
			"",
			"## Acceptance criteria",
			"- AC1: beta module exists",
			"",
		}, "\n")
		local raftDoc = table.concat({
			"---",
			"id: R0010",
			"type: chore",
			"title: two-ticket stack",
			"slug: two-ticket-stack",
			"single: false",
			"issues: [c0010, c0020]",
			"design: ready",
			"created: 2026-11-11",
			`status: {PREPARED}`,
			"---",
			"",
			"# R0010: two-ticket stack",
			"",
			"## Order & dependencies",
			"c0010",
			"c0020",
			"",
		}, "\n")
		write(f.main, "pickman/.tracker/issues/c0010/c0010.md", readyC0010)
		write(f.main, "pickman/.tracker/issues/c0010/check.sh", checkC0010)
		write(f.main, "pickman/.tracker/issues/c0010/acceptance/.gitkeep", "")
		write(f.main, "pickman/.tracker/issues/c0020/c0020.md", readyC0020)
		write(f.main, "pickman/.tracker/issues/c0020/check.sh", checkC0020)
		write(f.main, "pickman/.tracker/issues/c0020/acceptance/.gitkeep", "")
		write(f.main, "pickman/.tracker/rafts/R0010/R0010.md", raftDoc)
		write(f.main, "pickman/.tracker/rafts/R0010/check.sh", checkRaft)
		require("@tests/lib/seal").stamp(f.main, "trace-e2e")
		git(f.main, { "add", "-A" })
		git(f.main, { "commit", "-qm", "prep R0010" })
		git(f.main, { "push", "-q", "origin", "HEAD:main" })

		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			'#!/bin/sh\ncase "$1 $2" in\n'
				.. '  "pr list") echo 1; exit 0 ;;\n'
				.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
				.. '  "pr view") echo main; exit 0 ;;\n'
				.. '  "pr edit") exit 0 ;;\n'
				.. "esac\nexit 0\n"
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		local env = {
			PATH = `{bin}:{process.env.PATH or ""}`,
			PICKMAN_DONE_GATE = "1",
			ZN_MEASURED = "1",
		}
		local fastDoneEnv = {
			PATH = `{bin}:{process.env.PATH or ""}`,
		}

		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })

		local function zn(args: { string }, runEnv: { [string]: string }?): fixture.Result
			return trackerfix.tr(f, wt, args, runEnv or env)
		end
		local function znOk(args: { string }, runEnv: { [string]: string }?): string
			local r = zn(args, runEnv)
			if not r.ok then
				error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
			end
			return (string.gsub(r.stdout, "%s+$", ""))
		end

		-- Layer 1: c0010 (real spec run via PICKMAN_DONE_GATE=1 records green result in SQLite db)
		znOk({ "start", "R0010" })
		write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
		write(wt, "pickman/tests/unit/alpha.spec.luau", alphaSpec)
		write(wt, "pickman/.tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0010 implementation" })
		local fin1 = znOk({ "finish", "c0010" }, env)
		t.expect(has(fin1, "affected specs are skipped")).toBe(false)
		t.expect(has(fin1, "passed")).toBe(true)

		-- Layer 2: c0020 (real spec run via PICKMAN_DONE_GATE=1 records green result in SQLite db)
		znOk({ "start", "R0010" })
		write(wt, "pickman/src/beta.luau", "--!strict\nreturn { beta = 2 }\n")
		write(wt, "pickman/tests/unit/beta.spec.luau", betaSpec)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0020 implementation" })
		local fin2 = znOk({ "finish", "c0020" }, env)
		t.expect(has(fin2, "affected specs are skipped")).toBe(false)
		t.expect(has(fin2, "passed")).toBe(true)

		local topFinishSha = git(wt, { "rev-parse", "HEAD" })

		-- 1. Skeleton printed by ./zn trace R0010
		local skeleton = znOk({ "trace", "R0010" }, fastDoneEnv)
		t.expect(has(skeleton, `Commit: {topFinishSha}`)).toBe(true)
		t.expect(has(skeleton, "| c0010:P1:")).toBe(true)
		t.expect(has(skeleton, "| c0010:S1:")).toBe(true)
		t.expect(has(skeleton, "| c0010:AC1:")).toBe(true)
		t.expect(has(skeleton, "| c0020:P1:")).toBe(true)
		t.expect(has(skeleton, "| c0020:P2:")).toBe(true)
		t.expect(has(skeleton, "| c0020:S1:")).toBe(true)
		t.expect(has(skeleton, "| c0020:AC1:")).toBe(true)
		t.expect(has(skeleton, "| pickman/src/alpha.luau |  |")).toBe(true)
		t.expect(has(skeleton, "| pickman/src/beta.luau |  |")).toBe(true)

		-- 2. ./zn done refused without a table
		local doneNoTable = zn({ "done", "R0010" }, fastDoneEnv)
		t.expect(doneNoTable.ok).toBe(false)
		t.expect(
			has(
				doneNoTable.stderr,
				"no pickman/.tracker/rafts/active/R0010/trace.md: run ./zn trace R0010 and fill the table"
			)
		).toBe(true)

		-- 3. Filled table that passes --check
		local doc1Path = "pickman/.tracker/issues/active/c0010/c0010.md"
		local check1Path = "pickman/.tracker/issues/active/c0010/check.sh"
		local doc2Path = "pickman/.tracker/issues/active/c0020/c0020.md"
		local check2Path = "pickman/.tracker/issues/active/c0020/check.sh"
		local tracePath = "pickman/.tracker/rafts/active/R0010/trace.md"

		local filledPass = table.concat({
			"# Trace: R0010",
			"",
			`Commit: {topFinishSha}`,
			"",
			"## Claims",
			"",
			"| claim | design | test | code |",
			"|---|---|---|---|",
			`| c0010:P1 | {doc1Path}:23 | pickman/tests/unit/alpha.spec.luau:4 :: computes alpha | pickman/src/alpha.luau:2 |`,
			`| c0010:S1 | {doc1Path}:23 | {check1Path}:2 | pickman/src/alpha.luau:2 |`,
			`| c0010:AC1 | {doc1Path}:23 | pickman/tests/unit/alpha.spec.luau:4 :: computes alpha | pickman/src/alpha.luau:2 |`,
			`| c0020:P1 | {doc2Path}:24 | pickman/tests/unit/beta.spec.luau:4 :: computes beta | pickman/src/beta.luau:2 |`,
			`| c0020:P2 | {doc2Path}:24 | {check2Path}:2 | pickman/src/beta.luau:2 |`,
			`| c0020:S1 | {doc2Path}:24 | {check2Path}:2 | pickman/src/beta.luau:2 |`,
			`| c0020:AC1 | {doc2Path}:24 | pickman/tests/unit/beta.spec.luau:4 :: computes beta | pickman/src/beta.luau:2 |`,
			"",
			"## Source files",
			"",
			"| file | claims |",
			"|---|---|",
			"| pickman/src/alpha.luau | c0010:P1, c0010:S1, c0010:AC1 |",
			"| pickman/src/beta.luau | c0020:P1, c0020:P2, c0020:S1, c0020:AC1 |",
			"",
		}, "\n")
		write(wt, tracePath, filledPass)
		local t0 = os.clock()
		local checkPass = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		local checkMs = math.floor((os.clock() - t0) * 1000 + 0.5)
		t.expect(checkPass.ok).toBe(true)
		t.expect(has(checkPass.stdout, "ok: R0010")).toBe(true)

		-- 4a. --check failing: claim removed from the table
		write(wt, tracePath, (string.gsub(filledPass, "| c0020:S1 |[^\n]+\n", "")))
		local failRemovedClaim = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(failRemovedClaim.ok).toBe(false)
		t.expect(has(failRemovedClaim.stderr, "row c0020:S1, claim: missing claim c0020:S1")).toBe(true)

		-- 4b. --check failing: file:line that does not exist
		write(
			wt,
			tracePath,
			(string.gsub(filledPass, "pickman/src/alpha%.luau:2", "pickman/src/alpha.luau:99", 1))
		)
		local failBadLine = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(failBadLine.ok).toBe(false)
		t.expect(has(failBadLine.stderr, "row c0010:P1, code: pickman/src/alpha.luau:99")).toBe(true)

		-- 4c. --check failing: test cell naming a spec that did not run green
		local unrunSpecPath = "pickman/.tracker/issues/active/c0010/acceptance/unrun.spec.luau"
		write(wt, unrunSpecPath, alphaSpec)
		write(
			wt,
			tracePath,
			(
				string.gsub(
					filledPass,
					"pickman/tests/unit/alpha%.spec%.luau:4 :: computes alpha",
					unrunSpecPath .. ":4 :: computes alpha",
					1
				)
			)
		)
		local failUnrunSpecFile = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		fs.removeFile(`{wt}/{unrunSpecPath}`)
		t.expect(failUnrunSpecFile.ok).toBe(false)
		t.expect(
			has(
				failUnrunSpecFile.stderr,
				`row c0010:P1, test: {unrunSpecPath} did not run green for this stack`
			)
		).toBe(true)

		write(
			wt,
			tracePath,
			(
				string.gsub(
					filledPass,
					"pickman/tests/unit/alpha%.spec%.luau:4 :: computes alpha",
					"pickman/tests/unit/alpha.spec.luau:4 :: never ran",
					1
				)
			)
		)
		local failUnrunSpec = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(failUnrunSpec.ok).toBe(false)
		t.expect(
			has(
				failUnrunSpec.stderr,
				'row c0010:P1, test: case "never ran" in pickman/tests/unit/alpha.spec.luau'
			)
		).toBe(true)

		-- 4d. --check failing: changed source file left out
		write(wt, tracePath, (string.gsub(filledPass, "| pickman/src/beta%.luau |[^\n]+\n", "")))
		local failMissingSource = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(failMissingSource.ok).toBe(false)
		t.expect(
			has(
				failMissingSource.stderr,
				"row pickman/src/beta.luau, file: changed source file missing from table"
			)
		).toBe(true)

		-- 4e. --check failing: code cell pointing at a file the stack did not change
		write(
			wt,
			tracePath,
			(string.gsub(filledPass, "pickman/src/beta%.luau:2", "pickman/src/untouched.luau:2", 1))
		)
		local failUnchangedCode = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(failUnchangedCode.ok).toBe(false)
		t.expect(
			has(
				failUnchangedCode.stderr,
				"row c0020:P1, code: pickman/src/untouched.luau was not changed by this stack"
			)
		).toBe(true)

		-- 4f. Claim marked not met: without ruling fails, with human's ruling passes
		local notMetTable = (
			string.gsub(
				filledPass,
				"| c0020:P2 |[^\n]+",
				'| c0020:P2 | not met: "defer telemetry hook to c0090" | - | - |'
			)
		)
		write(wt, tracePath, notMetTable)
		local failNotMetNoRuling = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(failNotMetNoRuling.ok).toBe(false)
		t.expect(
			has(
				failNotMetNoRuling.stderr,
				'row c0020:P2, design: ruling "defer telemetry hook to c0090" is not recorded under ## Open to the human'
			)
		).toBe(true)

		local raftDocPath = "pickman/.tracker/rafts/active/R0010/R0010.md"
		local origRaftDoc = fs.readFile(`{wt}/{raftDocPath}`)
		write(
			wt,
			raftDocPath,
			origRaftDoc
				.. "\n## Open to the human\n- P2: telemetry hook. Answer: out of scope. Decision: defer.\n  Ruled (user, 2026-11-11): defer telemetry hook to c0090.\n"
		)
		local passNotMetWithRuling = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(passNotMetWithRuling.ok).toBe(true)
		t.expect(has(passNotMetWithRuling.stdout, "ok: R0010")).toBe(true)
		write(wt, raftDocPath, origRaftDoc)

		-- 4g. ./zn done refused with a failing table
		write(wt, tracePath, (string.gsub(filledPass, "| c0020:S1 |[^\n]+\n", "")))
		git(wt, { "add", tracePath })
		git(wt, { "commit", "-qm", "R0010: broken trace" })
		git(wt, { "push", "-q" })
		local doneBadTable = zn({ "done", "R0010" }, fastDoneEnv)
		t.expect(doneBadTable.ok).toBe(false)
		t.expect(has(doneBadTable.stderr, "R0010 trace --check failed")).toBe(true)
		t.expect(has(doneBadTable.stderr, "row c0020:S1, claim: missing claim")).toBe(true)

		-- 4h. Commit added to a layer after the table was written -> --check reports stale
		write(wt, tracePath, filledPass)
		git(wt, { "add", tracePath })
		git(wt, { "commit", "-qm", "R0010: valid trace" })
		git(wt, { "commit", "-q", "--allow-empty", "-m", "post-review fix" })
		local failStale = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
		t.expect(failStale.ok).toBe(false)
		t.expect(has(failStale.stderr, "row Commit, commit: table is stale")).toBe(true)
		git(wt, { "reset", "--hard", topFinishSha })
		git(wt, { "push", "-q", "--force-with-lease" })

		-- 4i. ./zn done refused when final review verdict is not approve and has an unruled finding
		write(wt, tracePath, filledPass)
		write(
			wt,
			"pickman/.tracker/rafts/active/R0010/final-review-001.md",
			"# Review 001: R0010 (final mode)\n\n### F1 [high] beta missing guard\nEvidence: beta.luau:2\n\nVerdict: changes\n"
		)
		write(
			wt,
			"pickman/.tracker/rafts/active/R0010/final-refute-001.md",
			"- F1: refuted: guard is in caller\n"
		)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "R0010: final-review-001 unruled" })
		git(wt, { "push", "-q" })
		local doneUnruled = zn({ "done", "R0010" }, fastDoneEnv)
		t.expect(doneUnruled.ok).toBe(false)
		t.expect(has(doneUnruled.stderr, "final-review-001.md")).toBe(true)
		t.expect(has(doneUnruled.stderr, "F1")).toBe(true)

		-- 4j. Final review approves (or human rules), and ./zn done lands with binding commit's Verdict and Trace
		git(wt, { "reset", "--hard", topFinishSha })
		fs.removeFile(`{wt}/pickman/.tracker/rafts/active/R0010/review-001.md`)
		write(wt, tracePath, filledPass)
		write(
			wt,
			"pickman/.tracker/rafts/active/R0010/final-review-001.md",
			"# Review 001: R0010 (final mode)\n\nVerdict: approve\n"
		)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "R0010: final-review-001" })
		git(wt, { "push", "-q", "--force-with-lease" })
		local doneOk = znOk({ "done", "R0010" }, fastDoneEnv)
		t.expect(has(doneOk, "landed R0010")).toBe(true)
		local bindMsg = git(f.main, { "log", "-1", "--format=%B", "origin/main" })
		t.expect(has(bindMsg, "R0010: bind c0010, c0020")).toBe(true)
		t.expect(has(bindMsg, "Verdict: approve")).toBe(true)
		t.expect(has(bindMsg, "Trace: pickman/.tracker/rafts/done/R0010/trace.md")).toBe(true)
		t.expect(checkMs >= 0).toBe(true)
	end)
end)
