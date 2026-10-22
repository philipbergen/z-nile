--!strict
-- c0111 AC4: `scripts/tracker.sh lessons` lists, shows, searches, validates and reports coverage, with the exit
-- codes and refusals specified, in tracker fixtures under .cache/lessons-cli and .cache/lessons-cli-empty
-- (tests/lib/trackerfix). It only reads; the edits below are to the fixture's own working tree.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function skill(name: string): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n`
end
local function lesson(when: string, tags: string, check: string, body: string, from: string?): string
	return `---\ntitle: A lesson\nwhen: {when}\ntags: [{tags}]\ncheck: {check}\n`
		.. (if from then `from: {from}\n` else "")
		.. `---\n{body}\n`
end
local function review(...: string): string
	local out = "# Review 001\n\n"
	for _, f in { ... } do
		out ..= `### {f} [low] claim\nEvidence: x\n\n`
	end
	return out .. "Verdict: changes\n"
end

local PIN = ".claude/skills/testing/lessons/pin-inputs.md"
local SEED: { [string]: string } = {
	[".claude/skills/testing/SKILL.md"] = skill("testing"),
	[".claude/skills/review/SKILL.md"] = skill("review"),
	[".claude/skills/ticket-prep/SKILL.md"] = skill("ticket-prep"),
	[PIN] = lesson("build", "wiring, seams", "Are the call site's inputs pinned?", "Pin them."),
	[".claude/skills/ticket-prep/lessons/lifetimes.md"] = lesson(
		"design",
		"lifetimes",
		"Which process outlives which?",
		"Name the owner."
	),
	[".claude/skills/review/lessons/both-kinds.md"] = lesson(
		"both",
		"wiring",
		"Is the text consistent?",
		"Read it twice; see testing/pin-inputs.",
		"user 2026-10-20: read it twice"
	),
	-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout), every item path in this seed
	["pickman/.tracker/rafts/R0010/design-review-001.md"] = review("F1", "F2", "F3"),
	["pickman/.tracker/rafts/R0010/review-001.md"] = review("F1", "F2"),
	["pickman/.tracker/rafts/R0010/harvest.md"] = "# Harvest: R0010\n\n- design-review-001 F1: testing/pin-inputs\n"
		.. "- design-review-001 F2: ticket-prep/lifetimes\n- design-review-001 F3: one-off: a typo\n"
		.. "- review-001 F2: testing/pin-inputs\n",
	["pickman/.tracker/issues/done/c0020/review-001.md"] = review("F1"),
	["pickman/.tracker/rafts/R0030/design-review-001.md"] = "# Review 001\n\nVerdict: approve\n",
	-- a readied raft with an unharvested finding, and an item with no reviews at all
	["pickman/.tracker/rafts/active/R0050/design-review-001.md"] = review("F1"),
	["pickman/.tracker/rafts/R0060/R0060.md"] = "# R0060\n",
	-- one unharvested item in each remaining kind and state, so every folder load walks is seen:
	-- rafts in the backlog (R0010), active/ (R0050) and done/ (R0070); issues in the backlog (c0090),
	-- active/ (c0080) and done/ (c0020)
	["pickman/.tracker/rafts/done/R0070/review-001.md"] = review("F1"),
	["pickman/.tracker/issues/active/c0080/review-001.md"] = review("F1"),
	["pickman/.tracker/issues/c0090/design-review-001.md"] = review("F1"),
	-- not reviews: a stream review and an experiment copy
	["pickman/.tracker/rafts/R0010/stream-review-c0010-001.md"] = review("F1"),
	["pickman/.tracker/issues/c0040/experiments/old/design-review-001.md"] = review("F1"),
}

local f: trackerfix.Fixture
local function run(args: { string }): (number, string, string)
	local argv = { "lessons" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = trackerfix.tr(f, f.main, argv)
	return r.code, r.stdout, r.stderr
end
local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0111 tracker.sh lessons", function(it)
	it("sets up a tracker fixture with lessons, ledgers and reviews", function()
		f = trackerfix.new("lessons-cli", SEED)
	end)

	it("lists every lesson by sources then id, one index line each", function()
		local code, out = run({})
		t.expect(code).toBe(0)
		t.expect(lines(out)).toEqual({
			"- testing/pin-inputs (build, 2 sources): Are the call site's inputs pinned?",
			"- review/both-kinds (both, 1 source): Is the text consistent?",
			"- ticket-prep/lifetimes (design, 1 source): Which process outlives which?",
		})
	end)

	it("filters by when, skill, tag and words", function()
		local _, design = run({ "--when", "design" })
		t.expect(#lines(design)).toBe(2)
		t.expect(has(design, "review/both-kinds") and has(design, "ticket-prep/lifetimes")).toBe(true)
		local _, build = run({ "--when", "build" })
		t.expect(has(build, "testing/pin-inputs") and has(build, "review/both-kinds")).toBe(true)
		t.expect(has(build, "lifetimes")).toBe(false)
		local _, two = run({ "--skill", "testing", "--skill", "ticket-prep" })
		t.expect(#lines(two)).toBe(2)
		local _, tagged = run({ "--tag", "wiring", "--tag", "seams" })
		t.expect(lines(tagged))
			.toEqual({ "- testing/pin-inputs (build, 2 sources): Are the call site's inputs pinned?" })
		local _, word = run({ "OWNER" })
		t.expect(#lines(word)).toBe(1)
		t.expect(has(word, "ticket-prep/lifetimes")).toBe(true)
		local code, none = run({ "nothing-matches-this" })
		t.expect(code).toBe(0)
		t.expect(none).toBe("(none)\n")
	end)

	it("--full prints the path, the sources and the file", function()
		local code, out = run({ "--full", "pin-inputs" })
		t.expect(code).toBe(0)
		t.expect(has(out, PIN)).toBe(true)
		t.expect(has(out, "R0010 design-review-001 F1, R0010 review-001 F2")).toBe(true)
		t.expect(has(out, "Pin them.")).toBe(true)
		t.expect(has(out, "lifetimes")).toBe(false)
	end)

	it("--full with no word shows every lesson in index order, one blank line apart, from last", function()
		local code, out = run({ "--full" })
		t.expect(code).toBe(0)
		local function block(path: string, sources: string): string
			return `== {path}\nsources: {sources}\n` .. SEED[path]
		end
		t.expect(out).toBe(
			block(PIN, "R0010 design-review-001 F1, R0010 review-001 F2")
				.. "\n"
				.. block(".claude/skills/review/lessons/both-kinds.md", "user 2026-10-20: read it twice")
				.. "\n"
				.. block(".claude/skills/ticket-prep/lessons/lifetimes.md", "R0010 design-review-001 F2")
		)
	end)

	it("a word that is a lesson id selects exactly that lesson", function()
		local function blocks(text: string): number
			local _, n = string.gsub("\n" .. text, "\n== ", "")
			return n
		end
		local _, word = run({ "--full", "pin-inputs" }) -- a plain word: both-kinds mentions it too
		t.expect(blocks(word)).toBe(2)
		local _, id = run({ "--full", "testing/pin-inputs" })
		t.expect(blocks(id)).toBe(1)
		t.expect(has(id, PIN)).toBe(true)
	end)

	it("--tags lists the tags in use, most used first", function()
		local code, out = run({ "--tags" })
		t.expect(code).toBe(0)
		t.expect(lines(out)).toEqual({ "wiring 2", "lifetimes 1", "seams 1" })
	end)

	it("--check passes a sound tree and says so", function()
		local code, out = run({ "--check" })
		t.expect(code).toBe(0)
		t.expect(lines(out)).toEqual({ "lessons: 3 lessons, 4 harvest entries, ok" })
	end)

	it("--uncovered lists every unharvested finding, and an id with no findings passes", function()
		local code, out = run({ "--uncovered" })
		t.expect(code).toBe(1)
		t.expect(lines(out)).toEqual({
			"R0010 review-001 F1",
			"R0050 design-review-001 F1",
			"R0070 review-001 F1",
			"c0020 review-001 F1",
			"c0080 review-001 F1",
			"c0090 design-review-001 F1",
		})
		local active, activeOut = run({ "--uncovered", "R0050" })
		t.expect(active).toBe(1)
		t.expect(lines(activeOut)).toEqual({ "R0050 design-review-001 F1" })
		local one, oneOut = run({ "--uncovered", "R0010" })
		t.expect(one).toBe(1)
		t.expect(lines(oneOut)).toEqual({ "R0010 review-001 F1" })
		local ok, okOut = run({ "--uncovered", "R0030" })
		t.expect(ok).toBe(0)
		t.expect(has(okOut, "harvest: every finding is covered")).toBe(true)
		local bare, bareOut = run({ "--uncovered", "R0060" })
		t.expect(bare).toBe(0)
		t.expect(has(bareOut, "R0060: no reviews")).toBe(true)
		local missing, _, missingErr = run({ "--uncovered", "R0099" })
		t.expect(missing).toBe(2)
		t.expect(has(missingErr, "R0099: no such item")).toBe(true)
	end)

	it("refuses bad usage with exit 2", function()
		for _, args in
			{
				{ "--when", "sometimes" },
				{ "--when", "design", "--when", "build" },
				{ "--check", "x" },
				{ "--check", "--tag", "x" },
				{ "--uncovered", "--full" },
				{ "--tags", "x" },
				{ "--bogus", "x" },
				{ "--skill" },
			}
		do
			local code, _, err = run(args)
			if code ~= 2 then
				error(`lessons {table.concat(args, " ")} exited {code}`)
			end
			t.expect(has(err, "usage")).toBe(true)
		end
	end)

	it("a bad lesson is skipped with a warning by the listing, and fails --check", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		fs.writeFile(`{f.main}/.claude/skills/testing/lessons/bad.md`, lesson("never", "x", "Q?", "B"))
		fs.writeFile(`{f.main}/.claude/skills/testing/lessons/notes.txt`, "scratch\n")
		local code, out, err = run({})
		t.expect(code).toBe(0)
		t.expect(#lines(out)).toBe(3)
		t.expect(has(err, "testing/bad")).toBe(true)
		-- a sound lesson with no source is listed (only parse failures are skipped), and --check names it
		fs.writeFile(
			`{f.main}/.claude/skills/testing/lessons/lonely.md`,
			lesson("build", "x", "Alone?", "No source.")
		)
		local _, lonely = run({ "--full", "testing/lonely" })
		t.expect(has(lonely, "sources: none")).toBe(true)
		local bad, badOut = run({ "--check" })
		t.expect(bad).toBe(1)
		t.expect(has(badOut, "testing/bad")).toBe(true)
		t.expect(has(badOut, "notes.txt")).toBe(true)
		t.expect(has(badOut, "testing/lonely")).toBe(true)
		fs.removeFile(`{f.main}/.claude/skills/testing/lessons/lonely.md`)
		fs.removeFile(`{f.main}/.claude/skills/testing/lessons/bad.md`)
		fs.removeFile(`{f.main}/.claude/skills/testing/lessons/notes.txt`)
		local h = `{f.main}/pickman/.tracker/rafts/R0010/harvest.md`
		fs.writeFile(h, fs.readFile(h) .. "- review-001 F1: testing/gone\n")
		local gone, goneOut = run({ "--check" })
		t.expect(gone).toBe(1)
		t.expect(has(goneOut, "testing/gone")).toBe(true)
	end)

	it("an empty tree lists (none), checks ok and is covered", function()
		f = trackerfix.new("lessons-cli-empty")
		local code, out = run({})
		t.expect(code).toBe(0)
		t.expect(out).toBe("(none)\n")
		local c, cOut = run({ "--check" })
		t.expect(c).toBe(0)
		t.expect(lines(cOut)).toEqual({ "lessons: 0 lessons, 0 harvest entries, ok" })
		local u, uOut = run({ "--uncovered" })
		t.expect(u).toBe(0)
		t.expect(has(uOut, "harvest: every finding is covered")).toBe(true)
	end)
end)
