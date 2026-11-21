--!strict
-- f0423: the approval run, the one reader and writer of `<main checkout>/.cache/approve/<run>/` (ignored). The folder
-- holds what the owner is walked through and nothing that records an approval:
--   queue.tsv    id, place, contract hash, verdict and parts: written by the command when it makes the run
--   brief.md     what the session reads: written by the command with the queue
--   rulings.tsv  one row per ruling: written ONLY by `./zn approve --ruling` (this module's `addRuling`)
--   applied.tsv  what `--apply` did with each ruling, so a later `--apply` does not ask twice
-- The pure half (formats, the ruling rules, the brief) takes texts; `write`, `read`, `addRuling` and `addApplied`
-- are the edge. No path is built from anything but a run id and a ticket id that passed their shape checks.
local fs = require("@lune/fs")

local approverun = {}

export type QueueRow = {
	id: string,
	place: string, -- as printed: origin/main or .worktree/<name>
	hash: string, -- the contract hash that was walked; "-" when the design has none
	state: string, -- "waits" | "working" | "clear"
	parts: string, -- contract.encodeParts of the part hashes; "-" when none
	why: string,
}

export type Ruling = {
	ticket: string,
	guess: string, -- G<n>, or "-" for an approval and a change that names no guess
	action: string, -- "approve" | "change"
	stage: string, -- idea | design | code for a change, "-" otherwise
	note: string, -- the owner's words ("-" for an approval)
	lesson: string, -- "-" when none
	ask: string,
	into: string,
}

export type Applied = { ticket: string, guess: string, outcome: string, when: string }

export type Run = { queue: { QueueRow }, rulings: { Ruling }, applied: { Applied } }

approverun.QUEUE = "queue.tsv"
approverun.BRIEF = "brief.md"
approverun.RULINGS = "rulings.tsv"
approverun.APPLIED = "applied.tsv"

local QUEUE_HEAD = "id\tplace\thash\tstate\tparts\twhy"
local RULINGS_HEAD = "ticket\tguess\taction\tstage\tnote\tlesson\task\tinto"
local APPLIED_HEAD = "ticket\tguess\toutcome\twhen"
local STATES = { waits = true, working = true, clear = true }
local STAGES = { idea = true, design = true, code = true }
local OUTCOMES = { recorded = true, ["change-printed"] = true }

-- ---------------------------------------------------------------- shapes

function approverun.validRun(run: string): boolean
	return string.match(run, "^%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%x%x%x%x$") ~= nil
end

function approverun.validTicket(id: string): boolean
	return string.match(id, "^[fdc]%d%d%d%d$") ~= nil
end

function approverun.validGuess(guess: string): boolean
	return guess == "-" or string.match(guess, "^G%d+$") ~= nil
end

-- `<UTC stamp>-<4 hex>`; nil when either part is out of shape.
function approverun.runId(stamp: string, hex: string): string?
	local run = `{stamp}-{hex}`
	return if approverun.validRun(run) then run else nil
end

-- The run folder under a checkout's root, or nil when the run id is not of the run shape (so `..`, a slash or an
-- absolute path never reaches the file system).
function approverun.dir(root: string, run: string): string?
	if not approverun.validRun(run) then
		return nil
	end
	return `{root}/.cache/approve/{run}`
end

-- One cell: no tab or line break, never empty (an empty cell is "-").
local function cell(text: string): string
	local flat = (string.gsub(string.gsub(text, "[\t\r\n]+", " "), "^%s*(.-)%s*$", "%1"))
	return if flat == "" then "-" else flat
end
approverun.cell = cell

local function rowsOf(text: string, head: string, width: number, what: string): ({ { string } }?, string?)
	local lines = string.split(text, "\n")
	if lines[1] ~= head then
		return nil, `{what}: the first line is not "{string.gsub(head, "\t", " ")}"`
	end
	local out: { { string } } = {}
	for n = 2, #lines do
		local line = lines[n]
		if line ~= "" then
			local cols = string.split(line, "\t")
			if #cols ~= width then
				return nil, `{what}: line {n} has {#cols} columns, not {width}`
			end
			table.insert(out, cols)
		end
	end
	return out, nil
end

-- ---------------------------------------------------------------- queue.tsv

function approverun.renderQueue(rows: { QueueRow }): string
	local lines = { QUEUE_HEAD }
	for _, r in rows do
		table.insert(
			lines,
			table.concat(
				{ cell(r.id), cell(r.place), cell(r.hash), cell(r.state), cell(r.parts), cell(r.why) },
				"\t"
			)
		)
	end
	return table.concat(lines, "\n") .. "\n"
end

function approverun.parseQueue(text: string): ({ QueueRow }?, string?)
	local rows, err = rowsOf(text, QUEUE_HEAD, 6, approverun.QUEUE)
	if not rows then
		return nil, err
	end
	local out: { QueueRow } = {}
	local seen: { [string]: boolean } = {}
	for _, c in rows :: { { string } } do
		if not approverun.validTicket(c[1]) then
			return nil, `{approverun.QUEUE}: "{c[1]}" is not a ticket id`
		end
		if seen[c[1]] then
			return nil, `{approverun.QUEUE}: {c[1]} is listed twice`
		end
		if not STATES[c[4]] then
			return nil, `{approverun.QUEUE}: {c[1]} has the unknown verdict "{c[4]}"`
		end
		seen[c[1]] = true
		table.insert(out, { id = c[1], place = c[2], hash = c[3], state = c[4], parts = c[5], why = c[6] })
	end
	return out, nil
end

-- ---------------------------------------------------------------- rulings.tsv

function approverun.renderRulings(list: { Ruling }): string
	local lines = { RULINGS_HEAD }
	for _, r in list do
		table.insert(
			lines,
			table.concat({
				cell(r.ticket),
				cell(r.guess),
				cell(r.action),
				cell(r.stage),
				cell(r.note),
				cell(r.lesson),
				cell(r.ask),
				cell(r.into),
			}, "\t")
		)
	end
	return table.concat(lines, "\n") .. "\n"
end

function approverun.parseRulings(text: string): ({ Ruling }?, string?)
	local rows, err = rowsOf(text, RULINGS_HEAD, 8, approverun.RULINGS)
	if not rows then
		return nil, err
	end
	local out: { Ruling } = {}
	for _, c in rows :: { { string } } do
		if not approverun.validTicket(c[1]) or not approverun.validGuess(c[2]) then
			return nil, `{approverun.RULINGS}: "{c[1]} {c[2]}" is not a ticket and a guess`
		end
		if c[3] ~= "approve" and c[3] ~= "change" then
			return nil, `{approverun.RULINGS}: {c[1]} has the unknown action "{c[3]}"`
		end
		table.insert(out, {
			ticket = c[1],
			guess = c[2],
			action = c[3],
			stage = c[4],
			note = c[5],
			lesson = c[6],
			ask = c[7],
			into = c[8],
		})
	end
	return out, nil
end

-- The refusal for adding `new` to the run, or nil. Pure over the queue and the rulings already written.
function approverun.refusal(queue: { QueueRow }, rulings: { Ruling }, new: Ruling): string?
	local row: QueueRow? = nil
	for _, r in queue do
		if r.id == new.ticket then
			row = r
		end
	end
	if not approverun.validTicket(new.ticket) then
		return `{new.ticket} is not a ticket id`
	end
	if row == nil then
		return `{new.ticket} is not in this run's queue: ./zn approve --queue lists what was walked`
	end
	if (row :: QueueRow).state ~= "waits" then
		return `{new.ticket} does not wait for approval in this run ({(row :: QueueRow).state}): there is nothing to rule on`
	end
	if new.action ~= "approve" and new.action ~= "change" then
		return `the ruling on {new.ticket} must be approve or change`
	end
	if not approverun.validGuess(new.guess) then
		return `{new.guess} is not a guess id (G<n>) or none`
	end
	if new.action == "approve" then
		if new.guess ~= "-" or new.stage ~= "-" then
			return `an approval of {new.ticket} takes no guess and no stage`
		end
	else
		if not STAGES[new.stage] then
			return `the change to {new.ticket} needs --stage idea, design or code`
		end
		if new.note == "-" then
			return `the change to {new.ticket} needs --note with the owner's own words`
		end
		if (new.lesson == "-") ~= (new.ask == "-") then
			return `the change to {new.ticket} needs --lesson and --ask together`
		end
		if new.ask ~= "-" and not string.find(new.ask, "?", 1, true) then
			return `the ask of the change to {new.ticket} must be a question (it has no "?")`
		end
	end
	for _, old in rulings do
		if old.ticket == new.ticket then
			if old.guess == new.guess and old.action == new.action then
				return `{new.ticket} {if new.guess == "-" then "" else new.guess .. " "}already has a ruling in this run`
			end
			if old.action == "approve" or new.action == "approve" then
				return `{new.ticket} already has a ruling that conflicts with {new.action}: approve and change exclude each other`
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- applied.tsv

function approverun.renderApplied(list: { Applied }): string
	local lines = { APPLIED_HEAD }
	for _, a in list do
		table.insert(
			lines,
			table.concat({ cell(a.ticket), cell(a.guess), cell(a.outcome), cell(a.when) }, "\t")
		)
	end
	return table.concat(lines, "\n") .. "\n"
end

function approverun.parseApplied(text: string): ({ Applied }?, string?)
	local rows, err = rowsOf(text, APPLIED_HEAD, 4, approverun.APPLIED)
	if not rows then
		return nil, err
	end
	local out: { Applied } = {}
	for _, c in rows :: { { string } } do
		if not approverun.validTicket(c[1]) or not approverun.validGuess(c[2]) or not OUTCOMES[c[3]] then
			return nil, `{approverun.APPLIED}: "{c[1]} {c[2]} {c[3]}" is not a ticket, a guess and an outcome`
		end
		table.insert(out, { ticket = c[1], guess = c[2], outcome = c[3], when = c[4] })
	end
	return out, nil
end

-- ---------------------------------------------------------------- brief.md

export type Entry = {
	id: string,
	title: string,
	unit: string, -- the raft, or the ticket itself
	state: string,
	why: string,
	stage: string,
	doc: string, -- the design document's path
	place: string,
	hash: string,
	guesses: { string }, -- guesses.md's guess lines, verbatim
	places: { string }, -- lines of the document that mark a guess (`Guess (prep)`)
	layer: string?, -- the layer branch when built
	rework: { string }, -- the rework history (f0423 step 3 fills it)
	lessons: { string }, -- up to three `ruled` lessons that share words with the guesses (step 4 fills it)
}

local function section(out: { string }, label: string, items: { string })
	table.insert(out, `- {label}{if #items == 0 then " none" else ":"}`)
	for _, line in items do
		table.insert(out, `  - {line}`)
	end
end

-- What the walkthrough session reads: the waiting tickets in queue order (the bottom of a stack first), then the
-- ones still being worked.
function approverun.brief(run: string, scope: string, entries: { Entry }): string
	local out = {
		`# Approval run {run}`,
		"",
		`Scope: {scope}. Read this once, then walk the owner through the tickets in this order (work that others build on comes first).`,
		`Write each ruling with \`./zn approve --ruling {run} <ticket> approve\` or \`... change --stage idea|design|code ...\`; never record anything else.`,
		"",
	}
	local waits: { Entry } = {}
	local working: { string } = {}
	for _, e in entries do
		if e.state == "waits" then
			table.insert(waits, e)
		else
			table.insert(working, `{e.id}: {e.title} ({e.why})`)
		end
	end
	table.insert(out, `## Waiting for the owner ({#waits})`)
	for n, e in waits do
		table.insert(out, "")
		table.insert(out, `### {n}. {e.id}: {e.title}`)
		table.insert(out, `- stage: {e.stage}; waits because: {e.why}`)
		table.insert(out, `- belongs to: {e.unit}; document: {e.doc}; design: {e.place}; contract: {e.hash}`)
		if e.layer then
			table.insert(out, `- built on layer: {e.layer}`)
		end
		section(out, `guesses ({#e.guesses}), verbatim`, e.guesses)
		section(out, "where the design marks a guess", e.places)
		section(out, "rework history", e.rework)
		if #e.lessons > 0 then
			section(out, "lessons the owner ruled on guesses like these", e.lessons)
		end
	end
	table.insert(out, "")
	table.insert(out, `## Still being worked ({#working})`)
	for _, line in working do
		table.insert(out, `- {line}`)
	end
	if #working == 0 then
		table.insert(out, "none")
	end
	return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------- the edge

-- A fresh run id under `root`: the UTC stamp and four hex digits, redrawn if the folder exists (at most 20 draws).
function approverun.newRun(root: string, stamp: string, draw: () -> number): string?
	for _ = 1, 20 do
		local run = approverun.runId(stamp, string.format("%04x", draw() % 65536))
		if run and not fs.isDir(`{root}/.cache/approve/{run}`) then
			return run
		end
	end
	return nil
end

function approverun.write(root: string, run: string, queue: { QueueRow }, brief: string): string?
	local dir = approverun.dir(root, run)
	if not dir then
		return `{run} is not a run id`
	end
	fs.writeDir(dir)
	fs.writeFile(`{dir}/{approverun.QUEUE}`, approverun.renderQueue(queue))
	fs.writeFile(`{dir}/{approverun.BRIEF}`, brief)
	fs.writeFile(`{dir}/{approverun.RULINGS}`, approverun.renderRulings({}))
	fs.writeFile(`{dir}/{approverun.APPLIED}`, approverun.renderApplied({}))
	return nil
end

function approverun.read(root: string, run: string): (Run?, string?)
	local dir = approverun.dir(root, run)
	if not dir then
		return nil, `{run} is not a run id (YYYYMMDDTHHMMSSZ-xxxx)`
	end
	if not fs.isDir(dir) then
		return nil, `no run {run}: ./zn approve <scope> --queue makes one`
	end
	local function text(name: string): string
		return if fs.isFile(`{dir}/{name}`) then fs.readFile(`{dir}/{name}`) else ""
	end
	local queue, qerr = approverun.parseQueue(text(approverun.QUEUE))
	if not queue then
		return nil, qerr
	end
	local rulings, rerr = approverun.parseRulings(
		if fs.isFile(`{dir}/{approverun.RULINGS}`) then text(approverun.RULINGS) else RULINGS_HEAD .. "\n"
	)
	if not rulings then
		return nil, rerr
	end
	local applied, aerr = approverun.parseApplied(
		if fs.isFile(`{dir}/{approverun.APPLIED}`) then text(approverun.APPLIED) else APPLIED_HEAD .. "\n"
	)
	if not applied then
		return nil, aerr
	end
	return { queue = queue :: { QueueRow }, rulings = rulings :: { Ruling }, applied = applied :: { Applied } },
		nil
end

-- The only write `--ruling` makes: one row in this run's rulings.tsv, or the refusal.
function approverun.addRuling(root: string, run: string, new: Ruling): string?
	local found, err = approverun.read(root, run)
	if not found then
		return err
	end
	local current = found :: Run
	local refused = approverun.refusal(current.queue, current.rulings, new)
	if refused then
		return refused
	end
	table.insert(current.rulings, new)
	fs.writeFile(
		`{approverun.dir(root, run)}/{approverun.RULINGS}`,
		approverun.renderRulings(current.rulings)
	)
	return nil
end

function approverun.addApplied(root: string, run: string, row: Applied): string?
	local found, err = approverun.read(root, run)
	if not found then
		return err
	end
	local current = found :: Run
	table.insert(current.applied, row)
	fs.writeFile(
		`{approverun.dir(root, run)}/{approverun.APPLIED}`,
		approverun.renderApplied(current.applied)
	)
	return nil
end

return approverun
