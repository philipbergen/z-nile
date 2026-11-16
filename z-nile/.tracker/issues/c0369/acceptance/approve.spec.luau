--!strict
-- c0369 AC2-AC5: one `./zn approve <id>`, run from the main checkout or any worktree, finds the design, records the
-- approval there and makes it count: published to origin/main when the design is merged, pushed on its branch when
-- it is not. A failed publish or push leaves the record and names `./zn approve <id> --publish`, which finds it too.
-- The fixtures are .cache/c0369-approve-main and .cache/c0369-approve-branch. Approving goes through `script`, which
-- allocates a terminal; the spec process itself has none.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MAIN_NAME = "c0369-approve-main"
local BRANCH_NAME = "c0369-approve-branch"
local ID = "c0001"
local SLUG = "hold"
local ROOT = "z-nile/.tracker"
local ISSUE = `{ROOT}/issues/{ID}`
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. `# {ROOT}/issues/{ID}/check.sh\n` .. "finish\n"
local SPEC = "--!strict\n"
	.. 'local t = require("@tests/lib/t")\n'
	.. 'return t.spec("holds", function(it)\n'
	.. '\tit("holds", function()\n'
	.. "\t\tt.expect(true).toBe(true)\n"
	.. "\tend)\n"
	.. "end)\n"
local REJECT = "#!/bin/sh\necho 'the fixture origin refuses this push' >&2\nexit 1\n"

local function doc(design: string, ready: boolean?): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: {SLUG}\nraft: \ndepends_on: []\nemergent: false\ndesign: {if ready
			== false
		then "draft"
		else "ready"}\ncreated: 2026-11-10\nstatus: preparing-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\n{design}\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end
local function seed(): { [string]: string }
	return {
		[`{ISSUE}/{ID}.md`] = doc("Hash the contract.", false), -- a ready seed would carry an approval (trackerfix seals it)
		[`{ISSUE}/check.sh`] = CHECK,
		[`{ISSUE}/acceptance/hold.spec.luau`] = SPEC,
	}
end
-- `./zn approve c0001 <extra>` in `cwd`, with a terminal on stdin
local function approve(cwd: string, extra: { string }?, env: { [string]: string }?): fixture.Result
	local merged: { [string]: string } = { PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
	local given: { [string]: string } = env or {}
	for k, v in given do
		merged[k] = v
	end
	local args = { "-q", "/dev/null", "./zn", "approve", ID }
	local more: { string } = extra or {}
	for _, a in more do
		table.insert(args, a)
	end
	return fixture.exec(cwd, "script", args, { env = merged })
end
local function must(r: fixture.Result): string
	if not r.ok then
		error(say(r), 2)
	end
	return say(r)
end
local function lines(text: string): number
	local n = 0
	for _ in string.gmatch(text, "[^\n]+") do
		n += 1
	end
	return n
end
-- the place of `first` in `text` comes before the place of `second`
local function before(text: string, first: string, second: string): boolean
	local a = string.find(text, first, 1, true)
	local b = string.find(text, second, 1, true)
	return a ~= nil and b ~= nil and a < b
end
local function refuse(origin: string, on: boolean)
	local hook = `{origin}/hooks/pre-receive`
	if on then
		fs.writeDir(`{origin}/hooks`)
		fs.writeFile(hook, REJECT)
		local made = fixture.exec(origin, "chmod", { "+x", hook })
		if not made.ok then
			error(made.stderr)
		end
	elseif fs.isFile(hook) then
		fs.removeFile(hook)
	end
end

return t.spec("c0369 one approve from anywhere records and publishes", function(it)
	local f: trackerfix.Fixture
	local scratch = "" -- the command's own worktree
	local other = "" -- a worktree of other work, behind main
	local persons = "" -- a worktree a person made, on a branch, named as the command's used to be

	local function onMain(rel: string): string
		return fixture.git(f.origin, { "show", `main:{rel}` })
	end
	local function count(): number
		return tonumber(fixture.git(f.origin, { "rev-list", "--count", "main" })) :: number
	end
	local function redesign(text: string)
		trackerfix.elsewhere(f, { [`{ISSUE}/{ID}.md`] = doc(text) }, `design: {text}`)
	end
	local function rowsOnMain(): number
		return lines(onMain(`{ISSUE}/approval.md`)) - 2 -- less the title and the header
	end

	it("sets up a design that merged to main with no approval", function()
		f = trackerfix.new(MAIN_NAME, seed())
		scratch = `{f.main}/.worktree/.approve-{ID}`
		other = `{f.main}/.worktree/other-work`
		persons = `{f.main}/.worktree/approve-{ID}`
		redesign("Hash the contract.")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "other-work", other, "HEAD" })
		fixture.git(f.main, { "worktree", "add", "-q", "-b", `approve-{ID}`, persons, "HEAD" })
	end)

	it("keeps every refusal before it makes anything, whatever ZN_APPROVE_IN says", function()
		local commits = count()
		local head = fixture.git(f.main, { "rev-parse", "HEAD" })
		local piped = fixture.exec(f.main, "./zn", { "approve", ID })
		t.expect(piped.ok).toBe(false)
		t.expect(has(say(piped), "approve is refused without a terminal on stdin")).toBe(true)
		local placed: { { [string]: string } } = { {}, { ZN_APPROVE_IN = f.main } }
		for _, extra in placed do
			local agent: { [string]: string } = { CLAUDECODE = "1" }
			local dispatched: { [string]: string } = { ZN_DISPATCH = "1" }
			for k, v in extra do
				agent[k] = v
				dispatched[k] = v
			end
			local a = approve(f.main, nil, agent)
			t.expect(a.ok).toBe(false)
			t.expect(has(say(a), "approve is refused in an agent session, terminal or not")).toBe(true)
			local d = approve(f.main, nil, dispatched)
			t.expect(d.ok).toBe(false)
			t.expect(has(say(d), "ZN_DISPATCH is set")).toBe(true)
		end
		-- a placed run never records in the main checkout
		local inMain = approve(f.main, nil, { ZN_APPROVE_IN = f.main })
		t.expect(inMain.ok).toBe(false)
		t.expect(has(say(inMain), "approve must run inside a worktree")).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fixture.git(f.main, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(fs.isFile(`{f.main}/{ISSUE}/approval.md`)).toBe(false)
		t.expect(fs.isDir(scratch)).toBe(false)
	end)

	it("refuses when its own worktree's path is taken by something else, naming the path", function()
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "taken", scratch, "HEAD" })
		local commits = count()
		local r = approve(f.main)
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), `.worktree/.approve-{ID} is in the way`)).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe("design: Hash the contract.")
		fixture.git(f.main, { "worktree", "remove", scratch })
	end)

	it(
		"from the main checkout records and publishes a merged design in one command, and writes no checkout",
		function()
			local commits = count()
			local head = fixture.git(f.main, { "rev-parse", "HEAD" })
			local out = must(approve(f.main))
			local hash = string.match(out, `approved {ID} (%x+) in a worktree of origin/main`)
			if not hash then
				error(out)
			end
			-- it says where before it records, and records before it publishes
			t.expect(before(out, `{ID}: approving in origin/main`, `approved {ID} `)).toBe(true)
			t.expect(before(out, `approved {ID} `, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			t.expect(fixture.git(f.origin, { "show", "--name-only", "--format=%s", "main" }))
				.toBe(`tracker: approve {ID}\n\n{ISSUE}/approval.md\n{ISSUE}/provenance.md`)
			t.expect(has(onMain(`{ISSUE}/approval.md`), `\t{MAIN_NAME}\t{hash}\t`)).toBe(true)
			t.expect(
				has(
					onMain(`{ISSUE}/provenance.md`),
					` | approved | human:{MAIN_NAME} | design={string.sub(hash :: string, 1, 12)} |`
				)
			).toBe(true)
			-- nothing was committed in the main checkout or in any other worktree, and the command's own is gone
			t.expect(fixture.git(f.main, { "log", "--format=%s", `{head}..HEAD`, "--", ISSUE })).toBe("")
			t.expect(fixture.git(f.main, { "status", "--porcelain", "--", ROOT })).toBe("")
			t.expect(fixture.git(other, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(fixture.git(persons, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(fs.isDir(scratch)).toBe(false)
			t.expect(has(fixture.git(f.main, { "worktree", "list" }), ".worktree/.approve-")).toBe(false)
		end
	)

	it("says an approved design is approved and publishes nothing more", function()
		local commits = count()
		local out = must(approve(f.main))
		t.expect(has(out, `{ID} is already approved on origin/main`)).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fs.isDir(scratch)).toBe(false)
	end)

	it("from a worktree that is only behind main approves main's design, not its own stale copy", function()
		redesign("A second design.")
		local head = fixture.git(other, { "rev-parse", "HEAD" })
		local commits = count()
		local out = must(approve(other))
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(count()).toBe(commits + 1)
		t.expect(rowsOnMain()).toBe(2)
		t.expect(fixture.git(other, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(fixture.git(other, { "status", "--porcelain" })).toBe("")
		-- the new row is for the second design: a checkout of main says it holds
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local held = fixture.exec(f.main, "./zn", { "approve", ID, "--check" })
		t.expect(held.ok).toBe(true)
	end)

	it("with publishing off keeps the record, fails saying so, and the retry publishes that row", function()
		redesign("A third design.")
		local commits = count()
		local off = approve(f.main, nil, { PICKMAN_PUBLISH = "0" })
		t.expect(off.ok).toBe(false)
		t.expect(has(say(off), "but it does not count yet: publishing is off")).toBe(true)
		t.expect(has(say(off), `Retry: ./zn approve {ID} --publish`)).toBe(true)
		t.expect(count()).toBe(commits)
		t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe(`tracker: approve {ID}`)
		local kept = fs.readFile(`{scratch}/{ISSUE}/approval.md`)
		-- the plain command, asked again, publishes what was recorded and records nothing new
		local out = must(approve(f.main))
		t.expect(has(out, `{ID}: publishing from .worktree/.approve-{ID}`)).toBe(true)
		t.expect(has(out, `approved {ID} `)).toBe(false)
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(count()).toBe(commits + 1)
		t.expect(onMain(`{ISSUE}/approval.md`)).toBe((string.gsub(kept, "%s+$", "")))
		t.expect(rowsOnMain()).toBe(3)
		t.expect(fs.isDir(scratch)).toBe(false)
	end)

	it(
		"keeps the record when the publish fails, names the retry, and the retry finds it from anywhere",
		function()
			redesign("A fourth design.")
			refuse(f.origin, true)
			local commits = count()
			local failed = approve(f.main)
			refuse(f.origin, false)
			t.expect(failed.ok).toBe(false)
			t.expect(
				has(say(failed), `{ID}: approved in a worktree of origin/main, but it does not count yet: `)
			)
				.toBe(true)
			t.expect(has(say(failed), `Retry: ./zn approve {ID} --publish`)).toBe(true)
			t.expect(count()).toBe(commits)
			-- the record stays, committed, in the command's worktree
			t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe(`tracker: approve {ID}`)
			local kept = fs.readFile(`{scratch}/{ISSUE}/approval.md`)
			t.expect(lines(kept)).toBe(6)
			local out = must(approve(other, { "--publish" }))
			t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			-- the row published is the one recorded at the first attempt
			t.expect(onMain(`{ISSUE}/approval.md`)).toBe((string.gsub(kept, "%s+$", "")))
			t.expect(fs.isDir(scratch)).toBe(false)
			local again = must(approve(f.main, { "--publish" }))
			t.expect(has(again, `{ID} is already approved on origin/main`)).toBe(true)
		end
	)

	it(
		"drops a record left by a failed publish once main's design is replaced, and approves the new one",
		function()
			redesign("A fifth design.")
			refuse(f.origin, true)
			local failed = approve(f.main)
			refuse(f.origin, false)
			t.expect(failed.ok).toBe(false)
			t.expect(fixture.git(scratch, { "log", "-1", "--format=%s" })).toBe(`tracker: approve {ID}`)
			redesign("A sixth design.")
			-- the retry has nothing: the record is of a design that is nobody's now
			local commits = count()
			local retry = approve(f.main, { "--publish" })
			t.expect(retry.ok).toBe(false)
			t.expect(has(say(retry), `{ID} has no recorded approval to publish. Run ./zn approve {ID}.`))
				.toBe(true)
			t.expect(count()).toBe(commits)
			-- the plain command approves main's design in the same worktree, moved to origin/main
			local out = must(approve(f.main))
			t.expect(before(out, `approved {ID} `, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			t.expect(rowsOnMain()).toBe(5) -- the fifth design's row was never published
			t.expect(fs.isDir(scratch)).toBe(false)
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			t.expect(fixture.exec(f.main, "./zn", { "approve", ID, "--check" }).ok).toBe(true)
		end
	)

	it(
		"run inside a worktree that left main before the design there was replaced, approves main's",
		function()
			-- the worktree holds an unapproved design that was main's own when it branched; main then got another
			redesign("A seventh design.")
			fixture.git(f.main, { "fetch", "-q", "origin" })
			local left = `{f.main}/.worktree/left-behind`
			fixture.git(f.main, { "worktree", "add", "-q", "-b", "left-behind", left, "origin/main" })
			redesign("An eighth design.")
			local head = fixture.git(left, { "rev-parse", "HEAD" })
			local commits = count()
			local out = must(approve(left))
			t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(count()).toBe(commits + 1)
			t.expect(fixture.git(left, { "rev-parse", "HEAD" })).toBe(head)
			-- and the person's own approve-<id> worktree was never in the way, nor touched
			t.expect(fixture.git(persons, { "log", "-1", "--format=%s" })).toBe("design: Hash the contract.")
		end
	)

	it("publishes a held approval onto main's rows, and loses none of them", function()
		-- a prep whose approval.md never had main's earlier rows, and whose design reached main without its approval
		fixture.git(f.main, { "fetch", "-q", "origin" })
		local prep = `{f.main}/.worktree/prep-{SLUG}`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", `prep-{SLUG}`, prep, "origin/main" })
		fixture.git(prep, { "rm", "-q", `{ISSUE}/approval.md`, `{ISSUE}/provenance.md` })
		fs.writeFile(`{prep}/{ISSUE}/{ID}.md`, doc("A ninth design."))
		fixture.git(prep, { "add", "-A" })
		fixture.git(prep, { "commit", "-q", "-m", "prep: a ninth design, with no rows" })
		must(approve(f.main))
		t.expect(lines(fs.readFile(`{prep}/{ISSUE}/approval.md`))).toBe(3)
		redesign("A ninth design.")
		local earlier = onMain(`{ISSUE}/approval.md`)
		local rows = rowsOnMain()
		local out = must(approve(f.main))
		t.expect(has(out, `{ID}: publishing from .worktree/prep-{SLUG}`)).toBe(true)
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		local now = onMain(`{ISSUE}/approval.md`)
		t.expect(rowsOnMain()).toBe(rows + 1)
		t.expect(string.sub(now, 1, #earlier)).toBe(earlier)
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		t.expect(fixture.exec(f.main, "./zn", { "approve", ID, "--check" }).ok).toBe(true)
	end)

	local g: trackerfix.Fixture
	local PREP = `prep-{SLUG}`
	local function wt(name: string): string
		return `{g.main}/.worktree/{name}`
	end
	local function design(name: string, text: string)
		fs.writeFile(`{wt(name)}/{ISSUE}/{ID}.md`, doc(text))
		fixture.git(wt(name), { "add", "-A" })
		fixture.git(wt(name), { "commit", "-q", "-m", `prep: {text}` })
	end
	local function tip(name: string): string
		return fixture.git(wt(name), { "log", "-1", "--format=%s" })
	end
	local function headOf(name: string): string
		return fixture.git(wt(name), { "rev-parse", "HEAD" })
	end
	local function onOrigin(name: string): string?
		local r = fixture.exec(g.origin, "git", { "rev-parse", "-q", "--verify", `refs/heads/{name}` })
		return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else nil
	end
	local function mainOf(): string
		return fixture.git(g.origin, { "rev-parse", "main" })
	end

	it(
		"from the main checkout records an unmerged design in its prep worktree and pushes the branch",
		function()
			g = trackerfix.new(BRANCH_NAME, seed())
			fixture.git(g.main, { "worktree", "add", "-q", "-b", PREP, wt(PREP), "origin/main" })
			design(PREP, "Hash the contract.")
			-- a prototype of the same issue: a ready design of its own that nobody is asked to approve
			fixture.git(
				g.main,
				{ "worktree", "add", "-q", "-b", "proto-hold", wt("proto-hold"), "origin/main" }
			)
			design("proto-hold", "A prototype's copy.")
			local mainBefore = mainOf()
			local head = fixture.git(g.main, { "rev-parse", "HEAD" })
			local out = must(approve(g.main))
			t.expect(before(out, `{ID}: approving in .worktree/{PREP}`, `approved {ID} `)).toBe(true)
			t.expect(has(out, `pushed {PREP}: the approval counts when its pull request merges`)).toBe(true)
			t.expect(fixture.git(wt(PREP), { "show", "--name-only", "--format=%s", "HEAD" }))
				.toBe(`tracker: approve {ID}\n\n{ISSUE}/approval.md\n{ISSUE}/provenance.md`)
			t.expect(onOrigin(PREP)).toBe(headOf(PREP))
			-- a draft on main takes nothing, even though its text hashes the same; no checkout but the prep's changed
			t.expect(mainOf()).toBe(mainBefore)
			t.expect(fixture.git(g.main, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(tip("proto-hold")).toBe("prep: A prototype's copy.")
			t.expect(onOrigin("proto-hold")).toBe(nil)
			t.expect(fs.isDir(`{g.main}/.worktree/.approve-{ID}`)).toBe(false)
			-- asked again, it says where the approval waits and changes nothing
			local again = must(approve(g.main))
			t.expect(
				has(again, `{ID} is approved in .worktree/{PREP}: it counts when its pull request merges`)
			)
				.toBe(true)
			t.expect(tip(PREP)).toBe(`tracker: approve {ID}`)
			t.expect(tip("proto-hold")).toBe("prep: A prototype's copy.")
		end
	)

	it("takes another worktree only when it is run inside it", function()
		local out = must(approve(wt("proto-hold")))
		t.expect(has(out, "pushed proto-hold: the approval counts when its pull request merges")).toBe(true)
		t.expect(tip("proto-hold")).toBe(`tracker: approve {ID}`)
		t.expect(onOrigin("proto-hold")).toBe(headOf("proto-hold"))
	end)

	it("keeps the record when the push fails, and --publish from the main checkout pushes it", function()
		design(PREP, "A second design.")
		refuse(g.origin, true)
		local failed = approve(g.main)
		refuse(g.origin, false)
		t.expect(failed.ok).toBe(false)
		t.expect(has(say(failed), "but it does not count yet: ")).toBe(true)
		t.expect(has(say(failed), `.worktree/{PREP}`)).toBe(true)
		t.expect(has(say(failed), `Retry: ./zn approve {ID} --publish`)).toBe(true)
		t.expect(tip(PREP)).toBe(`tracker: approve {ID}`)
		t.expect(onOrigin(PREP) == headOf(PREP)).toBe(false)
		local out = must(approve(g.main, { "--publish" }))
		t.expect(has(out, `pushed {PREP}: the approval counts when its pull request merges`)).toBe(true)
		t.expect(onOrigin(PREP)).toBe(headOf(PREP))
		-- one row for the second design, not two
		t.expect(lines(fs.readFile(`{wt(PREP)}/{ISSUE}/approval.md`))).toBe(4)
	end)

	it("approves a redesign in its prep worktree while main still holds the approved older design", function()
		-- the prep's pull request merges: main holds its design and its approvals
		fixture.git(wt(PREP), { "push", "-q", "origin", "HEAD:main" })
		design(PREP, "A third design.")
		local mainBefore = mainOf()
		local out = must(approve(g.main))
		t.expect(has(out, `{ID}: approving in .worktree/{PREP}`)).toBe(true)
		t.expect(has(out, `pushed {PREP}: the approval counts when its pull request merges`)).toBe(true)
		t.expect(lines(fs.readFile(`{wt(PREP)}/{ISSUE}/approval.md`))).toBe(5)
		t.expect(mainOf()).toBe(mainBefore)
	end)

	it(
		"publishes the approval a prep holds when its design reached main without it, and records no second one",
		function()
			-- the pull request is squashed onto main from before the approval: the design is there, its approval is not
			trackerfix.elsewhere(g, { [`{ISSUE}/{ID}.md`] = doc("A third design.") }, "squash of the prep")
			local held = fs.readFile(`{wt(PREP)}/{ISSUE}/approval.md`)
			local head = headOf(PREP)
			local commits = tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" })) :: number
			local out = must(approve(g.main))
			t.expect(has(out, `{ID}: publishing from .worktree/{PREP}`)).toBe(true)
			t.expect(has(out, `approved {ID} `)).toBe(false)
			t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
			t.expect(tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" }))).toBe(commits + 1)
			t.expect(fixture.git(g.origin, { "show", `main:{ISSUE}/approval.md` }))
				.toBe((string.gsub(held, "%s+$", "")))
			t.expect(headOf(PREP)).toBe(head)
			local again = must(approve(g.main))
			t.expect(has(again, `{ID} is already approved on origin/main`)).toBe(true)
		end
	)

	it("does not take a prep worktree left behind after its design merged and main moved on", function()
		trackerfix.elsewhere(g, { [`{ISSUE}/{ID}.md`] = doc("The design after it.") }, "a later design")
		local head = headOf(PREP)
		local pushed = onOrigin(PREP)
		local commits = tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" })) :: number
		local out = must(approve(g.main))
		t.expect(has(out, `{ID}: approving in origin/main`)).toBe(true)
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(tonumber(fixture.git(g.origin, { "rev-list", "--count", "main" }))).toBe(commits + 1)
		t.expect(headOf(PREP)).toBe(head)
		t.expect(onOrigin(PREP)).toBe(pushed)
		-- the same for a prep that was never approved in its own worktree: its design merged, was approved on main,
		-- and main moved on again
		design(PREP, "A fifth design.")
		trackerfix.elsewhere(g, { [`{ISSUE}/{ID}.md`] = doc("A fifth design.") }, "squash of the prep, again")
		must(approve(g.main))
		trackerfix.elsewhere(g, { [`{ISSUE}/{ID}.md`] = doc("A sixth design.") }, "and a later one")
		local left = headOf(PREP)
		local later = must(approve(g.main))
		t.expect(has(later, `{ID}: approving in origin/main`)).toBe(true)
		t.expect(has(later, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(headOf(PREP)).toBe(left)
	end)
end)
