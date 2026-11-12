--!strict
-- The pure format of spend.md (c0084): nine columns, rows only appended. A tenth column, the model id, appears only
-- when some row records one (c0117): a file with no model row keeps the nine-column header. A measured row (the tool
-- wrote it) adds wall, cpu, ai and test seconds. An old 7-, 9- or 10-cell file still parses; its minutes are reported
-- time, kept apart from the measured cells. `unmeasured` in a measured cell means the tool looked and found nothing.
local ledger = {}

ledger.PHASES = { "capture", "prep", "design-review", "build", "code-review", "deliver" }
-- Measured rows also use these. They are not part of the lifecycle list the board and the old reports walk.
ledger.EXTRA = { "test", "other" }
local IS: { [string]: boolean } = {}
for _, p in ledger.PHASES do
	IS[p] = true
end
for _, p in ledger.EXTRA do
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
	model: string?,
	wall: number?,
	cpu: number?,
	ai: number?,
	test: number?,
	-- comma-separated cell names whose text was the word unmeasured (ai, tokens, wall, cpu, test)
	unmeasured: string?,
}
export type Totals = { added: number, removed: number, minutes: number, records: number, tokens: number }
export type Ledger = { id: string, title: string, rows: { Row } }

ledger.HEADER = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n"
	.. "|---|---|---|---|---|---|---|---|---|\n"
-- the header once any row records the model that spent its tokens (c0117)
ledger.HEADER_MODEL = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model |\n"
	.. "|---|---|---|---|---|---|---|---|---|---|\n"
ledger.HEADER_MEASURED = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens | model | wall | cpu | ai | test |\n"
	.. "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"

-- A model id as spend.md stores it: letters, digits, dots, dashes and underscores (no cell separator or space).
function ledger.isModel(s: string): boolean
	return string.match(s, "^[%w][%w%._%-]*$") ~= nil
end

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
		if #c ~= 7 and #c ~= 9 and #c ~= 10 and #c ~= 14 then
			return nil, `not a spend row (7, 9, 10 or 14 cells): {line}`
		end
		local n, added, removed = count(c[1]), count(c[4]), count(c[5])
		local minutes = if string.match(c[6], "^%d+%.?%d*$") then tonumber(c[6]) else nil
		if not minutes and #c == 14 and c[6] == "" then
			minutes = 0
		end
		if not n or not added or not removed or not minutes then
			return nil, `not a spend row (numbers): {line}`
		end
		if not string.match(c[2], "^%d%d%d%d%-%d%d%-%d%d") then
			return nil, `not a spend row (when): {line}`
		end
		local phase = if #c >= 9 then c[8] else "build"
		if not IS[phase] then
			return nil, `unknown phase {phase}: {line}`
		end
		local tokens: number? = nil
		local flags: { string } = {}
		if #c >= 9 and c[9] ~= "" then
			if c[9] == "unmeasured" then
				table.insert(flags, "tokens")
			else
				tokens = count(c[9])
				if not tokens then
					return nil, `not a spend row (tokens): {line}`
				end
			end
		end
		local model: string? = nil
		if (#c == 10 or #c == 14) and c[10] ~= "" then
			if not ledger.isModel(c[10]) then
				return nil, `not a spend row (model): {line}`
			end
			model = c[10]
		end
		local wall: number? = nil
		local cpu: number? = nil
		local ai: number? = nil
		local test: number? = nil
		if #c == 14 then
			local function seconds(cell: string, name: string): (number?, string?)
				if cell == "" then
					return nil, nil
				end
				if cell == "unmeasured" then
					table.insert(flags, name)
					return nil, nil
				end
				if not string.match(cell, "^%d+%.?%d*$") then
					return nil, `not a spend row ({name}): {line}`
				end
				return tonumber(cell), nil
			end
			local err: string? = nil
			wall, err = seconds(c[11], "wall")
			if err then
				return nil, err
			end
			cpu, err = seconds(c[12], "cpu")
			if err then
				return nil, err
			end
			ai, err = seconds(c[13], "ai")
			if err then
				return nil, err
			end
			test, err = seconds(c[14], "test")
			if err then
				return nil, err
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
			model = model,
			wall = wall,
			cpu = cpu,
			ai = ai,
			test = test,
			unmeasured = if #flags > 0 then table.concat(flags, ",") else nil,
		})
	end
	return out
end

local function hasFlag(r: Row, name: string): boolean
	return r.unmeasured ~= nil and string.find(`,{r.unmeasured},`, `,{name},`, 1, true) ~= nil
end

local function measuredRow(r: Row): boolean
	return r.wall ~= nil or r.cpu ~= nil or r.ai ~= nil or r.test ~= nil or r.unmeasured ~= nil
end

export type Cost = {
	reported: number,
	wall: number,
	cpu: number,
	ai: number,
	test: number,
	tokens: number,
	n: number,
	aiOpen: boolean,
	tokensOpen: boolean,
}

-- Reported minutes are the typed ones (a row the tool measured does not add its minutes here). Wall, cpu, ai and
-- test are the measured seconds. A cell the tool could not read sets the matching *Open flag and adds nothing.
function ledger.cost(rows: { Row }): Cost
	local c: Cost = {
		reported = 0,
		wall = 0,
		cpu = 0,
		ai = 0,
		test = 0,
		tokens = 0,
		n = #rows,
		aiOpen = false,
		tokensOpen = false,
	}
	local rep = 0
	for _, r in rows do
		if not measuredRow(r) then
			rep += tenths(r.minutes)
		end
		c.wall += r.wall or 0
		c.cpu += r.cpu or 0
		c.ai += r.ai or 0
		c.test += r.test or 0
		c.tokens += r.tokens or 0
		if hasFlag(r, "ai") then
			c.aiOpen = true
		end
		if hasFlag(r, "tokens") then
			c.tokensOpen = true
		end
	end
	c.reported = rep / 10
	return c
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

export type ModelTotals = {
	model: string,
	tokens: number,
	aiMinutes: number, -- the measured AI time (ai seconds, else wall seconds) in minutes: what spend.d rows carry
	typedMinutes: number, -- the typed minutes of the older rows (a measured row types none)
	unmeasured: number, -- rows whose AI time the tool could not read
	records: number,
}
-- Tokens, AI minutes, typed minutes and rows per model id, rows with no model under "none", the biggest spender (tokens)
-- first (c0261). The cost helper `ledger.cost` sums each model's rows (tokens and typed minutes); the measured time is
-- the row's ai seconds, falling back to its wall seconds.
function ledger.byModel(rows: { Row }): { ModelTotals }
	local groups: { [string]: { Row } } = {}
	for _, r in rows do
		local k = r.model or "none"
		groups[k] = groups[k] or {}
		table.insert(groups[k], r)
	end
	local out: { ModelTotals } = {}
	for model, group in groups do
		local c = ledger.cost(group)
		local seconds, open = 0, 0
		for _, r in group do
			local s = r.ai or r.wall
			if s ~= nil then
				seconds += s
			elseif hasFlag(r, "ai") then
				open += 1
			end
		end
		table.insert(out, {
			model = model,
			tokens = c.tokens,
			aiMinutes = seconds / 60,
			typedMinutes = c.reported,
			unmeasured = open,
			records = #group,
		})
	end
	table.sort(out, function(a, b)
		if a.tokens ~= b.tokens then
			return a.tokens > b.tokens
		end
		return a.model < b.model
	end)
	return out
end

-- The table `./zn metrics` prints last. A model whose AI time could not be read on some rows shows "+?" after what was
-- read, and "unmeasured" when none was.
function ledger.renderByModel(totals: { ModelTotals }): string
	local lines = {
		"by model",
		"| model | tokens | ai minutes | typed minutes | rows |",
		"|---|---|---|---|---|",
	}
	for _, e in totals do
		local ai = string.format("%.1f", e.aiMinutes)
		if e.unmeasured > 0 then
			ai = if e.aiMinutes == 0 then "unmeasured" else ai .. "+?"
		end
		table.insert(
			lines,
			string.format("| %s | %d | %s | %.1f | %d |", e.model, e.tokens, ai, e.typedMinutes, e.records)
		)
	end
	return table.concat(lines, "\n") .. "\n"
end

function ledger.byPhase(rows: { Row }): { [string]: Totals }
	local groups: { [string]: { Row } } = {}
	for _, p in ledger.PHASES do
		groups[p] = {}
	end
	for _, r in rows do
		if not groups[r.phase] then
			groups[r.phase] = {}
		end
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

local function secondsCell(r: Row, name: string, n: number?): string
	if hasFlag(r, name) then
		return "unmeasured"
	end
	if n == nil then
		return ""
	end
	return string.format("%.3f", n)
end

local function tokensCell(r: Row): string
	if hasFlag(r, "tokens") then
		return "unmeasured"
	end
	return if r.tokens then tostring(r.tokens) else ""
end

function ledger.render(id: string, title: string, rows: { Row }): string
	local withModel = false
	local withMeasured = false
	for _, r in rows do
		if r.model then
			withModel = true
		end
		if measuredRow(r) then
			withMeasured = true
		end
	end
	local header = if withMeasured
		then ledger.HEADER_MEASURED
		elseif withModel then ledger.HEADER_MODEL
		else ledger.HEADER
	local lines = { `# Spend: {id} {title}`, "", (string.gsub(header, "\n$", "")) }
	for i, r in rows do
		local base = string.format(
			"| %d | %s | %s | %d | %d | %.1f | %s | %s | %s |",
			i,
			r.when,
			clean(r.subject),
			r.added,
			r.removed,
			tenths(r.minutes) / 10,
			clean(r.how),
			r.phase,
			tokensCell(r)
		)
		if withMeasured then
			base ..= string.format(
				" %s | %s | %s | %s | %s |",
				r.model or "",
				secondsCell(r, "wall", r.wall),
				secondsCell(r, "cpu", r.cpu),
				secondsCell(r, "ai", r.ai),
				secondsCell(r, "test", r.test)
			)
		elseif withModel then
			base ..= ` {r.model or ""} |`
		end
		table.insert(lines, base)
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
	if row.model and not ledger.isModel(row.model) then
		error(`not a model id: {row.model}`)
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
		and a.model == b.model
		and a.wall == b.wall
		and a.cpu == b.cpu
		and a.ai == b.ai
		and a.test == b.test
		and a.unmeasured == b.unmeasured
end

-- True when every row of `prefix` is field-equal to the same position in `rows` (minutes in tenths,
-- tokens nil distinct from 0). An empty prefix extends anything.
function ledger.extends(prefix: { Row }, rows: { Row }): boolean
	if #prefix > #rows then
		return false
	end
	for i, r in prefix do
		local got = rows[i]
		if not got or not same(r, got) then
			return false
		end
	end
	return true
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
