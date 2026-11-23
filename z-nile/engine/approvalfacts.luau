--!strict
-- f0437 step 4: the facts the app's Approvals view shows, one JSON file the live daemon serves (GET /api/approvals).
-- Pure: entries (what `./zn approve <scope> --queue` read, in queue order, a stack's bottom first) in, themes then rafts
-- then tickets out, which is the owner's one linear pass. The reads and the write are approvewalk's, at the edge.
-- This module records nothing and decides nothing: approving stays the person's own act (`./zn approve` in a terminal).
local guesses = require("./guesses")
local serde = require("@lune/serde")
local tributaries = require("./tributaries")

local approvalfacts = {}

approvalfacts.VERSION = 1
approvalfacts.FILE = "approvals.json"
approvalfacts.TEXT_CAP = 1500 -- characters of one design part or idea text the view carries

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
	state: string, -- "waits" | "working" | "clear": only "waits" is shown
	why: string,
	place: string,
	problem: string,
	solution: string,
	design: { Part },
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
	guesses: { guesses.Guess },
	reviews: { Review },
	cost: { tokens: number?, minutes: number? }?,
	links: { pr: string?, branch: string? },
}
export type Raft = { id: string, title: string, single: boolean, tickets: { Ticket } }
export type Theme = { id: string, title: string, purpose: string, rafts: { Raft } }
export type Facts = { version: number, at: number, run: string, scope: string, themes: { Theme } }
export type Input = { at: number, run: string, scope: string, themes: { ThemeDef }, entries: { Entry } }

-- Cut at the cap, never inside a UTF-8 character: a split character makes the JSON encoder raise.
local function clip(text: string): string
	if #text <= approvalfacts.TEXT_CAP then
		return text
	end
	local cut = 0
	for at = approvalfacts.TEXT_CAP, 1, -1 do
		local b = string.byte(text, at + 1)
		if b == nil or b < 0x80 or b >= 0xC0 then
			cut = at
			break
		end
	end
	return string.sub(text, 1, cut) .. "..."
end

-- The theme a ticket is shown under: its raft's tributary when the raft names one, else its own (a raft's members take
-- their raft's, so a stack is never split across themes).
function approvalfacts.themeOf(raft: string, own: string): string
	return if raft ~= "" then raft else own
end

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- The parts of a document's `## Design` section: the text before its first `###` under the heading "Design", then one
-- part per `###` heading. HTML comments are template notes and are dropped; a part with no text is dropped.
function approvalfacts.designParts(doc: string): { Part }
	local hay = "\n" .. (string.gsub(doc, "<!%-%-.-%-%->", ""))
	local at = string.find(hay, "\n## Design\n", 1, true)
	local out: { Part } = {}
	if not at then
		return out
	end
	local body = at + #"\n## Design\n"
	local nextAt = string.find(hay, "\n## ", body - 1, true)
	local chunk = if nextAt then string.sub(hay, body, nextAt - 1) else string.sub(hay, body)
	local heading, lines = "Design", {}
	local function flush()
		local text = trim(table.concat(lines, "\n"))
		if text ~= "" then
			table.insert(out, { heading = heading, text = clip(text) })
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
				raft = { id = e.unit, title = e.unitTitle, single = e.unit == e.id, tickets = {} }
				raftAt[rk] = raft
				table.insert(theme.rafts, raft)
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
				design = e.design,
				guesses = e.guesses,
				reviews = e.reviews,
				cost = cost,
				links = { pr = e.pr, branch = e.branch },
			})
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

-- The JSON text of the facts (the file the daemon reads).
function approvalfacts.encode(facts: Facts): string
	return serde.encode("json" :: "json", facts, false)
end

return approvalfacts
