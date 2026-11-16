--!strict
-- c0181 AC9: the skills and AGENTS.md say the same thing about writing a lesson: settle overlap, then whether a check
-- can enforce it, then record both, then run the policy and the lints. The rule is stated once (zz-rules, "Writing a lesson") and
-- the other skills point at it; every skill's Lessons paragraph stays one paragraph (c0111). Reads the real files.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function section(text: string, prefix: string): string
	local start = string.find(text, "\n## " .. prefix, 1, true)
	if not start then
		error(`no "## {prefix}" section`, 2)
	end
	local after = string.find(text, "\n## ", start + 1, true)
	return string.sub(text, start, if after then after - 1 else #text)
end
local function at(text: string, phrase: string, from: number?): number
	local i = string.find(text, phrase, from or 1, true)
	if not i then
		error(`missing: {phrase}`, 2)
	end
	return i
end
local function skills(): { string }
	local out = {}
	for _, base in { "z-nile/skills", "pickman/skills" } do
		for _, name in fs.readDir(`{TOP}/{base}`) do
			if fs.isFile(`{TOP}/{base}/{name}/SKILL.md`) then
				table.insert(out, `{base}/{name}`)
			end
		end
	end
	table.sort(out)
	return out
end

local BULLET =
	"- **Every lesson written or sharpened** is first checked for overlap and for a check that can enforce it (zz-rules skill, Writing a lesson)."

return t.spec("c0181 skills and the lesson process", function(it)
	it("every skill's Lessons paragraph carries the same fourth bullet and still the three roles", function()
		local n = 0
		for _, dir in skills() do
			local s = section(read(`{dir}/SKILL.md`), "Lessons")
			at(s, BULLET)
			at(s, "- **A subagent** (")
			at(s, "- **The lead of a prep or raft** writes it in")
			at(s, "- **Any other lead** (")
			n += 1
		end
		t.expect(n >= 14).toBe(true)
	end)

	it("zz-rules states the format, the commands and the order once", function()
		local text = read("z-nile/skills/zz-rules/SKILL.md")
		for _, key in { "`enforced_by`", "`enforced`", "`not_codifiable`", "`distinct_from`", "`merged`" } do
			at(text, key)
		end
		for _, cmd in
			{
				"--enforced",
				"--codified",
				"--consolidate",
				"--check --policy",
				"`./zn lesson-merge <into> <from>…`",
				"`./zn prove <id>",
				"`./zn mutate ",
				"`./zn clean ",
			}
		do
			at(text, cmd)
		end
		-- the refusal list of the main checkout names the new writer
		local refuse = at(text, "The tracker enforces part of this:")
		local list = string.sub(text, refuse, at(text, "\n", refuse)) -- the sentence's own line
		at(list, "`lesson-merge`")
		at(list, "`prove`")
		local s = section(text, "Writing a lesson")
		local a = at(s, "./zn lessons --consolidate <id>")
		local b = at(s, "`enforced_by`", a)
		local c = at(s, "- codify <lesson id>:", b)
		local d = at(s, "./zn lessons --check --policy", c)
		at(s, "lune run z-nile/lints", d)
		at(s, "not codifiable: <why>")
		at(s, "a rule the tool runs at the moment of the mistake")
		at(s, "`enforced: full` means every clause of the lesson's `check` is decided by the named checks")
		at(s, "`Codify:`") -- a subagent's candidate carries the line
		at(s, "./zn lessons --check --policy --item <id>")
	end)

	it(
		"the order of the process is stated in exactly one skill, and no 'Lessons' section holds it",
		function()
			local PHRASE = "whether a lint over texts or a spec case can decide the rule"
			local holders = {}
			for _, dir in skills() do
				local text = read(`{dir}/SKILL.md`)
				if string.find(text, PHRASE, 1, true) then
					table.insert(holders, dir)
				end
			end
			t.expect(holders).toEqual({ "z-nile/skills/zz-rules" })
			t.expect(
				(string.find(section(read("z-nile/skills/zz-rules/SKILL.md"), "Lessons"), PHRASE, 1, true))
			)
				.toBe(nil)
		end
	)

	it("z-design and zz-execute harvest, codify and confirm with the same commands", function()
		local design = read("z-nile/skills/z-design/SKILL.md")
		local h = at(design, "**Harvest the round**")
		at(design, "./zn lessons --consolidate <id>", h)
		at(design, "- codify <lesson id>:", h)
		local confirm = at(design, "**Confirm the harvest**")
		at(design, "./zn lessons --check --policy", confirm)
		at(design, "lune run z-nile/lints", confirm)
		local exec = read("z-nile/skills/zz-execute/SKILL.md")
		local e = at(exec, "**Harvest the round**")
		at(exec, "./zn lessons --consolidate <id>", e)
		at(exec, "- codify <lesson id>:", e)
		local ec = at(exec, "**Confirm the harvest**")
		at(exec, "./zn lessons --check --policy", ec)
		at(exec, "`Codify:`") -- the stream report format
	end)

	it("zz-review does not ask a fully enforced lesson", function()
		local s = read("z-nile/skills/zz-review/SKILL.md")
		at(s, "A fully enforced lesson is not asked: the gate asks it.")
		at(
			s,
			"A lesson marked `enforced: full` whose `check` leaves a clause the named checks do not decide is a finding."
		)
	end)

	it(
		"zz-test says where a codified lesson lives and what it must carry; zz-arch the rules for lints",
		function()
			local test = section(read("z-nile/skills/zz-test/SKILL.md"), "Codifying a lesson")
			for _, key in
				{
					"z-nile/lints/",
					"z-nile/engine/rules/",
					"`bad`",
					"`good`",
					"lint-ok <lesson id>: <reason>",
					"`allow`",
					"`PICKMAN_LESSONS_ROOT`",
					"a threshold on a live count",
				}
			do
				at(test, key)
			end
			local arch = read("z-nile/skills/zz-arch/SKILL.md")
			at(arch, "A lint is a pure scan over texts")
			at(arch, "scanned 0 files")
		end
	)

	it("zz-stats reports the codified share", function()
		at(read("z-nile/skills/zz-stats/SKILL.md"), "./zn lessons --codified")
	end)

	it("AGENTS.md says a lesson is codified or consolidated when written", function()
		local s = read("AGENTS.md")
		local i = at(s, "Each skill keeps what reviews and mistakes taught it in its `lessons/` folder")
		at(s, "codified as a check where it can be", i)
		at(s, "merged into an overlapping one", i)
	end)

	it(
		"z-design runs ./zn prove before the confirm step, z-ready says what a stale stamp means, and the removal text uses ./zn clean",
		function()
			local design = read("z-nile/skills/z-design/SKILL.md")
			local p = at(design, "./zn prove <id>")
			t.expect(p < at(design, "**Confirm the harvest**")).toBe(true)
			at(read("z-nile/skills/z-ready/SKILL.md"), "proof.md")
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			at(section(rules, "Landing"), "./zn clean")
			at(read("z-nile/engine/main.luau"), "remove this worktree: ./zn clean")
			at(read("z-nile/skills/z-ticket/SKILL.md"), "./zn clean")
		end
	)
end)
