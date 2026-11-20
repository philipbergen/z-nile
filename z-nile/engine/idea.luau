--!strict
-- The idea stage (`./zn idea`). Pure: texts in, the ticket body, the review file and the
-- design-start decision out. `main.luau` starts the models and writes the files.
--
-- Contract for the Python port:
--
--   ./zn idea <id> [--text <rough>]
--     Rewrites ticket <id>'s Problem, Solution and Non-goals as checkable outcomes.
--     The author is the `idea` role. The `idea-challenge` role challenges, the author
--     revises and answers, and it challenges again, until it approves with no
--     findings or has challenged MAX_ROUNDS (5) times; the last challenge is never
--     followed by a revision. Each challenge is idea-review-NNN.md, as the
--     challenger wrote it, under a `Round:` line naming the state of the idea it
--     judged; its findings are answered by id in idea-refute-NNN.md (`revised`, or
--     `disputed: <reason>`). The numbers continue from the highest in the folder.
--     Every pass is written when it completes. What the last challenge found, and
--     every finding raised for the user (`ask:`), goes under ## Open to the human.
--     `./zn capture <id>` stays the read-only view. `./zn new` only allocates the
--     shell (`idea: unchallenged`). There is no second way to write the idea.
--
--   idea-review-NNN.md
--     # Idea review NNN
--     Round: ask <m>, interview <q>, idea <hash>
--     ## Findings
--     - F1: <the challenger's words, or "none">
--     - F2: ask: <a question only the user can answer>
--     ## Verdict
--     approve | revise
--
--   idea-refute-NNN.md
--     # Idea refute NNN
--     - F1: revised
--     - F2: disputed: <why>
--
--   A ticket with no `idea:` frontmatter key was captured before this stage: design
--   may start. `idea: unchallenged` (what `./zn new` writes) refuses until this
--   command has written the review and set `idea: challenged`, and every bullet
--   under ## Open to the human is `Ruled (user, YYYY-MM-DD):`.
local capturecheck = require("./capturecheck")
local openlist = require("./openlist")
local serde = require("@lune/serde")

local idea = {}

-- The most challenges one `./zn idea` loop makes before the user sees the idea (c0260, F15; the owner's cap of five,
-- 2026-11-18, ruled for c0260 on 2026-11-19): a challenge, a revision, and another challenge, until the challenger
-- approves. Each is an Opus call capped by the role, so a loop costs at most five challenges and five author calls (the
-- draft and four revisions). What the last challenge still disputes goes under `## Open to the human`. The one place
-- the number is written: the loop, its output and the specs read it from here.
idea.MAX_ROUNDS = 5

-- Where a `./zn idea` run's loop starts and how many challenges it may still make: the run's first review number and
-- its challenges left. Every run is a loop of its own (a change of the user's starts one, and so does a rerun after a
-- failure): it numbers on from the highest review in the folder and may challenge MAX_ROUNDS times. The one function
-- the loop asks, so a later rule (a loop that continues across runs) replaces it alone.
export type LoopStart = { first: number, left: number }
function idea.loopStart(_doc: string, names: { string }): LoopStart
	return { first = idea.latestRound(names) + 1, left = idea.MAX_ROUNDS }
end

export type Draft = {
	problem: { string },
	solution: { string },
	nonGoals: { string },
}

export type Finding = { id: string, text: string, ask: boolean }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function sentence(line: string): string?
	local text = trim(line)
	text = (string.gsub(text, "^[-*]%s+", ""))
	text = trim(text)
	if text == "" or text == "none" or text == "None" then
		return nil
	end
	local last = string.sub(text, -1)
	if last ~= "." and last ~= "!" and last ~= "?" then
		return nil
	end
	if not string.find(text, " ", 1, true) then
		return nil
	end
	return text
end

local function sectionBody(md: string, heading: string): string?
	local found = string.find(md, `\n## {heading}\n`, 1, true)
	local startAt = 1
	if string.sub(md, 1, #heading + 4) == `## {heading}\n` then
		found = 1
		startAt = #heading + 4
	elseif found then
		startAt = found + #heading + 4
	else
		return nil
	end
	local rest = string.sub(md, startAt)
	local nextAt = string.find(rest, "\n## ", 1, true)
	local body = if nextAt then string.sub(rest, 1, nextAt - 1) else rest
	return body
end

local function bullets(body: string?): ({ string }, { string })
	local items, bad = {}, {}
	if body == nil then
		return items, bad
	end
	for line in string.gmatch(body .. "\n", "(.-)\n") do
		local raw = trim(line)
		if raw ~= "" and raw ~= "none" and raw ~= "None" then
			local ok = sentence(raw)
			if ok then
				table.insert(items, ok)
			else
				table.insert(bad, raw)
			end
		end
	end
	return items, bad
end

-- The model's draft. Each Problem and Solution line is one sentence a later claim can check.
function idea.parseDraft(text: string): (Draft?, string?)
	local body = text
	local fenced = string.match(text, "```[^\n]*\n(.-)\n```")
	if fenced then
		body = fenced
	end
	if string.sub(body, 1, 1) ~= "\n" then
		body = "\n" .. body
	end
	local problem, badP = bullets(sectionBody(body, "Problem"))
	local solution, badS = bullets(sectionBody(body, "Solution"))
	local nonGoals, badN = bullets(sectionBody(body, "Non-goals"))
	if #problem == 0 then
		return nil, "the draft has no checkable ## Problem sentence"
	end
	if #solution == 0 then
		return nil, "the draft has no checkable ## Solution sentence"
	end
	if #badP + #badS + #badN > 0 then
		return nil, `a line is not one checkable sentence: {badP[1] or badS[1] or badN[1]}`
	end
	return {
		problem = problem,
		solution = solution,
		nonGoals = nonGoals,
	}, nil
end

function idea.parseReview(text: string): ({ Finding }, string?)
	local body = text
	if string.sub(body, 1, 1) ~= "\n" then
		body = "\n" .. body
	end
	local found: { Finding } = {}
	local raw = sectionBody(body, "Findings")
	if raw then
		for line in string.gmatch(raw .. "\n", "(.-)\n") do
			local item = trim((string.gsub(trim(line), "^[-*]%s+", "")))
			if item ~= "" and item ~= "none" and item ~= "None" then
				local id, rest = string.match(item, "^(F%d+):%s*(.+)$")
				if id == nil or rest == nil or trim(rest) == "" then
					return {}, nil
				end
				local question = string.match(trim(rest), "^ask:%s*(.+)$")
				table.insert(
					found,
					{ id = id, text = if question then trim(question) else trim(rest), ask = question ~= nil }
				)
			end
		end
	end
	local verdictBody = sectionBody(body, "Verdict")
	local verdict = if verdictBody then string.lower(trim(string.match(verdictBody, "[^\n]+") or "")) else nil
	if verdict ~= "approve" and verdict ~= "revise" then
		verdict = nil
	end
	return found, verdict
end

-- id -> the words after `F1: ` (`revised`, or `disputed: ...`).
function idea.parseAnswers(text: string): { [string]: string }
	local body = text
	if string.sub(body, 1, 1) ~= "\n" then
		body = "\n" .. body
	end
	local out: { [string]: string } = {}
	local raw = sectionBody(body, "Answers")
	if not raw then
		return out
	end
	for line in string.gmatch(raw .. "\n", "(.-)\n") do
		local item = trim((string.gsub(trim(line), "^[-*]%s+", "")))
		local id, rest = string.match(item, "^(F%d+):%s*(.+)$")
		if id ~= nil and rest ~= nil and trim(rest) ~= "" then
			out[id] = trim(rest)
		end
	end
	return out
end

-- A finding answered `revised` is closed. One disputed, or not answered, is open.
function idea.openLines(findings: { Finding }, answers: { [string]: string }): { string }
	local lines: { string } = {}
	for _, f in findings do
		local ans = answers[f.id]
		if ans == nil then
			table.insert(lines, `- {f.id}: {f.text}`)
		elseif string.match(ans, "^revised$") == nil then
			table.insert(lines, `- {f.id}: {f.text} Answer: {ans}`)
		end
	end
	return lines
end

-- The findings a challenge raised for the user (`- F2: ask: <question>`) and the others.
function idea.splitFindings(findings: { Finding }): ({ Finding }, { Finding })
	local asks, rest = {}, {}
	for _, f in findings do
		table.insert(if f.ask then asks else rest, f)
	end
	return asks, rest
end

-- What stays under `## Open to the human` when the loop ends, numbered F1 on: each item is a finding still disputed,
-- unanswered, or raised for the user, with the author's answer when there is one.
function idea.openBullets(items: { { text: string, answer: string? } }): { string }
	local lines: { string } = {}
	for i, item in items do
		table.insert(lines, `- F{i}: {item.text}{if item.answer then ` Answer: {item.answer}` else ""}`)
	end
	return lines
end

local function bulletLines(items: { string }): string
	if #items == 0 then
		return "none\n"
	end
	local lines = {}
	for _, item in items do
		table.insert(lines, `- {item}`)
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Puts the draft into the ticket. `openLines` are the challenger's findings still open, already `- F1: ...`.
function idea.apply(doc: string, draft: Draft, openLines: { string }): string
	local out = capturecheck.replace(doc, "Problem", bulletLines(draft.problem))
	out = capturecheck.replace(out, "Solution", bulletLines(draft.solution))
	out = capturecheck.replace(out, "Non-goals", bulletLines(draft.nonGoals))
	local openBody = if #openLines == 0 then "none\n" else table.concat(openLines, "\n") .. "\n"
	return capturecheck.replace(out, "Open to the human", openBody)
end

-- The file names of round `n` (001, 002 …): a user's change after the idea was shown runs `./zn idea` again.
function idea.reviewName(n: number): string
	return string.format("idea-review-%03d.md", n)
end

function idea.refuteName(n: number): string
	return string.format("idea-refute-%03d.md", n)
end

-- The highest round among file names (0 when there is none).
function idea.latestRound(names: { string }): number
	local last = 0
	for _, name in names do
		local n = string.match(name, "^idea%-review%-(%d%d%d)%.md$")
		if n then
			last = math.max(last, tonumber(n) :: number)
		end
	end
	return last
end

function idea.reviewText(findings: { Finding }, verdict: string, round: number?, state: string?): string
	local lines = { string.format("# Idea review %03d", round or 1), "" }
	if state then
		table.insert(lines, `Round: {state}`)
		table.insert(lines, "")
	end
	table.insert(lines, "## Findings")
	table.insert(lines, "")
	if #findings == 0 then
		table.insert(lines, "none")
	else
		for _, item in findings do
			table.insert(lines, `- {item.id}: {item.text}`)
		end
	end
	table.insert(lines, "")
	table.insert(lines, "## Verdict")
	table.insert(lines, "")
	table.insert(lines, verdict)
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

function idea.refuteText(findings: { Finding }, answers: { [string]: string }, round: number?): string
	local lines = { string.format("# Idea refute %03d", round or 1), "" }
	for _, f in findings do
		local ans = answers[f.id]
		if ans then
			table.insert(lines, `- {f.id}: {ans}`)
		end
	end
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

-- The user's words kept on the ticket (c0260): `## Ask (verbatim)` and `## Interview`, as written, or nil.
function idea.recordText(doc: string): string?
	local parts: { string } = {}
	for _, heading in { "Ask (verbatim)", "Interview" } do
		local body = capturecheck.section(doc, heading)
		if body and trim(body) ~= "" then
			table.insert(parts, `## {heading}\n{trim(body)}`)
		end
	end
	return if #parts == 0 then nil else table.concat(parts, "\n\n")
end

local function withRecord(prompt: string, record: string?): string
	if record == nil then
		return prompt
	end
	return prompt
		.. "\n\nWhat the user said, kept on the ticket word for word. Write only what this says; the idea adds nothing the user did not say or answer:\n"
		.. record
end

function idea.authorPrompt(rough: string, record: string?): string
	return withRecord(
		[[Write the idea as checkable outcomes. Each bullet is one sentence a test or a reader could later find true or false. No design, no file names, no tasks.
Reply in exactly this shape:

## Problem
- <what is wrong or missing, as one sentence.>

## Solution
- <the smallest change that would make that sentence false, as one sentence.>

## Non-goals
- <what this idea will not do, as one sentence.>

Rough idea:
]] .. rough,
		record
	)
end

function idea.answerPrompt(rough: string, findings: { Finding }, record: string?, current: string?): string
	local list = ""
	for _, f in findings do
		list ..= `- {f.id}: {f.text}\n`
	end
	return withRecord(
		[[Revise the idea and answer each finding by id. Reply in exactly this shape:

## Problem
- <one checkable sentence.>

## Solution
- <one checkable sentence.>

## Non-goals
- <one checkable sentence.>

## Answers
- F1: revised
- F2: disputed: <why the finding is wrong, one sentence.>

A line "revised" means the outcomes now meet that finding. A line "disputed:" means they do not. A finding with no line stays open for the human.

Findings:
]]
			.. list
			.. (if current then "\nCurrent idea (revise this one):\n" .. current .. "\n" else "")
			.. "\nRough idea:\n"
			.. rough,
		record
	)
end

function idea.challengePrompt(doc: string, record: string?, unattended: boolean?, prior: string?): string
	local against = ""
	if record then
		against = '\n\nThe user\'s own words follow the idea. Check the idea against them: is anything the user asked for or answered dropped, is anything in the idea one the user never said or answered (added), is a meaning bent by a word ("can" made "must", "some" made "all")? Quote the user\'s words in each such finding. Also: a question that should have been asked of the user and was not (a gap, a conflict, an edge case, an unstated assumption) is a finding.'
			.. (if unattended
				then " The user answered only the questions in ## Interview, and nobody can be asked now."
				else "")
			.. "\n\n"
			.. record
	end
	local again = ""
	if prior then
		again = "\n\nThis idea was challenged before and revised. The previous round's findings and the author's answers follow: judge whether each answer holds in the idea above, and raise a finding for any point that still fails, including one an earlier round missed; an earlier finding whose answer holds is not raised again. Approve when nothing remains.\n"
			.. prior
	end
	return [[Challenge this idea once. Is each Problem and Solution sentence something a reader could find true or false? Is the solution the smallest that solves the problem? Are non-goals real fences? Reply in exactly this shape:

## Findings
- F1: <one disputed point, or the single word none>

## Verdict
approve

Use verdict approve when nothing is disputed. Use revise when a finding remains. Do not rewrite the idea. A finding that only the user can settle (a question to ask them) is written `- F2: ask: <the question for the user>`: the author is never asked to answer it, and it stays open for the user.

]] .. doc .. again .. against
end

-- The idea as the prompts show it, from a draft.
function idea.draftText(draft: Draft): string
	return "## Problem\n"
		.. bulletLines(draft.problem)
		.. "\n## Solution\n"
		.. bulletLines(draft.solution)
		.. "\n## Non-goals\n"
		.. bulletLines(draft.nonGoals)
end

-- A round's findings with the author's answers, for the next challenge.
function idea.priorText(findings: { Finding }, answers: { [string]: string }): string
	local lines: { string } = {}
	for _, f in findings do
		table.insert(lines, `- {f.id}: {f.text} => {answers[f.id] or "no answer"}`)
	end
	return table.concat(lines, "\n")
end

-- nil when design may start. A missing `idea:` key is a ticket captured before this stage.
function idea.designRefusal(doc: string, review: string?, id: string, skipOpen: boolean?): string?
	local key = string.match(doc, "\nidea:%s*([%w%-]+)")
	if key == nil and string.sub(doc, 1, 5) == "idea:" then
		key = string.match(doc, "^idea:%s*([%w%-]+)")
	end
	if key == nil then
		return nil
	end
	if key ~= "challenged" or review == nil or trim(review) == "" then
		return `no idea-review-001.md (the idea was not challenged): ./zn idea {id}`
	end
	local pending = if skipOpen then {} else openlist.pending(doc)
	if #pending > 0 then
		return `open to the human ({table.concat(pending, ", ")}): record each under ## Open to the human with Ruled (user, YYYY-MM-DD):`
	end
	return nil
end

function idea.frontKey(doc: string): string?
	return string.match(doc, "\nidea:%s*([%w%-]+)")
end

-- The model's words out of a CLI stream: plain lines, a claude `result` string, and assistant text blocks.
-- Usage lines stay out. This is what `parseDraft` and `parseReview` read.
function idea.prose(stdout: string): string
	local parts: { string } = {}
	local function keep(text: string)
		local line = trim(text)
		if line ~= "" then
			table.insert(parts, text)
		end
	end
	for line in string.gmatch(stdout .. "\n", "(.-)\n") do
		if string.sub(line, 1, 1) ~= "{" then
			keep(line)
		else
			local ok, value = pcall(function()
				return serde.decode("json", line)
			end)
			if ok and type(value) == "table" then
				local j = value :: any
				if j.type == "result" and type(j.result) == "string" and j.is_error ~= true then
					keep(j.result)
				elseif j.type == "assistant" and type(j.message) == "table" then
					local content = j.message.content
					if type(content) == "string" then
						keep(content)
					elseif type(content) == "table" then
						for _, block in content do
							if
								type(block) == "table"
								and block.type == "text"
								and type(block.text) == "string"
							then
								keep(block.text)
							end
						end
					end
				end
			end
		end
	end
	return table.concat(parts, "\n")
end

return idea
