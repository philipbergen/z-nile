--!strict
-- c0152 AC1: `./zn merge-check <head>` says whether a PR whose CI went green at <head> may merge although origin's main
-- moved since: exit 0 only when every commit main gained is tracker state the publisher allows that edits no existing
-- item's check.sh (a new item's, or the same item's moved unchanged, is fine) and touches none of the PR's files (merge
-- commits judged by their first-parent diff), and the would-be merged tree passes every gate stage that reads tracker
-- files (the `run` lines of z-nile/tests/merge-stages.txt in that tree; decided with the user, 2026-10-25: "Run those
-- checks first"); otherwise exit 1, naming each commit and path or the failing stage. Main's tip comes from the remote
-- (ls-remote), never the local tracking ref, and must be fetched. The trial is its own repository under $TMPDIR, never a
-- worktree of the checkout (design review 002 F1). Fixture under .cache/c0152-merge-check (tests/lib/trackerfix),
-- seeded with this checkout's whole working tree so the stages judge a real tree, and a stage list of three (audit,
-- check-paths, classified) to keep the spec's time down; the real list is c0152's stages.spec's concern.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local R = "z-nile/.tracker/issues/"
local DOC1 = R .. "c0901/c0901.md"
local DOC2 = R .. "c0902/c0902.md"
local OLD_SPEC = "z-nile/tests/tooling/c0152-old.spec.luau"
local CLASSIFIED = "z-nile/tests/acceptance/c0114/classified.spec.luau"
local DRAFT =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\nfinish\n'
local PROBE = "z-nile/tests/tooling/c0152-trial-probe.spec.luau"
local STAGES = "notrial */.tracker/**/spend.md -- spend rows (the user's decision, 2026-10-26)\n"
	.. "run z-nile tests/tooling/c0152-trial-probe.spec.luau -- the trial's own guards, and a move of main during it\n"
	.. "run z-nile tests/acceptance/c0082/real-tree.spec.luau -- audit\n"
	.. "run z-nile tests/acceptance/c0120/check-paths.spec.luau -- check-paths\n"
	.. "run z-nile tests/acceptance/c0114/classified.spec.luau -- classified\n"
-- the fixture's folders, known before trackerfix.new makes them (it uses the same physical path)
local BASE = `{fixture.physical(".")}/.cache/c0152-merge-check`
local TRIGGER = `{BASE}/move-during-trial`
-- a stage the trial runs first (design review 003): the trial borrows no objects from the checkout and its nested runs
-- protect the checkout's git directory; and, when a case leaves a trigger, origin's main moves while the trial runs
local function probe(): string
	return table.concat({
		"--!strict",
		'local fs = require("@lune/fs")',
		'local process = require("@lune/process")',
		'local t = require("@tests/lib/t")',
		"local function trim(s: string): string",
		'\treturn (string.gsub(s, "%s+$", ""))',
		"end",
		'return t.spec("c0152 trial probe", function(it)',
		'\tit("borrows nothing, guards the checkout, and moves main when asked", function()',
		'\t\tlocal common = trim(process.exec("git", { "rev-parse", "--path-format=absolute", "--git-common-dir" }).stdout)',
		'\t\tt.expect(fs.isFile(common .. "/objects/info/alternates")).toBe(false)',
		'\t\tlocal real = ":" .. (process.env.PICKMAN_FENCE_REAL_GIT or "") .. ":"',
		`\t\tt.expect(string.find(real, ":{BASE}/main/.git:", 1, true) ~= nil).toBe(true)`,
		`\t\tlocal trigger = "{TRIGGER}"`,
		"\t\tif fs.isFile(trigger) then",
		"\t\t\tlocal queue: { string } = {}",
		'\t\t\tfor sha in string.gmatch(fs.readFile(trigger), "%x+") do',
		"\t\t\t\ttable.insert(queue, sha)",
		"\t\t\tend",
		'\t\t\tlocal sha = table.remove(queue, 1) or ""',
		"\t\t\tif #queue == 0 then",
		"\t\t\t\tfs.removeFile(trigger)",
		"\t\t\telse",
		'\t\t\t\tfs.writeFile(trigger, table.concat(queue, "\\n") .. "\\n")',
		"\t\t\tend",
		`\t\t\tlocal r = process.exec("git", \{ "-C", "{BASE}/other", "push", "-q", "origin", sha .. ":refs/heads/main" \})`,
		"\t\t\tt.expect(r.ok).toBe(true)",
		"\t\tend",
		"\tend)",
		"end)",
		"",
	}, "\n")
end
local f: trackerfix.Fixture
local head = ""
local baseline = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
local function stub(id: string, slug: string, status: string): string
	return trackerfix.stub(id, slug, status)
end
-- merge-check builds its trial under $TMPDIR; here a folder in the fixture (under this checkout's .cache), so the
-- trial's spec runs are fixtures of this guarded run (a jailed run can't nest another jail)
local function tmp(): string
	local d = `{f.base}/tmp`
	fs.writeDir(d)
	return d
end
local function check(h: string?): fixture.Result
	return trackerfix.tr(f, f.main, { "merge-check", h or head }, { TMPDIR = tmp() })
end
local function fetch()
	fixture.git(f.main, { "fetch", "-q", "origin" })
end
local function originMain(): string
	fixture.git(f.other, { "fetch", "-q", "origin" })
	return trim(fixture.git(f.other, { "rev-parse", "origin/main" }))
end
-- origin's main back to the baseline (the fixture's own bare origin; never the real one)
local function reset()
	fixture.git(f.other, { "push", "-q", "-f", "origin", `{baseline}:refs/heads/main` })
	fixture.git(f.other, { "fetch", "-q", "origin" })
	fixture.git(f.other, { "reset", "-q", "--hard", baseline })
	fetch()
end
local function expectNo(needles: { string }, h: string?)
	fetch()
	local r = check(h)
	t.expect(r.code).toBe(1)
	for _, needle in needles do
		if not has(r.stdout, needle) then
			error(`merge-check's no lacks "{needle}":\n{r.stdout}{r.stderr}`)
		end
	end
	t.expect(has(r.stdout, "merge origin/main in")).toBe(true)
	reset()
end
-- this checkout's working tree (tracked and untracked, not ignored): the fixture's seed
local function workingTree(): { [string]: string }
	local top = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
	local listed = process.exec("git", { "ls-files", "-co", "--exclude-standard" }, { cwd = top })
	t.expect(listed.ok).toBe(true)
	local out: { [string]: string } = {}
	for p in string.gmatch(listed.stdout, "[^\n]+") do
		if fs.isFile(`{top}/{p}`) and not string.match(p, "^%.claude/") then
			out[p] = fs.readFile(`{top}/{p}`)
		end
	end
	return out
end

return t.spec(
	"c0152 a PR may merge past main's tracker-only commits only when the merged tree passes",
	function(it)
		it("sets up a PR branch; main hasn't moved: ok, naming the head to merge", function()
			local seed = workingTree()
			seed["z-nile/tests/merge-stages.txt"] = STAGES
			seed[DOC1] = stub("c0901", "c0152-fixture-one", "new-a-b-c")
			seed[DOC2] = stub("c0902", "c0152-fixture-two", "new-a-b-c")
			seed[R .. "c0902/check.sh"] = DRAFT
			seed[OLD_SPEC] = "return nil\n"
			seed[PROBE] = probe()
			f = trackerfix.new("c0152-merge-check", seed)
			-- the PR: code, c0901's document, a new item, and the deletion of a spec
			fixture.git(f.main, { "checkout", "-q", "-b", "pr" })
			fs.writeFile(`{f.main}/z-nile/engine/c0152-demo.luau`, "return nil\n")
			fs.writeFile(`{f.main}/{DOC1}`, stub("c0901", "c0152-fixture-one", "preparing-a-b-c"))
			fs.writeDir(`{f.main}/{R}c0904`)
			fs.writeFile(`{f.main}/{R}c0904/c0904.md`, stub("c0904", "c0152-pr-item", "new-a-b-c"))
			fs.removeFile(`{f.main}/{OLD_SPEC}`)
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-qm", "the PR" })
			head = trim(fixture.git(f.main, { "rev-parse", "HEAD" }))
			baseline = originMain()
			local r = check()
			t.expect(r.code).toBe(0)
			t.expect(has(r.stdout, "has not moved")).toBe(true)
			t.expect(has(r.stdout, `judged main {baseline}`)).toBe(true)
			t.expect(has(r.stdout, `--match-head-commit {head}`)).toBe(true)
		end)

		it("a commit on origin's main that isn't fetched here refuses: fetch first", function()
			trackerfix.elsewhere(f, { [R .. "c0902/spend.md"] = "| a spend row |\n" }, "tracker: spend c0902")
			local r = check()
			t.expect(r.code).toBe(1)
			t.expect(has(r.stdout, "git fetch origin")).toBe(true)
			reset()
		end)

		it(
			"tracker state the PR doesn't touch, a new item and a move to done/ pass, and so does the merged tree",
			function()
				trackerfix.elsewhere(
					f,
					{ [R .. "c0902/spend.md"] = "| a spend row |\n" },
					"tracker: spend c0902"
				)
				trackerfix.elsewhere(
					f,
					{ [DOC2] = stub("c0902", "c0152-fixture-two", "preparing-a-b-c") },
					"tracker: c0902"
				)
				trackerfix.elsewhere(f, {
					[R .. "c0903/c0903.md"] = stub("c0903", "c0152-fixture-three", "new-a-b-c"),
					[R .. "c0903/check.sh"] = DRAFT,
				}, "tracker: new c0903")
				-- a move (its check.sh with it, as done and ready move items)
				fixture.git(f.other, { "pull", "-q", "origin", "main" })
				fs.writeDir(`{f.other}/{R}done`)
				fixture.git(f.other, { "mv", R .. "c0902", R .. "done/c0902" })
				fixture.git(f.other, { "commit", "-qm", "tracker: done c0902" })
				fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
				fetch()
				local r = check()
				if r.code ~= 0 then
					error(`expected ok:\n{r.stdout}{r.stderr}`)
				end
				t.expect(has(r.stdout, "moved by 4 commit(s), all tracker state")).toBe(true)
				t.expect(has(r.stdout, "passes every tracker-reading stage")).toBe(true)
				-- design review 003 F1/F3: the trial's folder named first, gone after; the tip judged named
				local folder = string.match(r.stdout, "merge%-check: trial of main %x+ in (%S+)\n")
				t.expect(folder ~= nil).toBe(true)
				t.expect(fs.isDir(folder :: string)).toBe(false)
				t.expect(has(r.stdout, `judged main {originMain()}`)).toBe(true)
				t.expect(has(r.stdout, `--match-head-commit {head}`)).toBe(true)
				reset()
			end
		)

		it(
			"a document the PR changes, a sequestered spec, code, an existing check.sh edited, or dropped beside a decoy: each a no",
			function()
				trackerfix.elsewhere(
					f,
					{ [DOC1] = stub("c0901", "c0152-fixture-one", "new-x-y-z") },
					"tracker: c0901"
				)
				expectNo({ `{DOC1} is a file this PR changes` })
				trackerfix.elsewhere(f, { [R .. "c0902/acceptance/x.spec.luau"] = "return nil\n" }, "a spec")
				expectNo({ R .. "c0902/acceptance/x.spec.luau is not tracker state" })
				trackerfix.elsewhere(f, { ["z-nile/engine/other.luau"] = "return nil\n" }, "code on main")
				expectNo({ "z-nile/engine/other.luau is not tracker state" })
				trackerfix.elsewhere(f, { [R .. "c0902/check.sh"] = DRAFT .. "# edited\n" }, "edit")
				expectNo({ R .. "c0902/check.sh edits an existing item's check.sh" })
				-- design review 002 F3: c0902's check.sh dropped, and another item's with the same text added (a decoy)
				fixture.git(f.other, { "pull", "-q", "origin", "main" })
				fixture.git(f.other, { "rm", "-q", R .. "c0902/check.sh" })
				fs.writeDir(`{f.other}/{R}c0909`)
				fs.writeFile(`{f.other}/{R}c0909/c0909.md`, stub("c0909", "c0152-decoy", "new-a-b-c"))
				fs.writeFile(`{f.other}/{R}c0909/check.sh`, DRAFT)
				fixture.git(f.other, { "add", "-A" })
				fixture.git(f.other, { "commit", "-qm", "tracker: decoy" })
				fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
				expectNo({ R .. "c0902/check.sh edits an existing item's check.sh" })
			end
		)

		it("a merge commit on main is judged by its own change (first parent)", function()
			fixture.git(f.other, { "checkout", "-q", "-b", "side" })
			fs.writeFile(`{f.other}/{R}c0902/spend.md`, "| side row |\n")
			fixture.git(f.other, { "add", "-A" })
			fixture.git(f.other, { "commit", "-qm", "tracker: side" })
			fixture.git(f.other, { "checkout", "-q", "main" })
			fixture.git(f.other, { "merge", "-q", "--no-ff", "--no-commit", "side" })
			fs.writeFile(`{f.other}/z-nile/engine/evil.luau`, "return nil\n")
			fixture.git(f.other, { "add", "-A" })
			fixture.git(f.other, { "commit", "-qm", "merge side, with code" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(f.other, { "branch", "-q", "-D", "side" })
			expectNo({ "z-nile/engine/evil.luau is not tracker state" })
		end)

		it("the merged tree is judged by every listed stage: check-paths and audit", function()
			trackerfix.elsewhere(f, {
				[R .. "c0909/c0909.md"] = stub("c0909", "c0152-nine", "new-a-b-c"),
				[R .. "c0909/check.sh"] = DRAFT:gsub("finish\n", "")
					.. 'check "AC1: old" lune run tests/run -- tests/tooling/c0152-old.spec.luau\nfinish\n',
				[R .. "c0910/c0910.md"] = "not a document\n",
			}, "tracker: new c0909, c0910")
			expectNo({
				"the merged tree fails z-nile/tests/acceptance/c0120/check-paths.spec.luau",
				"the merged tree fails z-nile/tests/acceptance/c0082/real-tree.spec.luau",
			})
		end)

		it(
			"and classified: a check.sh that doesn't list, a slug the PR's new item has (design review 002 F2)",
			function()
				trackerfix.elsewhere(f, {
					[R .. "c0911/c0911.md"] = stub("c0911", "c0152-eleven", "new-a-b-c"),
					[R .. "c0911/check.sh"] = DRAFT:gsub("finish\n", "") .. 'check "AC1: broken\nfinish\n',
					[R .. "c0912/c0912.md"] = stub("c0912", "c0152-pr-item", "new-a-b-c"),
				}, "tracker: new c0911, c0912")
				expectNo({
					"the merged tree fails z-nile/tests/acceptance/c0114/classified.spec.luau",
					"c0911/check.sh",
					"c0152-pr-item",
				})
			end
		)

		it("a listed stage missing from the merged tree is a no, never a skip", function()
			fixture.git(f.main, { "rm", "-q", CLASSIFIED })
			fixture.git(f.main, { "commit", "-qm", "the PR drops a stage" })
			local h2 = trim(fixture.git(f.main, { "rev-parse", "HEAD" }))
			trackerfix.elsewhere(f, { [R .. "c0902/spend.md"] = "| a spend row |\n" }, "tracker: spend c0902")
			expectNo({ `the merged tree has no {CLASSIFIED}` }, h2)
			fixture.git(f.main, { "reset", "-q", "--hard", head })
		end)

		-- design review 003 F1: main's tip is read again after the trial. Each move is one commit, made in `other` and
		-- pushed by the trial's probe stage, the next one on each trial (design review 004 F1); the commits, in order
		local function movesDuringTrial(moves: { { files: { [string]: string }, msg: string } }): { string }
			trackerfix.elsewhere(f, { [R .. "c0902/spend.md"] = "| a spend row |\n" }, "tracker: spend c0902")
			fetch()
			fixture.git(f.other, { "pull", "-q", "origin", "main" })
			local shas: { string } = {}
			for _, move in moves do
				for path, text in move.files do
					local parent = string.match(path, "^(.*)/[^/]+$")
					if parent then
						fs.writeDir(`{f.other}/{parent}`)
					end
					fs.writeFile(`{f.other}/{path}`, text)
				end
				fixture.git(f.other, { "add", "-A" })
				fixture.git(f.other, { "commit", "-qm", move.msg })
				table.insert(shas, trim(fixture.git(f.other, { "rev-parse", "HEAD" })))
			end
			fs.writeFile(TRIGGER, table.concat(shas, "\n") .. "\n")
			return shas
		end
		local function moveDuringTrial(files: { [string]: string }, msg: string): string
			return movesDuringTrial({ { files = files, msg = msg } })[1]
		end
		local function item(n: string): { files: { [string]: string }, msg: string }
			return {
				files = { [R .. `c{n}/c{n}.md`] = stub(`c{n}`, `c0152-fixture-{n}`, "new-a-b-c") },
				msg = `tracker: new c{n}`,
			}
		end
		local function trials(out: string): number
			local n = 0
			for _ in string.gmatch(out, "merge%-check: trial of main ") do
				n += 1
			end
			return n
		end

		it(
			"main moving during the check by spend rows only is accepted without a new trial (the user's decision)",
			function()
				local moved = moveDuringTrial(
					{ [R .. "c0902/spend.md"] = "| a spend row |\n| another |\n" },
					"tracker: spend"
				)
				local r = check()
				if r.code ~= 0 then
					error(`expected ok:\n{r.stdout}{r.stderr}`)
				end
				t.expect(fs.isFile(TRIGGER)).toBe(false)
				t.expect(trials(r.stdout)).toBe(1)
				t.expect(has(r.stdout, "changing only files the stage list marks notrial")).toBe(true)
				t.expect(has(r.stdout, `judged main {moved}`)).toBe(true)
				reset()
			end
		)

		it("any other tracker move during the check runs the trial again; code is a no", function()
			local moved = moveDuringTrial({
				[R .. "c0905/c0905.md"] = stub("c0905", "c0152-fixture-five", "new-a-b-c"),
			}, "tracker: new c0905")
			local r = check()
			if r.code ~= 0 then
				error(`expected ok:\n{r.stdout}{r.stderr}`)
			end
			t.expect(trials(r.stdout)).toBe(2)
			t.expect(has(r.stdout, "the trial ran again")).toBe(true)
			t.expect(has(r.stdout, `judged main {moved}`)).toBe(true)
			reset()
			moveDuringTrial({ ["z-nile/engine/late.luau"] = "return nil\n" }, "code, mid-check")
			local r2 = check()
			t.expect(r2.code).toBe(1)
			t.expect(has(r2.stdout, "z-nile/engine/late.luau is not tracker state")).toBe(true)
			t.expect(has(r2.stdout, "judged main")).toBe(false)
			reset()
		end)

		-- design review 004 F1: the bound is three trials
		it("three tracker moves during the check: a no after the third trial", function()
			movesDuringTrial({ item("0911"), item("0912"), item("0913"), item("0914") })
			local r = check()
			t.expect(r.code).toBe(1)
			t.expect(trials(r.stdout)).toBe(3)
			t.expect(has(r.stdout, "origin's main kept moving during the check (3 trials)")).toBe(true)
			t.expect(has(r.stdout, "judged main")).toBe(false)
			if fs.isFile(TRIGGER) then
				fs.removeFile(TRIGGER)
			end
			reset()
		end)

		it("two tracker moves, then spend rows only after the third trial: ok, three trials", function()
			local shas = movesDuringTrial({
				item("0915"),
				item("0916"),
				{
					files = { [R .. "c0902/spend.md"] = "| a spend row |\n| late |\n" },
					msg = "tracker: spend, late",
				},
			})
			local r = check()
			if r.code ~= 0 then
				error(`expected ok:\n{r.stdout}{r.stderr}`)
			end
			t.expect(trials(r.stdout)).toBe(3)
			t.expect(has(r.stdout, "changing only files the stage list marks notrial")).toBe(true)
			t.expect(has(r.stdout, `judged main {shas[3]}`)).toBe(true)
			reset()
		end)

		-- design review 004 F2: a spend row for a folder the PR moved away belongs to no live item: tried, and audit says no
		it("a first spend row at the old folder of an item the PR moves is tried again", function()
			fixture.git(f.main, { "checkout", "-q", "-b", "pr-move", head })
			fs.writeDir(`{f.main}/{R}done`)
			fixture.git(f.main, { "mv", R .. "c0901", R .. "done/c0901" })
			fixture.git(f.main, { "commit", "-qm", "the PR moves c0901 to done/" })
			local h3 = trim(fixture.git(f.main, { "rev-parse", "HEAD" }))
			moveDuringTrial({ [R .. "c0901/spend.md"] = "| a first spend row |\n" }, "tracker: spend c0901")
			local r = check(h3)
			-- never ok: the row is tried again, and that second trial fails (git's merge sees main's file in the folder
			-- the PR renamed as a conflict; were it merged, audit would find the orphan folder)
			if r.code ~= 1 or has(r.stdout, "judged main") then
				error(`expected a no:\n{r.stdout}{r.stderr}`)
			end
			t.expect(
				has(r.stdout, "the PR and origin's main conflict")
					or has(
						r.stdout,
						"the merged tree fails z-nile/tests/acceptance/c0082/real-tree.spec.luau"
					)
			).toBe(true)
			fixture.git(f.main, { "checkout", "-q", "pr" })
			fixture.git(f.main, { "branch", "-q", "-D", "pr-move" })
			reset()
		end)

		it("the local tracking ref is never the judge, and the trial leaves nothing behind", function()
			trackerfix.elsewhere(f, { ["z-nile/engine/other.luau"] = "return nil\n" }, "code on main")
			fetch()
			local base = trim(fixture.git(f.main, { "merge-base", head, "refs/remotes/origin/main" }))
			fixture.git(f.main, { "update-ref", "refs/remotes/origin/main", base })
			local r = check()
			t.expect(r.code).toBe(1)
			t.expect(has(r.stdout, "z-nile/engine/other.luau is not tracker state")).toBe(true)
			-- design review 002 F1: the trials above left no folder under $TMPDIR, nothing under the checkout's .cache and
			-- no worktree
			t.expect(#fs.readDir(tmp())).toBe(0)
			t.expect(fs.isDir(`{f.main}/.cache`)).toBe(false)
			t.expect(#string.split(trim(fixture.git(f.main, { "worktree", "list" })), "\n")).toBe(1)
			fs.removeDir(f.base)
		end)
	end
)
