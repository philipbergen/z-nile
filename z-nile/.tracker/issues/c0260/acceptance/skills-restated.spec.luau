--!strict
-- c0260 AC8: the places that restate the flow agree: z-design, zz-review, zz-rules and the README. Shape rules over their
-- text (the exact wording is not pinned: a place can be reworded and stay green; a place that stops saying it fails).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function skill(name: string): string
	return fs.readFile(`{ROOT}/z-nile/skills/{name}/SKILL.md`)
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0260 the places that restate the flow agree", function(it)
	it(
		"AC8: z-design confirms an unattended capture first, as the one small exception, and changes nothing else",
		function()
			local d = skill("z-design")
			t.expect(has(d, "**Confirm an unattended capture first**")).toBe(true)
			t.expect(has(d, "Unconfirmed (unattended")).toBe(true)
			t.expect(has(d, '--confirm "<their words>"')).toBe(true)
			t.expect(has(d, "Nothing else in z-design changes")).toBe(true)
			t.expect(has(d, "questions.md")).toBe(true)
			t.expect(has(d, "you never type the line")).toBe(true)
			t.expect(has(d, "the user runs in a terminal")).toBe(true)
			t.expect(has(d, "a ruling is the next `### Qn`")).toBe(true)
		end
	)

	it("AC7: zz-review's idea challenge checks the idea against the user's words: dropped, added, bent", function()
		local r = skill("zz-review")
		local at = string.find(r, "## Idea challenge", 1, true) :: number
		local part = string.sub(r, at, string.find(r, "## Output file", 1, true) :: number)
		for _, word in
			{
				"**dropped**",
				"**added**",
				"**bent**",
				"## Ask (verbatim)",
				"## Interview",
				"only the questions in `## Interview`",
			}
		do
			t.expect(has(part, word)).toBe(true)
		end
	end)

	it("AC8: zz-rules lists the idea files in the item layout, the idea flags, and what land carries", function()
		local r = skill("zz-rules")
		t.expect(has(r, "<ID>/idea-review-NNN.md, idea-refute-NNN.md")).toBe(true)
		local row = string.match(r, "\n| idea | ([^\n]*)") or ""
		for _, flag in { "--record", "--confirm", "--unattended", "ZN_DISPATCH=1" } do
			t.expect(has(row, flag)).toBe(true)
		end
		local land = string.match(r, "A capture lands with `./zn land` instead[^\n]*") or ""
		t.expect(has(land, "idea-review-NNN.md")).toBe(true)
		t.expect(has(land, "never changed")).toBe(true)
		local direct = string.match(r, "%*%*The direct%-push exception%.%*%*[^\n]*") or ""
		t.expect(has(direct, "idea-review-NNN.md")).toBe(true)
	end)

	it(
		"AC8: the README's Skills row and flow step 1 describe the record, the challenge and the confirmation",
		function()
			local r = fs.readFile(`{ROOT}/z-nile/README.md`)
			local row = string.match(r, "\n| `z%-ticket` | 1 | ([^\n]*)") or ""
			t.expect(has(row, "verbatim ask")).toBe(true)
			t.expect(has(row, "challenge it against them")).toBe(true)
			t.expect(has(row, "confirmation")).toBe(true)
			local step = string.match(r, "\n1%. %*%*z%-ticket%*%*([^\n]*)") or ""
			t.expect(has(step, "verbatim ask")).toBe(true)
			t.expect(has(step, "Unconfirmed (unattended)")).toBe(true)
		end
	)

	it("AC8: z-design says who challenges an agent-filed ticket, and that it then needs no confirmation", function()
		local d = skill("z-design")
		t.expect(has(d, "still `idea: unchallenged` is challenged first")).toBe(true)
		t.expect(has(d, "`./zn idea <id>` and `./zn land` it")).toBe(true)
		t.expect(has(d, "needs no confirmation and is designed at once")).toBe(true)
		t.expect(has(d, "or filed by an agent, is designed at once")).toBe(false) -- only once its idea is challenged
	end)

	it("AC7: zz-review, zz-rules and the port contract describe the loop and its cap, not one challenge", function()
		local review = skill("zz-review")
		t.expect(has(review, "A short pass, repeated up to three times, before any design")).toBe(true)
		t.expect(has(review, "One short pass")).toBe(false)
		t.expect(has(review, "never followed by a revision")).toBe(true)
		t.expect(has(review, "`- F2: ask: <the question for the user>`")).toBe(true)
		t.expect(has(review, "A `revise` verdict needs at least one finding")).toBe(true)
		local rules = skill("zz-rules")
		local row = string.match(rules, "\n| idea | ([^\n]*)") or ""
		t.expect(has(row, "until it approves with no findings or has challenged three times")).toBe(true)
		t.expect(has(row, "the third challenge is not followed by a revision")).toBe(true)
		t.expect(has(row, "challenges once")).toBe(false)
		t.expect(has(row, "An approval with no findings stops there")).toBe(false)
		local contract = fs.readFile(`{ROOT}/z-nile/engine/idea.luau`)
		t.expect(has(contract, "challenges, the author\n--     revises and answers, and it challenges again"))
			.toBe(true)
		t.expect(has(contract, "The `idea-challenge` role challenges once")).toBe(false)
	end)
end)
