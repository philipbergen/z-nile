--!strict
-- d0333 AC3 to AC5 (real git): a raft finishes its one layer, then commits its trace table, its final review and its
-- final refute with `./zn commit`, as zz-execute Phase 5 says. Every `./zn commit` rewrites the raft's spend.md, which
-- no post-finish rule took before d0333: the layer read as not finished, the table as stale, and `./zn done` refused.
-- Here the layer stays finished, `./zn trace --check` passes and `./zn done` lands, with no plain `git commit` after
-- the finish and no second finish. A post-finish commit of any other file still unfinishes the layer, and with the
-- table and the final review in place `./zn done` refuses for that reason.
-- Fixture under .cache/d0333-commit-land-github.com.
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

local RAFT = "pickman/.tracker/rafts/active/R0010"
local DOC = "pickman/.tracker/issues/active/c0010/c0010.md"
local CHECK = "pickman/.tracker/issues/active/c0010/check.sh"

local f: trackerfix.Fixture
local wt = ""
local finishSha = ""
local env: { [string]: string } = {}
local gateEnv: { [string]: string } = {}

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
-- the files the newest commit changed, one per line
local function changed(): string
	return git(wt, { "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD" })
end
local function table1(commit: string): string
	return table.concat({
		"# Trace: R0010",
		"",
		`Commit: {commit}`,
		"",
		"## Claims",
		"",
		"| claim | design | test | code |",
		"|---|---|---|---|",
		`| c0010:P1 | {DOC}:23 | pickman/tests/unit/alpha.spec.luau:4 :: computes alpha | pickman/src/alpha.luau:2 |`,
		`| c0010:S1 | {DOC}:23 | {CHECK}:2 | pickman/src/alpha.luau:2 |`,
		`| c0010:AC1 | {DOC}:23 | pickman/tests/unit/alpha.spec.luau:4 :: computes alpha | pickman/src/alpha.luau:2 |`,
		"",
		"## Source files",
		"",
		"| file | claims |",
		"|---|---|",
		"| pickman/src/alpha.luau | c0010:P1, c0010:S1, c0010:AC1 |",
		"",
	}, "\n")
end

return t.spec("d0333 a raft lands with ./zn commit after finish", function(it)
	it("sets up a one-ticket raft, finished", function()
		local checkC0010 = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. 'check "AC1: alpha module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
		local checkRaft = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
			.. 'check "RC1: the module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
		local alphaSpec = "--!strict\nlocal t = "
			.. R
			.. '("@tests/lib/t")\nreturn t.spec("alpha", function(it)\n\tit("computes alpha", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["z-nile/projects.toml"] = FAST_PROJECTS,
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		}
		f = trackerfix.new("d0333-commit-land-github.com", seed)
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
			local parent = string.match(rel, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{f.main}/{parent}`)
			end
			local copied = process.exec("cp", { "-R", `{TOP}/{rel}`, `{f.main}/{rel}` })
			if not copied.ok then
				error(`cp {rel}: {copied.stderr}`)
			end
		end
		local function doc(raft: string, design: string, status: string, rest: { string }): string
			local lines = {
				"---",
				"id: c0010",
				"type: chore",
				"title: alpha module",
				"slug: c0010",
				`raft: {raft}`,
				"depends_on: []",
				"emergent: false",
				`design: {design}`,
				"created: 2026-11-11",
				`status: {status}`,
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
			}
			for _, line in rest do
				table.insert(lines, line)
			end
			return table.concat(lines, "\n")
		end
		write(
			f.main,
			"pickman/.tracker/issues/c0010/c0010.md",
			doc("", "draft", "new-quiet-copper-falcon", {})
		)
		git(f.main, { "add", "-A" })
		git(f.main, { "commit", "-qm", "tracker: new c0010" })
		write(
			f.main,
			"pickman/.tracker/issues/c0010/c0010.md",
			doc("R0010", "ready", PREPARED, {
				"## Design",
				"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
				"",
				"## Acceptance criteria",
				"- AC1: alpha module exists",
				"",
			})
		)
		write(f.main, "pickman/.tracker/issues/c0010/check.sh", checkC0010)
		write(f.main, "pickman/.tracker/issues/c0010/acceptance/.gitkeep", "")
		write(
			f.main,
			"pickman/.tracker/rafts/R0010/R0010.md",
			table.concat({
				"---",
				"id: R0010",
				"type: chore",
				"title: one-ticket stack",
				"slug: one-ticket-stack",
				"single: false",
				"issues: [c0010]",
				"design: ready",
				"created: 2026-11-11",
				`status: {PREPARED}`,
				"---",
				"",
				"# R0010: one-ticket stack",
				"",
				"## Order & dependencies",
				"c0010",
				"",
			}, "\n")
		)
		write(f.main, "pickman/.tracker/rafts/R0010/check.sh", checkRaft)
		require("@tests/lib/seal").stamp(f.main, "d0333-commit-land")
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
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		gateEnv = { PATH = env.PATH, PICKMAN_DONE_GATE = "1" }

		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		znOk({ "start", "R0010" })
		write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
		write(wt, "pickman/tests/unit/alpha.spec.luau", alphaSpec)
		write(wt, `{RAFT}/review-001.md`, "# Review 001\n\nVerdict: approve\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0010 implementation" })
		znOk({ "finish", "c0010" }, gateEnv)
		finishSha = git(wt, { "rev-parse", "HEAD" })
		t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0010: alpha module")
		t.expect(has(znOk({ "trace", "R0010" }), `Commit: {finishSha}`)).toBe(true)
		-- c0248: the layer's approved review, committed after the finish (a review file leaves the layer finished)
		require("@tests/lib/seal").layerReview(wt, "c0010")
	end)

	it(
		"AC3: the Verification log committed with ./zn commit before the table leaves the layer finished",
		function()
			-- zz-execute Phase 5 step 1: the issue's log and the raft's "Addressed during execution"
			local doc = fs.readFile(`{wt}/{DOC}`)
			-- appended with no blank line before it: the approved contract hashes the Acceptance criteria section's lines
			write(wt, DOC, doc .. "## Verification log\n- 2026-11-11: check 1/1.\n")
			local raftDoc = fs.readFile(`{wt}/{RAFT}/R0010.md`)
			write(wt, `{RAFT}/R0010.md`, raftDoc .. "\n## Addressed during execution\nNone.\n")
			znOk({ "commit", "-m", "R0010: verification log", "--phase", "deliver", "--time", "1" })
			t.expect(has(changed(), DOC)).toBe(true)
			t.expect(has(changed(), `{RAFT}/spend.md`)).toBe(true)
			t.expect(has(znOk({ "trace", "R0010" }), `Commit: {finishSha}`)).toBe(true)
			t.expect(has(znOk({ "work", "next", "R0010" }), "./zn finish c0010")).toBe(false)
		end
	)

	it(
		"AC3: the trace table committed with ./zn commit leaves the layer finished and the table current",
		function()
			write(wt, `{RAFT}/trace-001.md`, table1(finishSha))
			local out = znOk({ "commit", "-m", "R0010: trace", "--phase", "deliver", "--time", "1" })
			t.expect(has(out, "committed: R0010: trace")).toBe(true)
			t.expect(has(changed(), `{RAFT}/trace-001.md`)).toBe(true)
			-- the commit carries what made the layer unfinished before d0333, and its spend row
			t.expect(has(changed(), `{RAFT}/spend.md`)).toBe(true)
			t.expect(has(changed(), "/spend.d/")).toBe(true)
			t.expect(has(git(wt, { "log", "-1", "--format=%B" }), "Issue: c0010")).toBe(true)
			-- the worker goes on to the final review, not back to finish the layer (c0343's third outcome)
			local nextLine = znOk({ "work", "next", "R0010" })
			t.expect(has(nextLine, "./zn finish c0010")).toBe(false)
			t.expect(has(nextLine, "final-review")).toBe(true)
			-- still finished: the skeleton, not "c0010 is not finished: ./zn finish c0010"
			t.expect(has(znOk({ "trace", "R0010" }), `Commit: {finishSha}`)).toBe(true)
			t.expect(has(znOk({ "trace", "R0010", "--check" }), "ok: R0010")).toBe(true)
		end
	)

	it(
		"AC3: the final review and the final refute committed with ./zn commit leave the table current",
		function()
			write(
				wt,
				`{RAFT}/final-review-001.md`,
				"# Review 001: R0010 (final mode)\n\n### F1 [low] a note\nWhere: x\n\nVerdict: changes\n"
			)
			znOk({
				"commit",
				"-m",
				"R0010: final-review-001",
				"--phase",
				"code-review",
				"--model",
				"m-1",
				"--time",
				"1",
			})
			t.expect(has(changed(), `{RAFT}/final-review-001.md`)).toBe(true)
			t.expect(has(changed(), `{RAFT}/spend.md`)).toBe(true)
			t.expect(has(changed(), "/spend.d/")).toBe(true)
			t.expect(has(znOk({ "trace", "R0010", "--check" }), "ok: R0010")).toBe(true)
			write(
				wt,
				`{RAFT}/final-refute-001.md`,
				"# Final refute 001\n- F1: fixed: noted; consequences: none\n"
			)
			znOk({ "commit", "-m", "R0010: final-refute-001", "--phase", "code-review", "--time", "1" })
			t.expect(has(changed(), `{RAFT}/final-refute-001.md`)).toBe(true)
			t.expect(has(changed(), `{RAFT}/spend.md`)).toBe(true)
			t.expect(has(changed(), "/spend.d/")).toBe(true)
			t.expect(has(znOk({ "trace", "R0010" }), `Commit: {finishSha}`)).toBe(true)
			t.expect(has(znOk({ "trace", "R0010", "--check" }), "ok: R0010")).toBe(true)
			-- absence only: what the line says after a `changes` verdict is d0345's
			t.expect(has(znOk({ "work", "next", "R0010" }), "./zn finish c0010")).toBe(false)
			-- nothing after the finish was made any other way, and the finish commit is the one made before
			t.expect(git(wt, { "log", "--format=%s", `{finishSha}..HEAD` })).toBe(table.concat({
				"R0010: final-refute-001",
				"R0010: final-review-001",
				"R0010: trace",
				"R0010: verification log",
				"tracker: review c0010",
			}, "\n"))
			t.expect(git(wt, { "rev-parse", "HEAD~5" })).toBe(finishSha)
		end
	)

	it("AC5: a ./zn commit of any other file after the finish still unfinishes the layer", function()
		-- with the table and the final review in place, so only the unfinished layer can be what refuses
		local reviewedTip = git(wt, { "rev-parse", "HEAD" })
		write(wt, `{RAFT}/notes.md`, "a file no post-finish rule names\n")
		znOk({ "commit", "-m", "R0010: late notes", "--phase", "deliver", "--time", "1" })
		t.expect(has(changed(), `{RAFT}/notes.md`)).toBe(true)
		local r = zn({ "trace", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "c0010 is not finished")).toBe(true)
		local check = zn({ "trace", "R0010", "--check" })
		t.expect(check.ok).toBe(false)
		t.expect(has(check.stderr .. check.stdout, "table is stale")).toBe(true)
		t.expect(has(znOk({ "work", "next", "R0010" }), "./zn finish c0010")).toBe(true)
		local done = zn({ "done", "R0010" })
		t.expect(done.ok).toBe(false)
		t.expect(has(done.stderr .. done.stdout, "c0010 is not finished")).toBe(true)
		-- back to the reviewed tip, as if that commit was never made
		git(wt, { "reset", "-q", "--hard", reviewedTip })
		git(wt, { "push", "-q", "--force-with-lease" })
		t.expect(has(znOk({ "trace", "R0010", "--check" }), "ok: R0010")).toBe(true)
	end)

	it("AC4: ./zn done lands that stack", function()
		local out = znOk({ "done", "R0010" })
		t.expect(has(out, "landed R0010")).toBe(true)
		t.expect(git(f.main, { "log", "-7", "--format=%s", "origin/main" })).toBe(table.concat({
			"R0010: bind c0010",
			"R0010: final-refute-001",
			"R0010: final-review-001",
			"R0010: trace",
			"R0010: verification log",
			"tracker: review c0010",
			"c0010: alpha module",
		}, "\n"))
		-- the finish commit made before the four commits is the one that landed: no second finish
		t.expect(has(git(f.main, { "log", "-9", "--format=%H", "origin/main" }), finishSha)).toBe(true)
		-- the commits' rows are in the landed issue's ledger
		local rows = git(f.main, {
			"grep",
			"-h",
			"-e",
			"R0010: ",
			"origin/main",
			"--",
			"pickman/.tracker/issues/done/c0010/spend.d",
		})
		t.expect(has(rows, "R0010: verification log")).toBe(true)
		t.expect(has(rows, "R0010: trace")).toBe(true)
		t.expect(has(rows, "R0010: final-review-001")).toBe(true)
		t.expect(has(rows, "R0010: final-refute-001")).toBe(true)
	end)
end)
