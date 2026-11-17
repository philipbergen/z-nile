--!strict
-- c0138 AC2: `trail.read` starts a new life at a commit that changed the compaction map and an item's document
-- only for an item that commit renames, read from the map as the commit leaves it. Fixture under .cache/c0138-kept
-- (tests/lib/trackerfix): `./zn capture <id>` and a small Lune script that calls `trail.read` with a review filter run
-- in it. Another terminal (the fixture's `other` clone) pushes every commit; the commands only read.
--
-- The fixture, in commit order (design review 004 F5): items c0010 (a kept item with a first review), c0300, c0020 (done),
-- c0500, the raft R0010, c0090, c0011, c0012, c0070; an old compaction in the retired map's file (tracker/compaction.txt,
-- which stays in the tree) that names c0070 and rewrites c0012 in place; a commit with a map that does not parse, which
-- rewrites c0011 and edits c0010's review file; the compaction (map: c0010 c0010, c0020 c0004, c0300 c0030, c0500 c0020),
-- which keeps c0010 and the raft and rewrites them in place, renumbers c0300 to c0030 and the done c0020 to c0004, and gives
-- the done c0020 to c0500 at the same path; a commit that repeats the map's pairs under a new header, adds c0090 c0009
-- and rewrites c0010, c0030 and c0090 in place and adds c0013; a second compaction whose whole map keeps every id; then
-- c0014 to c0019 and the commits that change both map files, one that does not parse (first, then last), the current map
-- deleted beside a changed retired one, and the current map's path turned into a submodule entry. `broken` sits before
-- the compaction on purpose: no fail-closed commit may stand right before a case that pins "this commit's data only".

local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local P = "pickman/.tracker"
local MAP = "z-nile/compaction.txt"
local LEGACY_MAP = "tracker/compaction.txt"
local f: trackerfix.Fixture
local SHA: { [string]: string } = {}

local function doc(id: string, line: string): string
	return trackerfix.stub(id, id, "new-a-b-c") .. `\n## Problem\n{line}\n`
end

-- `other` commits `files` (false removes a path) with `message`, pushes, and remembers the sha under `key`
local function push(key: string, files: { [string]: string | false }, message: string)
	fixture.git(f.other, { "pull", "-q", "origin", "main" })
	for path, text in files do
		if text == false then
			fixture.git(f.other, { "rm", "-q", "-r", path })
		else
			local parent = string.match(path, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{f.other}/{parent}`)
			end
			fs.writeFile(`{f.other}/{path}`, text :: string)
		end
	end
	fixture.git(f.other, { "add", "-A" })
	fixture.git(f.other, { "commit", "-q", "-m", message })
	fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
	SHA[key] = fixture.git(f.other, { "rev-parse", "HEAD" })
end

local function capture(id: string): (string, string)
	fixture.git(f.main, { "fetch", "-q", "origin" })
	local r = trackerfix.tr(f, f.main, { "capture", id })
	t.expect(r.code).toBe(0)
	return string.match(r.stdout, "^[^\n]+") :: string, r.stdout
end

local function short(sha: string): string
	return string.sub(sha, 1, 7)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- the marker `capture` puts on a life that starts at the compaction commit `key`
local function notFollowed(key: string): string
	return `(history before {short(SHA[key])} not followed: it changed {MAP})`
end

-- the same marker when the commit changed more than one map file, so the file it names is the first of them
local function restartedAt(head: string, key: string): boolean
	return has(head, `(history before {short(SHA[key])} not followed`)
end

return t.spec("c0138 a compaction starts a new life only for the ids its map renames", function(it)
	it(
		"sets up a fixture: kept, renumbered and reused ids, a compaction, a repeated map and a broken one",
		function()
			f = trackerfix.new("c0138-kept", {})
			push(
				"kept",
				{ [`{P}/issues/c0010/c0010.md`] = doc("c0010", "kept, as captured") },
				"tracker: new c0010 Kept"
			)
			push("prep", {
				[`{P}/issues/c0010/c0010.md`] = doc("c0010", "kept, prepped, depends on c0300"),
				[`{P}/issues/c0010/design-review-001.md`] = "# Review 001\n\nit names c0300\n",
			}, "tracker: prep c0010 Kept")
			push(
				"moved",
				{ [`{P}/issues/c0300/c0300.md`] = doc("c0300", "moved") },
				"tracker: new c0300 Moved"
			)
			push(
				"old20",
				{ [`{P}/issues/c0020/c0020.md`] = doc("c0020", "old twenty") },
				"tracker: new c0020 Old twenty"
			)
			push("done20", {
				[`{P}/issues/c0020`] = false,
				[`{P}/issues/done/c0020/c0020.md`] = doc("c0020", "old twenty"),
			}, "R0020: done")
			push(
				"new500",
				{ [`{P}/issues/c0500/c0500.md`] = doc("c0500", "newcomer") },
				"tracker: new c0500 Newcomer"
			)
			push("raft", {
				[`{P}/rafts/active/R0010/R0010.md`] = trackerfix.stub("R0010", "r", "new-d-e-f")
					.. "\nnames c0300\n",
			}, "tracker: new raft R0010 r")
			push("hand", { [`{P}/issues/c0090/c0090.md`] = doc("c0090", "hand") }, "tracker: new c0090 Hand")
			push(
				"eleven",
				{ [`{P}/issues/c0011/c0011.md`] = doc("c0011", "eleven") },
				"tracker: new c0011 Eleven"
			)
			push(
				"twelve",
				{ [`{P}/issues/c0012/c0012.md`] = doc("c0012", "twelve") },
				"tracker: new c0012 Twelve"
			)
			push(
				"seventy",
				{ [`{P}/issues/c0070/c0070.md`] = doc("c0070", "seventy") },
				"tracker: new c0070 Seventy"
			)
			-- an old compaction, in the retired map's file, that renames other ids and rewrites c0012 in place
			push("legacy", {
				[LEGACY_MAP] = "# old compaction\nc0700 c0070\n",
				[`{P}/issues/c0012/c0012.md`] = doc("c0012", "twelve, depends on c0070"),
			}, "tracker: compact ids (old)")
			-- a map that no longer parses, in a commit that rewrites a kept item in place
			push("broken", {
				[MAP] = "# broken\nnot a map line\n",
				[`{P}/issues/c0011/c0011.md`] = doc("c0011", "eleven, edited"),
				-- and a review file of c0010 changes in the same commit, with no change to c0010's document
				[`{P}/issues/c0010/design-review-001.md`] = "# Review 001\n\nit names c0300, edited\n",
			}, "R0011: prep with a broken map")
			-- the compaction: it writes its whole map, renames some folders and rewrites, in place, the kept documents
			-- that name a renumbered id
			push("compact", {
				[MAP] = "# ./zn compact, test\nc0010 c0010\nc0020 c0004\nc0300 c0030\nc0500 c0020\n",
				[`{P}/issues/c0010/c0010.md`] = doc("c0010", "kept, prepped, depends on c0030"),
				[`{P}/issues/c0010/design-review-001.md`] = "# Review 001\n\nit names c0030\n",
				[`{P}/issues/c0070/c0070.md`] = doc("c0070", "seventy, depends on c0030"),
				[`{P}/rafts/active/R0010/R0010.md`] = trackerfix.stub("R0010", "r", "new-d-e-f")
					.. "\nnames c0030\n",
				[`{P}/issues/c0300`] = false,
				[`{P}/issues/c0030/c0030.md`] = doc("c0030", "moved"),
				[`{P}/issues/c0500`] = false,
				[`{P}/issues/done/c0020/c0020.md`] = doc("c0020", "newcomer"),
				[`{P}/issues/done/c0004/c0004.md`] = doc("c0004", "old twenty"),
			}, "tracker: compact ids")
			-- later: the same pairs word for word under a new header, one more pair, and three documents rewritten
			push("again", {
				[MAP] = "# edited by hand\nc0010 c0010\nc0020 c0004\nc0300 c0030\nc0500 c0020\nc0090 c0009\n",
				[`{P}/issues/c0010/c0010.md`] = doc("c0010", "kept, prepped, depends on c0030, edited"),
				[`{P}/issues/c0030/c0030.md`] = doc("c0030", "moved, edited"),
				[`{P}/issues/c0090/c0090.md`] = doc("c0090", "hand, edited"),
				[`{P}/issues/c0013/c0013.md`] = doc("c0013", "thirteen, first here"),
			}, "tracker: map edited by hand")
			-- a second compaction: its whole map keeps every id the first one renamed, and rewrites two of them in place
			push("compact2", {
				[MAP] = "# ./zn compact 2\nc0004 c0004\nc0010 c0010\nc0011 c0011\nc0020 c0020\nc0030 c0030\n",
				[`{P}/issues/done/c0020/c0020.md`] = doc("c0020", "newcomer, depends on c0030"),
				[`{P}/issues/done/c0004/c0004.md`] = doc("c0004", "old twenty, depends on c0030"),
			}, "tracker: compact ids again")
			-- four more items, then commits that change several map files at once (design review 002 F2)
			push("fourteen", {
				[`{P}/issues/c0014/c0014.md`] = doc("c0014", "fourteen"),
				[`{P}/issues/c0015/c0015.md`] = doc("c0015", "fifteen"),
				[`{P}/issues/c0016/c0016.md`] = doc("c0016", "sixteen"),
				[`{P}/issues/c0017/c0017.md`] = doc("c0017", "seventeen"),
				[`{P}/issues/c0018/c0018.md`] = doc("c0018", "eighteen"),
				[`{P}/issues/c0019/c0019.md`] = doc("c0019", "nineteen"),
			}, "tracker: new c0014 Fourteen")
			-- both map files change in one commit: c0014 is named by the current one, c0015 by the retired one
			push("both", {
				[LEGACY_MAP] = "# old compaction\nc0700 c0070\nc0150 c0015\n",
				[MAP] = "# both\nc0140 c0014\n",
				[`{P}/issues/c0014/c0014.md`] = doc("c0014", "fourteen, edited"),
				[`{P}/issues/c0015/c0015.md`] = doc("c0015", "fifteen, edited"),
			}, "tracker: both maps")
			-- both map files change and one of them does not parse: the retired one (listed first), then the current one
			push("badold", {
				[LEGACY_MAP] = "# broken old\nnot a map line\n",
				[MAP] = "# fine\nc0141 c0014\n",
				[`{P}/issues/c0018/c0018.md`] = doc("c0018", "eighteen, edited"),
			}, "tracker: one old map that does not parse")
			push("badnew", {
				[LEGACY_MAP] = "# old compaction\nc0700 c0070\n",
				[MAP] = "# broken new\nnope\n",
				[`{P}/issues/c0019/c0019.md`] = doc("c0019", "nineteen, edited"),
			}, "tracker: one new map that does not parse")
			-- the current map is deleted and the retired one changed, in a commit that rewrites c0016 in place
			push("dropped", {
				[MAP] = false,
				[LEGACY_MAP] = "# old compaction, again\nc0710 c0071\n",
				[`{P}/issues/c0016/c0016.md`] = doc("c0016", "sixteen, edited"),
			}, "tracker: drop the current map")
			-- the current map's path becomes a submodule entry: listed as added, but `git show` can't read it
			fixture.git(f.other, { "pull", "-q", "origin", "main" })
			fs.writeFile(`{f.other}/{LEGACY_MAP}`, "# old compaction, third\nc0720 c0072\n")
			fs.writeFile(`{f.other}/{P}/issues/c0017/c0017.md`, doc("c0017", "seventeen, edited"))
			fixture.git(f.other, { "add", LEGACY_MAP, `{P}/issues/c0017/c0017.md` })
			fixture.git(
				f.other,
				{ "update-index", "--add", "--cacheinfo", `160000,{string.rep("1", 40)},{MAP}` }
			)
			fixture.git(f.other, { "commit", "-q", "-m", "tracker: a submodule where the map was" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			SHA.gitlink = fixture.git(f.other, { "rev-parse", "HEAD" })
		end
	)

	it(
		"keeps an id the compaction keeps (a pair whose sides agree), though two commits rewrite it in place",
		function()
			local head, out = capture("c0010")
			t.expect(head).toBe(`capture {SHA.kept} {P}/issues/c0010/c0010.md tracker: new c0010 Kept`)
			t.expect(has(out, "kept, as captured")).toBe(true)
			t.expect(has(out, "not followed")).toBe(false)
		end
	)

	it("keeps a raft the compaction keeps and rewrites in place", function()
		local head = capture("R0010")
		t.expect(has(head, `capture {SHA.raft} {P}/rafts/active/R0010/R0010.md tracker: new raft R0010 r`))
			.toBe(true)
		t.expect(has(head, "not followed")).toBe(false)
	end)

	it("finds a kept item's first review across the compaction", function()
		-- trail.read with a review filter, as a first-review lookup would call it
		local script = table.concat({
			"local trail = req" .. 'uire("./z-nile/engine/trail")',
			"local commits, notes = trail.read('issues', 'c0010', function(name)",
			"\treturn string.match(name, '^design%-review%-%d+%.md$') ~= nil",
			"end, 'HEAD')",
			"for _, c in commits or {} do",
			"\tprint(c.sha .. ' ' .. c.status)",
			"end",
			"print('notes ' .. #notes)",
			"",
		}, "\n")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		fs.writeFile(`{f.main}/first-review.luau`, script)
		local r = fixture.exec(f.main, "lune", { "run", "first-review.luau" })
		t.expect(r.code).toBe(0)
		t.expect(r.stdout).toBe(`{SHA.compact} M\n{SHA.broken} M\n{SHA.prep} A\nnotes 0\n`)
	end)

	it(
		"reads the ids a compaction commit renames from the map it leaves, and a commit that changed no map as unreadable",
		function()
			-- trail.renames on four of the fixture's commits: the compaction, the commit that repeats its pairs under a new
			-- header, a prep commit that changed no map, and the old compaction in the retired file
			local script = table.concat({
				"local trail = req" .. 'uire("./z-nile/engine/trail")',
				"local process = req" .. 'uire("@lune/process")',
				"for _, sha in process.args do",
				"\tlocal got = trail.renames(sha)",
				"\tlocal names = {}",
				"\tfor id in got or {} do",
				"\t\ttable.insert(names, id)",
				"\tend",
				"\ttable.sort(names)",
				"\tprint(if got then table.concat(names, ' ') else 'nil')",
				"end",
				"",
			}, "\n")
			fs.writeFile(`{f.main}/renames.luau`, script)
			local r = fixture.exec(
				f.main,
				"lune",
				{ "run", "renames.luau", SHA.compact, SHA.again, SHA.prep, SHA.legacy, SHA.compact2 }
			)
			t.expect(r.code).toBe(0)
			-- the compaction's map names c0020 c0004 c0300 c0030 c0500 (c0010 c0010 agrees); the repeat adds c0090 c0009;
			-- the old compaction's map is the retired file's, and does not mix into the later ones; the second compaction's map
			-- keeps every id (a whole map of pairs whose sides agree), so it renames nothing: an empty line, not nil
			t.expect(r.stdout)
				.toBe(
					"c0004 c0020 c0030 c0300 c0500\nc0004 c0009 c0020 c0030 c0090 c0300 c0500\nnil\nc0070 c0700\n\n"
				)
		end
	)

	it("starts a new life at a renumbered id's arrival, and marks it", function()
		local head, out = capture("c0004")
		t.expect(has(head, `capture {SHA.compact} {P}/issues/done/c0004/c0004.md`)).toBe(true)
		t.expect(has(head, notFollowed("compact"))).toBe(true)
		t.expect(has(out, "old twenty")).toBe(true)
	end)

	it(
		"stops an id the compaction gives to another item at the compaction, though its path is the same",
		function()
			local head, out = capture("c0020")
			t.expect(has(head, `capture {SHA.compact} {P}/issues/done/c0020/c0020.md`)).toBe(true)
			t.expect(has(head, notFollowed("compact"))).toBe(true)
			t.expect(has(out, "newcomer")).toBe(true)
			t.expect(has(out, "old twenty")).toBe(false)
			t.expect(has(head, short(SHA.done20))).toBe(false)
		end
	)

	it(
		"restarts at a later commit that repeats a renamed pair word for word and rewrites the document",
		function()
			-- c0030 was renamed by the first compaction; the later map lists the same pair, so a diff would miss it
			local head = capture("c0030")
			t.expect(has(head, `capture {SHA.again} {P}/issues/c0030/c0030.md`)).toBe(true)
			t.expect(has(head, notFollowed("again"))).toBe(true)
			t.expect(has(head, notFollowed("compact"))).toBe(false)
		end
	)

	it("restarts an id that stands on the old side of a pair alone", function()
		local head = capture("c0090")
		t.expect(has(head, `capture {SHA.again} {P}/issues/c0090/c0090.md`)).toBe(true)
		t.expect(has(head, notFollowed("again"))).toBe(true)
	end)

	it("reads the retired map's file the same way: a kept id stays", function()
		local head, out = capture("c0012")
		t.expect(head).toBe(`capture {SHA.twelve} {P}/issues/c0012/c0012.md tracker: new c0012 Twelve`)
		t.expect(has(out, "not followed")).toBe(false)
	end)

	it("does not count a map file the commit left alone: the retired map still names c0070", function()
		-- the old compaction named c0070 and its file stays in the tree; the later compaction rewrites c0070 in place
		-- and changed only the current map file
		local head, out = capture("c0070")
		t.expect(head).toBe(`capture {SHA.seventy} {P}/issues/c0070/c0070.md tracker: new c0070 Seventy`)
		t.expect(has(out, "not followed")).toBe(false)
	end)

	it(
		"keeps the earlier compaction's restart when a later compaction keeps the id and rewrites it in place",
		function()
			-- the second compaction's map holds c0020 c0020 and c0004 c0004; neither is renamed again, so neither restarts
			local head20 = capture("c0020")
			t.expect(has(head20, `capture {SHA.compact} `)).toBe(true)
			t.expect(has(head20, notFollowed("compact"))).toBe(true)
			t.expect(has(head20, notFollowed("compact2"))).toBe(false)
			local head4 = capture("c0004")
			t.expect(has(head4, notFollowed("compact"))).toBe(true)
			t.expect(has(head4, notFollowed("compact2"))).toBe(false)
		end
	)

	it(
		"marks an item that first appears in a commit that changed the map, though the map does not name it",
		function()
			-- c0013 is added by the commit that edits the map by hand; the map names other ids only
			local head = capture("c0013")
			t.expect(has(head, `capture {SHA.again} {P}/issues/c0013/c0013.md`)).toBe(true)
			t.expect(has(head, notFollowed("again"))).toBe(true)
		end
	)

	it("reads every map file one commit changed: each one names the items it names", function()
		-- c0014 is named only by the current map, c0015 only by the retired one; the commit changed both
		for _, id in { "c0014", "c0015" } do
			local head = capture(id)
			t.expect(has(head, `capture {SHA.both} {P}/issues/{id}/{id}.md`)).toBe(true)
			t.expect(restartedAt(head, "both")).toBe(true)
		end
	end)

	it("restarts an item when one of two map files a commit changed does not parse, first or last", function()
		-- badold: the retired map (listed first) is broken beside a current map that parses and names nothing here
		t.expect(restartedAt(capture("c0018"), "badold")).toBe(true)
		-- badnew: the current map (listed last) is broken beside a retired map that parses
		t.expect(restartedAt(capture("c0019"), "badnew")).toBe(true)
	end)

	it(
		"reads only the map files a commit added or changed: a deleted one beside a changed one starts nothing",
		function()
			-- c0016 is rewritten in place by the commit that deletes the current map and changes the retired one
			local head, out = capture("c0016")
			t.expect(head).toBe(
				`capture {SHA.fourteen} {P}/issues/c0016/c0016.md tracker: new c0014 Fourteen (no capture commit: first add)`
			)
			t.expect(has(out, "not followed")).toBe(false)
		end
	)

	it("restarts an item when a map file the commit changed can't be read", function()
		-- the commit's listing names the map path and `git show` fails on it, though the retired map beside it parses
		local head = capture("c0017")
		t.expect(has(head, `capture {SHA.gitlink} {P}/issues/c0017/c0017.md`)).toBe(true)
		t.expect(restartedAt(head, "gitlink")).toBe(true)
	end)

	it("restarts every item a commit touches when its map does not parse", function()
		local head = capture("c0011")
		t.expect(has(head, `capture {SHA.broken} {P}/issues/c0011/c0011.md`)).toBe(true)
		t.expect(has(head, notFollowed("broken"))).toBe(true)
	end)
end)
