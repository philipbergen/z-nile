--!strict
-- c0115 AC4: the old skill names are gone from every live file: z-nile/ and pickman/ (their .tracker/ aside),
-- AGENTS.md, SETUP.md, .claude/, zn, scripts/, .github/ and the root's tests/ (promoted specs aside: they are
-- history). The forms: a path through .claude/skills/<old>, any of the six hyphenated names (make-issue, ticket-prep,
-- ready-raft, launch-raft, execute-raft, stop-raft, as a /command or a bare word), and `<old>` skill or <old> skill
-- for the five ordinary words (review, tracker, metrics, testing, architecture). And no code or spec names a path
-- through a .claude/skills link (.claude/skills/<name>/...): git can't add through one, so every tool reads the real
-- folder. And no live file cites an old lesson id (`testing/no-vacuous-pass`) whose renamed lesson exists. Plain finds
-- only (lesson zz-test/plain-find-for-literals); `scan` and `oldLessonIds` are also run on planted texts.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local HYPHENATED = { "make-issue", "ticket-prep", "ready-raft", "launch-raft", "execute-raft", "stop-raft" }
local WORDS = { "review", "tracker", "metrics", "testing", "architecture" }

local function starts(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end
local function nameChar(c: string): boolean
	return c ~= "" and (string.match(c, "[%w_%-]") ~= nil)
end

-- Every old form in `text`, as "<form> at <line>".
local function scan(text: string): { string }
	local found: { string } = {}
	local function lineAt(i: number): number
		local n = 1
		for _ in string.gmatch(string.sub(text, 1, i), "\n") do
			n += 1
		end
		return n
	end
	local function each(needle: string, ok: (number, number) -> boolean)
		local from = 1
		while true do
			local a, b = string.find(text, needle, from, true)
			if not a then
				return
			end
			if ok(a :: number, b :: number) then
				table.insert(found, `{needle} at line {lineAt(a :: number)}`)
			end
			from = (b :: number) + 1
		end
	end
	local function before(a: number): string
		return string.sub(text, a - 1, a - 1)
	end
	local function after(b: number): string
		return string.sub(text, b + 1, b + 1)
	end
	for _, old in HYPHENATED do
		each(old, function(a, b)
			local prev = before(a)
			-- a promoted spec's file name (tests/acceptance/c0043/ticket-prep.spec.luau) is history, not a skill
			return not nameChar(prev)
				and prev ~= "."
				and not nameChar(after(b))
				and string.sub(text, b + 1, b + 5) ~= ".spec"
		end)
	end
	for _, old in WORDS do
		each(`.claude/skills/{old}`, function(_, b)
			return not nameChar(after(b))
		end)
		each(`\`{old}\` skill`, function()
			return true
		end)
		each(`{old} skill`, function(a)
			local prev = before(a)
			return not nameChar(prev) and prev ~= "`"
		end)
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

-- c0115 §5: an old lesson id is `<old skill>/<slug>` whose renamed lesson `<new skill>/<slug>.md` exists (the rename
-- script's own rule), so look-alike paths (tracker/next, scripts/tracker/x.luau) never count.
local LESSON_SKILL: { [string]: string } = {
	["make-issue"] = "z-ticket",
	["ticket-prep"] = "z-design",
	["ready-raft"] = "z-ready",
	["launch-raft"] = "z-run",
	["execute-raft"] = "z-run",
	["stop-raft"] = "z-stop",
	review = "zz-review",
	tracker = "zz-rules",
	metrics = "zz-stats",
	testing = "zz-test",
	architecture = "zz-arch",
}
local function existingLessons(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, base in { "z-nile/skills", "pickman/skills" } do
		if fs.isDir(base) then
			for _, skill in fs.readDir(base) do
				local dir = `{base}/{skill}/lessons`
				if fs.isDir(dir) then
					for _, name in fs.readDir(dir) do
						local slug = string.match(name, "^(.+)%.md$")
						if slug then
							out[`{skill}/{slug}`] = true
						end
					end
				end
			end
		end
	end
	return out
end
local function oldLessonIds(text: string, existing: { [string]: boolean }): { string }
	local found: { string } = {}
	for old, new in LESSON_SKILL do
		local from = 1
		while true do
			local a, b = string.find(text, old .. "/", from, true)
			if not a then
				break
			end
			local prev = string.sub(text, (a :: number) - 1, (a :: number) - 1)
			local slug = string.match(string.sub(text, (b :: number) + 1), "^([%w][%w%-]*)")
			if not nameChar(prev) and prev ~= "/" and prev ~= "." and slug and existing[`{new}/{slug}`] then
				table.insert(found, `{old}/{slug}`)
			end
			from = (b :: number) + 1
		end
	end
	table.sort(found)
	return found
end

local function tracked(): { string }
	local r = process.exec("git", { "ls-files" })
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
local LIVE_DIRS = { "z-nile/", "pickman/", ".claude/", "scripts/", ".github/", "tests/" }
local function live(path: string): boolean
	if string.find(path, "/.tracker/", 1, true) or starts(path, "tracker/") then
		return false
	end
	if
		starts(path, "tests/acceptance/")
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
local function readable(path: string): string?
	if not fs.isFile(path) then
		return nil -- a deleted file, or a link
	end
	local text = fs.readFile(path)
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
		local existing = existingLessons()
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
