--!strict
-- c0114 AC5: a move between project roots keeps the id, so every reader of an item's past follows it like a
-- move between folders: `capture` still finds the original `tracker: new` commit with no marker, the move of the
-- compaction map is no compaction, a later compaction of z-nile/compaction.txt still marks the history before it,
-- history keeps the item's state and close day across the move, and the lessons reader finds a z-nile raft's reviews
-- and harvest. The metrics cutoff keeps the first add of the lessons module across its move. Fixtures under
-- .cache/c0114-trail (tests/lib/trackerfix) and .cache/c0114-cutoff (a repository of its own).
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local history = require("@znile/engine/history")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local Z = "z-nile/.tracker"
local f: trackerfix.Fixture
local SHA: { [string]: string } = {}

local function doc(id: string, line: string, status: string): string
	return trackerfix.stub(id, id, status) .. `\n## Problem\n{line}\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
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
			local parent = string.match(path, "^(.*)/[^/]+$") :: string
			fs.writeDir(`{f.other}/{parent}`)
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

return t.spec("c0114 an item's past follows it across roots", function(it)
	it(
		"sets up items captured under tracker/, moved into z-nile/.tracker/ with the map, then compacted",
		function()
			f = trackerfix.new("c0114-trail", {})
			-- the fixture's seed has no map: an old compaction writes tracker/compaction.txt, as main's history does
			push(
				"oldmap",
				"2026-09-01",
				{ ["tracker/compaction.txt"] = "# compact, old\nc0900 c0009\n" },
				"tracker: compact"
			)
			push(
				"new",
				"2026-09-02",
				{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "the user's words", "new-a-b-c") },
				"tracker: new c0010 one"
			)
			push(
				"prep",
				"2026-09-03",
				{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "a rewrite", "prepared-a-b-c") },
				"tracker: prep R0010 r"
			)
			push("done", "2026-09-04", {
				["tracker/issues/c0010"] = false,
				["tracker/issues/done/c0010/c0010.md"] = doc("c0010", "a rewrite", "prepared-a-b-c"),
			}, "R0010: done")
			push(
				"backlog",
				"2026-09-05",
				{ ["tracker/issues/c0300/c0300.md"] = doc("c0300", "before compaction", "new-a-b-c") },
				"tracker: new c0300 three"
			)
			-- c0114's own move: the items and the map change roots in one commit, renames only
			push("move", "2026-10-21", {
				[`{Z}/issues/done/c0010/c0010.md`] = { from = "tracker/issues/done/c0010/c0010.md" },
				[`{Z}/issues/c0300/c0300.md`] = { from = "tracker/issues/c0300/c0300.md" },
				["z-nile/compaction.txt"] = { from = "tracker/compaction.txt" },
			}, "c0114: move the tracker into z-nile")
			push(
				"after",
				"2026-10-22",
				{ [`{Z}/issues/c0400/c0400.md`] = doc("c0400", "born in z-nile", "new-a-b-c") },
				"tracker: new c0400 four"
			)
			-- a compaction after the move writes z-nile/compaction.txt and renames c0300 to c0030 in z-nile's root
			push("compact", "2026-10-23", {
				[`{Z}/issues/c0300`] = false,
				[`{Z}/issues/c0030/c0030.md`] = doc("c0030", "before compaction", "new-a-b-c"),
				["z-nile/compaction.txt"] = "# compact, new\nc0300 c0030\n",
			}, "tracker: compact ids")
		end
	)

	it("capture of an item moved between roots is its original capture commit, unmarked", function()
		local r = capture("c0010")
		t.expect(r.ok).toBe(true)
		local head = string.match(r.stdout, "^[^\n]*") :: string
		t.expect(head).toBe(`capture {SHA.new} tracker/issues/c0010/c0010.md tracker: new c0010 one`)
		t.expect(has(r.stdout, "the user's words")).toBe(true)
	end)

	it("an item born in z-nile's root is captured there", function()
		local r = capture("c0400")
		t.expect(r.ok).toBe(true)
		t.expect(string.match(r.stdout, "^[^\n]*"))
			.toBe(`capture {SHA.after} {Z}/issues/c0400/c0400.md tracker: new c0400 four`)
	end)

	it(
		"moving the map is no compaction; a compaction of the moved map still marks the history before it",
		function()
			local r = capture("c0030")
			t.expect(r.ok).toBe(true)
			local head = string.match(r.stdout, "^[^\n]*") :: string
			t.expect(
				has(
					head,
					`(history before {string.sub(SHA.compact, 1, 7)} not followed: it changed z-nile/compaction.txt)`
				)
			).toBe(true)
			t.expect(has(head, string.sub(SHA.move, 1, 7))).toBe(false)
		end
	)

	it("history keeps a moved item's close day and state: the move is no change", function()
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local parsed = history.read(f.main)
		t.expect(parsed ~= nil).toBe(true)
		local p = parsed :: history.Parsed
		t.expect(p.closed.c0010).toBe("2026-09-04")
		-- c0300 opened on 09-05 and was still new when it moved: one spell, never restarted by the move
		t.expect(#(p.spells.c0300 or {})).toBe(1)
		t.expect(p.spells.c0300[1].from).toBe("2026-09-05T12:00:00Z")
		-- an item born in z-nile's root has a history too
		t.expect(#(p.spells.c0400 or {})).toBe(1)
	end)

	it("the lessons reader finds a z-nile raft's reviews and harvest", function()
		local review =
			"# Review 001\n\n### F1 [low] claim\nEvidence: x\n\n### F2 [low] claim\nEvidence: y\n\nVerdict: changes\n"
		local dir = `{f.main}/{Z}/rafts/done/R0010`
		fs.writeDir(dir)
		fs.writeFile(`{dir}/R0010.md`, trackerfix.stub("R0010", "r", "new-a-b-c"))
		fs.writeFile(`{dir}/design-review-001.md`, review)
		fs.writeFile(`{dir}/harvest.md`, "# Harvest: R0010\n\n- design-review-001 F1: one-off: x\n")
		local r = trackerfix.tr(f, f.main, { "lessons", "--uncovered", "R0010" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "R0010 design-review-001 F2")).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "no such item")).toBe(false)
		fs.writeFile(
			`{dir}/harvest.md`,
			"# Harvest: R0010\n\n- design-review-001 F1: one-off: x\n- design-review-001 F2: one-off: y\n"
		)
		local ok = trackerfix.tr(f, f.main, { "lessons", "--uncovered", "R0010" })
		t.expect(ok.code).toBe(0)
		fs.removeDir(dir)
	end)

	it("the metrics cutoff is the first add of the lessons module, before its move into z-nile/", function()
		local root = fixture.physical(".") :: string
		local base = `{root}/.cache/c0114-cutoff`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", base }).ok).toBe(true)
		fixture.git(base, { "config", "user.name", "c0114-cutoff" })
		fixture.git(base, { "config", "user.email", "c0114-cutoff@example.invalid" })
		local function commit(day: string, message: string)
			fixture.git(base, { "add", "-A" })
			fixture.git(base, { "commit", "-q", "-m", message }, { env = at(day) })
		end
		local function raft(id: string, day: string)
			local dir = `{base}/tracker/rafts/done/{id}`
			fs.writeDir(dir)
			-- metrics dates a raft by its created: day
			local stubbed =
				string.gsub(trackerfix.stub(id, id, "new-a-b-c"), "created: [%d%-]+", `created: {day}`)
			fs.writeFile(`{dir}/{id}.md`, stubbed)
			fs.writeFile(`{dir}/design-review-001.md`, "# Review 001\n\nVerdict: approve\n")
		end
		fs.writeDir(`{base}/scripts/tracker`)
		fs.writeFile(`{base}/scripts/tracker/lessons.luau`, "--!strict\nreturn {}\n")
		commit("2020-01-01", "lessons, at its old home")
		raft("R0010", "2021-01-01")
		commit("2021-01-01", "a raft reviewed after lessons existed")
		fixture.git(base, { "rm", "-q", "-r", "scripts" })
		engine.copy(root, base) -- z-nile/engine/lessons.luau is first added now
		fs.writeFile(`{base}/rokit.toml`, fs.readFile(`{root}/rokit.toml`))
		commit("2022-01-01", "the move into z-nile")
		raft("R0020", "2023-01-01")
		commit("2023-01-01", "another raft")
		local r = fixture.exec(base, "bash", { "zn", "metrics" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		-- both rafts started after 2020: a cutoff at the move (2022) would put R0010 before it
		t.expect(has(r.stdout, "| before | 0 | 0 | 0.0 |")).toBe(true)
		t.expect(has(r.stdout, "| after | 2 | 2 | 1.0 |")).toBe(true)
		fs.removeDir(base)
	end)
end)
