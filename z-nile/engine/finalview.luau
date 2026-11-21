--!strict
-- The ticket's final review (c0262): what the reviewer is shown, how its reviews are read, and what the
-- worker does next. Pure: texts in, texts out. Git and the files are read at the edge (finalread.luau).
--
-- The last review of a ticket is not one more round of the back and forth. It checks the layer's diff
-- against the original ask, as given, with none of the trail that led to it. The view is built from a
-- fixed list of files (ask.md, design.md, contract/, diff.patch, README.md), so the limits are the
-- tool's and not the reviewer's restraint. It is a convenience layer, not a security boundary: a
-- reviewer of the same user can still read the repository, and the prompt tells it not to.
--
-- A review file, `final-review-NNN.md` in the ticket's folder (not the raft's: the raft's final review,
-- trace.md and the verdict approve | changes are #297's and stay as they are):
--   ### F<n>            one per gap, each with a `Gap: design` or `Gap: implementation` line
--   View: <id>          the view the review judged (finalview.viewId)
--   Verdict: on-course | off-course

local capturecheck = require("./capturecheck")
local capturecut = require("./capturecut")
local serde = require("@lune/serde")

local finalview = {}

export type Review = {
	n: number,
	verdict: string, -- on-course, off-course, or "" when no valid Verdict line
	view: string,
	findings: number,
	gaps: { string }, -- the Gap word of each finding, in order, "" when a finding names none
	measured: { boolean }, -- whether each finding quotes what it is measured against
	quotes: { string }?, -- what each finding quotes ("" when none); nil in a Review built by hand
	-- why the review's quotes are not in the view it judged (finalview.unquoted), set at the edge for a review of the
	-- current view; finalview.state reads it as it reads `problem`, so the human's retry or approve lifts it too
	unquoted: string?,
}

export type State = {
	state: string, -- none, on-course, review-again, redo-design, redo-layer, blocked, invalid
	why: string,
	latest: string, -- the latest review's verdict, "" when there is none
}

-- Files the view holds, and no others. Anything not listed here is never copied in.
finalview.FILES = { "README.md", "ask.md", "design.md", "design-changes.patch", "diff.patch" }
finalview.CONTRACT_DIR = "contract/"

-- A path of the layer's diff the reviewer is shown. The trail of THIS ticket and raft (their folders, and
-- spend.d anywhere) is never shown: design reviews, refutes, harvests, results, code and final reviews, questions,
-- the ticket's own document. Another item's document the ticket delivers, and a project's own tracker documents
-- (game-design.md, architecture.md), are deliverables and are shown.
function finalview.keepPath(path: string, issue: string?, raft: string?): boolean
	if string.find(path, "/spend.d/", 1, true) or string.find(path, "/.cache/", 1, true) then
		return false
	end
	if string.sub(path, 1, 7) == ".cache/" then
		return false
	end
	if issue and issue ~= "" then
		for _, dir in { "/issues/", "/issues/active/", "/issues/done/" } do
			if string.find("/" .. path, `/.tracker{dir}{issue}/`, 1, true) then
				return false
			end
		end
	end
	if raft and raft ~= "" then
		for _, dir in { "/rafts/", "/rafts/active/", "/rafts/done/" } do
			if string.find("/" .. path, `/.tracker{dir}{raft}/`, 1, true) then
				return false
			end
		end
	end
	return true
end

local function sectionOf(doc: string, heading: string): string?
	local hay = "\n" .. doc
	local mark = "\n## " .. heading .. "\n"
	local s, e = string.find(hay, mark, 1, true)
	if not s or not e then
		return nil
	end
	local nxt = string.find(hay, "\n## ", e, true)
	local chunk = if nxt then string.sub(hay, e + 1, nxt - 1) else string.sub(hay, e + 1)
	return (string.gsub(chunk, "^%s*(.-)%s*$", "%1"))
end

local ASK_HEADS = { "Ask (verbatim)", "Interview", "Idea", "Confirmation" } -- a hand-made record
local IDEA_HEADS = { "Problem", "Solution", "Non-goals" } -- the capture, or c0260's confirmed idea
local AGENT_HEAD = "Filed by (agent)" -- c0260: an agent-filed ticket's record
local DECISION_MARKS = { "Scope decision (user, ", "Decided with the user (", "Confirmed (" }

local function trimmed(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Lines of `doc` outside `## Open to the human` that carry a user decision, markers (list dash, bold) stripped.
local function decisionLines(doc: string): { string }
	local out: { string } = {}
	local open = sectionOf(doc, "Open to the human")
	local rest = doc
	if open then
		local hay = "\n" .. doc
		local s, e = string.find(hay, "\n## Open to the human\n", 1, true)
		if s and e then
			local nxt = string.find(hay, "\n## ", e, true)
			rest = string.sub(hay, 1, s) .. (if nxt then string.sub(hay, nxt + 1) else "")
		end
	end
	for line in string.gmatch(rest .. "\n", "([^\n]*)\n") do
		local noList = (string.gsub(line, "^%s*[%-%*]%s+", ""))
		local plain = trimmed((string.gsub(noList, "%*%*", "")))
		for _, mark in DECISION_MARKS do
			if string.find(plain, mark, 1, true) then
				table.insert(out, plain)
				break
			end
		end
	end
	return out
end

-- A ruling the user made on an `## Open to the human` bullet: its Decision clause and the ruling, never the
-- finding or the author's Answer (those are the trail).
local function rulings(doc: string): { string }
	local out: { string } = {}
	local body = sectionOf(doc, "Open to the human")
	if not body then
		return out
	end
	for bullet in string.gmatch("\n" .. body, "\n%- (.-)%f[\n%z]") do
		local joined = (string.gsub(bullet, "\n%s+", " "))
		local ruled = string.find(joined, "Ruled (user, ", 1, true)
		if ruled then
			local dec = string.find(joined, "Decision:", 1, true)
			local from = if dec and dec < ruled then dec else ruled
			table.insert(out, "Ruling: " .. trimmed(string.sub(joined, from)))
		end
	end
	return out
end

-- The original ask, from the BASE document (origin/main's copy of the ticket's document: the approved prep, never
-- the branch under review), read with c0260's fence-aware reader (`capturecheck.section`), so a heading inside a pasted
-- message is text. Three kinds of ticket:
-- - **recorded by c0260** (`capturecut.required(front)` and a record, `capturecheck.kind`): the ask is the verbatim
--   messages and the interview (`## Ask (verbatim)`, `## Interview`), or for an agent-filed ticket its filing
--   (`## Filed by (agent)`); the confirmed idea is the base's `## Problem`, `## Solution` and `## Non-goals` (c0260 has
--   no `## Idea`: `./zn idea` wrote them at the round the confirmation names); then `## Confirmation`.
-- - **a hand-made record** (the sections, no mark: c0175, c0248 to c0254, c0275, c0277): `## Ask (verbatim)`,
--   `## Interview`, `## Idea` and `## Confirmation` as the base has them; with no `## Idea`, the capture's Problem,
--   Solution and Non-goals stand for the idea.
-- - **an older ticket**: its capture, Problem, Solution and Non-goals as captured.
-- Either way the user's words since are added: every line of the base carrying a decision mark (`Scope decision
-- (user, `, `Decided with the user (`, `Confirmed (`), in any section and in a list or bold, and the Decision clause and
-- ruling of each `Ruled (user, ...)` bullet under Open to the human. Nothing else of the document is.
function finalview.ask(captured: string, base: string, front: { [string]: string }?): string
	local out: { string } = {}
	local title = string.match(captured, "\ntitle:%s*([^\n]+)")
		or string.match(captured, "^title:%s*([^\n]+)")
		or string.match(base, "\ntitle:%s*([^\n]+)")
	table.insert(out, `# Ask: {title or "(untitled)"}`)
	local function add(doc: string, head: string, label: string): boolean
		local body = capturecheck.section(doc, head)
		local text = if body then trimmed(body) else ""
		if text == "" then
			return false
		end
		table.insert(out, `## {label}\n\n{text}`)
		return true
	end
	local function asCaptured()
		for _, head in IDEA_HEADS do
			add(captured, head, `{head} (as captured)`)
		end
	end
	local kind: string = capturecheck.kind(base)
	local recorded: boolean = front ~= nil and capturecut.required(front) and kind ~= "none"
	if recorded then
		if kind == "agent" then
			add(base, AGENT_HEAD, AGENT_HEAD)
		else
			add(base, "Ask (verbatim)", "Ask (verbatim)")
			add(base, "Interview", "Interview")
		end
		for _, head in IDEA_HEADS do
			add(base, head, `{head} (the confirmed idea)`)
		end
		add(base, "Confirmation", "Confirmation")
	elseif kind == "user" then
		local hadIdea = false
		for _, head in ASK_HEADS do
			local shown = add(base, head, head)
			hadIdea = hadIdea or (shown and head == "Idea")
		end
		if not hadIdea then
			asCaptured()
		end
	else
		asCaptured()
	end
	local decisions = decisionLines(base)
	for _, r in rulings(base) do
		table.insert(decisions, r)
	end
	if #decisions > 0 then
		table.insert(out, "## The user's later decisions\n\n" .. table.concat(decisions, "\n\n"))
	end
	return table.concat(out, "\n\n") .. "\n"
end

local TRAIL = { "design%-review%-%d", "refute%-%d", "review %d%d%d", "round %d" }

-- The design as given: the Design and Acceptance criteria sections of the BASE document. A line that names a
-- design review, a refute or a round is the trail and is dropped (the README says so). Its Unknowns and experiments,
-- Regression guard, Open to the human, Verification log and the rest record how it was reached and are not shown.
function finalview.design(base: string): string
	local out: { string } = {}
	for _, head in { "Design", "Acceptance criteria" } do
		local body = sectionOf(base, head)
		if body and body ~= "" then
			local kept: { string } = {}
			for line in string.gmatch(body .. "\n", "([^\n]*)\n") do
				local low = string.lower(line)
				local trail = false
				for _, pat in TRAIL do
					if string.find(low, pat) then
						trail = true
					end
				end
				if not trail then
					table.insert(kept, line)
				end
			end
			table.insert(out, `## {head}\n\n{table.concat(kept, "\n")}`)
		end
	end
	return table.concat(out, "\n\n") .. "\n"
end

local function lineSet(lines: { string }): { [string]: number }
	local set: { [string]: number } = {}
	for _, l in lines do
		set[l] = (set[l] or 0) + 1
	end
	return set
end

local function sectionLines(doc: string, withDecisions: boolean?): { string }
	local out: { string } = {}
	for _, head in { "Design", "Acceptance criteria" } do
		local body = sectionOf(doc, head)
		if body then
			for line in string.gmatch(body .. "\n", "([^\n]*)\n") do
				if trimmed(line) ~= "" then
					table.insert(out, line)
				end
			end
		end
	end
	if withDecisions ~= false then
		for _, l in decisionLines(doc) do
			table.insert(out, l)
		end
	end
	return out
end

-- What the layer changed in the design and in the user's decisions since the base: lines only the tip has (`+`)
-- and lines only the base has (`-`) in the Design and Acceptance criteria sections and among the decision lines.
-- A decision line only the base has is never a `-`: decisions are only added, so it reached main after the layer was
-- cut (a resolve's Decided line, say) and is in ask.md already.
-- They are claims to check, never the design as given; the Verification log and every other section never appear.
-- "" when nothing changed.
function finalview.changes(base: string, tip: string): string
	local b, t = lineSet(sectionLines(base)), lineSet(sectionLines(tip))
	local out: { string } = {}
	for _, l in sectionLines(tip) do
		if (b[l] or 0) < (t[l] or 0) then
			table.insert(out, "+ " .. l)
			b[l] = (b[l] or 0) + 1
		end
	end
	b, t = lineSet(sectionLines(base, false)), lineSet(sectionLines(tip, false))
	for _, l in sectionLines(base, false) do
		if (t[l] or 0) < (b[l] or 0) then
			table.insert(out, "- " .. l)
			t[l] = (t[l] or 0) + 1
		end
	end
	if #out == 0 then
		return ""
	end
	return "Changed on the layer since the design was approved. These are claims to check, not the design as given:\n\n"
		.. table.concat(out, "\n")
		.. "\n"
end

export type Input = {
	id: string,
	captured: string, -- the capture (./zn capture)
	base: string, -- the ticket's document on origin/main (the approved prep), or at the tip when it is not there
	-- the base document's front matter as audit.front reads it (c0260's `capture: required` mark), nil when unknown
	front: { [string]: string }?,
	tip: string, -- the ticket's document at the layer tip
	contract: { [string]: string }, -- check.sh and acceptance/<name> from the base: path under contract/ -> text
	diff: string, -- the layer's diff against the merge base with the layer below, limited to keepPath files
	patchId: string, -- git patch-id --stable of that diff: what the view id follows, not the diff text
}

local function canon(text: string): string
	local n = (string.gsub(text, "\r\n?", "\n"))
	if n ~= "" and string.sub(n, -1) ~= "\n" then
		n ..= "\n"
	end
	return n
end

local function sortedKeys(t: { [string]: string }): { string }
	local keys: { string } = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- The line `./zn resolve <R> approve` writes into the Layer member's Problem (c0250's `escalation.decidedLine`). It
-- is the human's ruling on a review, read back as that review's ruling (finalview.ruling), so it stays in ask.md for
-- every later reviewer but never moves the view it rules on.
local RESOLVE_LINE = "^Decided with the user %(%d%d%d%d%-%d%d%-%d%d%), resolve [%a%-]+: "

local function idText(name: string, text: string): string
	if name ~= "ask.md" then
		return canon(text)
	end
	local kept: { string } = {}
	for line in string.gmatch(canon(text), "([^\n]*)\n") do
		if not string.match(line, RESOLVE_LINE) then
			table.insert(kept, line)
		end
	end
	-- the lines around a removed one, and a decisions heading left with none under it, read as if it had never been
	local out = table.concat(kept, "\n") .. "\n"
	out = string.gsub(out, "\n\n\n+", "\n\n")
	out = string.gsub(out, "\n## The user.s later decisions\n+$", "\n")
	return (string.gsub(out, "\n\n+$", "\n"))
end

-- sha256 of what a reviewer judges: the ask, the design, its changes, the contract and the diff's patch id (never
-- the README, never the diff text: a restack or main's own movement rewrites index lines and offsets and leaves the
-- patch id alone). A redo that changes the ask, the design, the contract or the change changes it; a resolve's own
-- Decided line (RESOLVE_LINE) does not. Two arguments: a later ticket may fold more in with an optional third.
function finalview.viewId(files: { [string]: string }, patchId: string): string
	local parts: { string } = { `patch\n{patchId}` }
	for _, k in sortedKeys(files) do
		if k ~= "README.md" and k ~= "diff.patch" then
			local text = idText(k, files[k])
			table.insert(parts, `{k}\n{#text}\n{text}`)
		end
	end
	return serde.hash("sha256", table.concat(parts, "\0"))
end

finalview.INSTRUCTIONS = [[# Final review of one ticket

You are the last review of this ticket. Everything you may read is in this folder: ask.md (the original ask,
and what the user later decided), design.md (the design as it was given; lines that cite a review or a round
were removed), design-changes.patch (when present: what the layer changed in the design since, as claims to check),
contract/ (the check and the acceptance specs) and diff.patch (the change); only design.md has such lines removed:
contract/ and diff.patch are as given. Read nothing else: not the repository, not
the ticket's other documents, not reviews, refutes, harvests, pull request comments or worker notes. You judge the
change on its merits.

Decide one thing: does the diff deliver the original ask? Read the design only to name where a gap arose.
- design: the design does not cover what the ask needs, so the change cannot either.
- implementation: the design covers the ask, but the diff does not deliver the design.
Quote the ask line or the design line each gap is measured against, as it stands in ask.md, design.md or
design-changes.patch (a design gap quotes ask.md): a quote that is in none of them is not read. A taste or a style is not
a gap.

Write the review in this shape and nothing else (the Gap line is one word, design or implementation):

## Findings
### F1
Gap: <design or implementation>
Measured against: "<the ask or design line>"
<what is missing or wrong, one short paragraph>

View: %s
Verdict: <on-course or off-course>

An on-course review has no findings. An off-course review has at least one finding, and every finding names its Gap and what it is measured against.
]]

function finalview.readme(id: string, viewId: string): string
	return `{string.format(finalview.INSTRUCTIONS, viewId)}\nTicket: {id}\n`
end

-- The view: path -> text. Nothing outside the fixed list can be in it.
function finalview.assemble(input: Input): { [string]: string }
	local files: { [string]: string } = {
		["ask.md"] = finalview.ask(input.captured, input.base, input.front),
		["design.md"] = finalview.design(input.base),
		["diff.patch"] = input.diff,
	}
	local changes = finalview.changes(input.base, input.tip)
	if changes ~= "" then
		files["design-changes.patch"] = changes
	end
	for path, text in input.contract do
		files[finalview.CONTRACT_DIR .. path] = text
	end
	files["README.md"] = finalview.readme(input.id, finalview.viewId(files, input.patchId))
	return files
end

-- Is `path` a file a view may hold?
function finalview.allowed(path: string): boolean
	for _, f in finalview.FILES do
		if path == f then
			return true
		end
	end
	return string.sub(path, 1, #finalview.CONTRACT_DIR) == finalview.CONTRACT_DIR
		and not string.find(path, "..", 1, true)
end

function finalview.parse(n: number, text: string): Review
	local body = "\n" .. text
	local word = string.match(body, "\nVerdict:%s*([%w%-]+)%s*\n")
		or string.match(body, "\nVerdict:%s*([%w%-]+)%s*$")
	local verdict: string = if word == "on-course" or word == "off-course" then word :: string else ""
	local view = string.match(body, "\nView:%s*(%x+)%s*\n") or string.match(body, "\nView:%s*(%x+)%s*$") or ""
	local gaps: { string } = {}
	local measured: { boolean } = {}
	local quotes: { string } = {}
	local findings = 0
	-- each finding runs from its `### F<n>` heading to the next heading or the end
	local starts: { number } = {}
	local at = 1
	while true do
		local s1, e1 = string.find(body, "\n###%s+F%d+[^\n]*", at)
		if not s1 then
			break
		end
		table.insert(starts, s1)
		at = (e1 :: number) + 1
	end
	for i, s1 in starts do
		local stop = starts[i + 1] or (#body + 1)
		local chunk = string.sub(body, s1, stop - 1) .. "\n"
		findings += 1
		-- the Gap line is exactly one word: a template line "design | implementation" is not a gap
		local gap = string.match(chunk, "\nGap:[ \t]*(%a+)[ \t]*\n") or ""
		if gap ~= "design" and gap ~= "implementation" then
			gap = ""
		end
		table.insert(gaps, gap)
		local quote = string.match(chunk, '\nMeasured against:[ \t]*"([^\n"]+)"')
		table.insert(measured, quote ~= nil and trimmed(quote) ~= "" and not string.find(quote, "^<"))
		table.insert(quotes, if quote then trimmed(quote) else "")
	end
	return {
		n = n,
		verdict = verdict,
		view = view,
		findings = findings,
		gaps = gaps,
		measured = measured,
		quotes = quotes,
	}
end

-- Why a review cannot be used, or nil. Fail closed: a verdict nobody wrote, a gap or a measure nobody named, and
-- an on-course with findings are not read as anything.
function finalview.problem(r: Review): string?
	local name = `final-review-{string.format("%03d", r.n)}.md`
	if r.verdict == "" then
		return `{name} has no "Verdict: on-course" or "Verdict: off-course" line`
	end
	if r.view == "" then
		return `{name} has no "View: <id>" line`
	end
	if r.verdict == "on-course" and r.findings > 0 then
		return `{name} is on-course with {r.findings} finding(s): an on-course review has none`
	end
	if r.verdict == "off-course" and r.findings == 0 then
		return `{name} is off-course with no finding: name each gap`
	end
	for i, gap in r.gaps do
		if gap == "" then
			return `{name} F{i} names no "Gap:" of one word, design or implementation`
		end
		if not r.measured[i] then
			return `{name} F{i} has no Measured against: "<the ask or design line>"`
		end
	end
	return nil
end

-- A quote and a view's text, compared loosely: case, runs of white space, curly quotes, markdown emphasis and code
-- marks, and a patch line's leading `+ `/`- ` do not count.
local function loose(text: string): string
	local s = string.lower("\n" .. text)
	s = string.gsub(s, "\226\128[\156\157\152\153]", '"')
	s = string.gsub(s, "[%*`]", "")
	s = string.gsub(s, "\n[%+%-] ", "\n")
	s = string.gsub(s, "%s+", " ")
	return s
end

finalview.MIN_QUOTE = 8 -- a quote shorter than this, after `loose`, measures nothing

-- Why a review's quotes are not in the view it judged, or nil. A `Gap: design` finding measures the design against
-- the ask, so it quotes `ask.md`; a `Gap: implementation` finding quotes the ask or the design (`ask.md`, `design.md`
-- or `design-changes.patch`). `files` is the view (finalview.assemble). A review built without quotes is not judged.
function finalview.unquoted(r: Review, files: { [string]: string }): string?
	if r.quotes == nil then
		return nil
	end
	local name = `final-review-{string.format("%03d", r.n)}.md`
	local ask = loose(files["ask.md"] or "")
	local design = ask
		.. " "
		.. loose(files["design.md"] or "")
		.. " "
		.. loose(files["design-changes.patch"] or "")
	for i, q in r.quotes :: { string } do
		local want = string.gsub(loose(q), "^ ", "")
		want = string.gsub(want, " $", "")
		if #want < finalview.MIN_QUOTE then
			return `{name} F{i} quotes too little to be measured against ("{q}")`
		end
		local designGap = r.gaps[i] == "design"
		if not string.find(if designGap then ask else design, want, 1, true) then
			return if designGap
				then `{name} F{i} is a design gap but quotes no line of ask.md ("{q}")`
				else `{name} F{i} quotes no line of ask.md, design.md or design-changes.patch ("{q}")`
		end
	end
	return nil
end

-- Whether the dispatcher may file one more ticket review in this state: the view changed since the latest
-- (review-again), or no review is left once the human's retry set every one aside (none).
function finalview.mayFileAgain(state: string): boolean
	return state == "review-again" or state == "none"
end

-- c0262: the human's ruling on a blocked ticket. A note of c0250 (`escalation.md`, or an archived `escalation-NNN.md`)
-- names the ticket on its `Layer:` line, names the review it is about on the first line of `## Open findings or error`
-- that names one (`final-review-NNN.md`), and holds `## Resolution` once the human ran `./zn resolve`. Returns that
-- review's number and the decision, or nil when the note is not a resolved block of this ticket's final review.
function finalview.ruling(
	issue: string,
	layer: string?,
	findings: string?,
	decision: string?
): (number?, string?)
	if layer ~= issue or decision == nil or findings == nil then
		return nil, nil
	end
	local n = string.match(findings, "final%-review%-(%d+)%.md")
	if not n then
		return nil, nil
	end
	return tonumber(n), decision
end

-- Where the ticket stands. `reviews` in any order, `view` the current view's id, `ruled` the human's decisions by review
-- number (finalview.ruling; nil: none).
--   none          no review yet: run the final review
--   on-course     the latest review judged this view on-course, or the human approved it (resolve approve)
--   review-again  the latest review judged another view (the redo happened, or the layer moved): review again
--   redo-design   off course on this view, a design gap named, or the human sent it back (resolve amend-design or split)
--   redo-layer    off course on this view, only implementation gaps: rebuild the layer
--   blocked       a second off-course review, whatever the view, until the human rules on it (c0250's block)
--   invalid       a review that cannot be read, or a second review of a view an off-course review already judged
-- A review the human ruled `retry` is set aside: it is not counted, and the review runs again. One ruled `approve`
-- counts as on course. `latest` is the latest review's verdict, so a caller can tell review-again after an off-course
-- verdict (the redo is not yet reviewed) from review-again after an on-course one (the layer moved).
function finalview.state(reviews: { Review }, view: string, ruled: { [number]: string }?): State
	local byReview: { [number]: string } = ruled or {}
	local sorted: { Review } = {}
	for _, r in reviews do
		if byReview[r.n] ~= "retry" then
			table.insert(sorted, r)
		end
	end
	if #sorted == 0 then
		return { state = "none", why = "no final review yet", latest = "" }
	end
	table.sort(sorted, function(a, b)
		return a.n < b.n
	end)
	local function name(r: Review): string
		return `final-review-{string.format("%03d", r.n)}.md`
	end
	local off = 0
	local judged: { [string]: boolean } = {}
	for _, r in sorted do
		if byReview[r.n] ~= "approve" then
			local bad = finalview.problem(r) or r.unquoted
			if bad then
				return { state = "invalid", why = bad, latest = "" }
			end
			if judged[r.view] then
				return {
					state = "invalid",
					why = `{name(r)} reviews a view an off-course review already judged: reviewed again without a redo`,
					latest = "",
				}
			end
			if r.verdict == "off-course" then
				off += 1
				judged[r.view] = true
			end
		end
	end
	local latest = sorted[#sorted] :: Review
	local rule = byReview[latest.n]
	-- a split, like an amend-design, takes the ticket out of its raft to be re-prepped (c0250's plan): the same ruling
	if rule == "split" then
		rule = "amend-design"
	end
	if rule == "approve" then
		if latest.view == view then
			return {
				state = "on-course",
				why = `the human approved {name(latest)} (resolve approve)`,
				latest = "on-course",
			}
		end
		return {
			state = "review-again",
			why = "the view changed since the latest review",
			latest = "on-course",
		}
	end
	if off >= 2 and latest.verdict == "off-course" and rule ~= "amend-design" then
		return {
			state = "blocked",
			why = `{off} off-course verdicts, the latest {name(latest)}: the ticket is blocked for the human`,
			latest = latest.verdict,
		}
	end
	if latest.view ~= view then
		return {
			state = "review-again",
			why = "the view changed since the latest review",
			latest = latest.verdict,
		}
	end
	if latest.verdict == "on-course" then
		return { state = "on-course", why = "on course", latest = latest.verdict }
	end
	if rule == "amend-design" then
		return {
			state = "redo-design",
			why = `the human sent it back to z-design (resolve {byReview[latest.n]} on {name(latest)})`,
			latest = latest.verdict,
		}
	end
	for _, gap in latest.gaps do
		if gap == "design" then
			return {
				state = "redo-design",
				why = "off course: the design missed the ask",
				latest = latest.verdict,
			}
		end
	end
	return {
		state = "redo-layer",
		why = "off course: the implementation missed the design",
		latest = latest.verdict,
	}
end

return finalview
