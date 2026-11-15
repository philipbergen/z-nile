--!strict
-- c0343 AC1: a finished raft lands through the commands the worker is allowed. The table and the final review are
-- committed with the real `./zn commit`, which also rewrites the raft's spend.md; `./zn trace <R> --check` passes,
-- `./zn work next <R>` asks for the final review and then for done (never for another finish), and `./zn done` lands
-- the raft. A commit after the finish commit that touches a source file still makes the table stale and the layer
-- unfinished, and a layer finished again lands once its table is re-pointed the same way. The fixture's set-up
-- (two tickets, two finished layers, the filled table) is tests/tooling/trace-land's, which commits the table with
-- plain git and so never met the ledger. Fixture under .cache/c0343-commit-land-github.com.
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

return t.spec("c0343 a raft lands with its table and final review committed by ./zn commit", function(it)
	it(
		"AC1: finish, the table and the final review by ./zn commit, trace --check, work next, a late source commit, done",
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
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["pickman/src/untouched.luau"] = "--!strict\nreturn { untouched = true }\n",
				["pickman/tests/unit/unrun.spec.luau"] = alphaSpec,
				["pickman/tests/unit/unrun.watch.txt"] = "pickman/src/untouched.luau\n",
			}
			local f = trackerfix.new("c0343-commit-land-github.com", seed)
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
			require("@tests/lib/seal").stamp(f.main, "c0343-commit-land")
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

			-- the table is committed by the real ./zn commit, which rewrites the raft's spend.md in the same commit
			local spendPath = "pickman/.tracker/rafts/active/R0010/spend.md"
			local function touched(): string
				return git(wt, { "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD" })
			end
			local function nextLine(): string
				return znOk({ "work", "next", "R0010" }, fastDoneEnv)
			end
			znOk({ "commit", "-m", "R0010: trace", "--phase", "deliver" }, fastDoneEnv)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("R0010: trace")
			t.expect(git(wt, { "rev-parse", "HEAD~1" })).toBe(topFinishSha)
			local first = touched()
			t.expect(has(first, tracePath)).toBe(true)
			t.expect(has(first, spendPath)).toBe(true) -- the fixture meets the ledger, as a real raft does
			t.expect(has(first, "/spend.d/")).toBe(true)

			-- the table stands, the top layer is still finished, and the worker is sent to the final review
			local afterTable = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
			t.expect(afterTable.stderr).toBe("")
			t.expect(afterTable.ok).toBe(true)
			local toReview = nextLine()
			t.expect(has(toReview, "./zn finish")).toBe(false)
			t.expect(has(toReview, "Run the final review")).toBe(true)

			-- the final review, committed the same way
			write(
				wt,
				"pickman/.tracker/rafts/active/R0010/final-review-001.md",
				"# Review 001: R0010 (final mode)\n\nVerdict: approve\n"
			)
			znOk({ "commit", "-m", "R0010: final-review-001", "--phase", "code-review" }, fastDoneEnv)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			local second = touched()
			t.expect(has(second, "final-review-001.md")).toBe(true)
			t.expect(has(second, spendPath)).toBe(true)
			local reviewedTip = git(wt, { "rev-parse", "HEAD" })
			local afterReview = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
			t.expect(afterReview.stderr).toBe("")
			t.expect(afterReview.ok).toBe(true)
			local toDone = nextLine()
			t.expect(has(toDone, "./zn finish")).toBe(false)
			t.expect(has(toDone, "Run ./zn done R0010")).toBe(true)

			-- a commit after the finish commit that touches a source file is still refused: the table is stale,
			-- the layer is no longer finished, and done does not land it
			write(wt, "pickman/src/beta.luau", "--!strict\nreturn { beta = 3 }\n")
			znOk({ "commit", "-m", "c0020: a late change" }, fastDoneEnv)
			t.expect(has(touched(), "pickman/src/beta.luau")).toBe(true)
			local late = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
			t.expect(late.ok).toBe(false)
			t.expect(has(late.stderr, "row Commit, commit: table is stale")).toBe(true)
			t.expect(has(late.stderr, "added to R0010/2/c0020 after trace.md")).toBe(true)
			t.expect(has(nextLine(), "Run ./zn finish c0020")).toBe(true)
			local refused = zn({ "done", "R0010" }, fastDoneEnv)
			t.expect(refused.ok).toBe(false)
			t.expect(has(git(f.main, { "ls-remote", "origin", "refs/heads/main" }), topFinishSha)).toBe(false)

			-- back at the reviewed tip the raft could land
			git(wt, { "reset", "-q", "--hard", reviewedTip })
			git(wt, { "push", "-q", "--force-with-lease" })
			t.expect(has(nextLine(), "Run ./zn done R0010")).toBe(true)

			-- a tracker file outside the set (the harvest a review answer adds) reopens the layer, as before;
			-- finish folds it in, the table then names the old finish commit, and re-pointing it with
			-- ./zn commit is enough: R0101's own path
			write(
				wt,
				"pickman/.tracker/rafts/active/R0010/harvest.md",
				"- review-001 F1: one-off: a fixture\n"
			)
			znOk({ "commit", "-m", "R0010: harvest", "--phase", "code-review" }, fastDoneEnv)
			t.expect(has(nextLine(), "Run ./zn finish c0020")).toBe(true)
			znOk({ "finish", "c0020" }, env)
			local refinished = git(wt, { "rev-parse", "HEAD" })
			t.expect(refinished == topFinishSha).toBe(false)
			t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0020: beta module")
			local folded = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
			t.expect(folded.ok).toBe(false)
			t.expect(
				has(
					folded.stderr,
					`table names commit {topFinishSha}, but top layer finish commit is {refinished}`
				)
			).toBe(true)
			write(wt, tracePath, (string.gsub(filledPass, topFinishSha, refinished)))
			znOk({ "commit", "-m", "R0010: trace", "--phase", "deliver" }, fastDoneEnv)
			local third = touched()
			t.expect(has(third, tracePath)).toBe(true)
			t.expect(has(third, spendPath)).toBe(true)
			local repointed = zn({ "trace", "R0010", "--check" }, fastDoneEnv)
			t.expect(repointed.stderr).toBe("")
			t.expect(repointed.ok).toBe(true)
			local last = nextLine()
			t.expect(has(last, "./zn finish")).toBe(false)
			t.expect(has(last, "Run ./zn done R0010")).toBe(true)
			local doneOk = znOk({ "done", "R0010" }, fastDoneEnv)
			t.expect(has(doneOk, "landed R0010")).toBe(true)
			local bindMsg = git(f.main, { "log", "-1", "--format=%B", "origin/main" })
			t.expect(has(bindMsg, "R0010: bind c0010, c0020")).toBe(true)
			t.expect(has(bindMsg, "Verdict: approve")).toBe(true)
			t.expect(has(bindMsg, "Trace: pickman/.tracker/rafts/done/R0010/trace.md")).toBe(true)
			local subjects = git(f.main, { "log", "-4", "--format=%s", "origin/main" })
			t.expect(subjects).toBe(table.concat({
				"R0010: bind c0010, c0020",
				"R0010: trace",
				"c0020: beta module",
				"c0010: alpha module",
			}, "\n"))
		end
	)
end)
