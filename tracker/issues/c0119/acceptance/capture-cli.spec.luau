--!strict
-- c0119 AC4: `scripts/tracker.sh capture <id>` prints an item's document as captured, read from origin/main, in a
-- tracker fixture under .cache/capture-cli (tests/lib/trackerfix). Another terminal (the fixture's `other` clone)
-- pushes every commit; the command only reads.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local f: trackerfix.Fixture
-- a legacy document name, built so the c0044 guard (no literal <ID>-<slug>.md in a spec) does not see it
local SLUG = "old-slug"
local LEGACY = `tracker/issues/c0020/c0020-{SLUG}.md`
local SHA: { [string]: string } = {}

local function doc(id: string, line: string): string
	return trackerfix.stub(id, id, "new-a-b-c") .. `\n## Problem\n{line}\n`
end

-- `other` commits `files` (nil text removes a path) with `message`, pushes, and remembers the sha under `key`
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

-- `tracker.sh renumber <args>` in a worktree of `other` (renumber refuses a main checkout), committed and pushed
local function renumber(key: string, args: { string }, message: string)
	fixture.git(f.other, { "pull", "-q", "origin", "main" })
	local wt = `{f.base}/wt-{key}`
	fixture.git(f.other, { "worktree", "add", "-q", "-b", `renumber-{key}`, wt, "HEAD" })
	local argv = { "renumber" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = trackerfix.tr(f, wt, argv, { PICKMAN_PUBLISH = "0" })
	if not r.ok then
		error(`renumber failed: {r.stderr}{r.stdout}`)
	end
	fixture.git(wt, { "add", "-A" })
	fixture.git(wt, { "commit", "-q", "-m", message })
	fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
	SHA[key] = fixture.git(wt, { "rev-parse", "HEAD" })
end

local function capture(id: string): (number, string, string)
	fixture.git(f.main, { "fetch", "-q", "origin" })
	local r = trackerfix.tr(f, f.main, { "capture", id })
	return r.code, r.stdout, r.stderr
end

local function short(sha: string): string
	return string.sub(sha, 1, 7)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0119 tracker.sh capture", function(it)
	it("sets up a fixture whose items were captured, prepped, migrated, compacted and moved", function()
		f = trackerfix.new("capture-cli", {})
		push(
			"stub",
			{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "stub line") },
			"tracker: new c0010 one"
		)
		push(
			"landed",
			{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "the user's words") },
			"tracker: new c0010 One"
		)
		push(
			"raft",
			{ ["tracker/rafts/R0010/R0010.md"] = trackerfix.stub("R0010", "r", "new-d-e-f") },
			"tracker: new raft R0010 r"
		)
		push(
			"prep",
			{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "a narrower rewrite") },
			"tracker: prep R0010 r"
		)
		-- a decision landed later, and another capture that edits c0010 on the way: neither is c0010's capture
		push(
			"scope",
			{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "a narrower rewrite, decided") },
			"tracker: scope c0010 the user decided"
		)
		push("other", {
			["tracker/issues/c0050/c0050.md"] = doc("c0050", "other"),
			["tracker/issues/c0010/c0010.md"] = doc("c0010", "a narrower rewrite, decided, edited"),
		}, "tracker: new c0050 other")
		push("done", {
			["tracker/issues/c0010"] = false,
			["tracker/issues/done/c0010/c0010.md"] = doc("c0010", "a narrower rewrite"),
		}, "R0010: done")
		-- a look-alike: the same text as c0010's capture, never captured itself
		push(
			"lookalike",
			{ ["tracker/issues/c0040/c0040.md"] = doc("c0010", "the user's words") },
			"R0040: prep"
		)
		-- a legacy document named by its slug, renamed by the layout migration
		-- its first add also writes check.sh, which must never be taken for the document
		push("legacy", {
			[LEGACY] = doc("c0020", "legacy words"),
			["tracker/issues/c0020/check.sh"] = "#!/usr/bin/env bash\n",
		}, "backlog")
		push("migrate", {
			[LEGACY] = false,
			["tracker/issues/c0020/c0020.md"] = doc("c0020", "legacy words"),
		}, "tracker: migrate")
		-- compaction renames c0300 to c0030, and a new item later takes the number c0300
		push(
			"old",
			{ ["tracker/issues/c0300/c0300.md"] = doc("c0300", "before compaction") },
			"tracker: new c0300 Old"
		)
		push(
			"oldLanded",
			{ ["tracker/issues/c0300/c0300.md"] = doc("c0300", "before compaction, landed") },
			"tracker: new c0300 Old, landed"
		)
		push("compact", {
			["tracker/issues/c0300"] = false,
			["tracker/issues/c0030/c0030.md"] = doc("c0030", "before compaction"),
			["tracker/compaction.txt"] = "# tracker.sh compact, test\nc0300 c0030\n",
		}, "tracker: compact ids")
		push(
			"reused",
			{ ["tracker/issues/c0300/c0300.md"] = doc("c0300", "a new item") },
			"tracker: new c0300 Reused"
		)
		-- a renumber of c0060 to c0061 on a prep branch that also rewrites it
		push(
			"c60",
			{ ["tracker/issues/c0060/c0060.md"] = doc("c0060", "sixty, as captured") },
			"tracker: new c0060 Sixty"
		)
		renumber("renum60", { "c0060", "c0061" }, "R0060: prep, with a renumber")
		-- two copies of c0070 (a collision): the backlog stub is renumbered by its directory, the done copy keeps c0070
		push(
			"c70stub",
			{ ["tracker/issues/c0070/c0070.md"] = doc("c0070", "the stub") },
			"tracker: new c0070 Stub"
		)
		push(
			"c70done",
			{ ["tracker/issues/done/c0070/c0070.md"] = doc("c0070", "the done copy") },
			"tracker: new c0070 Done copy"
		)
		renumber("renum70", { "tracker/issues/c0070", "c0071" }, "tracker: renumber the c0070 stub")
		-- a second compaction writes only its own map: c0030 becomes c0003
		push("compact2", {
			["tracker/issues/c0030"] = false,
			["tracker/issues/c0003/c0003.md"] = doc("c0003", "before compaction"),
			["tracker/compaction.txt"] = "# tracker.sh compact, test 2\nc0030 c0003\n",
		}, "tracker: compact ids again")
		-- an item removed, and later a new one at its number with no capture commit: never the old item's capture
		push(
			"c90old",
			{ ["tracker/issues/c0090/c0090.md"] = doc("c0090", "old ninety") },
			"tracker: new c0090 Old ninety"
		)
		push("c90gone", { ["tracker/issues/c0090"] = false }, "tracker: drop c0090")
		push("c90new", { ["tracker/issues/c0090/c0090.md"] = doc("c0090", "new ninety") }, "R0090: prep")
		-- a compaction that rotates ids: c0080 becomes c0008 while c0800 becomes c0080, at the same path
		push(
			"c80",
			{ ["tracker/issues/c0080/c0080.md"] = doc("c0080", "eighty") },
			"tracker: new c0080 Eighty"
		)
		push(
			"c700",
			{ ["tracker/issues/c0700/c0700.md"] = doc("c0700", "seven hundred") },
			"tracker: new c0700 Seven hundred"
		)
		push(
			"c800",
			{ ["tracker/issues/c0800/c0800.md"] = doc("c0800", "eight hundred") },
			"tracker: new c0800 Eight hundred"
		)
		push("rotate", {
			["tracker/issues/c0800"] = false,
			["tracker/issues/c0700"] = false,
			["tracker/issues/c0007/c0007.md"] = doc("c0007", "seven hundred"),
			["tracker/issues/c0008/c0008.md"] = doc("c0008", "eighty"),
			["tracker/issues/c0080/c0080.md"] = doc("c0080", "eight hundred"),
			["tracker/compaction.txt"] = "# tracker.sh compact, rotate\nc0080 c0008\nc0700 c0007\nc0800 c0080\n",
		}, "tracker: compact ids, rotating")
		-- an edit to the map's header only: no item moved, so it changes no capture
		push("mapedit", {
			["tracker/compaction.txt"] = "# tracker.sh compact, rotate (header edited)\nc0080 c0008\nc0700 c0007\nc0800 c0080\n",
		}, "tracker: edit the compaction header")
		-- c0007, renamed by that compaction, is removed and a new item takes c0007 later: a life the map does not prove
		push("c7gone", { ["tracker/issues/c0007"] = false }, "tracker: drop c0007")
		push("c7back", { ["tracker/issues/c0007/c0007.md"] = doc("c0007", "a new seven") }, "R0007: prep")
		-- a commit that edits only the map's header and also edits c0008's document: not a compaction
		push("fix", {
			["tracker/compaction.txt"] = "# tracker.sh compact, rotate (fixed)\nc0080 c0008\nc0700 c0007\nc0800 c0080\n",
			["tracker/issues/c0008/c0008.md"] = doc("c0008", "eighty, edited"),
		}, "tracker: fix the map header, edit c0008")
		-- a map that no longer parses, in a commit that also edits c0095: unproven, so the walk stops and says so
		push(
			"c95",
			{ ["tracker/issues/c0095/c0095.md"] = doc("c0095", "ninety-five") },
			"tracker: new c0095 Ninety-five"
		)
		push("badmap", {
			["tracker/compaction.txt"] = "# broken\nnot a map line\n",
			["tracker/issues/c0095/c0095.md"] = doc("c0095", "ninety-five, edited"),
		}, "R0095: prep with a broken map")
	end)

	it(
		"prints the newest `tracker: new <id>` version, not a later prep's rewrite, after a move to done/",
		function()
			local code, out = capture("c0010")
			t.expect(code).toBe(0)
			local first = string.match(out, "^[^\n]+") :: string
			t.expect(first).toBe(`capture {SHA.landed} tracker/issues/c0010/c0010.md tracker: new c0010 One`)
			t.expect(has(out, "the user's words")).toBe(true)
			t.expect(has(out, "a narrower rewrite")).toBe(false)
		end
	)

	it("falls back to the first add of a legacy slug-named document", function()
		local code, out = capture("c0020")
		t.expect(code).toBe(0)
		t.expect(has(out, `capture {SHA.legacy} {LEGACY} backlog`)).toBe(true)
		t.expect(has(out, "#!/usr/bin/env bash")).toBe(false)
	end)

	it("never follows a compaction: it marks the start, and keeps a reused number to its own item", function()
		local _, renamed = capture("c0003")
		local head = string.match(renamed, "^[^\n]+") :: string
		t.expect(has(head, `capture {SHA.compact2} tracker/issues/c0003/c0003.md`)).toBe(true)
		t.expect(
			has(
				head,
				`(history before {short(SHA.compact2)} not followed: it changed tracker/compaction.txt)`
			)
		)
			.toBe(true)
		local _, reused = capture("c0300")
		t.expect(has(reused, `capture {SHA.reused} tracker/issues/c0300/c0300.md`)).toBe(true)
		t.expect(has(reused, "a new item")).toBe(true)
		t.expect(has(reused, "not followed")).toBe(false)
	end)

	it("does not follow a renumber, and marks what it cannot settle", function()
		-- a renumbered item's capture is its first add at the new id, marked, never another item's capture
		local _, sixty = capture("c0061")
		local first = string.match(sixty, "^[^\n]+") :: string
		t.expect(first).toBe(
			`capture {SHA.renum60} tracker/issues/c0061/c0061.md R0060: prep, with a renumber (no capture commit: first add)`
		)
		local _, stub = capture("c0071")
		t.expect(has(stub, `capture {SHA.renum70} tracker/issues/c0071/c0071.md`)).toBe(true)
		t.expect(has(stub, "(no capture commit: first add)")).toBe(true)
		-- the id two items held at once is marked ambiguous
		local _, kept = capture("c0070")
		t.expect(has(string.match(kept, "^[^\n]+") :: string, "(ambiguous: two items held this id at once)"))
			.toBe(true)
		local _, landed = capture("c0010")
		t.expect(has(landed, "ambiguous")).toBe(false)
	end)

	it("starts a life at the last appearance or at a commit that changed the map and the document", function()
		local _, reused = capture("c0090")
		t.expect(
			has(
				reused,
				`capture {SHA.c90new} tracker/issues/c0090/c0090.md R0090: prep (no capture commit: first add)`
			)
		).toBe(true)
		t.expect(has(reused, "old ninety")).toBe(false)
		-- a rotating compaction: neither item is followed to its old id, and neither is taken for the other
		local _, rotatedIn = capture("c0080")
		local inHead = string.match(rotatedIn, "^[^\n]+") :: string
		t.expect(has(inHead, `capture {SHA.rotate} tracker/issues/c0080/c0080.md`)).toBe(true)
		t.expect(has(inHead, `(history before {short(SHA.rotate)} not followed`)).toBe(true)
		t.expect(has(inHead, "Eighty")).toBe(false)
		-- a commit that edits the map's header and the document is marked too; it never names another item
		local _, eighty = capture("c0008")
		local eHead = string.match(eighty, "^[^\n]+") :: string
		t.expect(has(eHead, `capture {SHA.fix} tracker/issues/c0008/c0008.md`)).toBe(true)
		t.expect(has(eHead, `(history before {short(SHA.fix)} not followed`)).toBe(true)
		local _, seven = capture("c0007")
		t.expect(
			has(
				seven,
				`capture {SHA.c7back} tracker/issues/c0007/c0007.md R0007: prep (no capture commit: first add)`
			)
		).toBe(true)
		-- a map that no longer parses changes nothing about the rule: the start is marked
		local _, broken = capture("c0095")
		local bHead = string.match(broken, "^[^\n]+") :: string
		t.expect(has(bHead, `(history before {short(SHA.badmap)} not followed`)).toBe(true)
	end)

	it("marks a first-add fallback, and only that", function()
		local _, legacy = capture("c0020")
		t.expect(has(string.match(legacy, "^[^\n]+") :: string, "(no capture commit: first add)")).toBe(true)
		local _, landed = capture("c0010")
		t.expect(has(landed, "(no capture commit: first add)")).toBe(false)
	end)

	it("reads a raft's folders for an R id", function()
		local code, out = capture("R0010")
		t.expect(code).toBe(0)
		t.expect(has(out, `capture {SHA.raft} tracker/rafts/R0010/R0010.md tracker: new raft R0010 r`))
			.toBe(true)
	end)

	it("never takes a look-alike document for another item's", function()
		local _, out = capture("c0040")
		t.expect(has(out, `capture {SHA.lookalike} tracker/issues/c0040/c0040.md R0040: prep`)).toBe(true)
	end)

	it("refuses an unknown id and a malformed one, and changes nothing", function()
		local before = fixture.git(f.main, { "status", "--porcelain" })
		local code, _, err = capture("c0999")
		t.expect(code).toBe(1)
		t.expect(has(err, "no history for c0999")).toBe(true)
		local bad, _, berr = capture("nope")
		t.expect(bad).toBe(1)
		t.expect(has(berr, "usage: capture <id>")).toBe(true)
		t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe(before)
	end)
end)
