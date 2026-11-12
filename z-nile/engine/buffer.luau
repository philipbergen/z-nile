--!strict
-- The measure buffer and the per-writer TSV. Both are plain text. The buffer is one line per measurement.
-- A fold turns the lines for a ticket into rows of spend.d/<writer>.tsv. Runs between two folds collapse
-- into one other row. spend.md stays the ledger of older typed rows; this module does not read it.
local ledger = require("./ledger")

local buffer = {}

-- A checkout that never folds (the main checkout, a branch with no ticket) keeps the file until a later
-- fold drops lines older than this, or until its .cache is deleted.
buffer.AGE_MS = 14 * 24 * 60 * 60 * 1000
buffer.HEADER = "when\tsubject\tadded\tremoved\tphase\ttokens\tmodel\twall\tcpu\tai\ttest\tunmeasured"

local FLAG_ORDER = { "tokens", "wall", "cpu", "ai", "test" }

export type Line = {
	ms: number,
	kind: string,
	phase: string,
	subject: string,
	wall: number?,
	cpu: number?,
	ai: number?,
	test: number?,
	tokens: number?,
	model: string?,
	unmeasured: string?,
	id: string,
	branch: string,
	head: string,
}

export type Fold = {
	rows: { [string]: { ledger.Row } },
	kept: { Line },
}

local function cell(s: string?): string
	if not s or s == "" then
		return ""
	end
	return (string.gsub(s, "[\t\r\n]", " "))
end

local function num(n: number?): string
	if n == nil then
		return ""
	end
	return string.format("%.3f", n)
end

local function whole(n: number?): string
	if n == nil then
		return ""
	end
	return tostring(math.floor(n))
end

function buffer.flags(s: string?): string?
	if not s or s == "" then
		return nil
	end
	local have: { [string]: boolean } = {}
	for part in string.gmatch(s, "[^,]+") do
		have[part] = true
	end
	local out: { string } = {}
	for _, name in FLAG_ORDER do
		if have[name] then
			table.insert(out, name)
		end
	end
	if #out == 0 then
		return nil
	end
	return table.concat(out, ",")
end

local function flagged(flags: string?, name: string): boolean
	if not flags then
		return false
	end
	return string.find("," .. flags .. ",", "," .. name .. ",", 1, true) ~= nil
end

function buffer.render(line: Line): string
	return table.concat({
		tostring(math.floor(line.ms)),
		cell(line.kind),
		cell(line.phase),
		cell(line.subject),
		num(line.wall),
		num(line.cpu),
		num(line.ai),
		num(line.test),
		whole(line.tokens),
		cell(line.model),
		cell(buffer.flags(line.unmeasured)),
		cell(line.id),
		cell(line.branch),
		cell(line.head),
	}, "\t")
end

local function optNum(s: string): number?
	if s == "" then
		return nil
	end
	return tonumber(s)
end

local function fields(raw: string): { string }
	local parts: { string } = {}
	for part in string.gmatch(raw .. "\t", "([^\t]*)\t") do
		table.insert(parts, part)
	end
	return parts
end

function buffer.parse(text: string): { Line }
	local out: { Line } = {}
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if raw ~= "" then
			local parts = fields(raw)
			local ms = tonumber(parts[1])
			if ms and #parts >= 14 then
				table.insert(out, {
					ms = ms,
					kind = parts[2],
					phase = parts[3],
					subject = parts[4],
					wall = optNum(parts[5]),
					cpu = optNum(parts[6]),
					ai = optNum(parts[7]),
					test = optNum(parts[8]),
					tokens = optNum(parts[9]),
					model = if parts[10] ~= "" then parts[10] else nil,
					unmeasured = buffer.flags(parts[11]),
					id = parts[12],
					branch = parts[13],
					head = parts[14],
				})
			end
		end
	end
	return out
end

function buffer.renderLines(lines: { Line }): string
	if #lines == 0 then
		return ""
	end
	local out: { string } = {}
	for _, line in lines do
		table.insert(out, buffer.render(line))
	end
	return table.concat(out, "\n") .. "\n"
end

local function whenOf(ms: number): string
	return os.date("!%Y-%m-%d %H:%M", math.floor(ms / 1000)) :: string
end

local function rowFrom(line: Line, phase: string, subject: string): ledger.Row
	return {
		when = whenOf(line.ms),
		subject = subject,
		added = 0,
		removed = 0,
		minutes = 0,
		how = "measured",
		phase = phase,
		tokens = line.tokens,
		model = line.model,
		wall = line.wall,
		cpu = line.cpu,
		ai = line.ai,
		test = line.test,
		unmeasured = buffer.flags(line.unmeasured),
	}
end

-- ids are the tickets this fold may write. A line that names one of them is taken only for that ticket.
-- A line with no id is taken when its branch matches, or, when it recorded no branch, when its head matches
-- (a detached checkout stores the commit id and an empty branch). It is written on the first issue id.
-- A raft id in the set consumes a matching line and does not become that home. takeBegins removes begin
-- lines this fold took; a commit leaves them for the spend that reads the transcripts.
function buffer.fold(
	lines: { Line },
	ids: { string },
	branch: string,
	head: string,
	nowMs: number,
	takeBegins: boolean
): Fold
	local want: { [string]: boolean } = {}
	local issues: { string } = {}
	for _, id in ids do
		if id ~= "" then
			want[id] = true
			if string.sub(id, 1, 1) ~= "R" then
				table.insert(issues, id)
			end
		end
	end
	table.sort(issues)
	local home: string? = issues[1]
	if not home then
		local all: { string } = {}
		for _, id in ids do
			if id ~= "" then
				table.insert(all, id)
			end
		end
		table.sort(all)
		home = all[1]
	end

	local function mine(line: Line): boolean
		if line.id ~= "" then
			return want[line.id] == true
		end
		if home == nil then
			return false
		end
		if line.branch ~= "" then
			return line.branch == branch
		end
		return line.head ~= "" and line.head == head
	end

	local kept: { Line } = {}
	local taken: { Line } = {}
	for _, line in lines do
		if nowMs - line.ms <= buffer.AGE_MS then
			if mine(line) and (line.kind ~= "begin" or takeBegins) then
				table.insert(taken, line)
			else
				table.insert(kept, line)
			end
		end
	end

	local function dest(line: Line): string
		if line.id ~= "" and want[line.id] and string.sub(line.id, 1, 1) ~= "R" then
			return line.id
		end
		return home or line.id
	end

	local function stageOf(line: Line): string
		local stage = ""
		local function consider(mark: Line)
			if mark.kind == "begin" and mark.ms <= line.ms and mine(mark) then
				stage = mark.phase
			end
		end
		for _, mark in taken do
			consider(mark)
		end
		for _, mark in kept do
			consider(mark)
		end
		return stage
	end

	local rows: { [string]: { ledger.Row } } = {}
	local function add(id: string, row: ledger.Row)
		if id == "" or string.sub(id, 1, 1) == "R" then
			return
		end
		local list = rows[id]
		if not list then
			list = {}
			rows[id] = list
		end
		table.insert(list, row)
	end

	local groups: { [string]: { n: number, wall: number, cpu: number, ms: number, id: string, stage: string } } =
		{}
	local order: { string } = {}
	for _, line in taken do
		if line.kind == "run" then
			local stage = stageOf(line)
			local id = dest(line)
			local key = `{id}\t{stage}`
			local g = groups[key]
			if not g then
				g = { n = 0, wall = 0, cpu = 0, ms = line.ms, id = id, stage = stage }
				groups[key] = g
				table.insert(order, key)
			end
			g.n += 1
			g.wall += line.wall or 0
			g.cpu += line.cpu or 0
			if line.ms > g.ms then
				g.ms = line.ms
			end
		elseif line.kind == "test" or line.kind == "row" then
			local phase = if line.phase ~= "" then line.phase else "test"
			add(dest(line), rowFrom(line, phase, line.subject))
		end
	end
	for _, key in order do
		local g = groups[key]
		if g then
			local subject = if g.n == 1 then "1 run" else `{g.n} runs`
			if g.stage ~= "" then
				subject ..= ` {g.stage}`
			end
			add(g.id, {
				when = whenOf(g.ms),
				subject = subject,
				added = 0,
				removed = 0,
				minutes = 0,
				how = "measured",
				phase = "other",
				tokens = nil,
				model = nil,
				wall = g.wall,
				cpu = g.cpu,
				ai = nil,
				test = nil,
				unmeasured = "tokens,ai",
			})
		end
	end
	return { rows = rows, kept = kept }
end

local function shown(flags: string?, name: string, n: number?, asWhole: boolean): string
	if flagged(flags, name) or n == nil then
		return ""
	end
	if asWhole then
		return whole(n)
	end
	return num(n)
end

function buffer.renderRow(row: ledger.Row): string
	local flags = buffer.flags(row.unmeasured)
	return table.concat({
		cell(row.when),
		cell(row.subject),
		tostring(row.added),
		tostring(row.removed),
		cell(row.phase),
		shown(flags, "tokens", row.tokens, true),
		cell(row.model),
		shown(flags, "wall", row.wall, false),
		shown(flags, "cpu", row.cpu, false),
		shown(flags, "ai", row.ai, false),
		shown(flags, "test", row.test, false),
		cell(flags),
	}, "\t")
end

function buffer.parseTsv(text: string): ({ ledger.Row }?, string?)
	local rows: { ledger.Row } = {}
	local first = true
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if raw ~= "" then
			if first then
				first = false
				if raw ~= buffer.HEADER then
					return nil, "not a measured tsv"
				end
			else
				local parts = fields(raw)
				if #parts < 12 then
					return nil, "short row"
				end
				local flags = buffer.flags(if parts[12] ~= "" then parts[12] else nil)
				local function numOr(name: string, s: string): number?
					if flagged(flags, name) or s == "" then
						return nil
					end
					return tonumber(s)
				end
				table.insert(rows, {
					when = parts[1],
					subject = parts[2],
					added = tonumber(parts[3]) or 0,
					removed = tonumber(parts[4]) or 0,
					minutes = 0,
					how = "measured",
					phase = parts[5],
					tokens = numOr("tokens", parts[6]),
					model = if parts[7] ~= "" then parts[7] else nil,
					wall = numOr("wall", parts[8]),
					cpu = numOr("cpu", parts[9]),
					ai = numOr("ai", parts[10]),
					test = numOr("test", parts[11]),
					unmeasured = flags,
				})
			end
		end
	end
	if first then
		return nil, "empty"
	end
	return rows, nil
end

function buffer.appendTsv(existing: string?, rows: { ledger.Row }): string
	local body: { string } = {}
	for _, row in rows do
		table.insert(body, buffer.renderRow(row))
	end
	local chunk = table.concat(body, "\n")
	if chunk ~= "" then
		chunk ..= "\n"
	end
	if not existing or existing == "" then
		return buffer.HEADER .. "\n" .. chunk
	end
	if string.sub(existing, -1) ~= "\n" then
		existing ..= "\n"
	end
	return existing .. chunk
end

return buffer
