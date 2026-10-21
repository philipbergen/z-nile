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
local LEDGER60, LEDGER70 = "", ""

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
local function renumber(key: string, args: { string }, message: string): string
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
	return fs.readFile(`{wt}/tracker/renumbered.txt`)
end

local function capture(id: string): (number, string, string)
	fixture.git(f.main, { "fetch", "-q", "origin" })
	local r = trackerfix.tr(f, f.main, { "capture", id })
	return r.code, r.stdout, r.stderr
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
		LEDGER60 = renumber("renum60", { "c0060", "c0061" }, "R0060: prep, with a renumber")
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
		LEDGER70 =
			renumber("renum70", { "tracker/issues/c0070", "c0071" }, "tracker: renumber the c0070 stub")
		-- a second compaction writes only its own map: c0030 becomes c0003
		push("compact2", {
			["tracker/issues/c0030"] = false,
			["tracker/issues/c0003/c0003.md"] = doc("c0003", "before compaction"),
			["tracker/compaction.txt"] = "# tracker.sh compact, test 2\nc0030 c0003\n",
		}, "tracker: compact ids again")
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

	it("follows every compaction to the old id, and keeps a reused number to its own item", function()
		local _, renamed = capture("c0003")
		t.expect(
			has(
				renamed,
				`capture {SHA.oldLanded} tracker/issues/c0300/c0300.md tracker: new c0300 Old, landed`
			)
		)
			.toBe(true)
		t.expect(has(renamed, "before compaction, landed")).toBe(true)
		local _, reused = capture("c0300")
		t.expect(has(reused, `capture {SHA.reused} tracker/issues/c0300/c0300.md`)).toBe(true)
		t.expect(has(reused, "a new item")).toBe(true)
	end)

	it("renumber records each renumber in the ledger, and capture follows it", function()
		t.expect(has(LEDGER60, "\nc0060 c0061\n")).toBe(true)
		t.expect(has(LEDGER70, "\nc0070 c0071 tracker/issues/c0070\n")).toBe(true)
		local code, out = capture("c0061")
		t.expect(code).toBe(0)
		local first = string.match(out, "^[^\n]+") :: string
		t.expect(first).toBe(`capture {SHA.c60} tracker/issues/c0060/c0060.md tracker: new c0060 Sixty`)
		-- the renumbered copy's history is its own folder's, not the done copy's that kept the number
		local _, stub = capture("c0071")
		t.expect(has(stub, `capture {SHA.c70stub} tracker/issues/c0070/c0070.md tracker: new c0070 Stub`))
			.toBe(true)
		local _, kept = capture("c0070")
		t.expect(has(kept, `capture {SHA.c70done} tracker/issues/done/c0070/c0070.md`)).toBe(true)
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
