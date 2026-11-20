--!strict
-- c0260: the shape of a capture's record, which lives in sections of the issue document (z-ticket skill, The capture
-- record): `## Ask (verbatim)`, `## Interview` and `## Confirmation`. The clean idea is the Problem, Solution and
-- Non-goals that `./zn idea` writes, and its review is `idea-review-NNN.md` beside the document (idea.luau). A ticket an
-- agent filed from its own finding has none of the three and carries `## Filed by (agent)` instead. Pure over texts:
-- audit.luau reads the document and the names of the reviews and calls `check`. It judges shape only: that the ask is
-- verbatim and that the user really confirmed is for the reviewers (the audit cannot see either).
local serde = require("@lune/serde")

local capturecheck = {}

capturecheck.REVIEW = "^idea%-review%-(%d%d%d)%.md$"

local CAPTURE = { "Ask (verbatim)", "Interview", "Confirmation" }
local AGENT = "Filed by (agent)"

-- True when the document names a capture section or the agent marker at the start of a line. A document that names
-- neither is not parsed at all (no fence of its own can fail the audit: every issue before c0260 is such a document).
local function mentions(doc: string): boolean
	for _, title in { "Ask (verbatim)", "Interview", "Confirmation", "Filed by (agent)" } do
		if string.find("\n" .. doc, "\n## " .. title .. "\n", 1, true) then
			return true
		end
	end
	return false
end

local function blank(text: string): boolean
	return string.match(text, "^%s*$") ~= nil
end

-- The fence a line opens or closes: its character and length (three or more backticks or tildes), or nil. A fenced
-- block holds the user's words as written, headings and all: nothing inside it is structure.
local function fenceOf(line: string): (string?, number)
	-- CommonMark: a backtick fence's info string holds no backtick; a tilde fence's may hold anything
	local ticks = string.match(line, "^(`+)[^`]*$")
	if ticks and #ticks >= 3 then
		return "`", #ticks
	end
	local tildes = string.match(line, "^(~+)")
	if tildes and #tildes >= 3 then
		return "~", #tildes
	end
	return nil, 0
end

-- Calls `visit(line, inFence)` for each line of `text`; returns false when a fence is never closed.
local function eachLine(text: string, visit: (string, boolean) -> ()): boolean
	local open: string? = nil
	local width = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local ch, n = fenceOf(line)
		if open == nil then
			if ch then
				open, width = ch, n
				visit(line, true)
			else
				visit(line, false)
			end
		else
			visit(line, true)
			if ch == open and n >= width and string.match(line, "^[`~]+%s*$") then
				open = nil
			end
		end
	end
	return open == nil
end

export type Section = { title: string, body: string }

-- The `## ` sections of `text` in order (fenced lines are body, never a heading). The second result is false when a
-- fence is never closed.
local function sections(text: string): ({ Section }, boolean)
	local out: { Section } = {}
	local closed = eachLine(text, function(line: string, fenced: boolean)
		local title = if fenced then nil else string.match(line, "^## (.-)%s*$")
		if title then
			table.insert(out, { title = title, body = "" })
		elseif #out > 0 then
			out[#out].body ..= line .. "\n"
		end
	end)
	return out, closed
end

local function find(secs: { Section }, title: string): Section?
	for _, sec in secs do
		if sec.title == title then
			return sec
		end
	end
	return nil
end

-- The `### ` headings of a section body, outside fences, with the lines under each.
local function blocks(body: string): ({ { head: string, text: string } }, boolean)
	local out: { { head: string, text: string } } = {}
	local closed = eachLine(body, function(line: string, fenced: boolean)
		local head = if fenced then nil else string.match(line, "^### (.-)%s*$")
		if head then
			table.insert(out, { head = head, text = "" })
		elseif #out > 0 then
			out[#out].text ..= line .. "\n"
		end
	end)
	return out, closed
end

-- The interview: `### Qn` blocks numbered from 1 without gaps, each with a Question: and an Answer: line (an
-- Options: line is welcome; an answer of several lines may sit in a fence after its key). Returns the number of
-- questions.
local function interview(body: string, out: { string }): number
	local qs, closed = blocks(body)
	if not closed then
		table.insert(out, "Interview: a fenced block is never closed")
	end
	if string.match(body, "^%s*None:") then
		table.insert(
			out,
			"Interview: `None:` is not an interview: Q1 is the restatement and the user's approval (z-ticket step 0b)"
		)
	end
	local want = 1
	for _, q in qs do
		local n = string.match(q.head, "^Q(%d+)$")
		if not n then
			table.insert(out, `Interview: "### {q.head}" is not a ### Qn heading`)
		elseif tonumber(n) ~= want then
			table.insert(out, `Interview: found Q{n} where Q{want} belongs (number from 1, no gaps)`)
		end
		want += 1
		local seen: { [string]: boolean } = {}
		local lastKey: string? = nil
		eachLine(q.text, function(line: string, fenced: boolean)
			if fenced then
				if lastKey and not seen[lastKey] then
					seen[lastKey] = true
				end
				return
			end
			local k, v = string.match(line, "^(%a+):%s*(.*)$")
			if k and (k == "Question" or k == "Options" or k == "Answer") then
				lastKey = k
				if not blank(v :: string) then
					seen[k] = true
				end
			end
		end)
		for _, key in { "Question", "Answer" } do
			if not seen[key] then
				table.insert(out, `Interview: {q.head} has no {key}: line`)
			end
		end
	end
	if #qs == 0 then
		table.insert(out, "Interview: no ### Q1 block (the restatement and the user's approval)")
	end
	return #qs
end

-- A confirmation line: kind (`Confirmed` or `Unconfirmed`), who, date, round, words.
local function confirmation(line: string): (string?, string?, string?, number?, string?)
	local kind, who, date, round, words =
		string.match(line, "^(%a+) %(([^,%)]+), (%d%d%d%d%-%d%d%-%d%d)%) after round (%d+): (.+)$")
	if kind ~= "Confirmed" and kind ~= "Unconfirmed" then
		return nil, nil, nil, nil, nil
	end
	return kind, who, date, tonumber(round), words
end

-- The doc kind: "agent" (filed from an agent's own finding), "user" (a capture record), or "none" (an issue from
-- before c0260). An issue cannot be both.
function capturecheck.kind(doc: string): string
	if not mentions(doc) then
		return "none"
	end
	local secs = sections(doc)
	local hasAgent = find(secs, AGENT) ~= nil
	local hasCapture = false
	for _, title in CAPTURE do
		if find(secs, title) then
			hasCapture = true
		end
	end
	if hasAgent then
		return "agent"
	end
	return if hasCapture then "user" else "none"
end

-- True when the last confirmation line of the record is an `Unconfirmed` one (z-design must still confirm).
function capturecheck.unconfirmed(doc: string): boolean
	if not mentions(doc) then
		return false
	end
	local secs = sections(doc)
	local sec = find(secs, "Confirmation")
	if not sec then
		return false
	end
	local last: string? = nil
	for line in string.gmatch(sec.body, "[^\n]+") do
		if not blank(line) then
			last = line
		end
	end
	return last ~= nil and string.sub(last :: string, 1, 12) == "Unconfirmed "
end

-- The problems of one document. `reviews`: the raw reviews beside it (`idea-review-NNN.md`), name -> text.
function capturecheck.check(doc: string, reviews: { [string]: string }): { string }
	local out: { string } = {}
	if not mentions(doc) then
		return out
	end
	local secs, closed = sections(doc)
	if not closed then
		table.insert(out, "the document has a fenced block that is never closed")
		return out
	end
	local agent = find(secs, AGENT)
	local present: { string } = {}
	for _, title in CAPTURE do
		if find(secs, title) then
			table.insert(present, title)
		end
	end
	if agent then
		if #present > 0 then
			table.insert(
				out,
				`a ticket filed by an agent cannot also carry a user's capture record (found: {table.concat(
					present,
					", "
				)}); the exemption is for tickets with no user ask`
			)
		end
		local source = string.match("\n" .. agent.body, "\nSource:%s*(%S[^\n]-)%s*\n")
		if not source or not capturecheck.source(source) then
			table.insert(
				out,
				"Filed by (agent) needs a `Source:` line that is a lesson (lesson:<skill>/<slug>), a review finding (review:<id>/<file> F<n>) or another finding of an agent (agent:<id>/<slug>)"
			)
		end
		local problem = find(secs, "Problem")
		if
			not (
				problem
				and string.find("\n" .. problem.body, "\n" .. capturecheck.SCOPE_LINE .. "\n", 1, true)
			)
		then
			table.insert(
				out,
				"a ticket filed by an agent carries the exact Scope decision line in its Problem (capturecheck.SCOPE_LINE)"
			)
		end
		return out
	end
	if #present == 0 then
		return out
	end
	-- the record sections come once each, in order (a record may still be growing: the audit and the claim ask for all
	-- three through `satisfies`)
	local order: { string } = {}
	for _, sec in secs do
		if table.find(CAPTURE, sec.title) then
			table.insert(order, sec.title)
		end
	end
	local want: { string } = {}
	for _, title in CAPTURE do
		if find(secs, title) then
			table.insert(want, title)
		end
	end
	if table.concat(order, "|") ~= table.concat(want, "|") then
		table.insert(
			out,
			`the capture sections must be {table.concat(CAPTURE, ", ")}, once each, in that order (found: {table.concat(
				order,
				", "
			)})`
		)
		return out
	end
	-- the record comes before the Design (z-ticket skill: after the Solution, before the Design)
	local designAt, askAt = nil, nil
	for i, sec in secs do
		if sec.title == "Design" and not designAt then
			designAt = i
		elseif sec.title == CAPTURE[1] then
			askAt = i
		end
	end
	if designAt and askAt and askAt > designAt then
		table.insert(out, "the capture record comes before ## Design")
	end
	-- a stray heading inside the record (a pasted plan's `## Goals` outside a fence) would drop the text after it
	local first, lastAt = nil, nil
	for i, sec in secs do
		if sec.title == want[1] then
			first = i
		elseif sec.title == want[#want] then
			lastAt = i
		end
	end
	if first and lastAt then
		for i = first, lastAt do
			if not table.find(CAPTURE, secs[i].title) then
				table.insert(
					out,
					`"## {secs[i].title}" sits inside the capture record: put the user's words in a fenced block`
				)
			end
		end
	end
	local ask = find(secs, CAPTURE[1])
	if ask then
		local askBlocks, askClosed = blocks(ask.body)
		if not askClosed then
			table.insert(out, "Ask (verbatim): a fenced block is never closed")
		end
		if #askBlocks == 0 then
			table.insert(out, "Ask (verbatim) needs at least one `### Message YYYY-MM-DD` block")
		end
		for _, m in askBlocks do
			if not string.match(m.head, "^Message %d%d%d%d%-%d%d%-%d%d$") then
				table.insert(
					out,
					`Ask (verbatim): "### {m.head}" must read "### Message YYYY-MM-DD" (every message is dated)`
				)
			elseif blank((string.gsub(m.text, "[`~]+[^\n]*", ""))) then
				table.insert(out, `Ask (verbatim): {m.head} is empty`)
			end
		end
	end
	local iv = find(secs, CAPTURE[2])
	if iv then
		interview(iv.body, out)
	end

	-- the reviews: numbered from 001 without gaps
	local last = 0
	local have: { [number]: boolean } = {}
	for name in reviews do
		local n = string.match(name, capturecheck.REVIEW)
		if n then
			have[tonumber(n) :: number] = true
			last = math.max(last, tonumber(n) :: number)
		end
	end
	for n = 1, last do
		if not have[n] then
			table.insert(
				out,
				`{string.format("idea-review-%03d.md", n)} is missing (rounds number from 001 without gaps)`
			)
		end
	end

	-- the confirmation: `Unconfirmed (unattended …)` first when nobody was asked, then `Confirmed (who …)` last
	local conf = find(secs, CAPTURE[3])
	if not conf then
		return out
	end
	local lines: { { kind: string, who: string, date: string, round: number, words: string } } = {}
	for line in string.gmatch(conf.body, "[^\n]+") do
		if not blank(line) then
			local kind, who, date, round, words = confirmation(line)
			if not kind then
				table.insert(
					out,
					"Confirmation lines read `Confirmed|Unconfirmed (who, YYYY-MM-DD) after round N: <words>`"
				)
				return out
			end
			table.insert(lines, {
				kind = kind,
				who = who :: string,
				date = date :: string,
				round = round :: number,
				words = words :: string,
			})
		end
	end
	if #lines == 0 or #lines > 2 then
		table.insert(
			out,
			`Confirmation holds one line, or an Unconfirmed line then a Confirmed line (found {#lines})`
		)
		return out
	end
	for i, l in lines do
		if l.kind == "Unconfirmed" then
			if i ~= 1 then
				table.insert(out, "an Unconfirmed line comes first, before the Confirmed one")
			end
			if l.who ~= "unattended" then
				table.insert(out, "Unconfirmed is only ever `(unattended, …)`")
			end
		else
			if l.who == "unattended" then
				table.insert(out, "Confirmed cannot be unattended: only the user confirms (use Unconfirmed)")
			end
			if i == 2 and lines[1].kind ~= "Unconfirmed" then
				table.insert(out, "a second line is the Confirmed one after an Unconfirmed one")
			end
		end
	end
	local final = lines[#lines]
	if last == 0 then
		table.insert(out, "Confirmation but no idea-review-001.md: the idea was never reviewed")
	elseif final.round ~= last then
		table.insert(out, `Confirmation follows round {final.round} but the last round is {last}`)
	end
	-- while the ticket is still an unclaimed capture, a Confirmed line stands for the idea and the record its round saw
	-- (z-design edits the Problem after the claim, so a claimed ticket is not bound)
	local capturing = string.match(doc, "\nstatus: (%a+)%-") == "new"
	if capturing and final.kind == "Confirmed" and last > 0 and final.round == last then
		local review = reviews[string.format("idea-review-%03d.md", last)]
		local seen = if review then capturecheck.reviewState(review) else nil
		if review ~= nil and review ~= "" and seen ~= capturecheck.roundState(doc) then
			table.insert(
				out,
				`the Confirmed line follows round {last}, but the record or the idea changed since that round ({seen or "its review holds no Round: line"}): run ./zn idea again and confirm`
			)
		end
	end
	return out
end

-- The Confirmation line `./zn idea --confirm` and `--unattended` write.
function capturecheck.confirmLine(
	kind: string,
	who: string,
	date: string,
	round: number,
	words: string
): string
	local clean = (string.gsub(who, "[,%(%)]", " "))
	return `{kind} ({clean}, {date}) after round {round}: {words}`
end

-- What `./zn new issue --filed-by` accepts (c0260): the finding an agent filed a ticket from, as a lesson id
-- (`lesson:<skill>/<slug>`), a review finding (`review:<item id>/<review file stem> F<n>`) or another finding of an agent (`agent:<item id>/<slug>`). Anything else (empty text,
-- the user's words) is refused. Returns the source as written, or nil.
capturecheck.SOURCE_RULE =
	"--filed-by takes a lesson (lesson:<skill>/<slug>), a review finding (review:<id>/<review file> F<n>) or another finding of yours (agent:<id>/<slug>), never the user's words or an empty text"

function capturecheck.source(text: string): string?
	if string.match(text, "^lesson:[a-z][a-z0-9%-]*/[a-z0-9][a-z0-9%-]*$") then
		return text
	end
	if string.match(text, "^review:[fdcR]%d%d%d%d/[%w%-]+ F%d+$") then
		return text
	end
	-- any other finding of an agent (a failed step, a graph miss, a deferred finding, a postponed problem, an override
	-- chore): the item it arose in and a short slug naming it
	if string.match(text, "^agent:[fdcR]%d%d%d%d/[a-z][a-z0-9%-]*$") then
		return text
	end
	return nil
end

-- The marker an agent-filed ticket carries: the Scope decision line for its Problem and the `## Filed by (agent)` section.
capturecheck.SCOPE_LINE =
	"Scope decision (user, 2026-11-08): agent-filed tickets are exempt from the ask, interview, idea review and confirmation (c0260)"

-- True when `doc` may be claimed: an agent-filed ticket with a valid marker, or a user capture whose three sections
-- are present, non-empty and pass `check` with the reviews beside it. The claim and the audit use this.
function capturecheck.satisfies(doc: string, reviews: { [string]: string }): boolean
	local kind = capturecheck.kind(doc)
	if kind == "agent" then
		return #capturecheck.check(doc, reviews) == 0
	end
	if kind ~= "user" then
		return false
	end
	local secs = sections(doc)
	for _, title in CAPTURE do
		local sec = find(secs, title)
		if not sec or blank(sec.body) then
			return false -- a missing or empty section: a headings-only record is not a record
		end
	end
	-- each section holds what its kind of section is for
	local function has(title: string, pattern: string): boolean
		return string.find("\n" .. (find(secs, title) :: Section).body, pattern) ~= nil
	end
	return has("Ask (verbatim)", "\n### Message ")
		and has("Interview", "\n### Q1")
		and has("Confirmation", "\n%u%l+ %(")
		and #capturecheck.check(doc, reviews) == 0 -- the gate calls the checker, not a lighter copy
end

-- The agent marker section's text, or nil: `./zn land` compares it between the base and the branch (only
-- `./zn new --filed-by` writes it, review 007 F3).
function capturecheck.markerOf(doc: string): string?
	if not mentions(doc) then
		return nil
	end
	local secs = sections(doc)
	local sec = find(secs, AGENT)
	if not sec then
		return nil
	end
	-- the Scope decision line of the Problem is part of the marker: dropping it breaks the ticket
	local problem = find(secs, "Problem")
	local scope = problem ~= nil
		and string.find("\n" .. problem.body, "\n" .. capturecheck.SCOPE_LINE .. "\n", 1, true) ~= nil
	return sec.body .. (if scope then "\n[scope line present]" else "")
end

-- True when the record's Confirmation holds a `Confirmed (…)` line (not only an Unconfirmed one).
function capturecheck.confirmed(doc: string): boolean
	if not mentions(doc) then
		return false
	end
	local sec = find((sections(doc)), "Confirmation")
	return sec ~= nil and string.find("\n" .. sec.body, "\nConfirmed (", 1, true) ~= nil
end

-- A document as its text before the first `## ` heading (outside fences) and its `## ` sections, whole. `join` puts it
-- back byte for byte, so a splice changes only the section it names and never reads a heading inside a fence.
export type Parts = { head: string, secs: { Section } }

local function split(doc: string): Parts
	local secs: { Section } = {}
	local head = ""
	eachLine(doc, function(line: string, fenced: boolean)
		local title = if fenced then nil else string.match(line, "^## (.-)%s*$")
		if title then
			table.insert(secs, { title = title, body = "" })
		elseif #secs > 0 then
			secs[#secs].body ..= line .. "\n"
		else
			head ..= line .. "\n"
		end
	end)
	return { head = head, secs = secs }
end

local function join(parts: Parts): string
	local out = { parts.head }
	for _, sec in parts.secs do
		table.insert(out, `## {sec.title}\n{sec.body}`)
	end
	return string.sub(table.concat(out), 1, -2) -- eachLine adds one closing newline
end

-- The body of `## title` (outside fences), or nil: the one reader every caller uses for the user's sections.
function capturecheck.section(doc: string, title: string): string?
	for _, sec in split(doc).secs do
		if sec.title == title then
			return sec.body
		end
	end
	return nil
end

-- `doc` with the body of `## title` replaced by `body` (a section made at the end when it is missing).
function capturecheck.replace(doc: string, title: string, body: string): string
	local parts = split(doc)
	local text = if string.sub(body, -1) == "\n" then body else body .. "\n"
	for i, sec in parts.secs do
		if sec.title == title then
			sec.body = text .. (if i < #parts.secs then "\n" else "")
			return join(parts)
		end
	end
	if #parts.secs > 0 then
		local last = parts.secs[#parts.secs]
		last.body = (string.gsub(last.body, "\n*$", "\n\n"))
	else
		parts.head = (string.gsub(parts.head, "\n*$", "\n\n"))
	end
	table.insert(parts.secs, { title = title, body = text })
	return join(parts)
end

-- The sections that may follow each record section: a new one goes before the first of them.
local AFTER: { [string]: { string } } = {
	["Ask (verbatim)"] = { "Interview", "Confirmation", "Design" },
	["Interview"] = { "Confirmation", "Design" },
	["Confirmation"] = { "Design" },
}

-- Inserts `## title` with `body` before the first section that may follow it, else at the end.
local function insertSection(parts: Parts, title: string, body: string)
	for i, sec in parts.secs do
		if table.find(AFTER[title], sec.title) then
			table.insert(parts.secs, i, { title = title, body = body .. "\n\n" })
			return
		end
	end
	local fresh: Section = { title = title, body = body .. "\n" }
	if #parts.secs > 0 then
		local last = parts.secs[#parts.secs]
		last.body = (string.gsub(last.body, "\n*$", "\n\n"))
	end
	table.insert(parts.secs, fresh)
end

local function trimEnds(text: string): string
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

-- True when `new`'s `## Ask (verbatim)` and `## Interview` begin with `old`'s (messages and questions are only
-- appended), or `old` has none.
function capturecheck.askOnlyGrows(old: string, new: string): boolean
	for _, title in { "Ask (verbatim)", "Interview" } do
		local a = capturecheck.section(old, title)
		if a then
			local b = capturecheck.section(new, title)
			local held = (string.gsub(a, "%s+$", ""))
			if b == nil or string.sub(b, 1, #held) ~= held then
				return false
			end
		end
	end
	return true
end

-- True when `new` keeps the user's words of `old`: the Ask and the Interview only grow, and the Confirmation keeps
-- every line it had, except a `Confirmed` line a new round dropped (the shared rule of `./zn land` and the end of prep).
function capturecheck.recordGrows(old: string, new: string): boolean
	if not capturecheck.askOnlyGrows(old, new) then
		return false
	end
	local was = capturecheck.section(old, "Confirmation")
	if not was then
		return true
	end
	local now = capturecheck.section(new, "Confirmation") or ""
	for line in string.gmatch(was, "[^\n]+") do
		if not blank(line) and string.sub(line, 1, 11) ~= "Confirmed (" then
			if not string.find("\n" .. now, "\n" .. line .. "\n", 1, true) then
				return false
			end
		elseif not blank(line) and string.find("\n" .. now, "\n" .. line .. "\n", 1, true) == nil then
			-- a Confirmed line is dropped only by a round: the new document then holds no Confirmed line at all, or this one
			if string.find(now, "Confirmed (", 1, true) then
				return false
			end
		end
	end
	return true
end

-- `doc` with the new blocks of a record file appended to its `## Ask (verbatim)` and `## Interview` (a missing section
-- is made in its place, before any section that may follow it), or nil and the reason. The file holds
-- `## Ask (verbatim)` and/or `## Interview` with only the new `### Message YYYY-MM-DD` and `### Qn` blocks; the
-- questions continue the numbers the document holds. The result must pass `check`; a Confirmed line goes (the record
-- grew, so the idea was not confirmed as it now stands).
function capturecheck.appendRecord(doc: string, file: string): (string?, string?)
	local given, closed = sections(file)
	if not closed then
		return nil, "the record file has a fenced block that is never closed"
	end
	if #given == 0 then
		return nil, "the record file holds no ## Ask (verbatim) or ## Interview section"
	end
	local parts = split(capturecheck.dropConfirmed(doc))
	for _, sec in given do
		if sec.title ~= CAPTURE[1] and sec.title ~= CAPTURE[2] then
			return nil, `the record file holds "## {sec.title}": only ## Ask (verbatim) and ## Interview`
		end
		if blank(sec.body) then
			return nil, `## {sec.title} of the record file is empty`
		end
		local body = trimEnds(sec.body)
		if sec.title == CAPTURE[2] then
			local before = capturecheck.section(doc, CAPTURE[2])
			local count = if before then #(blocks(before)) else 0
			local firstQ = blocks(body)[1]
			if firstQ and firstQ.head ~= `Q{count + 1}` then
				return nil,
					`the record file's first question is "{firstQ.head}" but the next one is Q{count + 1}`
			end
		end
		local placed = false
		for i, existing in parts.secs do
			if existing.title == sec.title then
				existing.body = (string.gsub(existing.body, "%s+$", ""))
					.. "\n\n"
					.. body
					.. "\n"
					.. (if i < #parts.secs then "\n" else "")
				placed = true
			end
		end
		if not placed then
			insertSection(parts, sec.title, body)
		end
	end
	local out = join(parts)
	for _, p in capturecheck.check(out, { ["idea-review-001.md"] = "" }) do
		if not string.find(p, "Confirmation", 1, true) then
			return nil, p
		end
	end
	return out, nil
end

-- `doc` with `line` added to `## Confirmation` (the section is made before `## Design` when missing).
function capturecheck.addConfirmation(doc: string, line: string): string
	local parts = split(doc)
	for _, sec in parts.secs do
		if sec.title == CAPTURE[3] then
			sec.body = (string.gsub(sec.body, "%s+$", "")) .. "\n" .. line .. "\n\n"
			return join(parts)
		end
	end
	insertSection(parts, CAPTURE[3], line)
	return join(parts)
end

-- `doc` without a `Confirmed (…)` line of its Confirmation: a changed idea is not the one the user confirmed. An
-- `Unconfirmed (unattended …)` line stays; a section left empty goes.
function capturecheck.dropConfirmed(doc: string): string
	if not mentions(doc) then
		return doc
	end
	local parts = split(doc)
	for i, sec in parts.secs do
		if sec.title == CAPTURE[3] then
			local kept: { string } = {}
			for line in string.gmatch(sec.body, "[^\n]+") do
				if not blank(line) and string.sub(line, 1, 11) ~= "Confirmed (" then
					table.insert(kept, line)
				end
			end
			if #kept == 0 then
				table.remove(parts.secs, i)
			else
				sec.body = table.concat(kept, "\n") .. "\n\n"
			end
			return join(parts)
		end
	end
	return doc
end

-- What one `./zn idea` round was given and wrote: the number of Ask messages and Interview questions and a hash of the
-- Problem, Solution and Non-goals. The round writes it into its review file (`Round: …`); `--confirm`, the claim and
-- `./zn land` compare it with the document, so a Confirmed line stands only for the idea and the record it covered.
function capturecheck.roundState(doc: string): string
	local ask = capturecheck.section(doc, CAPTURE[1])
	local iv = capturecheck.section(doc, CAPTURE[2])
	local messages = if ask then #(blocks(ask)) else 0
	local questions = if iv then #(blocks(iv)) else 0
	local idea: { string } = {}
	for _, title in { "Problem", "Solution", "Non-goals" } do
		table.insert(idea, trimEnds(capturecheck.section(doc, title) or ""))
	end
	local hash = string.sub(serde.hash("sha256", table.concat(idea, "\n--\n")), 1, 12)
	return `ask {messages}, interview {questions}, idea {hash}`
end

-- The `Round: …` line of an idea review, or nil.
function capturecheck.reviewState(review: string): string?
	return string.match("\n" .. review, "\nRound: ([^\n]+)")
end

-- `doc` with the Scope decision line an agent-filed ticket carries kept in its Problem: `./zn idea` rewrites the whole
-- Problem, and without the line the marker is no marker.
function capturecheck.keepScope(doc: string): string
	if capturecheck.markerOf(doc) == nil then
		return doc
	end
	local problem = capturecheck.section(doc, "Problem") or ""
	if string.find("\n" .. problem, "\n" .. capturecheck.SCOPE_LINE .. "\n", 1, true) then
		return doc
	end
	return capturecheck.replace(
		doc,
		"Problem",
		trimEnds(problem) .. "\n\n" .. capturecheck.SCOPE_LINE .. "\n"
	)
end

return capturecheck
