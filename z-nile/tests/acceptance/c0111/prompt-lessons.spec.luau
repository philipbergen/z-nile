--!strict
-- c0111 AC5: the prompt `ready` writes carries the build and both lessons (never the design ones) in a Lessons
-- section before Work items; no lessons gives (none); a bad lesson is left out with a warning and never stops
-- `ready`. Fixtures under .cache/prompt-lessons and .cache/prompt-lessons-none (tests/lib/trackerfix).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
-- c0120 override: specs run from their project's home (z-nile/); the repository's files are read from the checkout's top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function lesson(when: string, check: string, from: boolean?): string
	return `---\ntitle: A lesson\nwhen: {when}\ntags: [wiring]\ncheck: {check}\n`
		.. (if from == false then "" else "from: user 2026-10-20: said so\n")
		.. "---\nBody.\n"
end

local function seed(withLessons: boolean): { [string]: string }
	local s: { [string]: string } = {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`), -- ignores prompt.md; c0120 override: read from the checkout's top
		-- c0120 override: pickman's items and architecture.md live in pickman/.tracker (engine.REGISTRY's layout)
		["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Lessons\nslug: lessons\nsingle: true\nissues: [c0010]\ndesign: ready\ncreated: 2026-10-20\nstatus: {PREPARED}\n---\n\n# R0010\n`,
		["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
		["pickman/.tracker/issues/c0010/c0010.md"] = `---\nid: c0010\ntype: chore\ntitle: c0010\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nstatus: {PREPARED}\n---\n\n# c0010\n`,
		["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
	}
	for _, name in { "execute-raft", "tracker", "architecture", "testing", "review", "ticket-prep" } do
		-- c0120 override: the spec runs from its home: the checkout's files are read from the top
		s[`.claude/skills/{name}/SKILL.md`] = fs.readFile(`{TOP}/.claude/skills/{name}/SKILL.md`)
	end
	if withLessons then
		-- two harvested sources and no from: its count and its place come from the harvest alone
		s[".claude/skills/testing/lessons/pin-inputs.md"] =
			lesson("build", "Are the call site's inputs pinned?", false)
		-- c0120 override: pickman's items and architecture.md live in pickman/.tracker (engine.REGISTRY's layout)
		s["pickman/.tracker/rafts/R0005/design-review-001.md"] =
			"# Review 001\n\n### F1 [low] a\n\n### F2 [low] b\n\nVerdict: changes\n"
		s["pickman/.tracker/rafts/R0005/harvest.md"] =
			"- design-review-001 F1: testing/pin-inputs\n- design-review-001 F2: testing/pin-inputs\n"
		s[".claude/skills/review/lessons/both-kinds.md"] = lesson("both", "Is the text consistent?")
		s[".claude/skills/ticket-prep/lessons/lifetimes.md"] =
			lesson("design", "Which process outlives which?")
		s[".claude/skills/testing/lessons/bad.md"] = lesson("never", "Is this ever shown?")
	end
	return s
end

local function lessonsSection(prompt: string): string
	local start = string.find(prompt, "\n## Lessons", 1, true)
	local work = string.find(prompt, "\n## Work items", 1, true)
	if not start or not work or start > work then
		error("no Lessons section before Work items", 2)
	end
	return string.sub(prompt, start, work)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0111 the prompt carries the build lessons", function(it)
	it("ready lists build and both lessons, not design ones, and warns about a bad one", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		local f = trackerfix.new("prompt-lessons", seed(true))
		local r = trackerfix.tr(f, f.main, { "ready", "R0010" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stderr, "warning") and has(r.stderr, "testing/bad")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local s = lessonsSection(fs.readFile(`{f.main}/pickman/.tracker/rafts/active/R0010/prompt.md`))
		-- exactly these lines, most sources first
		t.expect(
			has(
				s,
				"\n- testing/pin-inputs (build, 2 sources): Are the call site's inputs pinned?\n"
					.. "- review/both-kinds (both, 1 source): Is the text consistent?\n"
			)
		).toBe(true)
		t.expect(has(s, "lifetimes")).toBe(false)
		t.expect(has(s, "Is this ever shown?")).toBe(false)
		t.expect(has(s, "{{LESSONS}}")).toBe(false)
	end)

	it("a tree with no lessons gives (none)", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		local f = trackerfix.new("prompt-lessons-none", seed(false))
		local r = trackerfix.tr(f, f.main, { "ready", "R0010" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local s = lessonsSection(fs.readFile(`{f.main}/pickman/.tracker/rafts/active/R0010/prompt.md`))
		t.expect(has(s, "(none)")).toBe(true)
		t.expect(has(s, "{{LESSONS}}")).toBe(false)
	end)
end)
