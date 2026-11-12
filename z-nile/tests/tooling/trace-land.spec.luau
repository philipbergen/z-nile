--!strict
-- Real git for the trace table: finish records results.txt, a second clone checks it,
-- done refuses a per-layer review, and the binding commit follows the finish commit.
-- Fixture under .cache/trace-e2e-github.com.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local R = "req" .. "uire"
local PREPARED = "prepared-quiet-copper-falcon"
local FAST_PROJECTS = table.concat({
	'retired = ["tracker"]',
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "pickman/.tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")

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

return t.spec(
	"finish records results.txt, a second clone checks the table, and done requires a final review",
	function(it)
		it(
			"drives a two-ticket raft through finish results.txt, a fresh second clone --check, final-review requirement, and done",
			function()
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
					["z-nile/projects.toml"] = FAST_PROJECTS,
					["pickman/.tracker/architecture.md"] = fs.readFile(
						`{TOP}/pickman/.tracker/architecture.md`
					),
					["pickman/src/untouched.luau"] = "--!strict\nreturn { untouched = true }\n",
					["pickman/tests/unit/unrun.spec.luau"] = alphaSpec,
					["pickman/tests/unit/unrun.watch.txt"] = "pickman/src/untouched.luau\n",
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
				git(f.main, { "commit", "-qm", "tracker: new c0010 c0020" })

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

				-- Layer 1: c0010 (real spec run via PICKMAN_DONE_GATE=1 writes c0010/results.txt into the layer commit)
				znOk({ "start", "R0010" }, fastDoneEnv)
				write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
				write(wt, "pickman/tests/unit/alpha.spec.luau", alphaSpec)
				write(
					wt,
					"pickman/.tracker/rafts/active/R0010/review-001.md",
					"# Review 001\n\nVerdict: approve\n"
				)
				git(wt, { "add", "-A" })
				git(wt, { "commit", "-qm", "c0010 implementation" })
				local fin1 = znOk({ "finish", "c0010" }, env)
				t.expect(has(fin1, "affected specs are skipped")).toBe(false)
				t.expect(has(fin1, "passed")).toBe(true)
				t.expect(git(wt, { "show", "HEAD:pickman/.tracker/issues/active/c0010/results.txt" }))
					.toBe("pickman/tests/unit/alpha.spec.luau\n\tcomputes alpha")
				require("@tests/lib/seal").layerReview(wt, "c0010") -- c0248: the layer is complete before the next one starts

				-- Layer 2: c0020 (real spec run via PICKMAN_DONE_GATE=1 writes c0020/results.txt into the layer commit)
				znOk({ "start", "R0010" }, fastDoneEnv)
				write(wt, "pickman/src/beta.luau", "--!strict\nreturn { beta = 2 }\n")
				write(wt, "pickman/tests/unit/beta.spec.luau", betaSpec)
				git(wt, { "add", "-A" })
				git(wt, { "commit", "-qm", "c0020 implementation" })
				local fin2 = znOk({ "finish", "c0020" }, env)
				t.expect(has(fin2, "affected specs are skipped")).toBe(false)
				t.expect(has(fin2, "passed")).toBe(true)
				t.expect(git(wt, { "show", "HEAD:pickman/.tracker/issues/active/c0020/results.txt" }))
					.toBe("pickman/tests/unit/beta.spec.luau\n\tcomputes beta")
				require("@tests/lib/seal").layerReview(wt, "c0020")

				local topFinishSha = git(wt, { "rev-parse", "HEAD~1" }) -- HEAD is the layer's review commit

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

				-- 2. Filled table committed on top of the finish commit
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
				git(wt, { "add", tracePath })
				git(wt, { "commit", "-qm", "R0010: trace" })
				git(wt, { "push", "-q" })

				-- 3. ./zn done is refused when only review-001.md exists (even with a passing trace.md)
				local doneOnlyLayerReview = zn({ "done", "R0010" }, fastDoneEnv)
				t.expect(doneOnlyLayerReview.ok).toBe(false)
				t.expect(has(doneOnlyLayerReview.stderr, "no final-review-NNN.md")).toBe(true)

				-- 4. Commit final-review-001.md on the top layer and push
				write(
					wt,
					"pickman/.tracker/rafts/active/R0010/final-review-001.md",
					"# Review 001: R0010 (final mode)\n\nVerdict: approve\n"
				)
				git(wt, { "add", "pickman/.tracker/rafts/active/R0010/final-review-001.md" })
				git(wt, { "commit", "-qm", "R0010: final-review-001" })
				git(wt, { "push", "-q" })
				local reviewedTip = git(wt, { "rev-parse", "HEAD" })

				-- 5. Fresh second clone of origin that has never run a spec:
				--    ./zn trace R0010 --check passes on the good table, and fails on the unrun spec, unrun case, and stale commit
				local clone2 = `{f.base}/clone2`
				local cloned = process.exec("git", { "clone", "-q", f.origin, clone2 })
				if not cloned.ok then
					error(`git clone clone2 failed: {cloned.stderr}`)
				end
				git(clone2, { "checkout", "-q", "-B", "R0010/2/c0020", "origin/R0010/2/c0020" })
				t.expect(fs.isFile(`{clone2}/.claude/.znile_tests.sqlite`)).toBe(false)

				local function znClone2(args: { string }): fixture.Result
					return trackerfix.tr(f, clone2, args, fastDoneEnv)
				end

				local passClone2 = znClone2({ "trace", "R0010", "--check" })
				t.expect(passClone2.ok).toBe(true)
				t.expect(has(passClone2.stdout, "ok: R0010")).toBe(true)

				-- Unrun spec on clone2
				write(
					clone2,
					tracePath,
					(
						string.gsub(
							filledPass,
							"pickman/tests/unit/alpha%.spec%.luau:4 :: computes alpha",
							"pickman/tests/unit/unrun.spec.luau:4 :: computes alpha",
							1
						)
					)
				)
				local failUnrunSpecClone2 = znClone2({ "trace", "R0010", "--check" })
				t.expect(failUnrunSpecClone2.ok).toBe(false)
				t.expect(
					has(
						failUnrunSpecClone2.stderr,
						"row c0010:P1, test: pickman/tests/unit/unrun.spec.luau did not run green for ticket c0010"
					)
				).toBe(true)

				-- Unrun case and substring case on clone2
				write(
					clone2,
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
				local failUnrunCaseClone2 = znClone2({ "trace", "R0010", "--check" })
				t.expect(failUnrunCaseClone2.ok).toBe(false)
				t.expect(
					has(
						failUnrunCaseClone2.stderr,
						'row c0010:P1, test: case "never ran" in pickman/tests/unit/alpha.spec.luau did not run green for ticket c0010'
					)
				).toBe(true)

				write(
					clone2,
					tracePath,
					(
						string.gsub(
							filledPass,
							"pickman/tests/unit/alpha%.spec%.luau:4 :: computes alpha",
							"pickman/tests/unit/alpha.spec.luau:4 :: computes",
							1
						)
					)
				)
				local failSubstringClone2 = znClone2({ "trace", "R0010", "--check" })
				t.expect(failSubstringClone2.ok).toBe(false)
				t.expect(
					has(
						failSubstringClone2.stderr,
						'row c0010:P1, test: case "computes" in pickman/tests/unit/alpha.spec.luau did not run green for ticket c0010'
					)
				).toBe(true)
				write(clone2, tracePath, filledPass)

				-- Commit added on top of the table in wt and pushed -> clone2 reports stale
				git(wt, { "commit", "-q", "--allow-empty", "-m", "post-review fix" })
				git(wt, { "push", "-q" })
				local failStaleClone2 = znClone2({ "trace", "R0010", "--check" })
				t.expect(failStaleClone2.ok).toBe(false)
				t.expect(
					has(failStaleClone2.stderr, "row Commit, commit: table is stale")
						and has(failStaleClone2.stderr, "added to R0010/2/c0020 after trace.md")
				).toBe(true)

				-- Reset wt back to reviewedTip and land with ./zn done R0010
				git(wt, { "reset", "--hard", reviewedTip })
				git(wt, { "push", "-q", "--force-with-lease" })
				local doneOk = znOk({ "done", "R0010" }, fastDoneEnv)
				t.expect(has(doneOk, "landed R0010")).toBe(true)
				local bindMsg = git(f.main, { "log", "-1", "--format=%B", "origin/main" })
				t.expect(has(bindMsg, "R0010: bind c0010, c0020")).toBe(true)
				t.expect(has(bindMsg, "Verdict: approve")).toBe(true)
				t.expect(has(bindMsg, "Trace: pickman/.tracker/rafts/done/R0010/trace.md")).toBe(true)
				local subjects = git(
					f.main,
					{ "log", "-5", "--format=%s", "--invert-grep", "--grep=^tracker: review", "origin/main" }
				)
				t.expect(subjects).toBe(table.concat({
					"R0010: bind c0010, c0020",
					"R0010: final-review-001",
					"R0010: trace",
					"c0020: beta module",
					"c0010: alpha module",
				}, "\n"))
			end
		)
	end
)
