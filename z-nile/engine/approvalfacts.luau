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

approvalfacts.VERSION = 1
approvalfacts.FILE = "approvals.json"
approvalfacts.TEXT_CAP = 1500 -- the clip of the other facts' short texts (themefacts titles); the walk carries sections whole (G40)
approvalfacts.HARD_CAP = 400000 -- characters of one section the walk carries: far above the largest real section (40 KB); a cut says so in place

export type Part = { heading: string, text: string }
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
function approvalfacts.capAt(text: string, cap: number): string
	if #text <= cap then
		return text
	end
	local cut = cap
	for at = cap, 1, -1 do
		local b = string.byte(text, at + 1)
		if b == nil or b < 0x80 or b >= 0xC0 then
			cut = at
			break
		end
	end
	local shown = string.sub(text, 1, cut)
	local n, m = utf8.len(shown) or #shown, utf8.len(text) or #text
	return `{shown}\n\n[first {n} of {m} characters shown; the full text is in the ticket file]`
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

-- f0437 step 6 (G41): a comment is dropped only when it is a comment of the issue or raft template (whitespace folded; a
-- `{{PLACEHOLDER}}` of a template matches any text), and the number dropped is counted. Every other comment is the
-- document's own text, which the contract hashes and an executor reads, so it stays in the text for the page to show.
export type Templates = { exact: { [string]: boolean }, patterns: { string } }

local function fold(s: string): string
	return trim((string.gsub(s, "%s+", " ")))
end

function approvalfacts.templateComments(texts: { string }): Templates
	local out: Templates = { exact = {}, patterns = {} }
	for _, text in texts do
		for c in string.gmatch(text, "<!%-%-.-%-%->") do
			local folded = fold(c)
			if string.find(folded, "{{", 1, true) then
				local pat = string.gsub(folded, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
				pat = string.gsub(pat, "{{[%w_]+}}", ".-")
				table.insert(out.patterns, "^" .. pat .. "$")
			else
				out.exact[folded] = true
			end
		end
	end
	return out
end

local function isTemplate(c: string, templates: Templates): boolean
	local folded = fold(c)
	if templates.exact[folded] then
		return true
	end
	for _, pat in templates.patterns do
		if string.find(folded, pat) then
			return true
		end
	end
	return false
end

-- `text` without its template comments, and how many were dropped.
local function dropTemplates(text: string, templates: Templates): (string, number)
	local n = 0
	local out = string.gsub(text, "<!%-%-.-%-%->", function(c: string): string
		if isTemplate(c, templates) then
			n += 1
			return ""
		end
		return c
	end)
	return out, n
end

local NO_TEMPLATES: Templates = { exact = {}, patterns = {} }

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
	for line in string.gmatch(chunk .. "\n", "(.-)\n") do
		local h = string.match(line, "^###%s+(.-)%s*$")
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
}

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
	if doc.version ~= approvalfacts.VERSION or type(doc.themes) ~= "table" then
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
