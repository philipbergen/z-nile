--!strict
-- c0120 AC8: pickman's move into pickman/.tracker keeps every item's past: the move commit retires tracker/ in the
-- registry, so `capture` still finds an item's original `tracker: new` commit with no marker, history keeps a done
-- item's close day and an open item's one spell across the move (a delete and an add in one commit is no change), and
-- an item born in pickman/.tracker after the move is captured there. Fixture under .cache/c0120-trail
-- (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local history = require("@znile/engine/history")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local P = "pickman/.tracker"
local MOVED_REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local f: trackerfix.Fixture
local SHA: { [string]: string } = {}

local function doc(id: string, line: string, status: string): string
	return trackerfix.stub(id, id, status) .. `\n## Problem\n{line}\n`
end
local function at(day: string): { [string]: string }
	return { GIT_COMMITTER_DATE = `{day}T12:00:00Z`, GIT_AUTHOR_DATE = `{day}T12:00:00Z` }
end
-- `other` changes `files` (false removes a path; a `{ from }` table moves one with git mv), commits on `day` and pushes
local function push(key: string, day: string, files: { [string]: any }, message: string)
	fixture.git(f.other, { "pull", "-q", "origin", "main" })
	for path, v in files do
		if v == false then
			fixture.git(f.other, { "rm", "-q", "-r", path })
		elseif type(v) == "table" then
			fs.writeDir(`{f.other}/{string.match(path, "^(.*)/[^/]+$") :: string}`)
			fixture.git(f.other, { "mv", v.from, path })
		else
			local parent = string.match(path, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{f.other}/{parent}`)
			end
			fs.writeFile(`{f.other}/{path}`, v :: string)
		end
	end
	fixture.git(f.other, { "add", "-A" })
	fixture.git(f.other, { "commit", "-q", "-m", message }, { env = at(day) })
	fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
	SHA[key] = fixture.git(f.other, { "rev-parse", "HEAD" })
end
local function capture(id: string): fixture.Result
	fixture.git(f.main, { "fetch", "-q", "origin" })
	return trackerfix.tr(f, f.main, { "capture", id })
end

return t.spec("c0120 an item's past follows it into pickman/.tracker", function(it)
	it(
		"sets up pickman items captured under tracker/, then moved with the registry into pickman/.tracker",
		function()
			f = trackerfix.new("c0120-trail", {})
			push(
				"new",
				"2026-09-02",
				{ ["tracker/issues/f0010/f0010.md"] = doc("f0010", "the user's words", "new-a-b-c") },
				"tracker: new f0010 one"
			)
			push("done", "2026-09-04", {
				["tracker/issues/f0010"] = false,
				["tracker/issues/done/f0010/f0010.md"] = doc("f0010", "a rewrite", "prepared-a-b-c"),
			}, "R0010: done")
			push(
				"open",
				"2026-09-05",
				{ ["tracker/issues/f0020/f0020.md"] = doc("f0020", "still open", "new-a-b-c") },
				"tracker: new f0020 two"
			)
			-- c0120's move: the items change roots in one commit, renames only, and the registry retires tracker/
			push("move", "2026-10-21", {
				[`{P}/issues/done/f0010/f0010.md`] = { from = "tracker/issues/done/f0010/f0010.md" },
				[`{P}/issues/f0020/f0020.md`] = { from = "tracker/issues/f0020/f0020.md" },
				["z-nile/projects.toml"] = MOVED_REGISTRY,
			}, "c0120: move pickman into pickman/")
			push(
				"after",
				"2026-10-22",
				{ [`{P}/issues/f0030/f0030.md`] = doc("f0030", "born in pickman/.tracker", "new-a-b-c") },
				"tracker: new f0030 three"
			)
		end
	)

	it("capture of a moved item is its original capture commit under tracker/, unmarked", function()
		local r = capture("f0010")
		t.expect(r.ok).toBe(true)
		t.expect(string.match(r.stdout, "^[^\n]*"))
			.toBe(`capture {SHA.new} tracker/issues/f0010/f0010.md tracker: new f0010 one`)
		t.expect(string.find(r.stdout, "the user's words", 1, true) ~= nil).toBe(true)
		local open = capture("f0020")
		t.expect(string.match(open.stdout, "^[^\n]*"))
			.toBe(`capture {SHA.open} tracker/issues/f0020/f0020.md tracker: new f0020 two`)
	end)

	it("an item born in pickman/.tracker after the move is captured there", function()
		local r = capture("f0030")
		t.expect(r.ok).toBe(true)
		t.expect(string.match(r.stdout, "^[^\n]*"))
			.toBe(`capture {SHA.after} {P}/issues/f0030/f0030.md tracker: new f0030 three`)
	end)

	it("history keeps the close day and the open spell across the move", function()
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local p = history.read(f.main) :: history.Parsed
		t.expect(p ~= nil).toBe(true)
		t.expect(p.closed.f0010).toBe("2026-09-04")
		t.expect(#(p.spells.f0020 or {})).toBe(1)
		t.expect(p.spells.f0020[1].from).toBe("2026-09-05T12:00:00Z")
		t.expect(#(p.spells.f0030 or {})).toBe(1)
	end)

	it("find sees the moved items in pickman/.tracker", function()
		t.expect(trackerfix.trOk(f, f.main, { "find", "f0020" })).toBe(`{P}/issues/f0020`)
		t.expect(trackerfix.trOk(f, f.main, { "find", "f0010" })).toBe(`{P}/issues/done/f0010`)
	end)
end)
