--!strict
-- c0115 AC4: the old skill names are gone from every live file: z-nile/ and pickman/ (their .tracker/ aside),
-- AGENTS.md, SETUP.md, .claude/, zn, scripts/ and .github/ (every project's promoted specs aside, z-nile/tests/acceptance
-- and pickman/tests/acceptance: they are history). The forms: a path through .claude/skills/<old>, any of the six hyphenated names (make-issue, ticket-prep,
-- ready-raft, launch-raft, execute-raft, stop-raft, as a /command or a bare word), and `<old>` skill or <old> skill
-- for the five ordinary words (review, tracker, metrics, testing, architecture). And no code or spec names a path
-- through a .claude/skills link (.claude/skills/<name>/...): git can't add through one, so every tool reads the real
-- folder. And no live file cites an old lesson id (`testing/no-vacuous-pass`) whose renamed lesson exists. Plain finds
-- only (lesson zz-test/plain-find-for-literals); `scan` and `oldLessonIds` are also run on planted texts.
local process = require("@lune/process")
local realfs = require("@lune/fs")
-- c0115 runs from its project's home, z-nile/ (c0120): every path this spec reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function top(p: string): string
	return if string.sub(p, 1, 1) == "/" then p else `{TOP}/{p}`
end
local fs = {
	readFile = function(p: string): string
		return realfs.readFile(top(p))
	end,
	isFile = function(p: string): boolean
		return realfs.isFile(top(p))
	end,
	isDir = function(p: string): boolean
		return realfs.isDir(top(p))
	end,
	readDir = function(p: string): { string }
		return realfs.readDir(top(p))
	end,
}
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")

local function starts(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- Every old form in `text`, as "<form> at <line>": the one old-name rule, skills.oldNames (the rename script renames
-- lesson bodies with it too).
local function scan(text: string): { string }
	local found: { string } = {}
	for _, f in skills.oldNames(text) do
		local line = 1
		for _ in string.gmatch(string.sub(text, 1, f.from), "\n") do
			line += 1
		end
		table.insert(found, `{f.form} at line {line}`)
	end
	return found
end

-- A path through a .claude/skills link: `.claude/skills/<segment>/`.
local function throughLink(text: string): boolean
	local from = 1
	while true do
		local a, b = string.find(text, ".claude/skills/", from, true)
		if not a then
			return false
		end
		local rest = string.sub(text, (b :: number) + 1, (b :: number) + 80)
		local seg = string.match(rest, "^([^%s/`'\",)]+)/")
		if seg then
			return true
		end
		from = (b :: number) + 1
	end
end

-- c0115 §5: the one old-id rule, skills.oldLessonIds, the rename script's own (prose mode: a token counts only where
-- its renamed lesson exists, so look-alike paths such as tracker/next never count)
local function oldLessonIds(text: string, existing: { [string]: boolean }): { string }
	local out: { string } = {}
	for _, id in skills.oldLessonIds(text, existing) do
		table.insert(out, `{id.old}/{id.slug}`)
	end
	table.sort(out)
	return out
end

local function tracked(): { string }
	local r = process.exec("git", { "ls-files" }, { cwd = TOP })
	if not r.ok then
		error(r.stderr)
	end
	local out = {}
	for path in string.gmatch(r.stdout, "[^\n]+") do
		table.insert(out, path)
	end
	return out
end

local LIVE_TOP = { "AGENTS.md", "SETUP.md", "zn" }
local LIVE_DIRS = { "z-nile/", "pickman/", ".claude/", "scripts/", ".github/" }
local function live(path: string): boolean
	if string.find(path, "/.tracker/", 1, true) or starts(path, "tracker/") then
		return false
	end
	if
		-- promoted specs are sequestered, every project's (z-nile's home is z-nile/, c0120)
		starts(path, "z-nile/tests/acceptance/")
		or starts(path, "pickman/tests/acceptance/")
		or starts(path, "z-nile/vendor/")
	then
		return false
	end
	if table.find(LIVE_TOP, path) then
		return true
	end
	for _, d in LIVE_DIRS do
		if starts(path, d) then
			return true
		end
	end
	return false
end
-- code and specs: what runs, as opposed to the documents a person or agent reads
local function code(path: string): boolean
	return live(path)
		and not starts(path, "z-nile/skills/")
		and not starts(path, "pickman/skills/")
		and not string.match(path, "%.md$")
end
-- The one place an old name must stay: the rename map itself, between the "c0115 rename map" markers in
-- z-nile/engine/skills.luau. Exactly that block is left out of the scan, nothing else in the file (a missing block is an
-- error, never a skip).
local RENAMED_FILE = "z-nile/engine/skills.luau"
local function withoutRenamed(text: string): string
	local a = string.find(text, "\n-- c0115 rename map: begin", 1, true)
	local b = a and string.find(text, "\n-- c0115 rename map: end\n", a :: number, true)
	if not a or not b then
		error(`{RENAMED_FILE} has no skills.RENAMED block`)
	end
	return string.sub(text, 1, a :: number) .. string.sub(text, (b :: number) + 1)
end
local function readable(path: string): string?
	if not fs.isFile(path) then
		return nil -- a deleted file, or a link
	end
	local text = fs.readFile(path)
	if path == RENAMED_FILE then
		text = withoutRenamed(text)
	end
	if string.find(text, "\0", 1, true) then
		return nil
	end
	return text
end

return t.spec("c0115 no old skill name is left in a live file", function(it)
	it("the scan finds each form, and leaves the new names, item paths and look-alikes alone", function()
		t.expect(#scan("run /launch-raft R0010\n")).toBe(1)
		t.expect(#scan("see the ticket-prep skill\n")).toBe(1)
		t.expect(#scan("read .claude/skills/testing/SKILL.md\n")).toBe(1)
		t.expect(#scan("the `tracker` skill, and the review skill\n")).toBe(2)
		t.expect(#scan("as make-issue does\nexecute-raft Phase 4\n")).toBe(2)
		t.expect(
			scan(
				"the zz-review skill, /z-run R0010, the zz-test skill, scripts/tracker.sh, design-review-001\n"
			)
		).toEqual({})
		t.expect(scan("tests/acceptance/c0043/ticket-prep.spec.luau, a pre-ready-raft-x name\n")).toEqual({})
		t.expect(throughLink('fs.readFile(".claude/skills/zz-test/SKILL.md")')).toBe(true)
		t.expect(throughLink("`.claude/skills/<name>` is a link")).toBe(false)
		t.expect(throughLink('skills.LINKS = ".claude/skills"')).toBe(false)
	end)

	it("the same rule renames: each form gets its new name, and look-alikes stay", function()
		local out, n = skills.renameOldNames(
			"see the ticket-prep skill and .claude/skills/testing/SKILL.md; run /launch-raft R0010; the `review` skill"
		)
		t.expect(out)
			.toBe(
				"see the z-design skill and z-nile/skills/zz-test/SKILL.md; run /z-run R0010; the `zz-review` skill"
			)
		t.expect(n).toBe(4)
		local same =
			"scripts/tracker.sh, tests/acceptance/c0043/ticket-prep.spec.luau, the zz-test skill, design-review-001"
		t.expect((skills.renameOldNames(same))).toBe(same)
	end)

	it("no live file names an old skill", function()
		local bad: { string } = {}
		local n = 0
		for _, path in tracked() do
			if live(path) then
				local text = readable(path)
				if text then
					n += 1
					for _, hit in scan(text) do
						table.insert(bad, `{path}: {hit}`)
					end
				end
			end
		end
		t.expect(n > 100).toBe(true) -- the scan read the tree, not an empty list
		if #bad > 0 then
			error("old skill names:\n" .. table.concat(bad, "\n"))
		end
	end)

	it("no code or spec names a path through a .claude/skills link", function()
		local bad: { string } = {}
		local n = 0
		for _, path in tracked() do
			if code(path) then
				local text = readable(path)
				if text then
					n += 1
					if throughLink(text) then
						table.insert(bad, path)
					end
				end
			end
		end
		t.expect(n > 50).toBe(true)
		if #bad > 0 then
			error("reads through a .claude/skills link:\n" .. table.concat(bad, "\n"))
		end
	end)
	it("the lesson-id scan finds an old id whose renamed lesson exists, and no look-alike path", function()
		local existing = { ["zz-arch/guards-trust-only-origin"] = true, ["zz-test/no-vacuous-pass"] = true }
		t.expect(
			oldLessonIds(
				"(lesson architecture/guards-trust-only-origin) and testing/no-vacuous-pass.",
				existing
			)
		).toEqual({ "architecture/guards-trust-only-origin", "testing/no-vacuous-pass" })
		t.expect(
			oldLessonIds(
				"tracker/next, tracker/compaction.txt, scripts/tracker/x.luau, testing/unknown-slug",
				existing
			)
		).toEqual({})
		t.expect(oldLessonIds("lesson zz-arch/guards-trust-only-origin", existing)).toEqual({})
	end)

	it("no live file, skills and comments included, cites an old lesson id", function()
		local existing = skills.lessonIndex(TOP)
		local count = 0
		for _ in existing do
			count += 1
		end
		t.expect(count > 10).toBe(true) -- the lesson folders were read
		local bad: { string } = {}
		for _, path in tracked() do
			if live(path) then
				local text = readable(path)
				if text then
					for _, id in oldLessonIds(text, existing) do
						table.insert(bad, `{path}: {id}`)
					end
				end
			end
		end
		if #bad > 0 then
			error("old lesson ids:\n" .. table.concat(bad, "\n"))
		end
	end)
end)
