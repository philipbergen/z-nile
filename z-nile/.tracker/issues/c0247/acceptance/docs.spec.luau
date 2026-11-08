--!strict
-- c0247 AC1 to AC5: z-ticket's "Confirm intent first" paragraph, its place before the numbered steps, and the
-- README's two lines that restate the flow. Each pinned line appears verbatim. Read from the checkout's top.
-- (That the numbered steps keep their numbers is a claim about this change, so it is check.sh's AC6, against the
-- merge base: design review 001 F6. Both files lie under z-nile/ outside tests/, which c0165's selector answers with
-- z-nile's full run, so the spec needs no declared inputs: design review 002 F2.)
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local TICKET = "z-nile/skills/z-ticket/SKILL.md"
local README = "z-nile/README.md"

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end
local function says(rel: string, line: string)
	if string.find(read(rel), line, 1, true) == nil then
		error(`{rel} does not say: {line}`)
	end
end
local function at(rel: string, line: string): number
	local i = string.find(read(rel), line, 1, true)
	if i == nil then
		error(`{rel} does not say: {line}`)
	end
	return i :: number
end

return t.spec("c0247 z-ticket confirms intent", function(it)
	it("AC1: the paragraph restates the request and creates nothing until the user approves", function()
		says(
			TICKET,
			"**Confirm intent first.** When the ticket carries words of the user's (a request, a correction, a problem they point out), restate it before anything is created (no worktree, no `./zn new`): the title, the outcome, who is affected, the non-goals, the Solution ideas, the type (feature, defect or chore) and the project, as you would write them into the Problem, with any overlap `./zn list backlog` shows."
		)
		says(TICKET, "The user approves or corrects it, and the stub is made from the approved version.")
		says(TICKET, "A correction means you restate again.")
	end)

	it(
		"AC2: a dispatched run asks first and exclusively; elsewhere plan mode, then printing or returning, in that order",
		function()
			-- the most specific environment comes first and is exclusive (design review 003 F1); the three sentences sit
			-- in this order inside the paragraph (design review 004 F1)
			local dispatch =
				"Under `./zn dispatch` (`ZN_DISPATCH=1`), on any CLI, never use plan mode and never only print: ask it the way the dispatcher's prompt tells you to ask the user a question, and stop."
			local otherwise =
				"Otherwise, in Claude Code, when `EnterPlanMode` is offered (or listed as a deferred tool: load it with ToolSearch) and you are not already in plan mode, call it, write the restatement to the plan file, ending with the line `Next: capture with the z-ticket skill, steps 0 to 6; build nothing.`, and call `ExitPlanMode`: the user's approval is the go-ahead, and a rejection means you ask what to change and restate."
			local without =
				"Without it, or if the user declines plan mode, or if you are already in plan mode (leave its plan alone), print the restatement and stop until the user answers; a subagent returns the restatement to its lead, which confirms it with the user."
			local start = at(TICKET, "**Confirm intent first.**")
			local d, o, w = at(TICKET, dispatch), at(TICKET, otherwise), at(TICKET, without)
			local step0 = at(TICKET, "0. **Open a capture worktree first**")
			t.expect(start < d and d < o and o < w and w < step0).toBe(true)
			-- nothing sits between the three sentences
			t.expect(o).toBe(d + #dispatch + 1)
			t.expect(w).toBe(o + #otherwise + 1)
		end
	)

	it(
		"AC3: one restatement per message, no added design or scope, and only the agent's own findings are not held",
		function()
			says(
				TICKET,
				"A message with several tickets gets one restatement covering all of them, one block per ticket."
			)
			says(TICKET, "The restatement adds no design and no scope: it is the user's words, sharpened.")
			says(
				TICKET,
				"A restatement the user has already approved counts, whether they gave it in this conversation or it comes in your brief or in the reply `./zn dispatch retry` hands over."
			)
			says(
				TICKET,
				"A ticket made only from your own finding (a review finding, a failed step, a graph miss you found) has no words of the user's to check and is filed at once."
			)
			-- the first version exempted by how a ticket is filed; nothing may say that again
			local doc = read(TICKET)
			local hit = string.find(doc, "files from a skill rule", 1, true)
			t.expect(hit).toBe(nil)
		end
	)

	it("AC4: the paragraph appears once, before the first numbered step, and step 0 waits for it", function()
		local confirm = at(TICKET, "**Confirm intent first.**")
		local step0 = at(
			TICKET,
			"0. **Open a capture worktree first**, after the confirmation above and before anything is created:"
		)
		t.expect(confirm < step0).toBe(true)
		local doc = read(TICKET)
		local _, count = string.gsub(doc, "%*%*Confirm intent first%.%*%*", "")
		t.expect(count).toBe(1)
	end)

	it("AC5: the README's table and flow name the confirmation", function()
		says(
			README,
			"after the user confirms a restatement of the request, captures a feature, defect or chore as a backlog issue, in a `capture-<slug>` worktree, landed with `./zn land`"
		)
		says(
			README,
			"1. **z-ticket**: the user confirms a restatement of the request first (plan mode in Claude Code); then, in `capture-<slug>`, the issue lands on `main` with `design: draft` and status `new`. No PR."
		)
	end)
end)
