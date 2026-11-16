--!strict
-- c0252 AC7 to AC9: the commands behind the landing, on a real two-layer raft in a fixture (a local github-shaped
-- origin, as stack-land.spec builds it) with a fake gh whose `pr view --json statusCheckRollup` answers from a file per
-- layer branch. `./zn land-check` reads the checks, `./zn done` refuses what the dispatcher would not land (and a
-- ZN_DISPATCH environment altogether), and a dispatched `./zn block` leaves a request instead of publishing.
-- Fixture: .cache/c0252-land-cmd-github.com. Cases build on each other.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string, title: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local RAFT =
	`---\nid: R0010\ntype: chore\ntitle: stack\nslug: stack\nsingle: false\nissues: [c0010, c0020]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\nc0020\n`

local f: trackerfix.Fixture
local bin = ""
local wt = ""
local env: { [string]: string } = {}

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	local e = table.clone(env)
	local more: { [string]: string } = extra or {}
	for k, v in more do
		e[k] = v
	end
	return trackerfix.tr(f, wt, args, e)
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end
-- what the fake gh answers for the layer branch `branch`: its head and checks
local function pr(branch: string, state: string, checks: string, head: string?)
	local sha = head or git(f.main, { "rev-parse", `origin/{branch}` })
	fs.writeFile(
		`{bin}/prview-{(string.gsub(branch, "/", "_"))}.json`,
		`\{"state":"OPEN","isDraft":false,"headRefOid":"{sha}","mergeable":"{state}","statusCheckRollup":{checks}}`
	)
end
local PENDING = '[{"name":"static","status":"IN_PROGRESS","conclusion":""}]'
local FAILED = '[{"name":"static","status":"COMPLETED","conclusion":"FAILURE"}]'
local GREEN =
	'[{"name":"static","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"deploy","conclusion":"SKIPPED"}]'
local function checked(extra: { string }): fixture.Result
	local args = { "land-check", "R0010" }
	for _, a in extra do
		table.insert(args, a)
	end
	table.insert(args, "--json") -- last: the flag parser gives a flag the word after it
	return zn(args)
end
local function problems(r: fixture.Result): { string }
	local j: any = serde.decode("json", r.stdout)
	local out: { string } = {}
	for _, p in j.problems do
		table.insert(out, p.code)
	end
	return out
end

return t.spec("c0252 land-check, done and a dispatched block", function(it)
	it(
		"sets up a readied two-layer raft, both layers complete, behind a local github-shaped origin",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["pickman/.tracker/rafts/R0010/R0010.md"] = RAFT,
				["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "alpha"),
				["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = "",
				["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "beta"),
				["pickman/.tracker/issues/c0020/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0020/acceptance/.gitkeep"] = "",
			}
			f = trackerfix.new("c0252-land-cmd-github.com", seed)
			bin = `{f.base}/bin`
			fs.writeDir(bin)
			-- `pr view <branch> --json state,...` answers from prview-<branch>.json (a failure when the file is absent);
			-- every other call is stack-land's stub
			local script = `#!/bin/sh\necho "$*" >> "{f.base}/gh.log"\n`
				.. 'case "$1 $2" in\n'
				.. `  "pr view") case "$*" in *statusCheckRollup*) b=$(printf "%s" "$3" | tr / _); [ -f "{bin}/prview-$b.json" ] && cat "{bin}/prview-$b.json" && exit 0; exit 1 ;; esac; echo main; exit 0 ;;\n`
				.. '  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
				.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
				.. '  "pr edit") exit 0 ;;\n'
				.. "esac\nexit 0\n"
			fs.writeFile(`{bin}/gh`, script)
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			must(trackerfix.tr(f, f.main, { "ready", "R0010" }, env), "ready")
			wt = must(trackerfix.tr(f, f.main, { "worktree", "R0010" }, env), "worktree")
			must(zn({ "start", "R0010" }), "start 1")
			write(wt, "pickman/src/alpha.luau", "alpha\n")
			write(
				wt,
				"pickman/.tracker/rafts/active/R0010/final-review-001.md",
				"# Final Review 001\n\nVerdict: approve\n"
			)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0010 work" })
			must(zn({ "finish", "c0010" }), "finish 1")
			seal.layerReview(wt, "c0010")
			must(zn({ "start", "R0010" }), "start 2")
			write(wt, "pickman/src/beta.luau", "beta\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0020 work" })
			must(zn({ "finish", "c0020" }), "finish 2")
			seal.layerReview(wt, "c0020")
			seal.trace(wt, "R0010")
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0020")
		end
	)

	it(
		"AC7: land-check names a pending check as a wait, a failed one as a block, and passes a green top layer",
		function()
			local top = "R0010/2/c0020"
			pr(top, "MERGEABLE", PENDING)
			local pending = checked({})
			t.expect(pending.code).toBe(1)
			t.expect(problems(pending)).toEqual({ "ci-pending" })
			pr(top, "MERGEABLE", FAILED)
			local failed = checked({})
			t.expect(failed.code).toBe(1)
			t.expect(problems(failed)).toEqual({ "ci-failed" })
			local j: any = serde.decode("json", failed.stdout)
			t.expect(j.problems[1].kind).toBe("block")
			t.expect(j.problems[1].reason).toBe("red-gate")
			t.expect(j.top).toBe(top)
			-- a draft layer pull request whose only check was skipped is green, and the line is readable without --json
			pr(top, "UNKNOWN", GREEN)
			local green = checked({})
			t.expect(green.ok).toBe(true)
			t.expect(problems(green)).toEqual({})
			local text = zn({ "land-check", "R0010" })
			t.expect(text.ok).toBe(true)
		end
	)

	it(
		"AC7: an unreadable pull request, a head that is not the layer tip and a conflict are named, never passed",
		function()
			local top = "R0010/2/c0020"
			fs.removeFile(`{bin}/prview-R0010_2_c0020.json`)
			local gone = checked({})
			t.expect(gone.code).toBe(1)
			t.expect(problems(gone)).toEqual({ "pr-unreadable" })
			pr(top, "MERGEABLE", GREEN, "0000000000000000000000000000000000000000")
			t.expect(problems(checked({}))).toEqual({ "pr-head-moved" })
			pr(top, "CONFLICTING", GREEN)
			t.expect(problems(checked({}))).toEqual({ "pr-conflicting" })
			pr(top, "MERGEABLE", GREEN)
			t.expect(problems(checked({}))).toEqual({})
		end
	)

	it(
		"AC7: --below names the layers under a Layer: the prefix is judged on its own top, and nothing below the first layer",
		function()
			pr("R0010/1/c0010", "MERGEABLE", PENDING)
			local below = checked({ "--below", "c0020" })
			local j: any = serde.decode("json", below.stdout)
			t.expect(j.through).toBe("c0010")
			t.expect(j.top).toBe("R0010/1/c0010")
			t.expect(table.find(problems(below), "ci-pending") ~= nil).toBe(true)
			local none = zn({ "land-check", "R0010", "--below", "c0010", "--json" })
			t.expect(none.ok).toBe(true)
			local k: any = serde.decode("json", none.stdout)
			t.expect(k.through).toBe("")
			local usage = zn({ "land-check", "R0010", "--through", "c0010", "--below", "c0020" })
			t.expect(usage.ok).toBe(false)
			t.expect(has(usage.stderr, "usage: land-check")).toBe(true)
		end
	)

	it("AC8: done is refused while ZN_DISPATCH is set, and lands nothing", function()
		pr("R0010/2/c0020", "MERGEABLE", GREEN)
		local before = git(f.main, { "ls-remote", "origin", "refs/heads/main" })
		local r = zn({ "done", "R0010" }, { ZN_DISPATCH = "1" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "done is refused while ZN_DISPATCH is set")).toBe(true)
		t.expect(has(r.stderr, "the dispatcher lands")).toBe(true)
		t.expect(git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(before)
	end)

	it(
		"AC8: done refuses a stack whose top layer has a failed check, naming the code, and changes nothing",
		function()
			pr("R0010/2/c0020", "MERGEABLE", FAILED)
			local before = git(f.main, { "ls-remote", "origin", "refs/heads/main" })
			local r = zn({ "done", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "R0010 is not ready to land")).toBe(true)
			t.expect(has(r.stderr, "ci-failed (block)")).toBe(true)
			t.expect(git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(before)
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0020")
		end
	)

	it(
		"AC9: under ZN_DISPATCH, block validates the note and leaves a request for the dispatcher, publishing nothing",
		function()
			local dir = "pickman/.tracker/rafts/active/R0010"
			write(
				wt,
				`{dir}/escalation.md`,
				"## Question\nShould c0030 wait for the json library?\n\n## What was tried\nTwo drafts.\n\n## Open findings or error\nF1: no reader.\n\n## Options\n- approve: take the library (recommended)\n- retry: one more round\n- amend-design: redesign it\n"
			)
			local state = `{f.base}/dispatch-state`
			fs.writeDir(state)
			local before = git(f.main, { "ls-remote", "origin", "refs/heads/main" })
			local r = zn(
				{ "block", "R0010", "design-gap", "--layer", "c0020" },
				{ ZN_DISPATCH = "1", ZN_DISPATCH_DIR = state }
			)
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "block requested: R0010 design-gap (layer c0020)")).toBe(true)
			t.expect(fs.readFile(`{state}/block-request`))
				.toBe("item: R0010\nreason: design-gap\nlayer: c0020\n")
			t.expect(git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(before)
			t.expect(fs.isFile(`{wt}/{dir}/escalation.md`)).toBe(true)
			-- the note is still checked: a reason that is not one, and a note without a recommended option, are refused
			local bad = zn({ "block", "R0010", "nonsense" }, { ZN_DISPATCH = "1", ZN_DISPATCH_DIR = state })
			t.expect(bad.ok).toBe(false)
			t.expect(has(bad.stderr, "nonsense is not a reason")).toBe(true)
			fs.removeFile(`{state}/block-request`)
			write(
				wt,
				`{dir}/escalation.md`,
				(string.gsub(fs.readFile(`{wt}/{dir}/escalation.md`), " %(recommended%)", ""))
			)
			local none = zn(
				{ "block", "R0010", "design-gap" },
				{ ZN_DISPATCH = "1", ZN_DISPATCH_DIR = state }
			)
			t.expect(none.ok).toBe(false)
			t.expect(fs.isFile(`{state}/block-request`)).toBe(false)
			fs.removeFile(`{wt}/{dir}/escalation.md`)
		end
	)

	it("AC8: a check still running is a person's to judge: done goes on, and lands the bind", function()
		pr("R0010/2/c0020", "MERGEABLE", PENDING)
		local landed = must(zn({ "done", "R0010" }), "done")
		t.expect(has(landed, "landed R0010")).toBe(true)
		t.expect(has(git(f.main, { "log", "-1", "--format=%s", "origin/main" }), "R0010: bind c0010, c0020"))
			.toBe(true)
	end)
end)
