--!strict
-- Prep prototype of scripts/tracker/ledger.luau (c0084): the pure format of spend.md. Copy it as the start.
local ledger = {}

ledger.PHASES = { "capture", "prep", "design-review", "build", "code-review", "deliver" }
local IS: { [string]: boolean } = {}
for _, p in ledger.PHASES do
	IS[p] = true
end

export type Row = {
	when: string,
	subject: string,
	added: number,
	removed: number,
	minutes: number,
	how: string,
	phase: string,
	tokens: number?,
}
export type Totals = { added: number, removed: number, minutes: number, records: number, tokens: number }
export type Ledger = { id: string, title: string, rows: { Row } }

ledger.HEADER = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n"
	.. "|---|---|---|---|---|---|---|---|---|\n"

function ledger.isPhase(s: string): boolean
	return IS[s] == true
end

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function count(s: string): number?
	if not string.match(s, "^%d+$") then
		return nil
	end
	return tonumber(s)
end

local function tenths(n: number): number
	return math.floor(n * 10 + 0.5)
end

function ledger.parse(text: string): (Ledger?, string?)
	local id, title = string.match(text, "^# Spend:%s*(%S+)[ ]?([^\n]*)")
	local out: Ledger = { id = id or "", title = title or "", rows = {} }
	-- Rows written before c0084 could span lines (a multi-line commit message in the commit cell): such a row starts
	-- with "| <n> |" and ends at the first later line that ends with "|". Its lines are joined with spaces.
	local logical: { string } = {}
	local pending: string? = nil
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if pending then
			pending ..= " " .. line
			if string.sub(line, -1) == "|" then
				table.insert(logical, pending :: string)
				pending = nil
			end
		elseif string.match(line, "^|%s*%d+%s*|") and string.sub(line, -1) ~= "|" then
			pending = line
		else
			table.insert(logical, line)
		end
	end
	if pending then
		return nil, `not a spend row (unterminated): {pending}`
	end
	for _, line in logical do
		if string.sub(line, 1, 1) ~= "|" then
			continue
		end
		if string.match(line, "^|%s*#%s*|") or string.match(line, "^|%-%-%-") then
			continue
		end
		if string.sub(line, -1) ~= "|" then
			return nil, `not a spend row: {line}`
		end
		local c: { string } = {}
		for cell in string.gmatch(string.sub(line, 2, -2) .. "|", "([^|]*)|") do
			table.insert(c, trim(cell))
		end
		if #c ~= 7 and #c ~= 9 then
			return nil, `not a spend row (7 or 9 cells): {line}`
		end
		local n, added, removed = count(c[1]), count(c[4]), count(c[5])
		local minutes = if string.match(c[6], "^%d+%.?%d*$") then tonumber(c[6]) else nil
		if not n or not added or not removed or not minutes then
			return nil, `not a spend row (numbers): {line}`
		end
		if not string.match(c[2], "^%d%d%d%d%-%d%d%-%d%d") then
			return nil, `not a spend row (when): {line}`
		end
		local phase = if #c == 9 then c[8] else "build"
		if not IS[phase] then
			return nil, `unknown phase {phase}: {line}`
		end
		local tokens: number? = nil
		if #c == 9 and c[9] ~= "" then
			tokens = count(c[9])
			if not tokens then
				return nil, `not a spend row (tokens): {line}`
			end
		end
		table.insert(out.rows, {
			when = c[2],
			subject = c[3],
			added = added,
			removed = removed,
			minutes = minutes,
			how = c[7],
			phase = phase,
			tokens = tokens,
		})
	end
	return out
end

function ledger.sum(rows: { Row }): Totals
	local t = { added = 0, removed = 0, minutes = 0, records = #rows, tokens = 0 }
	local tm = 0
	for _, r in rows do
		t.added += r.added
		t.removed += r.removed
		tm += tenths(r.minutes)
		t.tokens += r.tokens or 0
	end
	t.minutes = tm / 10
	return t
end

function ledger.byPhase(rows: { Row }): { [string]: Totals }
	local groups: { [string]: { Row } } = {}
	for _, p in ledger.PHASES do
		groups[p] = {}
	end
	for _, r in rows do
		table.insert(groups[r.phase], r)
	end
	local out: { [string]: Totals } = {}
	for p, g in groups do
		out[p] = ledger.sum(g)
	end
	return out
end

local function clean(s: string): string
	return trim((string.gsub(s, "[|\r\n]", function(ch)
		return if ch == "|" then "/" else " "
	end)))
end

function ledger.render(id: string, title: string, rows: { Row }): string
	local lines = { `# Spend: {id} {title}`, "", (string.gsub(ledger.HEADER, "\n$", "")) }
	for i, r in rows do
		table.insert(
			lines,
			string.format(
				"| %d | %s | %s | %d | %d | %.1f | %s | %s | %s |",
				i,
				r.when,
				clean(r.subject),
				r.added,
				r.removed,
				tenths(r.minutes) / 10,
				clean(r.how),
				r.phase,
				if r.tokens then tostring(r.tokens) else ""
			)
		)
	end
	local t = ledger.sum(rows)
	table.insert(lines, "")
	table.insert(
		lines,
		string.format(
			"**Total:** +%d / -%d lines, %.1f agent-minutes, %d tokens over %d records",
			t.added,
			t.removed,
			t.minutes,
			t.tokens,
			t.records
		)
	)
	table.insert(
		lines,
		string.format(
			"<!-- totals: added=%d removed=%d minutes=%.1f records=%d tokens=%d -->",
			t.added,
			t.removed,
			t.minutes,
			t.records,
			t.tokens
		)
	)
	return table.concat(lines, "\n") .. "\n"
end

function ledger.append(text: string?, id: string, title: string, row: Row): string
	local rows: { Row } = {}
	if text then
		local l, err = ledger.parse(text)
		if not l then
			error(`spend.md does not parse: {err}`)
		end
		rows = l.rows
		if l.id ~= "" then
			id, title = l.id, l.title
		end
	end
	if not IS[row.phase] then
		error(`unknown phase {row.phase}`)
	end
	table.insert(rows, row)
	return ledger.render(id, title, rows)
end

local function same(a: Row, b: Row): boolean
	return a.when == b.when
		and a.subject == b.subject
		and a.added == b.added
		and a.removed == b.removed
		and tenths(a.minutes) == tenths(b.minutes)
		and a.how == b.how
		and a.phase == b.phase
		and a.tokens == b.tokens
end

function ledger.appendOnly(old: string?, new: string, id: string): string?
	local n, nerr = ledger.parse(new)
	if not n then
		return `the new spend.md does not parse: {nerr}`
	end
	if n.id ~= id then
		return `the spend.md title names {n.id}, not {id}`
	end
	if new ~= ledger.render(n.id, n.title, n.rows) then
		return "the new spend.md is not in the ledger's own form (rows, numbering or totals)"
	end
	local before = 0
	if old then
		local o, oerr = ledger.parse(old)
		if not o then
			return `spend.md on origin/main does not parse ({oerr}); fix it by pull request`
		end
		if o.id ~= "" and (o.id ~= n.id or o.title ~= n.title) then
			return "a published spend row may not change the ledger's title"
		end
		for i, r in o.rows do
			if not n.rows[i] or not same(r, n.rows[i]) then
				return `row {i} differs from origin/main: rows are only appended`
			end
		end
		before = #o.rows
	end
	if #n.rows <= before then
		return "no row was appended"
	end
	return nil
end

return ledger
