--!strict
-- d0297: a one-time proof, run by check.sh and never promoted (it drives ready, start and finish in a fixture). The
-- gate stops running sequestered specs, and `./zn finish` still records its own ticket's acceptance spec in the
-- layer's results.txt (through --own-acceptance), so a trace cell that cites that spec still passes, as R0103's
-- did. It runs outside the dispatcher's publish broker (the fixture's origin is its own). Fixture: .cache/d0297-finish.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local R = "req" .. "uire"
local PREPARED = "prepared-quiet-copper-falcon"
local PROJECTS = table.concat({
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
local AC = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'

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

local function spec(name: string, case: string): string
	return `--!strict\nlocal t = {R}("@tests/lib/t")\nreturn t.spec("{name}", function(it)\n\tit("{case}", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n`
end

local function doc(front: { string }, body: { string }): string
	return "---\n" .. table.concat(front, "\n") .. "\n---\n\n" .. table.concat(body, "\n") .. "\n"
end

return t.spec("d0297 proof: finish records its own ticket's acceptance spec", function(it)
	it(
		"AC3: finish's results.txt lists the ticket's acceptance spec and its case beside the watched unit spec",
		function()
			-- the runner and its helpers ride in the seed commit, so every later push to the fixture's main is tracker
			-- state (a dispatched step's git refuses any other push to main, even a fixture's)
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["z-nile/projects.toml"] = PROJECTS,
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			}
			local function add(rel: string)
				if fs.isDir(`{TOP}/{rel}`) then
					for _, name in fs.readDir(`{TOP}/{rel}`) do
						add(`{rel}/{name}`)
					end
				else
					seed[rel] = fs.readFile(`{TOP}/{rel}`)
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
				add(rel)
			end
			local f = trackerfix.new("d0297-finish", seed)
			local problem = { "# c0010: alpha module", "", "## Problem", "Alpha value is not computed.", "" }
			local solution = { "## Solution", "Add `pickman/src/alpha.luau`.", "" }
			local captured = table.clone(problem)
			table.move(solution, 1, #solution, #captured + 1, captured)
			local front = {
				"id: c0010",
				"type: chore",
				"title: alpha module",
				"slug: c0010",
				"raft: ",
				"depends_on: []",
				"emergent: false",
				"design: draft",
				"created: 2026-11-15",
				"status: new-quiet-copper-falcon",
			}
			write(f.main, "pickman/.tracker/issues/c0010/c0010.md", doc(front, captured))
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-qm", "tracker: new c0010" })
			front[5] = "raft: R0010"
			front[8] = "design: ready"
			front[10] = `status: {PREPARED}`
			local ready = table.clone(captured)
			for _, line in
				{
					"## Design",
					"Export `{ alpha = 1 }`.",
					"",
					"## Acceptance criteria",
					"- AC1: alpha exists",
					"",
				}
			do
				table.insert(ready, line)
			end
			write(f.main, "pickman/.tracker/issues/c0010/c0010.md", doc(front, ready))
			write(
				f.main,
				"pickman/.tracker/issues/c0010/check.sh",
				AC .. 'check "AC1: alpha exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
			)
			write(f.main, "pickman/.tracker/issues/c0010/acceptance/own.spec.luau", spec("own", "own case"))
			write(
				f.main,
				"pickman/.tracker/rafts/R0010/R0010.md",
				doc({
					"id: R0010",
					"type: chore",
					"title: one ticket",
					"slug: one-ticket",
					"single: true",
					"issues: [c0010]",
					"design: ready",
					"created: 2026-11-15",
					`status: {PREPARED}`,
				}, { "# R0010: one ticket", "", "## Order & dependencies", "c0010", "" })
			)
			write(f.main, "pickman/.tracker/rafts/R0010/check.sh", AC .. 'check "RC1: ok" true\nfinish\n')
			seal.stamp(f.main, "d0297-finish")
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-qm", "prep R0010" })
			fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })

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
			-- the fixture publishes to its own origin, never through a dispatcher's broker
			local env =
				{ PATH = `{bin}:{process.env.PATH or ""}`, ZN_PUBLISH_BROKER = "", ZN_PUBLISH_TOKEN = "" }
			local function zn(cwd: string, args: { string }, extra: { [string]: string }?): string
				local runEnv = table.clone(env)
				local more: { [string]: string } = extra or {}
				for k, v in more do
					runEnv[k] = v
				end
				local r = trackerfix.tr(f, cwd, args, runEnv)
				if not r.ok then
					error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
				end
				return r.stdout
			end
			zn(f.main, { "ready", "R0010" })
			local wt = (string.gsub(zn(f.main, { "worktree", "R0010" }), "%s+$", ""))
			zn(wt, { "start", "R0010" })
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
			write(wt, "pickman/tests/unit/alpha.spec.luau", spec("alpha", "computes alpha"))
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-qm", "c0010 implementation" })
			local out = zn(wt, { "finish", "c0010" }, { PICKMAN_DONE_GATE = "1" })
			t.expect(has(out, "affected specs are skipped")).toBe(false)
			local results =
				fixture.git(wt, { "show", "HEAD:pickman/.tracker/issues/active/c0010/results.txt" })
			t.expect(results).toBe(table.concat({
				"pickman/.tracker/issues/active/c0010/acceptance/own.spec.luau",
				"\town case",
				"pickman/tests/unit/alpha.spec.luau",
				"\tcomputes alpha",
			}, "\n"))
		end
	)
end)
