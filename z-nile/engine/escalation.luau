--!strict
-- c0250: the escalation note, `escalation.md` in a blocked item's folder: the one reader and writer of its shape, the
-- closed reason list, the decisions and the table that maps each decision to the item's next state. Pure over texts
-- (zz-arch): `./zn block` and `./zn resolve` read and write the files, the board and the dispatcher hand texts here.

export type Option = { decision: string, text: string, recommended: boolean }
export type Resolution = { decision: string, answer: string?, by: string, said: string?, when: string }
export type Header = {
	item: string,
	reason: string,
	from: string,
	layer: string?,
	actor: string,
	when: string,
}
export type Note = {
	item: string?,
	reason: string?,
	from: string?,
	layer: string?,
	actor: string?,
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
}

local escalation = {}

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
		resolution = {
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
	table.insert(out, `When: {header.when}`)
	for _, name in SECTIONS do
		table.insert(out, "")
		table.insert(out, `## {name}`)
		table.insert(out, sections[name])
	end
	table.insert(out, "")
	table.insert(out, "## Resume")
	for _, o in (note :: Note).options do
		table.insert(out, `./zn resolve {header.item} {o.decision} --answer "<your answer>"`)
	end
	return table.concat(out, "\n") .. "\n"
end

-- The note with its `## Resolution` appended.
function escalation.resolution(text: string, r: Resolution): string
	local out = string.gsub(text, "\n+$", "") .. "\n\n## Resolution\n"
	out ..= `Decision: {r.decision}\nAnswer: {r.answer or "none"}\nBy: {r.by}\n`
	if r.said then
		out ..= `Said: "{r.said}"\n`
	end
	return out .. `When: {r.when}\n`
end

-- The edge of a decision: where a blocked item goes from `from` (the status it was blocked from).
function escalation.plan(from: "preparing" | "active", isRaft: boolean, decision: string): Plan
	if not table.find(escalation.DECISIONS, decision) then
		error(`{decision} is not a decision`, 2)
	end
	local raftRun = from == "active" and isRaft
	local status = if raftRun then "prepared" else "new"
	local amend = decision == "amend-design" or decision == "split"
	return {
		status = status,
		design = if amend and not raftRun then "draft" else nil,
		decided = decision == "approve",
		unfold = amend and raftRun,
		split = decision == "split",
		copyNote = amend and raftRun,
	}
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
