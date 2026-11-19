--!strict
-- f0417 AC11: the skills say the loops (idea 5, design 9, code 9), the round's reviewer and what it reads, the cap and
-- the person, z-work's idea action, the assumption record, the approval the last gate binds and the refusal; they keep
-- the sentences f0399's docs spec pins; and z-design gives c0161 the multi-round sentences its spec needs. Reads the
-- real tree, plain finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function skill(name: string): string
	return read(`z-nile/skills/{name}/SKILL.md`)
end
local function at(text: string, needle: string, where: string): number
	return string.find(text, needle, 1, true) or error(`{where} is missing: {needle}`, 2)
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still says: {needle}`, 2)
	end
end
local function section(text: string, heading: string): string
	local mark = `\n## {heading}`
	local start = string.find(text, mark, 1, true) or error(`no "## {heading}" section`, 2)
	local nxt = string.find(text, "\n## ", start + #mark, true)
	return if nxt then string.sub(text, start, nxt - 1) else string.sub(text, start)
end

return t.spec("f0417: the skills say the loops", function(it)
	it("z-design: the design loop of up to 9 rounds, and c0161's sentences", function()
		local s5 = section(skill("z-design"), "5.")
		local w = "z-design step 5"
		at(
			s5,
			"Back and forth: a clean reviewer, your answers, then a new clean reviewer, until a round approves with no open finding or the cap of 9 rounds is reached",
			w
		)
		at(s5, "given the earlier rounds' review and refute files", w)
		at(s5, "Answering a finding by an edit needs a new round", w)
		at(s5, "A Design changed after a round needs a new round too", w)
		at(s5, "a round that says `changes` is followed by another round", w)
		at(s5, "the user decides another round past the cap", w)
		at(
			s5,
			"An approving final round's findings answered by a refute keep it final; answered by an edit, they need the next round.",
			w
		)
		at(s5, "`one more design round past design-review-NNN`", w)
		at(s5, "`review-exhausted`", w)
		at(s5, "**The loop ends**", w)
		at(skill("z-design"), "A `guess mode` line is not asked about: z-work carries it, and the person's `./zn approve` confirms it.", "z-design")
		absent(s5, "There is no second reviewer round.", w)
		absent(s5, "One clean reviewer, one round", w)
		absent(s5, "restarts the count", w)
		absent(s5, "Do not start another reviewer", w)
		-- c0119's structure stays: the scope rule inside step 3, the scope check in step 5 before design: ready
		local three, four = at(s5, "\n3. ", w), at(s5, "\n4. ", w)
		local rule = at(s5, "**Never answer a finding by cutting scope.**", w)
		t.expect(rule > three and rule < four).toBe(true)
		local five = at(s5, "\n5. ", w)
		local check = at(s5, "Then **check the scope**", w)
		t.expect(check > five and check < at(s5, "set `design: ready`", w)).toBe(true)
	end)

	it("zz-review: rounds, the fix delta, the last review's Contract line", function()
		local s = skill("zz-review")
		local w = "zz-review"
		at(s, "`Dropped from <file>: F<n>`", w)
		at(s, "`(repeat of <file> F<n>)`", w)
		at(s, "A repeat the author refutes again goes to the human", w)
		at(s, "**Fix delta**", w)
		at(s, "`rounds.filing`", w)
		at(s, "`Contract: <hash>`", w)
		at(s, "an unmarked item keeps one round", w)
		absent(s, "This is the only round", w)
		absent(s, "There is no second reviewer round.", w)
		absent(s, "A second review of the same kind is refused, before any reviewer starts", w)
	end)

	it("zz-execute: the code loop of up to 9 rounds per layer", function()
		local p4 = section(skill("zz-execute"), "Phase 4")
		local w = "zz-execute Phase 4"
		at(p4, "up to 9 rounds per layer", w)
		at(p4, "a new clean reviewer each round", w)
		at(p4, "fix delta", w)
		at(p4, "`review-exhausted`", w)
		absent(p4, "There is no second reviewer.", w)
		local p5 = section(skill("zz-execute"), "Phase 5")
		at(p5, "the contract the ticket's last review judged", "zz-execute Phase 5")
	end)

	it("z-work: the idea action and assume, and the pinned guess-mode sentences kept", function()
		local s = skill("z-work")
		local w = "z-work"
		at(s, "an `idea` (run the idea stage of a new ticket)", w)
		local g = section(s, "Guess mode")
		at(g, "`./zn guess <issue-id> --step design|raft|build`", w)
		at(g, "never guess an idea's open line", w)
		at(g, "Nothing unapproved lands", w)
		at(g, "`./zn assume <issue-id> --step idea|design|raft|build`", w)
		at(g, "`./zn assumptions <R-id>`", w)
		local z = skill("z-ticket")
		at(z, "`rounds.CAP.idea`", "z-ticket")
		local readme = read("z-nile/README.md")
		at(readme, "Reviews are back and forth, except for the last one", "README")
		at(readme, "up to 9 rounds", "README")
		at(readme, "| back-and-forth reviews, idea to merge ready | f0417 |", "README")
	end)

	it("zz-rules: assume, assumptions, refuse, and the approve row's parts", function()
		local s = skill("zz-rules")
		local w = "zz-rules"
		at(s, "| assume | `./zn assume <issue-id> --step idea|design|raft|build --what <text> --because <text> --unproven <text>` |", w)
		at(s, "| assumptions | `./zn assumptions <issue-id|R-id> [--check]` |", w)
		at(s, "| refuse | `./zn refuse <issue-id> --to idea|design|build --why <text>` |", w)
		at(s, "<ID>/assumptions.md", w)
		at(s, "the idea's files (for an issue with `rounds: on`) and `assumptions.md`", w)
		at(s, "`rounds: on`", w)
	end)
end)
