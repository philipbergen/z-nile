--!strict
-- The idea stage (`./zn idea`). Pure: texts in, the ticket body, the review file and the
-- design-start decision out. `main.luau` starts the models and writes the files.
--
-- Contract for the Python port:
--
--   ./zn idea <id> [--text <rough>]
--     Rewrites ticket <id>'s Problem, Solution and Non-goals as checkable outcomes,
--     writes <issue-dir>/idea-review-001.md, and leaves whatever is still disputed
--     under ## Open to the human. The author is the `idea` role; the one challenge
--     is the `idea-challenge` role; then the author revises once. `./zn capture <id>`
--     stays the read-only view of the captured document. `./zn new` only allocates
--     the shell (`idea: unchallenged`). There is no second way to write the idea.
--
--   idea-review-001.md
--     # Idea review 001
--     ## Findings
--     - F1: <what is still wrong, or "none">
--     ## Verdict
--     approve | open
--
--   A ticket with no `idea:` frontmatter key was captured before this stage: design
--   may start. `idea: unchallenged` (what `./zn new` writes) refuses until this
--   command has written the review and set `idea: challenged`, and every bullet
--   under ## Open to the human is `Ruled (user, YYYY-MM-DD):`.
local openlist = require("./openlist")
local serde = require("@lune/serde")

local idea = {}

export type Draft = {
	problem: { string },
	solution: { string },
	nonGoals: { string },
	open: { string },
}

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
	local openItems = bullets(sectionBody(body, "Open"))
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
		open = openItems,
	}, nil
end

function idea.parseReview(text: string): ({ string }, string?)
	local body = text
	if string.sub(body, 1, 1) ~= "\n" then
		body = "\n" .. body
	end
	local findings = bullets(sectionBody(body, "Findings"))
	local verdictBody = sectionBody(body, "Verdict")
	local verdict = if verdictBody then string.lower(trim(string.match(verdictBody, "[^\n]+") or "")) else nil
	if verdict == "" then
		verdict = nil
	end
	return findings, verdict
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

local function replaceSection(md: string, heading: string, body: string): string
	local needle = `## {heading}\n`
	local at = string.find(md, needle, 1, true)
	if not at then
		local suffix = if string.sub(md, -1) == "\n" then "" else "\n"
		return `{md}{suffix}\n## {heading}\n{body}`
	end
	local restAt = at + #needle
	local rest = string.sub(md, restAt)
	local nextAt = string.find(rest, "\n## ", 1, true)
	local tail = if nextAt then string.sub(rest, nextAt) else ""
	return string.sub(md, 1, restAt - 1) .. body .. tail
end

-- Puts the draft into the ticket. Open items become `- F<n>:` under ## Open to the human.
function idea.apply(doc: string, draft: Draft): string
	local out = replaceSection(doc, "Problem", bulletLines(draft.problem))
	out = replaceSection(out, "Solution", bulletLines(draft.solution))
	out = replaceSection(out, "Non-goals", bulletLines(draft.nonGoals))
	if #draft.open > 0 then
		local lines = {}
		for i, item in draft.open do
			table.insert(lines, `- F{i}: {item}`)
		end
		out = replaceSection(out, "Open to the human", table.concat(lines, "\n") .. "\n")
	end
	return out
end

function idea.reviewText(findings: { string }, verdict: string): string
	local lines = { "# Idea review 001", "", "## Findings", "" }
	if #findings == 0 then
		table.insert(lines, "none")
	else
		for i, item in findings do
			table.insert(lines, `- F{i}: {item}`)
		end
	end
	table.insert(lines, "")
	table.insert(lines, "## Verdict")
	table.insert(lines, "")
	table.insert(lines, verdict)
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

function idea.authorPrompt(rough: string, findings: { string }?): string
	local extra = ""
	if findings and #findings > 0 then
		extra = "\n\nThe challenge still disputes:\n"
		for _, item in findings do
			extra ..= `- {item}\n`
		end
		extra ..= "\nRevise the outcomes. Put anything you will not change under ## Open, one sentence each. Leave ## Open as none when nothing is disputed.\n"
	end
	return [[Write the idea as checkable outcomes. Each bullet is one sentence a test or a reader could later find true or false. No design, no file names, no tasks.
Reply in exactly this shape:

## Problem
- <what is wrong or missing, as one sentence.>

## Solution
- <the smallest change that would make that sentence false, as one sentence.>

## Non-goals
- <what this idea will not do, as one sentence.>

## Open
- none

Rough idea:
]] .. rough .. extra
end

function idea.challengePrompt(doc: string): string
	return [[Challenge this idea once. Is each Problem and Solution sentence something a reader could find true or false? Is the solution the smallest that solves the problem? Are non-goals real fences? Reply in exactly this shape:

## Findings
- F1: <one disputed point, or the single word none>

## Verdict
approve

Use verdict approve when nothing is disputed. Use revise when a finding remains. Do not rewrite the idea.

]] .. doc
end

-- nil when design may start. A missing `idea:` key is a ticket captured before this stage.
function idea.designRefusal(doc: string, review: string?, id: string): string?
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
	local pending = openlist.pending(doc)
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
