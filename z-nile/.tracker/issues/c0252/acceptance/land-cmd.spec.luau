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

local function issue(id: string, title: string, raft: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft or "R0010"}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
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
local function pr(branch: string, mergeable: string, checks: string, head: string?, draft: boolean?)
	local sha = head or git(f.main, { "rev-parse", `origin/{branch}` })
	fs.writeFile(
		`{bin}/prview-{(string.gsub(branch, "/", "_"))}.json`,
		`\{"state":"OPEN","isDraft":{draft == true},"headRefOid":"{sha}","mergeable":"{mergeable}","statusCheckRollup":{checks}}`
	)
end
local PENDING = '[{"name":"static","status":"IN_PROGRESS","conclusion":""}]'
local FAILED = '[{"name":"static","status":"COMPLETED","conclusion":"FAILURE"}]'
local GREEN =
	'[{"name":"static","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"deploy","conclusion":"SKIPPED"}]'
local DEPLOY_SKIPPED = '[{"name":"deploy","conclusion":"SKIPPED"}]'
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
				-- an old single-branch raft: readied, no layer branch ever (as R0061 and R0084 are)
				["pickman/.tracker/rafts/R0020/R0020.md"] = `---\nid: R0020\ntype: chore\ntitle: old\nslug: old\nsingle: false\nissues: [c0030]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0020\n\n## Order & dependencies\nc0030\n`,
				["pickman/.tracker/rafts/R0020/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "gamma", "R0020"),
				["pickman/.tracker/issues/c0030/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0030/acceptance/.gitkeep"] = "",
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
			must(trackerfix.tr(f, f.main, { "ready", "R0020" }, env), "ready R0020")
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
		"AC7: land-check names a pending check as a wait, a failed one as a redo, and passes a green top layer",
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
			t.expect(j.problems[1].kind).toBe("redo")
			t.expect(j.problems[1].reason).toBe("red-gate")
			t.expect(j.top).toBe(top)
			-- a draft layer pull request whose only check was skipped is green (its mergeable is UNKNOWN while it is a draft)
			pr(top, "UNKNOWN", DEPLOY_SKIPPED, nil, true)
			local draft = checked({})
			t.expect(draft.ok).toBe(true)
			t.expect(problems(draft)).toEqual({})
			-- a non-draft one that GitHub is still computing, and one with no check registered yet, are waits
			pr(top, "UNKNOWN", GREEN)
			t.expect(problems(checked({}))).toEqual({ "pr-mergeable-unknown" })
			pr(top, "MERGEABLE", "[]")
			t.expect(problems(checked({}))).toEqual({ "ci-none" })
			pr(top, "MERGEABLE", GREEN)
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
			-- an answer that is not JSON is the pull request unread, not a pass
			fs.writeFile(`{bin}/prview-R0010_2_c0020.json`, "garbage")
			t.expect(problems(checked({}))).toEqual({ "pr-unreadable" })
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

	it("AC7: an old single-branch raft gets an explicit no-layers answer, not a problem list", function()
		local text = trackerfix.tr(f, f.main, { "land-check", "R0020" }, env)
		t.expect(text.code).toBe(2)
		t.expect(has(text.stdout, "R0020 has no layer branches")).toBe(true)
		t.expect(has(text.stdout, "a human's merge")).toBe(true)
		local asJson = trackerfix.tr(f, f.main, { "land-check", "R0020", "--json" }, env)
		t.expect(asJson.code).toBe(2)
		local j: any = serde.decode("json", asJson.stdout)
		t.expect(j.layered).toBe(false)
		t.expect(#j.problems).toBe(0)
	end)

	it(
		"AC8: in a session that holds the agent's credential, ZN_DISPATCH or ZN_HEADLESS, done runs every check, writes a land request and pushes nothing",
		function()
			local before = git(f.main, { "ls-remote", "origin", "refs/heads/main" })
			local request = `{f.main}/.cache/land-requests/R0010`
			local tip = git(f.main, { "rev-parse", "origin/R0010/2/c0020" })
			for _, marker in { "ZN_DISPATCH", "ZN_HEADLESS" } do
				pr("R0010/2/c0020", "MERGEABLE", GREEN)
				local r = zn({ "done", "R0010" }, { [marker] = "1" })
				t.expect(r.ok).toBe(true)
				t.expect(has(r.stdout, "R0010 passes every check and waits for a lander")).toBe(true)
				t.expect(has(r.stdout, "Nothing was pushed")).toBe(true)
				t.expect(has(r.stdout, "./zn lander R0010")).toBe(true)
				t.expect(fs.readFile(request)).toBe(`item: R0010\ntip: {tip}\nthrough: \nworktree: {wt}\n`)
				t.expect(git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(before)
				fs.removeFile(request)
				-- a check that fails is refused in that session too, and leaves no request
				pr("R0010/2/c0020", "MERGEABLE", PENDING)
				local pending = zn({ "done", "R0010" }, { [marker] = "1" })
				t.expect(pending.ok).toBe(false)
				t.expect(has(pending.stderr, "ci-pending (wait)")).toBe(true)
				t.expect(fs.isFile(request)).toBe(false)
			end
			t.expect(git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(before)
		end
	)

	it(
		"AC21: the lander is refused in a session that holds the agent's credential, and with no request it lands nothing",
		function()
			for _, marker in { "ZN_DISPATCH", "ZN_HEADLESS" } do
				local r = trackerfix.tr(
					f,
					f.main,
					{ "lander" },
					(function()
						local e = table.clone(env)
						e[marker] = "1"
						return e
					end)()
				)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "lander is refused in a session that holds the agent's credential"))
					.toBe(true)
			end
			local none = trackerfix.tr(f, f.main, { "lander" }, env)
			t.expect(none.ok).toBe(true)
			t.expect(has(none.stdout, "no land request waits")).toBe(true)
		end
	)

	it(
		"AC8: done refuses every problem the dispatcher would not land on, a wait included, naming the codes, and changes nothing",
		function()
			local top = "R0010/2/c0020"
			local before = git(f.main, { "ls-remote", "origin", "refs/heads/main" })
			local cases: { { branchState: string, checks: string, code: string, gone: boolean? } } = {
				{ branchState = "MERGEABLE", checks = FAILED, code = "ci-failed (redo)" },
				{ branchState = "MERGEABLE", checks = PENDING, code = "ci-pending (wait)" },
				{ branchState = "MERGEABLE", checks = "[]", code = "ci-none (wait)" },
				{ branchState = "UNKNOWN", checks = GREEN, code = "pr-mergeable-unknown (wait)" },
				{ branchState = "MERGEABLE", checks = GREEN, code = "pr-unreadable (wait)", gone = true },
			}
			for _, c in cases do
				if c.gone then
					fs.removeFile(`{bin}/prview-R0010_2_c0020.json`)
				else
					pr(top, c.branchState, c.checks)
				end
				local r = zn({ "done", "R0010" })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "R0010 is not ready to land")).toBe(true)
				t.expect(has(r.stderr, c.code)).toBe(true)
				t.expect(git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(before)
				t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0020")
			end
		end
	)

	it(
		"AC17: zn -C runs this checkout's engine against another worktree of the same repository and refuses a directory of another repository",
		function()
			local ok = trackerfix.tr(f, f.main, { "-C", wt, "land-check", "R0010", "--json" }, env)
			local j: any = serde.decode("json", ok.stdout)
			t.expect(j.top).toBe("R0010/2/c0020")
			local other = fixture.exec(
				f.main,
				"bash",
				{ "zn", "-C", TOP, "land-check", "R0010" },
				{ env = env }
			)
			t.expect(other.ok).toBe(false)
			t.expect(has(other.stderr, "is not a worktree of this repository")).toBe(true)
			local missing = fixture.exec(
				f.main,
				"bash",
				{ "zn", "-C", `{f.base}/nowhere`, "land-check", "R0010" },
				{ env = env }
			)
			t.expect(missing.ok).toBe(false)
			t.expect(has(missing.stderr, "is not a directory")).toBe(true)
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
			local tip = git(f.main, { "rev-parse", "origin/R0010/2/c0020" })
			t.expect(fs.readFile(`{state}/block-request`))
				.toBe(`item: R0010\nreason: design-gap\nlayer: c0020\ntip: {tip}\n`)
			-- the validated note travels with the request: the dispatcher restores it when it files the block
			t.expect(fs.readFile(`{state}/block-note.md`)).toBe(fs.readFile(`{wt}/{dir}/escalation.md`))
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

	it(
		"AC24: land-check reads c0251's frontier floor from the landing's own folders: a review off the [review] frontier list is the problem no-frontier-review (kind review), a listed one clears it, and done names it once",
		function()
			local top = "R0010/2/c0020"
			pr(top, "MERGEABLE", GREEN)
			local list = `{wt}/pickman/.tracker/rafts/active/R0010/.models.toml`
			-- the list is a fixture detail kept out of the tree (done needs a clean one)
			local exclude = git(wt, { "rev-parse", "--git-path", "info/exclude" })
			local excludePath = if string.sub(exclude, 1, 1) == "/" then exclude else `{wt}/{exclude}`
			fs.writeDir(string.match(excludePath, "^(.*)/[^/]+$") :: string)
			fs.writeFile(
				excludePath,
				(if fs.isFile(excludePath) then fs.readFile(excludePath) else "") .. "\n.models.toml\n"
			)
			-- the layers' reviews ran on claude-opus-5-5 (seal.layerReview): a list without it is unmet
			write(
				wt,
				"pickman/.tracker/rafts/active/R0010/.models.toml",
				'[review]\nfrontier = ["claude-fable-5-2"]\n'
			)
			local unmet = checked({})
			t.expect(unmet.code).toBe(1)
			t.expect(problems(unmet)).toEqual({ "no-frontier-review" })
			local j: any = serde.decode("json", unmet.stdout)
			t.expect(j.problems[1].kind).toBe("review")
			t.expect(j.problems[1].reason).toBe("needs-decision")
			t.expect(has(j.problems[1].text, "./zn dispatch zz-review R0010 --mode final --frontier"))
				.toBe(true)
			local text = zn({ "land-check", "R0010" })
			t.expect(text.code).toBe(1)
			t.expect(has(text.stdout, "no-frontier-review (review):")).toBe(true)
			-- the prefix below the second layer needs the floor too (the verdict the dispatcher reads for a block request)
			local below = checked({ "--below", "c0020" })
			local belowCodes = problems(below)
			t.expect(table.find(belowCodes, "no-frontier-review") ~= nil).toBe(true)
			t.expect((serde.decode("json", below.stdout) :: any).through).toBe("c0010")
			t.expect(j.through).toBe("")
			-- a person's done is refused by c0251's own refusal, which names the code once; c0252's check adds no second line
			local refused = zn({ "done", "R0010" })
			t.expect(refused.ok).toBe(false)
			local said = refused.stdout .. refused.stderr
			t.expect(has(said, "no-frontier-review")).toBe(true)
			local _, n = string.gsub(said, "no%-frontier%-review", "")
			t.expect(n <= 2).toBe(true)
			t.expect(has(said, "is not ready to land")).toBe(false)
			-- a list that names the model of the reviews meets the floor
			fs.writeFile(list, '[review]\nfrontier = ["claude-opus-5-5"]\n')
			t.expect(problems(checked({}))).toEqual({})
			-- the file is a fixture detail: the landing below is the raft's own
			fs.removeFile(list)
		end
	)

	it("AC8: with a green top layer done goes on, and lands the bind", function()
		pr("R0010/2/c0020", "MERGEABLE", GREEN)
		local landed = must(zn({ "done", "R0010" }), "done")
		t.expect(has(landed, "landed R0010")).toBe(true)
		t.expect(has(git(f.main, { "log", "-1", "--format=%s", "origin/main" }), "R0010: bind c0010, c0020"))
			.toBe(true)
	end)
end)
