--!strict
-- c0250: the escalation note, `escalation.md` in a blocked item's folder: the one reader and writer of its shape, the
-- closed reason list, the decisions and the table that maps each decision to the item's next state. Pure over texts
-- (zz-arch): `./zn block` and `./zn resolve` read and write the files, the board and the dispatcher hand texts here.

export type Option = { decision: string, text: string, recommended: boolean }
export type Ruled = { id: string, words: string }
export type Resolution = {
	decision: string,
	answer: string?,
	by: string,
	said: string?,
	ruled: { Ruled }?, -- review-exhausted: the user's ruling on each open id (`Ruled F2: "<words>"`)
	when: string,
}
export type Header = {
	item: string,
	reason: string,
	from: string,
	layer: string?,
	actor: string,
	session: string?, -- the running CLI session that filed the block, when one is known
	open: { string }?, -- review-exhausted: the ids of the unruled bullets under `## Open to the human`
	when: string,
}
export type Note = {
	item: string?,
	reason: string?,
	from: string?,
	layer: string?,
	actor: string?,
	session: string?,
	open: { string },
	when: string?,
	question: string,
	tried: string,
	findings: string,
	options: { Option },
	resume: { string },
	resolution: Resolution?,
}
-- `status`: the item's next status. `design`: set to draft. `decided`: the answer becomes a Decided line (in the
-- item, or in the Layer member of a raft). `unfold`: the Layer member leaves the raft and goes to `new`. `split`: a
-- new backlog issue, and a Scope decision line. `copyNote`: the member gets a copy of the note.
export type Plan = {
	status: string,
	design: string?,
	decided: boolean,
	unfold: boolean,
	split: boolean,
	copyNote: boolean,
	regroup: boolean, -- a raft's `approve`: the Layer member's `grouped:` entry is re-recorded (keepRecords)
	refuse: string?, -- the decision is refused for this origin
}

local openlist = require("./openlist")

local escalation = {}

-- the answer the dispatcher writes to a c0256 question the block superseded
escalation.SUPERSEDED = "(no reply: the item was blocked, and its resolution answers in the next message)"
escalation.REASONS = { "review-exhausted", "design-gap", "needs-decision", "red-gate", "quota", "tripwire" }
escalation.DECISIONS = { "amend-design", "approve", "split", "retry", "abort" }

local SECTIONS = { "Question", "What was tried", "Open findings or error", "Options" }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- The text of each `## <name>` section, in a table by name; the lines before the first section are the header.
local function split(text: string): ({ [string]: string }, { string }, { string })
	local sections: { [string]: string } = {}
	local order: { string } = {}
	local head: { string } = {}
	local current: string? = nil
	local buf: { string } = {}
	local function close()
		if current then
			sections[current] = trim(table.concat(buf, "\n"))
		end
		buf = {}
	end
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local name = string.match(line, "^## (.-)%s*$")
		if name then
			close()
			current = name
			table.insert(order, name)
		elseif current then
			table.insert(buf, line)
		else
			table.insert(head, line)
		end
	end
	close()
	return sections, order, head
end

local function parseOptions(body: string): { Option }
	local out: { Option } = {}
	for line in string.gmatch(body .. "\n", "([^\n]*)\n") do
		local text = string.match(line, "^%- (.*)$")
		if text then
			local decision = string.match(text, "^([%w%-]+):") or string.match(text, "^([%w%-]+)%s*$") or ""
			local recommended = string.match(text, "%(recommended%)%s*$") ~= nil
			table.insert(out, { decision = decision, text = text, recommended = recommended })
		end
	end
	return out
end

local function field(lines: { string }, key: string): string?
	for _, line in lines do
		local v = string.match(line, `^{key}:%s*(.-)%s*$`)
		if v then
			return v
		end
	end
	return nil
end

-- The note a text holds, or nil and why. The four sections the worker writes are required and may not be empty; the
-- header and `## Resume` are `block`'s and may be missing from a note that has not been stamped yet.
function escalation.parse(text: string): (Note?, string?)
	local sections, _, head = split(text)
	for _, name in SECTIONS do
		local body = sections[name]
		if body == nil then
			return nil, `the note has no "## {name}" section`
		elseif body == "" then
			return nil, `the "## {name}" section is empty`
		end
	end
	local resume: { string } = {}
	for line in string.gmatch((sections["Resume"] or "") .. "\n", "([^\n]*)\n") do
		if line ~= "" then
			table.insert(resume, line)
		end
	end
	local resolution: Resolution? = nil
	local rbody = sections["Resolution"]
	if rbody then
		local lines: { string } = {}
		for line in string.gmatch(rbody .. "\n", "([^\n]*)\n") do
			table.insert(lines, line)
		end
		local decision, by, when = field(lines, "Decision"), field(lines, "By"), field(lines, "When")
		if not decision or not by or not when then
			return nil, 'the "## Resolution" section needs Decision, By and When lines'
		end
		local answer = field(lines, "Answer")
		local ruled: { Ruled } = {}
		for _, line in lines do
			local rid, words = string.match(line, '^Ruled (%w+): "(.*)"$')
			if rid and words then
				table.insert(ruled, { id = rid, words = words })
			end
		end
		resolution = {
			ruled = ruled,
			decision = decision,
			answer = if answer == "none" then nil else answer,
			by = by,
			said = (function(): string?
				local v = field(lines, "Said")
				return if v then (string.match(v, '^"(.*)"$') or v) else nil
			end)(),
			when = when,
		}
	end
	return {
		item = field(head, "Item"),
		reason = field(head, "Reason"),
		from = field(head, "From"),
		layer = field(head, "Layer"),
		actor = field(head, "Actor"),
		session = field(head, "Session"),
		open = (function(): { string }
			local out: { string } = {}
			for id in string.gmatch(field(head, "Open") or "", "[%w]+") do
				table.insert(out, id)
			end
			return out
		end)(),
		when = field(head, "When"),
		question = sections["Question"],
		tried = sections["What was tried"],
		findings = sections["Open findings or error"],
		options = parseOptions(sections["Options"]),
		resume = resume,
		resolution = resolution,
	},
		nil
end

-- Why a note may not be filed, or nil: an option names no decision, no or several recommended options.
function escalation.check(note: Note): string?
	if note.resolution then
		return "this is the last block's note: write the new one"
	end
	if #note.options == 0 then
		return "the note has no option: each is a bullet starting with a decision"
	end
	local recommended = 0
	for _, o in note.options do
		if not table.find(escalation.DECISIONS, o.decision) then
			return `option "{o.text}" names no decision ({table.concat(escalation.DECISIONS, ", ")})`
		end
		if o.recommended then
			recommended += 1
		end
	end
	if recommended ~= 1 then
		return `exactly one option ends with (recommended), not {recommended}`
	end
	if note.reason ~= nil and not table.find(escalation.REASONS, note.reason) then
		return `{note.reason} is not a reason ({table.concat(escalation.REASONS, ", ")})`
	end
	return nil
end

-- The worker's four sections with the header and `## Resume` that `block` adds. The body is taken from `text` as it is;
-- a header or title the worker wrote is replaced.
function escalation.stamp(text: string, header: Header): string
	if not table.find(escalation.REASONS, header.reason) then
		error(`{header.reason} is not a reason ({table.concat(escalation.REASONS, ", ")})`, 2)
	end
	local note, why = escalation.parse(text)
	if not note then
		error(why, 2)
	end
	local sections = split(text)
	local out: { string } = {
		`# Escalation: {header.item}`,
		`Item: {header.item}`,
		`Reason: {header.reason}`,
		`From: {header.from}`,
	}
	if header.layer then
		table.insert(out, `Layer: {header.layer}`)
	end
	table.insert(out, `Actor: {header.actor}`)
	if header.session and header.session ~= "" then
		table.insert(out, `Session: {header.session}`)
	end
	if header.open and #header.open > 0 then
		table.insert(out, `Open: {table.concat(header.open, ", ")}`)
	end
	table.insert(out, `When: {header.when}`)
	for _, name in SECTIONS do
		table.insert(out, "")
		table.insert(out, `## {name}`)
		table.insert(out, sections[name])
	end
	table.insert(out, "")
	table.insert(out, "## Resume")
	for _, o in (note :: Note).options do
		local line = `./zn resolve {header.item} {o.decision} --answer "<your answer>"`
		if o.decision == "split" then
			line ..= ` --title "<the new issue's title>"`
		end
		if header.reason == "review-exhausted" then
			for _, id in (header.open :: any) or ({} :: { string }) do
				line ..= ` --rule {id}="<your ruling>"`
			end
		end
		table.insert(out, line)
	end
	table.insert(out, `An agent adds --said "<the user's message>" to each command.`)
	return table.concat(out, "\n") .. "\n"
end

-- The note with its `## Resolution` appended.
function escalation.resolution(text: string, r: Resolution): string
	local out = string.gsub(text, "\n+$", "") .. "\n\n## Resolution\n"
	out ..= `Decision: {r.decision}\nAnswer: {r.answer or "none"}\nBy: {r.by}\n`
	if r.said then
		out ..= `Said: "{r.said}"\n`
	end
	for _, ruled in (r.ruled :: any) or ({} :: { Ruled }) do
		out ..= `Ruled {ruled.id}: "{ruled.words}"\n`
	end
	return out .. `When: {r.when}\n`
end

-- The edge of a decision: where a blocked item goes from `from` (the status it was blocked from). An issue is never
-- blocked from `active` (its raft is: F2), a draft raft has no design to amend or split, so its `approve` and
-- `amend-design` act as `retry` and `split` is refused.
function escalation.plan(from: "preparing" | "active", isRaft: boolean, decision: string): Plan
	if not table.find(escalation.DECISIONS, decision) then
		error(`{decision} is not a decision`, 2)
	end
	if from == "active" and not isRaft then
		error("an issue is never blocked from active: its raft is", 2)
	end
	local raftRun = from == "active"
	local draftRaft = isRaft and not raftRun
	local status = if raftRun then "prepared" else "new"
	local amend = decision == "amend-design" or decision == "split"
	return {
		status = status,
		design = if amend and not isRaft then "draft" else nil,
		decided = decision == "approve" and not draftRaft,
		unfold = amend and raftRun,
		split = decision == "split" and not draftRaft,
		copyNote = amend and raftRun,
		regroup = decision == "approve" and raftRun,
		refuse = if draftRaft and decision == "split"
			then "a draft raft has no design to split: resolve it amend-design, then split the issue in z-design"
			else nil,
	}
end

-- The Decided line a resolve `approve` adds to a Problem (Q5): in a terminal the user's answer, in an agent session
-- the user's words (`--said`) and the option the agent chose.
function escalation.decidedLine(date: string, decision: string, answer: string?, said: string?): string
	if said then
		return `Decided with the user ({date}), resolve {decision}: "{said}" (the option: {answer or "none"})`
	end
	return `Decided with the user ({date}), resolve {decision}: "{answer or decision}"`
end

-- The Scope decision line of a split: only the user changes scope, so the words are the user's (`--said` in an agent
-- session, else the answer).
function escalation.scopeLine(date: string, words: string, newId: string): string
	return `Scope decision (user, {date}): "{words}" (split into {newId})`
end

-- The recorded rulings of a resolved note, by finding id.
function escalation.rulings(note: Note): { [string]: string }
	local out: { [string]: string } = {}
	if note.resolution then
		for _, r in (note.resolution.ruled :: any) or ({} :: { Ruled }) do
			out[r.id] = r.words
		end
	end
	return out
end

-- `doc` with `Ruled (user, <date>): <words>` under each unruled bullet of its `## Open to the human`, taken from the
-- note's recorded rulings; nil and why when a bullet has no recorded ruling, or the note holds no resolution.
function escalation.applyRulings(doc: string, note: Note, date: string): (string?, string?)
	if not note.resolution then
		return nil, "the note holds no resolution: ./zn resolve it first"
	end
	local pending = openlist.pending(doc)
	local rulings = escalation.rulings(note)
	if #pending == 0 then
		return doc, nil
	end
	for _, id in pending do
		if not rulings[id] then
			return nil, `{id} has no recorded ruling: ./zn resolve needs --rule {id}="<the ruling>"`
		end
	end
	local lines: { string } = string.split(doc, "\n")
	local out: { string } = {}
	local inSection = false
	local open: string? = nil
	local function flush()
		if open then
			table.insert(out, `  Ruled (user, {date}): {rulings[open]}`)
			open = nil
		end
	end
	for _, line in lines do
		local heading = string.match(line, "^## (.-)%s*$")
		if heading then
			flush()
			inSection = heading == "Open to the human"
		elseif inSection then
			local id = string.match(line, "^%- (F%d+):") or string.match(line, "^%- (JC%d+):")
			if id then
				flush()
				if table.find(pending, id) then
					open = id
				end
			end
		end
		if inSection and open and string.match(line, "^%s*$") then
			-- a blank line ends the bullet: the ruling goes before it
			flush()
		end
		table.insert(out, line)
	end
	flush()
	return table.concat(out, "\n"), nil
end

-- A resolution as the dispatcher's exchange carries it: the user's answer to the question the note put.
function escalation.answerText(r: Resolution): string
	return `Decision: {r.decision}\nAnswer: {r.answer or "none"}\n`
end

-- The Question section, as one paragraph.
function escalation.question(note: Note): string
	return trim(note.question)
end

-- The name the resolved note is kept under before the item blocks again: the next free `escalation-NNN.md`.
function escalation.nextArchive(names: { string }): string
	local top = 0
	for _, name in names do
		local n = tonumber(string.match(name, "^escalation%-(%d%d%d)%.md$"))
		if n and n > top then
			top = n
		end
	end
	return string.format("escalation-%03d.md", top + 1)
end

return escalation
