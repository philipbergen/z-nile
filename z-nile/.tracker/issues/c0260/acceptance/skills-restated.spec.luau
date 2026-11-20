--!strict
-- c0260 AC8: the places that restate the flow agree: z-design, zz-review, zz-rules and the README. Shape rules over their
-- text (the exact wording is not pinned: a place can be reworded and stay green; a place that stops saying it fails).
local fs = require("@lune/fs")
local ideaMod = require("@znile/engine/idea")
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
			t.expect(has(d, "you never type the line")).toBe(true)
			t.expect(has(d, "a ruling is the next `### Qn`")).toBe(true)
		end
	)

	it(
		"AC8: a dispatched z-design confirms through c0250's block: the note, the block, the user's rulings and confirmation in the prep worktree, the resolve, then the retry",
		function()
			-- the flow is pinned in its order, inside the one bullet, not by a word anywhere in the file (R0093 F5)
			local d = skill("z-design")
			local from = string.find(d, "**Confirm an unattended capture first**", 1, true) :: number
			local bullet = string.sub(d, from, (string.find(d, "\n", from, true) :: number) - 1)
			local steps = {
				"Under `./zn dispatch` (`ZN_DISPATCH=1`) you cannot confirm, and you never type the line: block the ticket for the user.",
				"Write `escalation.md` in the issue's folder",
				"`- retry: confirm the idea, and z-design then designs it (recommended)`",
				"`- abort: ",
				"Run `./zn block <id> needs-decision` and stop, leaving the prep worktree as it is.",
				"in a terminal in this prep worktree (the dispatcher reuses `prep-<slug>` and reads the open list from it)",
				"the new round when they recorded words",
				'`./zn idea <id> --confirm "<your words>"`',
				'a commit of the document on the prep branch (`git commit -am "tracker: <id> confirmed"`)',
				"then `./zn resolve <id> retry`",
				"then `./zn dispatch retry <id>`",
				"the prep pull request carries the `Confirmed` line",
				"while the last line is still `Unconfirmed`, it blocks again",
				"`./zn work next` does not offer an `Unconfirmed` ticket as a `draft`",
			}
			local at = 0
			for _, step in steps do
				local i = string.find(bullet, step, at + 1, true)
				if i == nil then
					error(`the z-design bullet does not say, after the step before: {step}`, 0)
				end
				at = i :: number
			end
			-- a ruling recorded as words is a change of the record: the next round runs before the confirmation, which binds to it
			t.expect(has(bullet, "a recorded word changes the record, so run `./zn idea <id>` again"))
				.toBe(true)
			t.expect(has(bullet, "when the outcomes changed")).toBe(false)
			local ticket = skill("z-ticket")
			t.expect(has(ticket, "A recorded ruling changes the record, so run `./zn idea <id>` again"))
				.toBe(true)
			-- a dispatched capture removes its worktree, so the dispatcher's open-list read does not stop the chain on the
			-- points the user rules at z-design
			t.expect(has(ticket, "remove the capture worktree with the command land prints")).toBe(true)
			-- a dispatched z-design never stops on an item's questions.md (c0250 sets it aside), and never answers it itself
			t.expect(has(bullet, "questions.md")).toBe(false)
			t.expect(has(bullet, "./zn resolve <id> retry --said")).toBe(false)
			-- in guess mode the confirmation is not a guess
			t.expect(
				has(
					bullet,
					"In guess mode (z-work, outside the dispatcher) the confirmation is never a guess"
				)
			)
				.toBe(true)
		end
	)

	it(
		"AC7: zz-review's idea challenge checks the idea against the user's words: dropped, added, bent",
		function()
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
		end
	)

	it(
		"AC8: zz-rules lists the idea files in the item layout, the idea flags, and what land carries",
		function()
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
		end
	)

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
			-- the Intent section describes the loop, not one challenge (design-review-012 F9)
			t.expect(has(r, "challenges it once")).toBe(false)
			t.expect(has(r, `up to {ideaMod.MAX_ROUNDS} times (\`idea.MAX_ROUNDS\`)`)).toBe(true)
		end
	)

	it(
		"AC8: z-design says who challenges an agent-filed ticket, and that it then needs no confirmation",
		function()
			local d = skill("z-design")
			t.expect(has(d, "still `idea: unchallenged` is challenged first")).toBe(true)
			t.expect(has(d, "`./zn idea <id>` and `./zn land` it")).toBe(true)
			t.expect(has(d, "needs no confirmation and is designed at once")).toBe(true)
			t.expect(has(d, "or filed by an agent, is designed at once")).toBe(false) -- only once its idea is challenged
		end
	)

	it(
		"AC7: zz-review, zz-rules and the port contract describe the loop and its cap, not one challenge",
		function()
			local review = skill("zz-review")
			local cap = ideaMod.MAX_ROUNDS
			t.expect(
				has(
					review,
					`A short pass, repeated up to {cap} times (\`idea.MAX_ROUNDS\`), before any design`
				)
			)
				.toBe(true)
			t.expect(has(review, `its last challenge, the {cap}th (\`idea.MAX_ROUNDS\`)`)).toBe(true)
			t.expect(has(review, "repeated up to three times")).toBe(false)
			t.expect(has(review, "One short pass")).toBe(false)
			t.expect(has(review, "never followed by a revision")).toBe(true)
			t.expect(has(review, "`- F2: ask: <the question for the user>`")).toBe(true)
			t.expect(has(review, "A `revise` verdict needs at least one finding")).toBe(true)
			local rules = skill("zz-rules")
			local row = string.match(rules, "\n| idea | ([^\n]*)") or ""
			t.expect(
				has(
					row,
					`until it approves with no findings or has challenged {cap} times (\`idea.MAX_ROUNDS\`)`
				)
			).toBe(true)
			t.expect(has(row, "the last challenge is not followed by a revision")).toBe(true)
			t.expect(has(row, "three times")).toBe(false)
			t.expect(has(row, "challenges once")).toBe(false)
			t.expect(has(row, "An approval with no findings stops there")).toBe(false)
			local contract = fs.readFile(`{ROOT}/z-nile/engine/idea.luau`)
			t.expect(
				has(contract, "challenges, the author\n--     revises and answers, and it challenges again")
			)
				.toBe(true)
			t.expect(has(contract, "The `idea-challenge` role challenges once")).toBe(false)
		end
	)
end)
