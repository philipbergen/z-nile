--!strict
-- c0166 AC5: five rounds need a prompt-failure note; stream review files do not count.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local api = lessons :: any
local f: any
local DESIGN =
	'- design rounds reached 5 at design-review-005.md: the design prompt was unclear: "the sentence".'
local CODE = '- code rounds reached 5 at review-005.md: the ready prompt was unclear: "the sentence".'
local NOTE = "- note 5 design rounds, design prompt unclear: zz-test/pin"
local CODE_NOTE = "- note 5 code rounds, ready prompt unclear: zz-test/pin"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function between(text: string, from: string, to: string): string
	local a = string.find(text, from, 1, true)
	if not a then
		error(`no {from}\n{text}`, 2)
	end
	local b = string.find(text, to, a + #from, true)
	return string.sub(text, a, if b then b - 1 else #text)
end

local function doc(id: string, slug: string, kind: string, extra: string): string
	local issues = if kind == "raft" then "issues: []\nsingle: true\n" else "raft: \n"
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {slug}\n{issues}depends_on: []\nemergent: false\n`
		.. `design: ready\ncreated: 2026-10-26\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n{extra}`
end

local function reviews(seed: { [string]: string }, dir: string, n: number, prefix: string)
	for i = 1, n do
		local name = string.format("%s-%03d.md", prefix, i)
		seed[`{dir}/{name}`] = "# Review\n\n### F1 [low] a claim\n\nVerdict: changes\n"
	end
end

local function run(args: { string })
	return trackerfix.tr(f, f.main, args)
end

local function commit(message: string)
	return run({ "commit", "-m", message, "--time", "1" })
end

return t.spec("c0166 five rounds", function(it)
	it("promptFailure and needsPromptNote", function()
		t.expect(api.promptFailure ~= nil).toBe(true)
		local text = "# Raft\n\n## Prompt failure\n" .. DESIGN .. "\n- not a bullet\n"
		t.expect(api.promptFailure(text)).toEqual({ DESIGN })
		t.expect(api.promptFailure("# Raft\n\nno note\n")).toEqual({})
		t.expect(api.needsPromptNote("design", 4, 5, {})).toBe(true)
		t.expect(api.needsPromptNote("design", 4, 5, { DESIGN })).toBe(true)
		t.expect(api.needsPromptNote("design", 4, 5, { DESIGN }, { NOTE }, { ["zz-test/pin"] = true }))
			.toBe(false)
		t.expect(api.needsPromptNote("design", 4, 5, { DESIGN }, { NOTE }, {})).toBe(true)
		local badNote = "- note 5 design rounds, design prompt unclear: zz-test/missing"
		t.expect(
			api.needsPromptNote("design", 4, 5, { DESIGN }, { NOTE, badNote }, { ["zz-test/pin"] = true })
		)
			.toBe(true)
		t.expect(api.needsPromptNote("design", 5, 6, {})).toBe(false)
		t.expect(api.needsPromptNote("code", 4, 5, { DESIGN })).toBe(true)
		t.expect(api.needsPromptNote("code", 4, 5, { CODE })).toBe(true)
		t.expect(api.needsPromptNote("code", 4, 5, { CODE }, { CODE_NOTE }, { ["zz-test/pin"] = true }))
			.toBe(false)
	end)

	it("sets up rafts at and under five rounds", function()
		local seed: { [string]: string } = {
			["z-nile/.tracker/rafts/active/R0001/R0001.md"] = (
				string.gsub(doc("R0001", "lessons", "raft", ""), "issues: %[%]\n", "issues: [c0001]\n")
			),
			["z-nile/.tracker/issues/active/c0001/c0001.md"] = (
				string.gsub(doc("c0001", "c0001", "issue", ""), "raft: \n", "raft: R0001\n")
			),
			["z-nile/.tracker/rafts/R0002/R0002.md"] = doc("R0002", "stream", "raft", ""),
			["z-nile/.tracker/rafts/R0003/R0003.md"] = doc("R0003", "missing", "raft", ""),
			["z-nile/.tracker/rafts/R0004/R0004.md"] = doc(
				"R0004",
				"noted",
				"raft",
				"\n## Prompt failure\n" .. DESIGN .. "\n"
			),
			["z-nile/.tracker/rafts/R0004/harvest.md"] = NOTE .. "\n",
			["z-nile/.tracker/rafts/active/R0005/R0005.md"] = (
				string.gsub(doc("R0005", "code", "raft", ""), "issues: %[%]\n", "issues: [c0005]\n")
			),
			["z-nile/.tracker/issues/active/c0005/c0005.md"] = (
				string.gsub(doc("c0005", "c0005", "issue", ""), "raft: \n", "raft: R0005\n")
			),
			["z-nile/.tracker/issues/c0002/c0002.md"] = doc("c0002", "c0002", "issue", ""),
			["z-nile/.tracker/issues/c0009/c0009.md"] = doc("c0009", "c0009", "issue", ""),
			["z-nile/skills/zz-test/lessons/pin.md"] = "---\ntitle: Pin\nwhen: build\ntags: [wiring]\ncheck: Is the pin specific?\nfrom: user 2026-10-26: said so\n---\nBody.\n",
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
			["z-nile/.tracker/rafts/R0007/R0007.md"] = doc("R0007", "split", "raft", ""),
			["z-nile/.tracker/issues/c0007/c0007.md"] = (
				string.gsub(doc("c0007", "c0007", "issue", ""), "raft: \n", "raft: R0007\n")
			),
			["z-nile/.tracker/issues/c0008/c0008.md"] = (
				string.gsub(doc("c0008", "c0008", "issue", ""), "raft: \n", "raft: R0007\n")
			),
			["z-nile/.tracker/rafts/R0008/R0008.md"] = doc("R0008", "member", "raft", ""),
			["z-nile/.tracker/issues/c0011/c0011.md"] = (
				string.gsub(doc("c0011", "c0011", "issue", ""), "raft: \n", "raft: R0008\n")
			),
		}
		reviews(seed, "z-nile/.tracker/rafts/active/R0001", 4, "design-review")
		reviews(seed, "z-nile/.tracker/rafts/R0002", 5, "stream-review")
		reviews(seed, "z-nile/.tracker/rafts/R0003", 5, "design-review")
		reviews(seed, "z-nile/.tracker/rafts/R0004", 5, "design-review")
		reviews(seed, "z-nile/.tracker/rafts/active/R0005", 4, "review")
		reviews(seed, "z-nile/.tracker/issues/c0002", 5, "design-review")
		reviews(seed, "z-nile/.tracker/issues/c0009", 4, "design-review")
		reviews(seed, "z-nile/.tracker/issues/c0007", 4, "design-review")
		reviews(seed, "z-nile/.tracker/issues/c0008", 4, "design-review")
		reviews(seed, "z-nile/.tracker/issues/c0011", 5, "design-review")
		f = trackerfix.new("c0166-rounds", seed, { noLessons = true })
		fixture.git(f.main, { "branch", "R0001-lessons" })
		fixture.git(f.main, { "branch", "R0005-code" })
	end)

	it("metrics lists a missing note and a recorded one, and stream files are not rounds", function()
		local r = run({ "metrics" })
		if r.code ~= 0 then
			error(`exit {r.code}\n{r.stderr}{r.stdout}`, 0)
		end
		local section = between(r.stdout, "## Review rounds at 5", "## Lesson recurrence")
		t.expect(has(section, "- R0003: design 5, code 0; missing")).toBe(true)
		t.expect(has(section, 'the design prompt was unclear: "the sentence".')).toBe(true)
		t.expect(has(section, "R0002")).toBe(false)
		t.expect(has(section, "R0001")).toBe(false)
		t.expect(has(section, "R0007")).toBe(false)
		t.expect(has(section, "- R0008: c0011 design 5; missing")).toBe(true)
		t.expect(has(r.stdout, "## Lesson recurrence")).toBe(true)
	end)

	it("rounds exits 1 at five without a note and 0 otherwise", function()
		local five = run({ "lessons", "--rounds", "c0002" })
		t.expect(five.code).toBe(1)
		t.expect(has(five.stderr, "rounds: c0002 design reached 5 without a prompt-failure note")).toBe(true)
		local four = run({ "lessons", "--rounds", "c0009" })
		if four.code ~= 0 then
			error(four.stderr .. four.stdout, 0)
		end
		t.expect(has(four.stdout, "rounds: c0009 design 4, code 0")).toBe(true)
		local stream = run({ "lessons", "--rounds", "R0002" })
		if stream.code ~= 0 then
			error(stream.stderr .. stream.stdout, 0)
		end
		t.expect(has(stream.stdout, "rounds: R0002 design 0, code 0")).toBe(true)
		local split = run({ "lessons", "--rounds", "R0007" })
		if split.code ~= 0 then
			error(split.stderr .. split.stdout, 0)
		end
		t.expect(has(split.stdout, "rounds: R0007 design 0, code 0")).toBe(true)
		local member = run({ "lessons", "--rounds", "R0008" })
		t.expect(member.code).toBe(1)
		t.expect(has(member.stderr, "rounds: R0008 c0011 design reached 5 without a prompt-failure note"))
			.toBe(true)
		local noted = run({ "lessons", "--rounds", "R0004" })
		if noted.code ~= 0 then
			error(noted.stderr .. noted.stdout, 0)
		end
	end)

	it("crossing", function()
		fixture.git(f.main, { "checkout", "-q", "R0001-lessons" })
		local dir = `{f.main}/z-nile/.tracker/rafts/active/R0001`
		fs.writeFile(`{dir}/design-review-005.md`, "# Review\n\n### F1 [low] a claim\n\nVerdict: approve\n")
		local early = run({ "lessons", "--rounds", "R0001" })
		t.expect(early.code).toBe(1)
		local refused = commit("fifth design round")
		t.expect(refused.code).toBe(1)
		t.expect(has(refused.stderr, "commit: R0001 design rounds reached 5 without a prompt-failure note"))
			.toBe(true)
		t.expect(fixture.git(f.main, { "log", "-1", "--format=%s" })).toBe("seed")
		local raft = fs.readFile(`{dir}/R0001.md`)
		fs.writeFile(`{dir}/R0001.md`, raft .. "\n## Prompt failure\n" .. DESIGN .. "\n")
		local bulletOnly = commit("bullet without a harvest note")
		t.expect(bulletOnly.code).toBe(1)
		t.expect(
			has(bulletOnly.stderr, "commit: R0001 design rounds reached 5 without a prompt-failure note")
		)
			.toBe(true)
		fs.writeFile(`{dir}/harvest.md`, "- note 5 design rounds, design prompt unclear: zz-test/missing\n")
		local missing = commit("a missing lesson id")
		t.expect(missing.code).toBe(1)
		t.expect(has(missing.stderr, "commit: R0001 design rounds reached 5 without a prompt-failure note"))
			.toBe(true)
		fs.writeFile(`{dir}/harvest.md`, NOTE .. "\n")
		local unchanged = commit("note without a check change")
		t.expect(unchanged.code).toBe(1)
		t.expect(
			has(unchanged.stderr, "commit: zz-test/pin gained a source and its check line did not change")
		)
			.toBe(true)
		local pin = `{f.main}/z-nile/skills/zz-test/lessons/pin.md`
		fs.writeFile(
			pin,
			(string.gsub(fs.readFile(pin), "Is the pin specific%?", "Is the pin still specific?"))
		)
		local allowed = commit("fifth design round noted")
		if allowed.code ~= 0 then
			error(`exit {allowed.code}\n{allowed.stderr}{allowed.stdout}`, 0)
		end
		fs.writeFile(`{dir}/design-review-006.md`, "# Review\n\n### F1 [low] a claim\n\nVerdict: changes\n")
		local later = commit("sixth design round")
		if later.code ~= 0 then
			error(`exit {later.code}\n{later.stderr}{later.stdout}`, 0)
		end
	end)

	it("a code round that crosses five is refused until the note is in the commit", function()
		fixture.git(f.main, { "checkout", "-q", "R0005-code" })
		local dir = `{f.main}/z-nile/.tracker/rafts/active/R0005`
		fs.writeFile(`{dir}/review-005.md`, "# Review\n\n### F1 [low] a claim\n\nVerdict: approve\n")
		local refused = commit("fifth code round")
		t.expect(refused.code).toBe(1)
		t.expect(has(refused.stderr, "commit: R0005 code rounds reached 5 without a prompt-failure note"))
			.toBe(true)
		local raft = fs.readFile(`{dir}/R0005.md`)
		fs.writeFile(`{dir}/R0005.md`, raft .. "\n## Prompt failure\n" .. CODE .. "\n")
		fs.writeFile(`{dir}/harvest.md`, CODE_NOTE .. "\n")
		local pin = `{f.main}/z-nile/skills/zz-test/lessons/pin.md`
		fs.writeFile(
			pin,
			(string.gsub(fs.readFile(pin), "Is the pin specific%?", "Is the pin still specific?"))
		)
		local allowed = commit("fifth code round noted")
		if allowed.code ~= 0 then
			error(`exit {allowed.code}\n{allowed.stderr}{allowed.stdout}`, 0)
		end
	end)

	it("members at four and four are not five", function()
		local r = run({ "lessons", "--rounds", "R0007" })
		if r.code ~= 0 then
			error(r.stderr .. r.stdout, 0)
		end
		t.expect(has(r.stdout, "rounds: R0007 design 0, code 0")).toBe(true)
	end)

	it("a member at five", function()
		local r = run({ "lessons", "--rounds", "R0008" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "rounds: R0008 c0011 design reached 5 without a prompt-failure note"))
			.toBe(true)
	end)

	it("a raft document bullet", function()
		local dir = `{f.main}/z-nile/.tracker/rafts/R0008`
		local body = fs.readFile(`{dir}/R0008.md`)
		local other =
			'- design rounds reached 5 at c0099/design-review-005.md: the design prompt was unclear: "the sentence".'
		fs.writeFile(`{dir}/R0008.md`, body .. "\n## Prompt failure\n" .. other .. "\n")
		fs.writeFile(`{dir}/harvest.md`, NOTE .. "\n")
		local wrong = run({ "lessons", "--rounds", "R0008" })
		t.expect(wrong.code).toBe(1)
		local named =
			'- design rounds reached 5 at c0011/design-review-005.md: the design prompt was unclear: "the sentence".'
		fs.writeFile(`{dir}/R0008.md`, body .. "\n## Prompt failure\n" .. named .. "\n")
		local right = run({ "lessons", "--rounds", "R0008" })
		if right.code ~= 0 then
			error(right.stderr .. right.stdout, 0)
		end
		fs.writeFile(`{dir}/R0008.md`, body)
		fs.removeFile(`{dir}/harvest.md`)
	end)

	it("a member's bullet", function()
		local dir = `{f.main}/z-nile/.tracker/issues/c0011`
		local body = fs.readFile(`{dir}/c0011.md`)
		local bullet =
			'- design rounds reached 5 at c0011/design-review-005.md: the design prompt was unclear: "the sentence".'
		fs.writeFile(`{dir}/c0011.md`, body .. "\n## Prompt failure\n" .. bullet .. "\n")
		fs.writeFile(`{dir}/harvest.md`, NOTE .. "\n")
		local r = run({ "lessons", "--rounds", "R0008" })
		if r.code ~= 0 then
			error(r.stderr .. r.stdout, 0)
		end
	end)
end)
