--!strict
-- c0166 AC7: the ready prompt filters on Touched modules, and keeps every build lesson when there are none.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local AREAS = "core: process, review, scope, sequestration\n"
	.. "mode code: zz-execute, zz-review, zz-test\n"
	.. "skill zz-arch: z-nile/lib\n"
	.. "fence: z-nile/lib/fence.sh\nwiring: @skill\n"
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function lesson(when: string, tags: string, check: string): string
	return `---\ntitle: A lesson\nwhen: {when}\ntags: [{tags}]\ncheck: {check}\nfrom: user 2026-10-26: said so\n---\nBody.\n`
end

local function seed(touched: { string }?): { [string]: string }
	local body = `---\nid: c0010\ntype: chore\ntitle: c0010\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\n`
		.. `design: ready\ncreated: 2026-10-26\nstatus: {PREPARED}\n---\n\n# c0010\n`
	if touched then
		body ..= "\n## Design\n\n### Touched modules\n"
		for _, path in touched do
			body ..= "- `" .. path .. "`\n"
		end
		body ..= "\n## Next\n"
	end
	return {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		["z-nile/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Lessons\nslug: lessons\n`
			.. `single: true\nissues: [c0010]\ndesign: ready\ncreated: 2026-10-26\nstatus: {PREPARED}\n---\n\n# R0010\n`,
		["z-nile/.tracker/rafts/R0010/check.sh"] = CHECK,
		["z-nile/.tracker/issues/c0010/c0010.md"] = body,
		["z-nile/.tracker/issues/c0010/check.sh"] = CHECK,
		["z-nile/skills/zz-test/lessons/wire.md"] = lesson("build", "wiring", "Does the wire hold?"),
		["z-nile/skills/zz-arch/lessons/fence.md"] = lesson("build", "fence", "Does the fence hold?"),
		["z-nile/skills/zz-review/lessons/core.md"] = lesson("both", "review", "Does the review apply?"),
		["z-nile/skills/z-design/lessons/only.md"] = lesson("design", "fence", "Is this design only?"),
		["z-nile/skills/zz-stats/lessons/tally.md"] = lesson("build", "wiring", "Does the tally hold?"),
		["z-nile/lesson-areas.md"] = AREAS,
	}
end

local function section(prompt: string): string
	local start = string.find(prompt, "\n## Lessons", 1, true)
	local work = string.find(prompt, "\n## Work items", 1, true)
	if not start or not work or start > work then
		error("no Lessons section before Work items", 2)
	end
	return string.sub(prompt, start, work)
end

local function ready(name: string, touched: { string }?): string
	local fx = trackerfix.new(name, seed(touched), { noLessons = true })
	local r = trackerfix.tr(fx, fx.main, { "ready", "R0010" })
	if not r.ok then
		error(r.stderr .. r.stdout, 0)
	end
	return section(fs.readFile(`{fx.main}/z-nile/.tracker/rafts/active/R0010/prompt.md`))
end

return t.spec("c0166 prompt lessons", function(it)
	it("a raft whose issues name no Touched modules keeps every build and both lesson", function()
		local s = ready("c0166-prompt-none", nil)
		t.expect(has(s, "zz-test/wire")).toBe(true)
		t.expect(has(s, "zz-arch/fence")).toBe(true)
		t.expect(has(s, "zz-review/core")).toBe(true)
		t.expect(has(s, "z-design/only")).toBe(false)
	end)

	it("a raft whose issues name Touched modules omits a build lesson that does not overlap them", function()
		local s = ready("c0166-prompt-fence", { "z-nile/lib/fence.sh" })
		t.expect(has(s, "zz-arch/fence")).toBe(true)
		t.expect(has(s, "zz-review/core")).toBe(true)
		t.expect(has(s, "zz-test/wire")).toBe(true)
		t.expect(has(s, "zz-stats/tally")).toBe(false)
		t.expect(has(s, "z-design/only")).toBe(false)
	end)

	it("a missing area file keeps every build lesson", function()
		local fx =
			trackerfix.new("c0166-prompt-noareas", seed({ "z-nile/lib/fence.sh" }), { noLessons = true })
		local areas = `{fx.main}/z-nile/lesson-areas.md`
		if fs.isFile(areas) then
			fixture.git(fx.main, { "rm", "-q", "--", "z-nile/lesson-areas.md" })
			fixture.git(fx.main, { "commit", "-q", "-m", "drop areas" })
			fixture.git(fx.main, { "push", "-q", "origin", "HEAD:main" })
		end
		local r = trackerfix.tr(fx, fx.main, { "ready", "R0010" })
		if not r.ok then
			error(r.stderr .. r.stdout, 0)
		end
		local s = section(fs.readFile(`{fx.main}/z-nile/.tracker/rafts/active/R0010/prompt.md`))
		t.expect(has(r.stderr, "warning: lesson-areas.md is missing; no path filter")).toBe(true)
		t.expect(has(s, "zz-test/wire")).toBe(true)
		t.expect(has(s, "zz-stats/tally")).toBe(true)
	end)

	it("a project-relative Touched path keeps every build lesson", function()
		local s = ready("c0166-prompt-relative", { "src/shared/Logic/Maze" })
		t.expect(has(s, "zz-test/wire")).toBe(true)
		t.expect(has(s, "zz-arch/fence")).toBe(true)
		t.expect(has(s, "zz-review/core")).toBe(true)
		t.expect(has(s, "z-design/only")).toBe(false)
	end)
end)
