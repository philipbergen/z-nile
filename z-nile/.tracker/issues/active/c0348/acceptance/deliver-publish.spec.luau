--!strict
-- c0348: `./zn spend <id> --phase deliver` for work that is done on origin/main publishes its row there, because the
-- raft has landed and no branch is left to carry it. It is one commit that appends the row to the done issue's
-- spend.d/<writer>.tsv and changes nothing else. Every other spend row still stays on its branch. The publisher takes
-- such a file only under done/, beside the issue's document, and only as an append of rows that holds a deliver row.
-- Only the rows of that one call are published: a worktree whose copy of the file is not origin's keeps the row on its
-- branch (it holds rows that have not landed) or is told to sync (it lacks rows origin holds).
-- (The same command after a real `./zn done` is pinned in tests/acceptance/d0333/commit-land.spec.luau.)
-- Fixture under .cache/c0348-deliver-publish: a bare origin, a main checkout, a second clone and a worktree.
local buffer = require("@znile/engine/buffer")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local STAMP = "quiet-copper-falcon"
local ROOT = "pickman/.tracker"
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

local f: trackerfix.Fixture
local wt = ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end
local function tip(): string
	return git(f.origin, { "rev-parse", "main" })
end
-- the one parent of origin's main ("" for the seed commit, so a missing publish fails an assertion, not git)
local function parent(): string
	return git(f.origin, { "log", "-1", "--format=%P", "main" })
end
local function zn(args: { string }): fixture.Result
	return trackerfix.tr(f, wt, args)
end
local function znOk(args: { string }): string
	local r = zn(args)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function issue(id: string, raft: string, status: string): string
	return table.concat({
		"---",
		`id: {id}`,
		"type: chore",
		`title: {id} title`,
		`slug: {id}`,
		`raft: {raft}`,
		"depends_on: []",
		"emergent: false",
		"design: ready",
		"created: 2026-11-15",
		`status: {status}`,
		"---",
		"",
		`# {id}: {id} title`,
		"",
	}, "\n")
end
local function raftDoc(id: string, members: string): string
	return table.concat({
		"---",
		`id: {id}`,
		"type: chore",
		"title: landed pair",
		"slug: landed-pair",
		"single: false",
		`issues: [{members}]`,
		"design: ready",
		"created: 2026-11-15",
		`status: active-{STAMP}`,
		"---",
		"",
		`# {id}: landed pair`,
		"",
	}, "\n")
end
-- the measured rows of an issue in the worktree's files, over every writer
local function rows(dir: string): number
	local n = 0
	if fs.isDir(`{wt}/{dir}/spend.d`) then
		for _, name in fs.readDir(`{wt}/{dir}/spend.d`) do
			local parsed = buffer.parseTsv(fs.readFile(`{wt}/{dir}/spend.d/{name}`))
			n += #(parsed :: { any })
		end
	end
	return n
end
-- the worktree back on origin's main, as a raft's worktree is right after `./zn done`
local function onMain()
	git(wt, { "fetch", "-q", "origin", "main" })
	git(wt, { "reset", "-q", "--hard", "origin/main" })
end

local DONE = `{ROOT}/issues/done/c0010`

return t.spec("c0348 a landed raft's deliver row reaches origin/main", function(it)
	it("sets up a done issue, a done raft of two, a backlog issue and a worktree", function()
		f = trackerfix.new("c0348-deliver-publish", {
			["z-nile/projects.toml"] = PROJECTS,
			[`{DONE}/c0010.md`] = issue("c0010", "", `active-{STAMP}`),
			[`{ROOT}/issues/done/c0020/c0020.md`] = issue("c0020", "R0010", `active-{STAMP}`),
			[`{ROOT}/issues/done/c0030/c0030.md`] = issue("c0030", "R0010", `active-{STAMP}`),
			[`{ROOT}/rafts/done/R0010/R0010.md`] = raftDoc("R0010", "c0020, c0030"),
			[`{ROOT}/issues/c0040/c0040.md`] = issue("c0040", "", `new-{STAMP}`),
		}, { noLessons = true })
		wt = trackerfix.trOk(f, f.main, { "worktree", "after-done" })
		t.expect(fs.isDir(`{wt}/{DONE}`)).toBe(true)
	end)

	it("a deliver row for a done issue is published as one commit that only appends that row", function()
		local before, head = tip(), git(wt, { "rev-parse", "HEAD" })
		local out = znOk({ "spend", "c0010", "--phase", "deliver" })
		-- one commit on origin's main, made by the command: nothing in this spec pushes for it
		local landed = tip()
		t.expect(parent()).toBe(before)
		t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" })).toBe("tracker: spend c0010 deliver")
		t.expect(has(out, `published c0010 deliver to origin/main {landed}`)).toBe(true)
		local file = git(f.origin, { "diff", "--name-only", before, landed })
		t.expect(string.match(file, "^pickman/%.tracker/issues/done/c0010/spend%.d/[%w._%-]+%.tsv$") ~= nil)
			.toBe(true)
		local parsed = buffer.parseTsv(git(f.origin, { "show", `main:{file}` }) .. "\n") :: { any }
		t.expect(#parsed).toBe(1)
		t.expect(parsed[1].phase).toBe("deliver")
		-- the worktree holds the same file in one commit of its own, and is clean
		t.expect(git(wt, { "rev-parse", "HEAD~1" })).toBe(head)
		t.expect(git(wt, { "diff", "--name-only", head, "HEAD" })).toBe(file)
		t.expect(git(wt, { "show", `HEAD:{file}` })).toBe(git(f.origin, { "show", `main:{file}` }))
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		-- a second row from this checkout is appended to the file origin now holds: one line more, none changed
		znOk({ "spend", "c0010", "--phase", "deliver", "--note", "again" })
		t.expect(parent()).toBe(landed)
		t.expect(git(f.origin, { "diff", "--numstat", landed, "main" })).toBe(`1\t0\t{file}`)
		t.expect(git(wt, { "show", `HEAD:{file}` })).toBe(git(f.origin, { "show", `main:{file}` }))
	end)

	it("a done raft's deliver row is shared over its done members in one published commit", function()
		onMain()
		local before = tip()
		local out = znOk({ "spend", "R0010", "--phase", "deliver" })
		local landed = tip()
		t.expect(parent()).toBe(before)
		t.expect(git(f.origin, { "log", "-1", "--format=%s", "main" })).toBe("tracker: spend R0010 deliver")
		t.expect(has(out, `published R0010 deliver to origin/main {landed}`)).toBe(true)
		local files = string.split(git(f.origin, { "diff", "--name-only", before, landed }), "\n")
		t.expect(#files).toBe(2)
		t.expect(has(files[1], `{ROOT}/issues/done/c0020/spend.d/`)).toBe(true)
		t.expect(has(files[2], `{ROOT}/issues/done/c0030/spend.d/`)).toBe(true)
		-- nothing is written for the raft itself: its summary is not a published file
		t.expect(has(git(f.origin, { "ls-tree", "-r", "--name-only", "main", `{ROOT}/rafts` }), "spend"))
			.toBe(false)
	end)

	it("a deliver row for an item that is not done stays on the branch, and the command says so", function()
		onMain()
		local before, head = tip(), git(wt, { "rev-parse", "HEAD" })
		local r = zn({ "spend", "c0040", "--phase", "deliver" })
		t.expect(r.ok).toBe(true)
		t.expect(tip()).toBe(before)
		t.expect(has(r.stdout, "published")).toBe(false)
		t.expect(has(r.stderr, "c0040 is not done on origin/main")).toBe(true)
		t.expect(has(r.stderr, "stays on this branch")).toBe(true)
		t.expect(git(wt, { "rev-parse", "HEAD~1" })).toBe(head)
		t.expect(rows(`{ROOT}/issues/c0040`)).toBe(1)
	end)

	it("the other phases never publish, for a done item either, and say nothing about it", function()
		onMain()
		for _, phase in { "capture", "prep", "design-review" } do
			local before, head = tip(), git(wt, { "rev-parse", "HEAD" })
			local r = zn({ "spend", "c0010", "--phase", phase })
			t.expect(r.ok).toBe(true)
			t.expect(tip()).toBe(before)
			t.expect(has(r.stdout, "published")).toBe(false)
			t.expect(has(r.stderr, "not done")).toBe(false)
			t.expect(git(wt, { "rev-parse", "HEAD~1" })).toBe(head)
		end
		-- `--begin` marks a start and records no row, so it publishes nothing for deliver either
		local before, head = tip(), git(wt, { "rev-parse", "HEAD" })
		znOk({ "spend", "c0010", "--phase", "deliver", "--begin" })
		t.expect(tip()).toBe(before)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
	end)

	it(
		"rows this branch has not landed keep the deliver row on the branch too, and the command says so",
		function()
			-- no reset: the case above left capture, prep and design-review rows for c0010 on this branch only
			local before, head = tip(), git(wt, { "rev-parse", "HEAD" })
			local r = zn({ "spend", "c0010", "--phase", "deliver", "--note", "rides-the-branch" })
			t.expect(r.ok).toBe(true)
			t.expect(tip()).toBe(before)
			t.expect(has(r.stdout, "published")).toBe(false)
			t.expect(has(r.stderr, "c0010's rows on this branch are not on origin/main yet")).toBe(true)
			t.expect(has(r.stderr, "stays on this branch")).toBe(true)
			t.expect(git(wt, { "rev-parse", "HEAD~1" })).toBe(head)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			local onOrigin = git(f.origin, { "grep", "-h", "-e", "", "main", "--", `{DONE}/spend.d` })
			t.expect(has(onOrigin, "\tcapture\t")).toBe(false)
			t.expect(has(onOrigin, "rides-the-branch")).toBe(false)
		end
	)

	it("a checkout that lacks rows origin holds records nothing and asks for a sync", function()
		onMain()
		local file = `{DONE}/spend.d/{fs.readDir(`{wt}/{DONE}/spend.d`)[1]}`
		local current = fs.readFile(`{wt}/{file}`)
		local parsed = buffer.parseTsv(current) :: { any }
		local row = table.clone(parsed[#parsed])
		row.subject = "from another checkout"
		-- origin gains a row in this writer's file that this worktree has not fetched into its files
		local pushed = publish.commit(f.other, function()
			return { { path = file, content = buffer.appendTsv(current, { row }) } }
		end, "tracker: spend rows")
		t.expect(pushed.ok).toBe(true)
		local before, head, had = tip(), git(wt, { "rev-parse", "HEAD" }), rows(DONE)
		local r = zn({ "spend", "c0010", "--phase", "deliver" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, `{file} has rows on origin/main that this checkout lacks`)).toBe(true)
		t.expect(has(r.stderr, "run ./zn sync, then record again")).toBe(true)
		t.expect(tip()).toBe(before)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		t.expect(rows(DONE)).toBe(had)
		-- how the two copies stand, by bytes
		t.expect(publish.rowsRelation(nil, nil)).toBe("same")
		t.expect(publish.rowsRelation("a\n", "a\n")).toBe("same")
		t.expect(publish.rowsRelation(nil, "a\n")).toBe("behind")
		t.expect(publish.rowsRelation("a\n", "a\nb\n")).toBe("behind")
		t.expect(publish.rowsRelation("a\nb\n", "a\n")).toBe("ahead")
		t.expect(publish.rowsRelation("a\n", nil)).toBe("ahead")
		t.expect(publish.rowsRelation("a\nb\n", "a\nc\n")).toBe("diverged")
	end)

	it("a deliver publish that fails records nothing, and the next run records one row", function()
		onMain()
		-- origin refuses every push, so the publish can't land
		local hook = `{f.origin}/hooks/pre-receive`
		fs.writeFile(hook, "#!/bin/sh\necho refused by the fixture >&2\nexit 1\n")
		process.exec("chmod", { "+x", hook })
		-- a pending start in the measure buffer: a failed publish must leave the buffer byte for byte
		znOk({ "spend", "c0010", "--phase", "deliver", "--begin" })
		local measure = `{wt}/.cache/measure.tsv`
		local buffered = fs.readFile(measure)
		t.expect(has(buffered, "begin")).toBe(true)
		local before, head, had = tip(), git(wt, { "rev-parse", "HEAD" }), rows(DONE)
		local r = zn({ "spend", "c0010", "--phase", "deliver" })
		t.expect(r.ok).toBe(false)
		t.expect(fs.readFile(measure)).toBe(buffered)
		t.expect(has(r.stderr, "could not publish c0010's deliver row to origin/main")).toBe(true)
		t.expect(has(r.stderr, "nothing was recorded")).toBe(true)
		t.expect(tip()).toBe(before)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		t.expect(rows(DONE)).toBe(had)
		fs.removeFile(hook)
		znOk({ "spend", "c0010", "--phase", "deliver" })
		t.expect(parent()).toBe(before)
		t.expect(rows(DONE)).toBe(had + 1)
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		-- the recorded run took the start it was measured from
		t.expect(fs.isFile(measure) and has(fs.readFile(measure), "begin")).toBe(false)
	end)

	it(
		"a local commit that fails after the publish warns, leaves the tree as it was, and a sync brings the row",
		function()
			onMain()
			-- the fixture's own repository refuses every commit; the publish, which makes none here, still lands
			local hooks = git(wt, { "rev-parse", "--path-format=absolute", "--git-common-dir" }) .. "/hooks"
			fs.writeDir(hooks)
			fs.writeFile(`{hooks}/pre-commit`, "#!/bin/sh\necho refused by the fixture >&2\nexit 1\n")
			process.exec("chmod", { "+x", `{hooks}/pre-commit` })
			local before, head, had = tip(), git(wt, { "rev-parse", "HEAD" }), rows(DONE)
			local r = zn({ "spend", "c0010", "--phase", "deliver" })
			fs.removeFile(`{hooks}/pre-commit`)
			t.expect(r.ok).toBe(true)
			local landed = tip()
			t.expect(parent()).toBe(before)
			t.expect(has(r.stdout, `published c0010 deliver to origin/main {landed}`)).toBe(true)
			t.expect(has(r.stderr, `the row is on origin/main ({landed}) but could not be committed here`))
				.toBe(true)
			t.expect(has(r.stderr, "./zn sync brings it")).toBe(true)
			t.expect(has(r.stderr, "Do not record it again")).toBe(true)
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			t.expect(rows(DONE)).toBe(had)
			-- the advice works from that state: the sync brings the row, and the next deliver publishes one more
			znOk({ "sync" })
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			t.expect(rows(DONE)).toBe(had + 1)
			znOk({ "spend", "c0010", "--phase", "deliver" })
			t.expect(parent()).toBe(landed)
			t.expect(rows(DONE)).toBe(had + 2)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		end
	)

	it("the publisher's path rule takes a spend.d file only for a done issue of a registered root", function()
		local roots = { ROOT }
		local name = "host-0000abcd.tsv"
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/spend.d/{name}`, roots)).toBe(true)
		t.expect(publish.allowed(`{ROOT}/issues/c0010/spend.d/{name}`, roots)).toBe(false)
		t.expect(publish.allowed(`{ROOT}/issues/active/c0010/spend.d/{name}`, roots)).toBe(false)
		t.expect(publish.allowed(`{ROOT}/rafts/done/R0010/spend.d/{name}`, roots)).toBe(false)
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/spend.d/notes.md`, roots)).toBe(false)
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/spend.d/deep/{name}`, roots)).toBe(false)
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/spend.d/..tsv/../{name}`, roots)).toBe(false)
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/acceptance/{name}`, roots)).toBe(false)
		t.expect(publish.allowed(`other/.tracker/issues/done/c0010/spend.d/{name}`, roots)).toBe(false)
		-- what it took before is as it was
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/c0010.md`, roots)).toBe(true)
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/spend.md`, roots)).toBe(true)
		t.expect(publish.allowed(`{ROOT}/issues/done/c0010/acceptance/a.spec.luau`, roots)).toBe(false)
	end)

	it("the publisher takes a done issue's spend.d file only as an append of rows", function()
		git(f.other, { "pull", "-q", "origin", "main" })
		local dir = `{DONE}/spend.d`
		t.expect(fs.isDir(`{f.other}/{dir}`)).toBe(true) -- the rows the cases above published
		local file = `{dir}/{fs.readDir(`{f.other}/{dir}`)[1]}`
		local current = git(f.origin, { "show", `main:{file}` }) .. "\n"
		local parsed = buffer.parseTsv(current) :: { any }
		t.expect(#parsed >= 2).toBe(true)
		local row = table.clone(parsed[#parsed])
		row.subject = "appended by the library"
		local good = buffer.appendTsv(current, { row })
		local fresh = buffer.appendTsv(nil, { row })
		local before = tip()
		local function refused(path: string, content: string, needle: string)
			local r = publish.commit(f.other, function()
				return { { path = path, content = content } }
			end, "tracker: spend rows")
			if r.ok then
				error(`published {path}`, 2)
			end
			if not has(r.reason, needle) then
				error(`{path}: the reason lacks "{needle}": {r.reason}`, 2)
			end
			if not has(r.reason, path) then
				error(`{path}: the reason does not name the path: {r.reason}`, 2)
			end
			t.expect(tip()).toBe(before)
		end
		-- a row of origin's dropped or changed, even with a row appended after it
		local first = string.find(current, "\n", 1, true) :: number
		local second = string.find(current, "\n", first + 1, true) :: number
		refused(file, string.sub(good, 1, first) .. string.sub(good, second + 1), "not an append")
		refused(file, (string.gsub(good, "deliver", "capture", 1)), "not an append")
		refused(file, current, "no new row")
		refused(file, current .. "not a row\n", "does not parse")
		refused(file, string.sub(good, 1, -2), "no newline")
		-- what is appended always holds a deliver row: rows of other phases alone are some branch's, never published
		local capture = table.clone(row)
		capture.phase = "capture"
		local other = table.clone(row)
		other.phase = "other"
		refused(file, buffer.appendTsv(current, { capture }), "no deliver row")
		refused(file, buffer.appendTsv(current, { other }), "no deliver row")
		good = buffer.appendTsv(current, { other, row }) -- a measure line folded with the deliver row
		-- only beside a done issue's document: a missing issue, and an issue that is not done
		refused(`{ROOT}/issues/done/c0987/spend.d/h.tsv`, fresh, "no c0987.md")
		refused(`{ROOT}/issues/c0040/spend.d/h.tsv`, fresh, "not a tracker item file")
		local appended = publish.commit(f.other, function()
			return { { path = file, content = good } }
		end, "tracker: spend rows")
		t.expect(appended.ok).toBe(true)
		t.expect(git(f.origin, { "show", `main:{file}` }) .. "\n").toBe(good)
		-- another writer's file beside it starts with the header and its first row
		local added = publish.commit(f.other, function()
			return { { path = `{dir}/h.tsv`, content = fresh } }
		end, "tracker: spend rows")
		t.expect(added.ok).toBe(true)
		t.expect(git(f.origin, { "show", `main:{dir}/h.tsv` }) .. "\n").toBe(fresh)
	end)
end)
