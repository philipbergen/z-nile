--!strict
-- f0437 step 4: the facts the app's Approvals view shows, one JSON file the live daemon serves (GET /api/approvals).
-- Pure: entries (what `./zn approve <scope> --queue` read, in queue order, a stack's bottom first) in, themes then rafts
-- then tickets out, which is the owner's one linear pass. The reads and the write are approvewalk's, at the edge.
-- This module records nothing and decides nothing: approving stays the person's own act (`./zn approve` in a terminal).
local contract = require("./contract")
local guesses = require("./guesses")
local serde = require("@lune/serde")
local tributaries = require("./tributaries")

local approvalfacts = {}

approvalfacts.VERSION = 2 -- f0437 step 6: whole sections, extra, comments, fenced (version 1 clipped every text at 1,500 characters)
approvalfacts.OLDEST_VERSION = 1 -- an older file still names the units that wait
approvalfacts.FILE = "approvals.json"
approvalfacts.TEXT_CAP = 1500 -- the clip of the other facts' short texts (themefacts titles); the walk carries sections whole (G40)
approvalfacts.HARD_CAP = 400000 -- characters of one section the walk carries: far above the largest real section (40 KB); a cut says so in place

export type Part = { heading: string, text: string }
export type Fenced = { heading: string, lines: number }
export type Review = { name: string, verdict: string }
export type ThemeDef = { project: string, name: string, purpose: string }
export type Entry = {
	project: string, -- the tracker root of the ticket: a theme is a project's own
	hash: string, -- the contract hash of the queue row ("-" when the design has none)
	id: string,
	title: string,
	unit: string, -- the raft, or the ticket itself
	unitTitle: string,
	tributary: string, -- "" when the unit names none
	lines: { string }?, -- f0437: the raft's own tributary line and the ticket's, as written ("" none): the themes the unit belongs to
	state: string, -- "waits" | "working" | "clear": only "waits" is shown
	why: string,
	place: string,
	problem: string,
	solution: string,
	design: { Part },
	acceptance: string?, -- f0437 step 6: the contract's other two sections, whole
	testplan: string?,
	comments: number?, -- the template comments dropped from this ticket's sections (shown as a count)
	fenced: { Fenced }?, -- the sections that end at a heading inside a code block (the contract reads them short)
	guesses: { guesses.Guess },
	reviews: { Review },
	tokens: number?,
	minutes: number?,
	pr: string?,
	branch: string?,
}
export type Ticket = {
	hash: string,
	id: string,
	title: string,
	why: string,
	place: string,
	idea: { problem: string, solution: string },
	design: { Part },
	extra: { Part }, -- Acceptance criteria and Test plan, when the document has them
	comments: number,
	fenced: { Fenced },
	guesses: { guesses.Guess },
	reviews: { Review },
	cost: { tokens: number?, minutes: number? }?,
	links: { pr: string?, branch: string? },
}
-- `themes`: every theme the raft belongs to (f0437: its own tributary and its members', the themes overview's one rule), by name
export type Raft = { id: string, title: string, single: boolean, themes: { string }, tickets: { Ticket } }
export type Theme = { id: string, project: string, title: string, purpose: string, rafts: { Raft } }
export type Facts = { version: number, at: number, run: string, scope: string, themes: { Theme } }
export type Input = { at: number, run: string, scope: string, themes: { ThemeDef }, entries: { Entry } }

-- Cut at `cap` bytes, never inside a UTF-8 character: a split character makes the JSON encoder raise.
function approvalfacts.clipAt(text: string, cap: number): string
	if #text <= cap then
		return text
	end
	local cut = 0
	for at = cap, 1, -1 do
		local b = string.byte(text, at + 1)
		if b == nil or b < 0x80 or b >= 0xC0 then
			cut = at
			break
		end
	end
	return string.sub(text, 1, cut) .. "..."
end

-- A section over the hard cap is cut on a character boundary and says so in place: how many characters are shown of how many.
-- Characters are Unicode code points, and the notice is inside the cap, so a text never exceeds `cap` (the page counts the same way).
local NOTICE_ROOM = 200
function approvalfacts.capAt(text: string, cap: number): string
	local total = utf8.len(text)
	if total == nil then
		-- not valid UTF-8 (the JSON encoder would refuse it anyway): count bytes and cut on a byte
		if #text <= cap then
			return text
		end
		return `{string.sub(text, 1, cap - NOTICE_ROOM)}\n\n[first {cap - NOTICE_ROOM} of {#text} characters shown; the full text is in the ticket file]`
	end
	if total <= cap then
		return text
	end
	local keep = cap - NOTICE_ROOM
	local at = utf8.offset(text, keep + 1) :: number
	return `{string.sub(text, 1, at - 1)}\n\n[first {keep} of {total} characters shown; the full text is in the ticket file]`
end

local function clip(text: string): string
	return approvalfacts.capAt(text, approvalfacts.HARD_CAP)
end

-- The theme a ticket is shown under: its raft's tributary when the raft names one, else its own (a raft's members take
-- their raft's, so a stack is never split across themes).
function approvalfacts.themeOf(raft: string, own: string): string
	return if raft ~= "" then raft else own
end

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- f0437 step 6 (G41, review F3): a comment is dropped only when its text (white space folded) is exactly a comment of the issue
-- or raft template that holds no `{{PLACEHOLDER}}`, and the number dropped is counted. A template comment with a placeholder, and
-- every other comment, is the document's own text, which the contract hashes and an executor reads: it stays for the page to show.
-- A comment inside fenced code is code and is never touched.
export type Templates = { exact: { [string]: boolean } }

local function fold(s: string): string
	return trim((string.gsub(s, "%s+", " ")))
end

function approvalfacts.templateComments(texts: { string }): Templates
	local out: Templates = { exact = {} }
	for _, text in texts do
		for c in string.gmatch(text, "<!%-%-.-%-%->") do
			if not string.find(c, "{{", 1, true) then
				out.exact[fold(c)] = true
			end
		end
	end
	return out
end

-- One description of "inside code", the same the page's renderer reads (review N5; the table of cases is
-- tests/fixtures/inside-code-cases.json, tested on both sides):
--  * a fence opens at three or more backticks or tildes after at most three spaces, counted from the container the line is in (a backtick
--    opener's info string holds no backtick); it closes at the same character, at least as long, with only spaces after it;
--  * a list item is the lines indented to the item's content column after a marker line; a fence in an item goes on whatever the
--    indent of its lines, and ends with the item; the opener may be on the marker line itself;
--  * a quote is the lines that start with `>` (not `>=`); a fence in a quote ends with the quote, at the first line without a mark;
--  * indented code is four or more columns, counted from the container, at the start of a block (after a blank line or other indented
--    code), never in the middle of a paragraph;
--  * a code span is a backtick run to the next run of the same length on the same line.
-- Returns, per line, whether it is inside a fence (the fence lines included) and whether it is indented code.
local function isHrLine(s: string): boolean
	local first = string.match(s, "^ ? ? ?([-*_])")
	if not first then
		return false
	end
	local n = 0
	for ch in string.gmatch(s, ".") do
		if ch == first then
			n += 1
		elseif ch ~= " " then
			return false
		end
	end
	return n >= 3
end

local function fenceOpenOf(content: string): (string?, number)
	local run = string.match(content, "^ ? ? ?(```+)") or string.match(content, "^ ? ? ?(~~~+)")
	if run == nil then
		return nil, 0
	end
	local ch = string.sub(run, 1, 1)
	if ch == "`" and string.find(string.match(content, "^ *" .. "`+(.*)$") or "", "`", 1, true) then
		return nil, 0
	end
	return ch, #run
end

local function codeMap(lines: { string }): ({ boolean }, { boolean })
	local inFence: { boolean } = {}
	local inIndented: { boolean } = {}
	local offs: { number } = {}
	local fence: { ch: string, len: number, q: number, off: number }? = nil
	local prevBlank, prevIndented = true, false
	for i, raw in lines do
		local line = string.gsub(raw, "^\t+", function(tabs: string): string
			return string.rep("    ", #tabs)
		end)
		local q, rest = 0, line
		for _ = 1, 16 do -- quote levels: the page reads eight, a line cannot hold more marks than characters
			local after = string.match(rest, "^ ? ? ?>(.*)$")
			if after == nil or string.sub(after, 1, 1) == "=" then
				break
			end
			q += 1
			rest = if string.sub(after, 1, 1) == " " then string.sub(after, 2) else after
		end
		local open = fence
		if open and q < open.q then
			fence = nil -- the quote ended and took its fence with it
			open = nil
		end
		inFence[i], inIndented[i] = false, false
		if open then
			inFence[i] = true
			local lead = #(string.match(rest, "^ *") :: string)
			local content = string.sub(rest, math.min(open.off, lead) + 1)
			local lead2 = #(string.match(content, "^ *") :: string)
			local run = if lead2 <= 3
				then string.match(string.sub(content, lead2 + 1), if open.ch == "`" then "^(`+)" else "^(~+)")
				else nil
			if run and #run >= open.len and string.match(string.sub(content, lead2 + #run + 1), "^ *$") then
				fence = nil
			end
			prevBlank, prevIndented = false, false
		else
			local blank = string.match(rest, "^%s*$") ~= nil
			local w = #(string.match(rest, "^ *") :: string)
			if not blank then
				for _ = 1, #offs do
					if w < offs[#offs] then
						table.remove(offs)
					end
				end
			end
			local base = offs[#offs] or 0
			if not blank then
				local content = string.sub(rest, math.min(base, w) + 1)
				local cw = #(string.match(content, "^ *") :: string)
				if cw <= 3 then
					local off = base
					local after = content
					if not isHrLine(content) then
						local ind, marker, spaces, tail = string.match(content, "^( *)([-*+])( +)(.*)$")
						if marker == nil then
							ind, marker, spaces, tail = string.match(content, "^( *)(%d+[.)])( +)(.*)$")
						end
						if marker == nil then
							local ind2, marker2 = string.match(content, "^( *)([-*+])$")
							if marker2 == nil then
								ind2, marker2 = string.match(content, "^( *)(%d+[.)])$")
							end
							if marker2 then
								ind, marker, spaces, tail = ind2, marker2, " ", ""
							end
						end
						if
							marker
							and #(ind :: string) <= 3
							and not string.match(marker, "^%d%d%d%d%d%d%d%d%d%d")
						then
							local sp = #(spaces :: string)
							off = base
								+ #(ind :: string)
								+ #marker
								+ (if sp >= 5 or (tail :: string) == "" then 1 else sp)
							table.insert(offs, off)
							after = tail :: string
						end
					end
					local ch, len = fenceOpenOf(after)
					if ch then
						fence = { ch = ch, len = len, q = q, off = off }
						inFence[i] = true
					end
				elseif (prevBlank or prevIndented) and cw - 0 >= 4 then
					inIndented[i] = true
				end
			end
			prevBlank, prevIndented = blank, inIndented[i]
		end
	end
	return inFence, inIndented
end

local function splitLines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		table.insert(out, line)
	end
	if #out > 0 and out[#out] == "" then
		table.remove(out)
	end
	return out
end

-- One run of text (lines that are not inside code) without its template comments; a comment inside a code span is code.
local function dropFrom(part: string, templates: Templates, counter: { n: number }): string
	local out: { string } = {}
	local at = 1
	for _ = 1, #part + 1 do -- each comment found moves `at` on by at least four characters
		local s, e = string.find(part, "<!%-%-.-%-%->", at)
		if not s then
			break
		end
		local comment = string.sub(part, s, e)
		local lineStart = string.find(string.sub(part, 1, s - 1), "[^\n]*$") :: number
		local _, runs = string.gsub(string.sub(part, lineStart, s - 1), "`+", "")
		table.insert(out, string.sub(part, at, s - 1))
		if runs % 2 == 0 and templates.exact[fold(comment)] then
			counter.n += 1
		else
			table.insert(out, comment)
		end
		at = (e :: number) + 1
	end
	table.insert(out, string.sub(part, at))
	return table.concat(out)
end

-- `text` without its template comments, and how many were dropped; code (fences, indented code, code spans) is left as it is.
local function dropTemplates(text: string, templates: Templates): (string, number)
	local lines = splitLines(text)
	local inFence, inIndented = codeMap(lines)
	local counter = { n = 0 }
	local out: { string } = {}
	local run: { string } = {}
	local function flush()
		if #run > 0 then
			table.insert(out, dropFrom(table.concat(run, "\n"), templates, counter))
			run = {}
		end
	end
	for i, line in lines do
		if inFence[i] or inIndented[i] then
			flush()
			table.insert(out, line)
		else
			table.insert(run, line)
		end
	end
	flush()
	return table.concat(out, "\n"), counter.n
end

local NO_TEMPLATES: Templates = { exact = {} }

-- The parts of a document's `## Design` section: the text before its first `###` under the heading "Design", then one
-- part per `###` heading; a part with no text is dropped. Texts are whole (f0437 step 6); template comments are dropped
-- and counted by `sections`, never here. `chunk` is the Design section's body.
local function partsOfChunk(chunk: string): { Part }
	local out: { Part } = {}
	local heading, lines = "Design", {}
	local function flush()
		local text = trim(table.concat(lines, "\n"))
		if text ~= "" then
			table.insert(out, { heading = heading, text = text })
		end
		lines = {}
	end
	local chunkLines = splitLines(chunk)
	local inFence = codeMap(chunkLines)
	for i, line in chunkLines do
		local h = if inFence[i] then nil else string.match(line, "^###%s+(.-)%s*$")
		if h and string.sub(line, 1, 4) ~= "####" then
			flush()
			heading = h
		else
			table.insert(lines, line)
		end
	end
	flush()
	return out
end

function approvalfacts.designParts(doc: string): { Part }
	return partsOfChunk(contract.section(contract.normalize(doc), "Design"))
end

export type Sections = {
	problem: string,
	solution: string,
	design: { Part },
	acceptance: string,
	testplan: string,
	comments: number,
	fenced: { Fenced },
}

-- Review F6: the contract ends a section at any line that starts `## `, even one inside a fenced block, so what follows that line is
-- neither hashed nor approved. For each of the five sections, the number of lines after such a heading that are outside the contract
-- (up to the section's real end, a `## ` line outside any fence; trailing blank lines not counted), when there are some.
local function fencedEnds(text: string): { Fenced }
	local lines = splitLines(text)
	local inFence = codeMap(lines)
	local out: { Fenced } = {}
	for _, heading in contract.HEADS do
		local start: number? = nil
		for i, line in lines do
			if line == "## " .. heading then
				start = i
				break
			end
		end
		if start then
			local contractEnd: number? = nil
			local realEnd = #lines + 1
			for i = start + 1, #lines do
				if string.sub(lines[i], 1, 3) == "## " then
					if contractEnd == nil then
						contractEnd = i
					end
					if not inFence[i] then
						realEnd = i
						break
					end
				end
			end
			if contractEnd and contractEnd < realEnd then
				local last = contractEnd
				for i = realEnd - 1, contractEnd + 1, -1 do
					if not string.match(lines[i], "^%s*$") then
						last = i
						break
					end
				end
				if last > contractEnd then
					table.insert(out, { heading = heading, lines = last - contractEnd })
				end
			end
		end
	end
	return out
end

-- One ticket's five contract sections (`contract.HEADS`), each whole under the hard cap, by the contract's own section rule,
-- with the template comments dropped and counted.
function approvalfacts.sections(doc: string, templates: Templates?): Sections
	local tpl = templates or NO_TEMPLATES
	local text = contract.normalize(doc)
	local dropped = 0
	local function read(heading: string): string
		local body, n = dropTemplates(contract.section(text, heading), tpl)
		dropped += n
		return clip(trim(body))
	end
	local designBody, nDesign = dropTemplates(contract.section(text, "Design"), tpl)
	dropped += nDesign
	local design = partsOfChunk(designBody)
	for _, part in design do
		part.text = clip(part.text)
	end
	local problem, solution = read("Problem"), read("Solution")
	local acceptance, testplan = read("Acceptance criteria"), read("Test plan")
	return {
		problem = problem,
		solution = solution,
		design = design,
		acceptance = acceptance,
		testplan = testplan,
		comments = dropped,
		fenced = fencedEnds(text),
	}
end

local function cappedParts(parts: { Part }): { Part }
	local out: { Part } = {}
	for _, p in parts do
		table.insert(out, { heading = p.heading, text = clip(p.text) })
	end
	return out
end

local function extraOf(e: Entry): { Part }
	local out: { Part } = {}
	if e.acceptance and e.acceptance ~= "" then
		table.insert(out, { heading = "Acceptance criteria", text = clip(e.acceptance) })
	end
	if e.testplan and e.testplan ~= "" then
		table.insert(out, { heading = "Test plan", text = clip(e.testplan) })
	end
	return out
end

-- Themes in the order of `input.themes` (tributaries.toml), then `unsorted` for a unit that names none or an undefined
-- one; a theme with nothing waiting is left out. Inside a theme the rafts follow the order of the entries (the bottom of
-- a stack first) and so do the tickets. Only entries whose state is "waits" are shown.
function approvalfacts.build(input: Input): Facts
	local themes: { Theme } = {}
	local byTheme: { [string]: Theme } = {}
	local known: { [string]: ThemeDef } = {}
	local order: { string } = {}
	local function key(project: string, name: string): string
		return `{project}\0{name}`
	end
	for _, tr in input.themes do
		known[key(tr.project, tr.name)] = tr
		table.insert(order, key(tr.project, tr.name))
	end
	local projects: { string } = {}
	local seenProject: { [string]: boolean } = {}
	local raftAt: { [string]: Raft } = {}
	for _, e in input.entries do
		if e.state == "waits" then
			if not seenProject[e.project] then
				seenProject[e.project] = true
				table.insert(projects, e.project)
			end
			local k = key(e.project, e.tributary)
			if not known[k] then
				k = key(e.project, tributaries.UNSORTED)
			end
			local theme: Theme
			local seen = byTheme[k]
			if seen then
				theme = seen
			else
				local def = known[k]
				local name = if def then def.name else tributaries.UNSORTED
				theme = {
					id = name,
					project = e.project,
					title = name,
					purpose = if def then def.purpose else tributaries.PURPOSES.unsorted,
					rafts = {},
				}
				byTheme[k] = theme
			end
			local rk = `{k}\0{e.unit}`
			local raft: Raft
			local had = raftAt[rk]
			if had then
				raft = had
			else
				raft =
					{ id = e.unit, title = e.unitTitle, single = e.unit == e.id, themes = {}, tickets = {} }
				raftAt[rk] = raft
				table.insert(theme.rafts, raft)
			end
			local function belong(line: string)
				local name = line
				if name == "" or name == tributaries.UNSORTED or name == tributaries.EARLIER then
					return
				end
				if not known[key(e.project, name)] then
					name = tributaries.UNSORTED
				end
				if not table.find(raft.themes, name) then
					table.insert(raft.themes, name)
				end
			end
			local ofUnit: { string } = if e.lines then e.lines else { e.tributary }
			for _, line in ofUnit do
				belong(line)
			end
			local cost = nil
			if e.tokens ~= nil or e.minutes ~= nil then
				cost = { tokens = e.tokens, minutes = e.minutes }
			end
			table.insert(raft.tickets, {
				id = e.id,
				title = e.title,
				hash = e.hash,
				why = e.why,
				place = e.place,
				idea = { problem = clip(e.problem), solution = clip(e.solution) },
				design = cappedParts(e.design),
				extra = extraOf(e),
				comments = e.comments or 0,
				fenced = e.fenced or {},
				guesses = e.guesses,
				reviews = e.reviews,
				cost = cost,
				links = { pr = e.pr, branch = e.branch },
			})
		end
	end
	for _, theme in byTheme do
		for _, raft in theme.rafts do
			if #raft.themes == 0 then
				raft.themes = { tributaries.UNSORTED }
			end
		end
	end
	for _, project in projects do
		table.insert(order, key(project, tributaries.UNSORTED))
	end
	for _, k in order do
		if byTheme[k] then
			table.insert(themes, byTheme[k])
			byTheme[k] = nil -- a theme is listed once
		end
	end
	return {
		version = approvalfacts.VERSION,
		at = input.at,
		run = input.run,
		scope = input.scope,
		themes = themes,
	}
end

-- The units (a raft, or a ticket in no raft) the facts text lists as waiting, with its time and scope; nil when the text is not
-- version 1 facts with a themes list. The one reader of this format outside the daemon (the themes facts use it).
export type Waiting = { units: { [string]: boolean }, at: number, scope: string }
function approvalfacts.waiting(text: string): Waiting?
	local ok, decoded = pcall(serde.decode, "json" :: "json", text)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local doc = decoded :: { [string]: any }
	if
		(doc.version ~= approvalfacts.VERSION and doc.version ~= approvalfacts.OLDEST_VERSION)
		or type(doc.themes) ~= "table"
	then
		return nil
	end
	local units: { [string]: boolean } = {}
	for _, th in doc.themes do
		if type(th) == "table" and type(th.rafts) == "table" then
			for _, raft in th.rafts do
				if type(raft) == "table" and type(raft.id) == "string" then
					units[raft.id] = true
				end
			end
		end
	end
	return {
		units = units,
		at = if type(doc.at) == "number" then doc.at else 0,
		scope = if type(doc.scope) == "string" then doc.scope else "",
	}
end

-- The JSON text of the facts (the file the daemon reads).
function approvalfacts.encode(facts: Facts): string
	return serde.encode("json" :: "json", facts, false)
end

return approvalfacts
