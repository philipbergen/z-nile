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
local STAGES = "run z-nile tests/acceptance/c0082/real-tree.spec.luau -- audit\n"
	.. "run z-nile tests/acceptance/c0120/check-paths.spec.luau -- check-paths\n"
	.. "run z-nile tests/acceptance/c0114/classified.spec.luau -- classified\n"
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

return t.spec("c0152 a PR may merge past main's tracker-only commits only when the merged tree passes", function(it)
	it("sets up a PR branch; main hasn't moved: ok, naming the head to merge", function()
		local seed = workingTree()
		seed["z-nile/tests/merge-stages.txt"] = STAGES
		seed[DOC1] = stub("c0901", "c0152-fixture-one", "new-a-b-c")
		seed[DOC2] = stub("c0902", "c0152-fixture-two", "new-a-b-c")
		seed[R .. "c0902/check.sh"] = DRAFT
		seed[OLD_SPEC] = "return nil\n"
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
			trackerfix.elsewhere(f, { [R .. "c0902/spend.md"] = "| a spend row |\n" }, "tracker: spend c0902")
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
			t.expect(has(r.stdout, `--match-head-commit {head}`)).toBe(true)
			reset()
		end
	)

	it(
		"a document the PR changes, a sequestered spec, code, an existing check.sh edited, or dropped beside a decoy: each a no",
		function()
			trackerfix.elsewhere(f, { [DOC1] = stub("c0901", "c0152-fixture-one", "new-x-y-z") }, "tracker: c0901")
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

	it("and classified: a check.sh that doesn't list, a slug the PR's new item has (design review 002 F2)", function()
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
	end)

	it("a listed stage missing from the merged tree is a no, never a skip", function()
		fixture.git(f.main, { "rm", "-q", CLASSIFIED })
		fixture.git(f.main, { "commit", "-qm", "the PR drops a stage" })
		local h2 = trim(fixture.git(f.main, { "rev-parse", "HEAD" }))
		trackerfix.elsewhere(f, { [R .. "c0902/spend.md"] = "| a spend row |\n" }, "tracker: spend c0902")
		expectNo({ `the merged tree has no {CLASSIFIED}` }, h2)
		fixture.git(f.main, { "reset", "-q", "--hard", head })
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
end)
