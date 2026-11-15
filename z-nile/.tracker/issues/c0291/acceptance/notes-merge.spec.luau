--!strict
-- c0291 AC2: two branches that each add a note to one lesson merge cleanly with both notes kept, in name order,
-- and `./zn lessons` reads and checks the merged tree; two edits of one lesson's own `check` still conflict; and
-- one note name with two texts conflicts (add/add); `--check` names an orphan notes folder, a folder inside one, a
-- misnamed note and an empty one. A tracker fixture under .cache/c0291-notes-merge
-- (tests/lib/trackerfix): `main` and `other` are two clones of one origin; `other` takes
-- `main`'s branch with a fetch from that clone (`peer/main`), so nothing is pushed.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local SKILL = "---\nname: zz-test\ndescription: x\n---\n\n# zz-test\n"
local LESSON = "z-nile/skills/zz-test/lessons/a-lesson.md"
local NOTES = "z-nile/skills/zz-test/lessons/a-lesson"
local TEXT = "---\ntitle: A lesson\nwhen: design\ntags: [merge]\ncheck: Is it merged?\n---\nThe rule.\n"
local OURS = "2026-11-02-c0020-design-review-001-f1.md" -- written on the branch that merges, and named first
local THEIRS = "2026-11-09-c0030-design-review-001-f2.md" -- on the other side (main's branch), named second
local SEED: { [string]: string } = {
	["z-nile/skills/zz-test/SKILL.md"] = SKILL,
	[LESSON] = TEXT,
	["pickman/.tracker/issues/c0010/harvest.md"] = "- note the seed: zz-test/a-lesson\n",
}

-- every .gitattributes the checkout tracks rides into the fixture, so a merge attribute (a union merge of lessons, a
-- driver) is merged under here as it would be in the checkout (the fixture's tooling copy carries none of them)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local listed = process.exec("git", { "ls-files", "--", ".gitattributes", "*/.gitattributes" }, { cwd = TOP })
if not listed.ok then
	error(`git ls-files failed in {TOP}: {listed.stderr}`)
end
for rel in string.gmatch(listed.stdout, "[^\n]+") do
	SEED[rel] = fs.readFile(`{TOP}/{rel}`)
end

local f: trackerfix.Fixture

local function write(dir: string, rel: string, text: string)
	local parent = string.match(rel, "^(.*)/[^/]+$") :: string
	fs.writeDir(`{dir}/{parent}`)
	fs.writeFile(`{dir}/{rel}`, text)
end

local function commit(dir: string, message: string)
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "commit", "-q", "-m", message })
end

-- `other` fetches `main`'s branch as peer/main
local function take(dir: string)
	fixture.git(dir, { "fetch", "-q", f.main, "+main:refs/remotes/peer/main" })
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0291 lesson notes merge", function(it)
	it("sets up a tracker fixture with one lesson", function()
		f = trackerfix.new("c0291-notes-merge", SEED, { noLessons = true })
		t.expect(fs.isFile(`{f.main}/{LESSON}`)).toBe(true)
	end)

	it(
		"AC2: a note on each side merges with no conflict, in git merge and in the dispatcher's merge-tree",
		function()
			write(f.main, `{NOTES}/{THEIRS}`, "Their note.\n")
			commit(f.main, "their note")
			write(f.other, `{NOTES}/{OURS}`, "Our note.\n")
			commit(f.other, "our note")
			take(f.other)
			local tree = fixture.exec(f.other, "git", { "merge-tree", "--write-tree", "peer/main", "HEAD" })
			t.expect(tree.code).toBe(0)
			local merged = fixture.exec(f.other, "git", { "merge", "--no-edit", "peer/main" })
			t.expect(merged.code).toBe(0)
			t.expect(fs.readFile(`{f.other}/{NOTES}/{OURS}`)).toBe("Our note.\n")
			t.expect(fs.readFile(`{f.other}/{NOTES}/{THEIRS}`)).toBe("Their note.\n")
			t.expect(fs.readFile(`{f.other}/{LESSON}`)).toBe(TEXT)
		end
	)

	it(
		"AC2: lessons --full shows the merged lesson's file, then both notes in name order, and --check passes, a hidden file aside",
		function()
			local r = trackerfix.tr(f, f.other, { "lessons", "--full", "zz-test/a-lesson" })
			t.expect(r.code).toBe(0)
			t.expect(r.stdout)
				.toBe(`== {LESSON}\nsources: c0010 note the seed\n` .. TEXT .. "\nOur note.\n\nTheir note.\n")
			fs.writeFile(`{f.other}/{NOTES}/.DS_Store`, "") -- a hidden file is never a note
			local c = trackerfix.tr(f, f.other, { "lessons", "--check" })
			t.expect(c.code).toBe(0)
			t.expect(c.stdout).toBe("lessons: 1 lessons, 1 harvest entries, ok\n")
			fs.removeFile(`{f.other}/{NOTES}/.DS_Store`)
		end
	)

	it("AC2: a word only a note holds finds the lesson", function()
		write(f.other, `{NOTES}/2026-11-10-c0040-review-001-f1.md`, "Mind the zebrafinch.\n")
		local r = trackerfix.tr(f, f.other, { "lessons", "zebrafinch" })
		t.expect(r.code).toBe(0)
		t.expect(has(r.stdout, "zz-test/a-lesson")).toBe(true)
		local none = trackerfix.tr(f, f.other, { "lessons", "okapi" })
		t.expect(none.stdout).toBe("(none)\n")
		fs.removeFile(`{f.other}/{NOTES}/2026-11-10-c0040-review-001-f1.md`)
	end)

	it("AC2: two edits of the lesson's own check still conflict, in git merge and in merge-tree", function()
		fixture.git(f.main, { "fetch", "-q", f.other, "+main:refs/remotes/peer/main" })
		fixture.git(f.main, { "merge", "-q", "--ff-only", "peer/main" })
		write(f.main, LESSON, (string.gsub(TEXT, "check: Is it merged%?", "check: Is it merged on main?")))
		commit(f.main, "their check")
		write(f.other, LESSON, (string.gsub(TEXT, "check: Is it merged%?", "check: Is it merged here?")))
		commit(f.other, "our check")
		take(f.other)
		local tree = fixture.exec(f.other, "git", { "merge-tree", "--write-tree", "peer/main", "HEAD" })
		t.expect(tree.code).toBe(1)
		local merged = fixture.exec(f.other, "git", { "merge", "--no-edit", "peer/main" })
		t.expect(merged.code ~= 0).toBe(true)
		t.expect(has(merged.stdout .. merged.stderr, `CONFLICT (content): Merge conflict in {LESSON}`))
			.toBe(true)
		fixture.git(f.other, { "merge", "--abort" })
	end)

	it(
		"AC2: one note name with two texts conflicts (add/add) in git merge and merge-tree; with one text it merges clean",
		function()
			-- both clones start from main's branch (the check-edit case left them apart)
			take(f.other)
			fixture.git(f.other, { "reset", "-q", "--hard", "peer/main" })
			local same = `{NOTES}/2026-11-12-c0060-review-001-f1.md`
			write(f.main, same, "Ours.\n")
			commit(f.main, "a note on main")
			write(f.other, same, "Theirs.\n")
			commit(f.other, "the same name on other")
			take(f.other)
			local tree = fixture.exec(f.other, "git", { "merge-tree", "--write-tree", "peer/main", "HEAD" })
			t.expect(tree.code).toBe(1)
			local merged = fixture.exec(f.other, "git", { "merge", "--no-edit", "peer/main" })
			t.expect(merged.code ~= 0).toBe(true)
			t.expect(has(merged.stdout .. merged.stderr, `CONFLICT (add/add): Merge conflict in {same}`))
				.toBe(true)
			fixture.git(f.other, { "merge", "--abort" })
			-- the same name with the same text on both sides merges clean: other drops its own text and writes main's
			local twin = `{NOTES}/2026-11-13-c0070-review-001-f1.md`
			write(f.main, twin, "Twin.\n")
			commit(f.main, "a twin note on main")
			fixture.git(f.other, { "reset", "-q", "--hard", "HEAD~1" })
			write(f.other, twin, "Twin.\n")
			commit(f.other, "the twin note on other")
			take(f.other)
			local clean = fixture.exec(f.other, "git", { "merge-tree", "--write-tree", "peer/main", "HEAD" })
			t.expect(clean.code).toBe(0)
			local ok = fixture.exec(f.other, "git", { "merge", "--no-edit", "peer/main" })
			t.expect(ok.code).toBe(0)
			t.expect(fs.readFile(`{f.other}/{twin}`)).toBe("Twin.\n")
			t.expect(fs.readFile(`{f.other}/{same}`)).toBe("Ours.\n")
		end
	)

	it(
		"AC2: lessons --check names a notes folder whose lesson is gone, a folder inside a notes folder, a misnamed note and an empty one",
		function()
			write(f.other, "z-nile/skills/zz-test/lessons/gone/2026-11-09-a.md", "A note.\n")
			write(f.other, `{NOTES}/deeper/2026-11-09-b.md`, "A note.\n")
			write(f.other, `{NOTES}/also.md`, "A note.\n")
			write(f.other, `{NOTES}/2026-11-11-c0050-review-001-f1.md`, " \n")
			local r = trackerfix.tr(f, f.other, { "lessons", "--check" })
			t.expect(r.code).toBe(1)
			t.expect(has(r.stdout, "z-nile/skills/zz-test/lessons/gone/: notes with no lesson gone.md"))
				.toBe(true)
			t.expect(has(r.stdout, `{NOTES}/deeper: not a note file`)).toBe(true)
			t.expect(has(r.stdout, `{NOTES}/also.md: not a note file (a note is <YYYY-MM-DD>-<label>.md)`))
				.toBe(true)
			t.expect(has(r.stdout, `{NOTES}/2026-11-11-c0050-review-001-f1.md: the note is empty`)).toBe(true)
		end
	)
end)
