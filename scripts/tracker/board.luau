--!strict
-- The tracker board: reads the tracker tree into a model and renders it as one self-contained HTML page.
local chart = require("./chart")
local fs = require("@lune/fs")
local history = require("./history")
local serde = require("@lune/serde")
local stats = require("./stats")
local store = require("./store")

local board = {}

export type Tab = "done" | "active" | "waiting"
export type Raft = {
	id: string, -- "R0040", or "none:<tab>" for a No raft entry
	kind: string, -- "raft"
	type: string, -- "feature" | "defect" | "chore" ("" for No raft)
	title: string, -- frontmatter title ("No raft" for the pseudo entries)
	state: string, -- "backlog" | "active" | "done", from the directory ("" for No raft)
	design: string, -- frontmatter design ("" if absent)
	status: string, -- "done" | "active" | "ready" | "reviewed" | "draft" ("" for No raft)
	single: boolean,
	pseudo: boolean, -- true only for No raft entries
	tab: Tab,
	issues: { string }, -- member issue ids, sorted
	dependsOn: { string }, -- raft ids, sorted
	dependents: { string }, -- raft ids, sorted
	blockedBy: { string }, -- unfinished dependencies: raft ids and raftless issue ids, sorted
	topLevel: boolean, -- #blockedBy == 0
	body: string, -- the document after its frontmatter ("" for No raft)
}
export type Issue = {
	id: string,
	kind: string, -- always "issue"
	type: string,
	title: string,
	state: string,
	design: string,
	status: string,
	raft: string?, -- frontmatter raft; nil when empty, absent or naming a raft that does not exist
	dependsOn: { string }, -- frontmatter depends_on ids, sorted, as written (even if they don't exist)
	emergent: boolean,
	body: string,
}
export type Model = {
	rafts: { Raft }, -- real rafts sorted by id, then No raft entries in done, active, waiting order
	issues: { Issue }, -- sorted by id
	tabs: { done: { string }, active: { string }, waiting: { string } },
	home: { [string]: string }, -- every raft and issue id -> the id of the entry whose pane shows it
	initialTab: Tab, -- "active" if tabs.active is non-empty, else "waiting"
	stats: stats.Stats,
}

board.MARKED_PATH = "scripts/vendor/marked.umd.js"
board.MARKED_SHA256 = "21568877a938d2c4e7d74e27f18e60da96bb73a68809610ca39216e1efebae62"
board.TEMPLATE_PATH = "scripts/tracker/board.html"

-- Errors unless the vendored marked is the pinned build.
function board.checkMarked(js: string)
	local got = serde.hash("sha256", js)
	if got ~= board.MARKED_SHA256 then
		error(
			`{board.MARKED_PATH} is not the pinned marked build (sha256 {got}, expected {board.MARKED_SHA256})`,
			0
		)
	end
end

-- marked without its trailing source-map comment, so a browser never fetches marked.umd.js.map.
function board.inlineMarked(js: string): string
	return (string.gsub(js, "\n//# sourceMappingURL=[^\n]*\n?$", "\n"))
end

local TAB_OF_STATE: { [string]: Tab } = { done = "done", active = "active", backlog = "waiting" }
local TAB_ORDER: { Tab } = { "done", "active", "waiting" }
local TYPES: { [string]: boolean } = { feature = true, defect = true, chore = true }

-- Every %w+ run of a frontmatter list like "[f0100, c0090]", sorted.
local function listOf(value: string?): { string }
	local out: { string } = {}
	for id in string.gmatch(value or "", "%w+") do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for k in set do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- The document after its frontmatter, without leading blank lines; a document without frontmatter is all body.
local function bodyOf(text: string): string
	if string.sub(text, 1, 4) ~= "---\n" then
		return text
	end
	local _, closeEnd = string.find(text, "\n%-%-%-[^\n]*", 4)
	if not closeEnd then
		return text
	end
	return (string.gsub(string.sub(text, closeEnd + 1), "^\n+", ""))
end

-- { id, state, front, body } for every item directory of one kind under root.
local function scan(
	root: string,
	kind: string
): { { id: string, state: string, front: { [string]: string }, body: string } }
	local found = {}
	local base = `{root}/{kind}`
	local function isId(name: string): boolean
		return if kind == "rafts" then store.isRaftId(name) else store.isIssueId(name)
	end
	for _, state in { "backlog", "active", "done" } do
		local dir = if state == "backlog" then base else `{base}/{state}`
		if not fs.isDir(dir) then
			continue
		end
		for _, name in fs.readDir(dir) do
			local doc = `{dir}/{name}/{name}.md`
			if isId(name) and fs.isFile(doc) then
				table.insert(found, {
					id = name,
					state = state,
					front = store.readFront(doc),
					body = bodyOf(fs.readFile(doc)),
				})
			end
		end
	end
	table.sort(found, function(a, b)
		return a.id < b.id
	end)
	return found
end

local function statusOf(state: string, design: string): string
	if state == "done" or state == "active" then
		return state
	end
	if design == "ready" or design == "reviewed" then
		return design
	end
	return "draft"
end

local VIEWS = { "month", "quarter", "year" }
local TYPE_ORDER = { "all", "feature", "defect", "chore" }
local TYPE_LABEL = { all = "All", feature = "Feature", defect = "Defect", chore = "Chore" }
local STATES = { "new", "preparing", "prepared", "active" }
local MINUS = utf8.char(0x2212)
type ChartKind = "bars" | "stacked" | "mirror" | "lines" | "hbars"

local function kindOf(value: string?): stats.Kind?
	if value == "feature" then
		return "feature"
	elseif value == "defect" then
		return "defect"
	elseif value == "chore" then
		return "chore"
	end
	return nil
end

local function dayOf(value: string?): string?
	return if value then string.match(value, "^(%d%d%d%d%-%d%d%-%d%d)") else nil
end

local function parentOf(dir: string): string
	local parent = string.match(dir, "^(.*)/[^/]+$")
	if not parent or parent == "" then
		return "."
	end
	return parent
end

local function spendPath(root: string, state: string, id: string): string
	if state == "backlog" then
		return `{root}/issues/{id}/spend.md`
	end
	return `{root}/issues/{state}/{id}/spend.md`
end

local function cellsOf(line: string): { string }
	local out: { string } = {}
	for cell in string.gmatch(line, "|([^|]*)") do
		table.insert(out, (string.gsub(cell, "^%s*(.-)%s*$", "%1")))
	end
	return out
end

-- Spend rows share the seven-column shape. Extra columns, if a later ledger adds them, are ignored.
local function readSpend(path: string): { { day: string, added: number, removed: number, minutes: number } }
	local out = {}
	if not fs.isFile(path) then
		return out
	end
	for line in string.gmatch(fs.readFile(path), "[^\n]+") do
		if string.sub(line, 1, 1) == "|" then
			local cells = cellsOf(line)
			local day = dayOf(cells[2])
			local added, removed, minutes = tonumber(cells[4]), tonumber(cells[5]), tonumber(cells[6])
			if tonumber(cells[1]) and day and added and removed and minutes then
				table.insert(out, { day = day, added = added, removed = removed, minutes = minutes })
			end
		end
	end
	return out
end

local function statistics(
	root: string,
	rawIssues: { { id: string, state: string, front: { [string]: string }, body: string } }
): stats.Stats
	local hist = history.read(parentOf(root))
	local items: { stats.Item } = {}
	local spends: { stats.Spend } = {}
	local latest = ""
	local function consider(day: string?)
		if day and day > latest then
			latest = day
		end
	end
	for _, raw in rawIssues do
		local kind = kindOf(raw.front.type)
		-- kindOf's singleton return is widened to string at the boundary; narrow it back.
		if kind == "feature" or kind == "defect" or kind == "chore" then
			local opened = dayOf(raw.front.created) or ""
			consider(if opened ~= "" then opened else nil)
			local closed: string? = nil
			local spells: { stats.Spell } = {}
			if hist then
				closed = hist.closed[raw.id]
				spells = hist.spells[raw.id] or {}
			end
			table.insert(
				items,
				{ id = raw.id, type = kind, opened = opened, closed = closed, spells = spells }
			)
			for _, row in readSpend(spendPath(root, raw.state, raw.id)) do
				consider(row.day)
				table.insert(spends, {
					id = raw.id,
					type = kind,
					day = row.day,
					added = row.added,
					removed = row.removed,
					minutes = row.minutes,
				})
			end
		end
	end
	local today = if hist and hist.today and hist.today ~= "" then hist.today else latest
	local out = stats.compute(items, spends, today, hist ~= nil)
	if not hist then
		out.durations = {}
	end
	return out
end

local function labelsOf(rows: { stats.Row }): { string }
	local labels: { string } = {}
	for _, row in rows do
		table.insert(labels, row.bucket.label)
	end
	return labels
end

local function column(rows: { stats.Row }, metric: string, ty: string): { number? }
	local values: { number? } = table.create(#rows)
	for i, row in rows do
		local counts = (row :: any)[metric] :: stats.Counts
		values[i] = (counts :: any)[ty]
	end
	return values
end

local function typeSeries(rows: { stats.Row }, metric: string, ty: string, label: string?): { chart.Series }
	if ty == "all" then
		return {
			{ key = "feature", label = "Feature", values = column(rows, metric, "feature") },
			{ key = "defect", label = "Defect", values = column(rows, metric, "defect") },
			{ key = "chore", label = "Chore", values = column(rows, metric, "chore") },
		}
	end
	return { { key = ty, label = label or TYPE_LABEL[ty], values = column(rows, metric, ty) } }
end

local function hiddenAttr(view: string, ty: string): string
	if (view == "month" or view == "all") and (ty == "all" or ty == "any") then
		return ""
	end
	return " hidden"
end

local function figure(
	id: string,
	view: string,
	ty: string,
	caption: string,
	series: { chart.Series },
	opts: chart.Options
): string
	opts.id = id
	opts.labels = opts.labels
	local svg = chart.svg(series, opts)
	return `<figure class="chart-fig" data-view="{view}" data-type="{ty}"{hiddenAttr(view, ty)}>{svg}<figcaption>{caption}</figcaption></figure>`
end

local function num(n: number?): string
	if n == nil then
		return ""
	end
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.1f", n)
end

local function num2(n: number?): string
	if n == nil then
		return ""
	end
	return string.format("%.2f", n)
end

local function viewTable(title: string, rows: { stats.Row }): string
	local body: { string } = {}
	for _, row in rows do
		table.insert(
			body,
			`<tr><td>{row.bucket.label}</td><td>{row.opened.all}</td><td>{row.closed.all}</td><td>{row.net.all}</td><td>{num(
				row.minutes.all
			)}</td><td>{row.added.all}</td><td>{row.removed.all}</td><td>{row.netLines.all}</td></tr>`
		)
	end
	return `<table><caption>{title}</caption><thead><tr><th>bucket</th><th>opened</th><th>closed</th><th>net</th><th>minutes</th><th>+lines</th><th>{MINUS}lines</th><th>net lines</th></tr></thead><tbody>{table.concat(
		body
	)}</tbody></table>`
end

local function pct(n: number?): string
	if n == nil then
		return ""
	end
	return `{num(n)}%`
end

local function periodsTable(
	periods: { week: stats.Row, month: stats.Row, quarter: stats.Row, year: stats.Row }?
): string
	local body: { string } = {}
	if periods then
		for _, name in { "week", "month", "quarter", "year" } do
			local row = (periods :: any)[name] :: stats.Row
			for _, ty in TYPE_ORDER do
				local ratios = if ty == "all"
					then `<td>{pct(row.ratios.defectCount)}</td><td>{pct(row.ratios.defectTime)}</td><td>{pct(
						row.ratios.choreCount
					)}</td><td>{pct(row.ratios.choreTime)}</td>`
					else "<td></td><td></td><td></td><td></td>"
				table.insert(
					body,
					`<tr><td>{row.bucket.label}</td><td>{TYPE_LABEL[ty]}</td><td>{(row.opened :: any)[ty]}</td><td>{(
						row.closed :: any
					)[ty]}</td><td>{num((row.minutes :: any)[ty])}</td>{ratios}</tr>`
				)
			end
		end
	end
	return `<table><caption>Periods</caption><thead><tr><th>period</th><th>type</th><th>opened</th><th>closed</th><th>minutes</th><th>defect %</th><th>defect time %</th><th>chore %</th><th>chore time %</th></tr></thead><tbody>{table.concat(
		body
	)}</tbody></table>`
end

local function durationsTable(durations: { [string]: stats.ByType }): string
	local body: { string } = {}
	for _, state in STATES do
		local by = durations[state]
		if by then
			for _, ty in { "all", "feature", "defect", "chore" } do
				local spread = (by :: any)[ty] :: stats.Spread
				table.insert(
					body,
					`<tr><td>{state}</td><td>{TYPE_LABEL[ty]}</td><td>{spread.n}</td><td>{num2(spread.mean)}</td><td>{num2(
						spread.median
					)}</td></tr>`
				)
			end
		end
	end
	return `<table><caption>Time in state</caption><thead><tr><th>state</th><th>type</th><th>n</th><th>mean days</th><th>median days</th></tr></thead><tbody>{table.concat(
		body
	)}</tbody></table>`
end

-- One line: the acceptance spec matches the stats section and the tables div without crossing a newline.
local function statsHtml(s: stats.Stats): string
	local parts: { string } = {}
	if not s.history then
		table.insert(
			parts,
			"<p>history unavailable (shallow or no git): closed and time in state are omitted</p>"
		)
	end
	if s.today == "" then
		table.insert(parts, "<p>no dated data</p>")
	end
	table.insert(
		parts,
		'<div id="stats-view"><button type="button" data-view="month" class="on">Month</button><button type="button" data-view="quarter">Quarter</button><button type="button" data-view="year">Year</button></div>'
	)
	table.insert(
		parts,
		'<div id="stats-type"><button type="button" data-type="all" class="on">All</button><button type="button" data-type="feature">Feature</button><button type="button" data-type="defect">Defect</button><button type="button" data-type="chore">Chore</button></div>'
	)
	table.insert(parts, '<button id="stats-table-toggle" type="button">Table</button>')
	local tables = {
		viewTable("Month", s.views.month),
		viewTable("Quarter", s.views.quarter),
		viewTable("Year", s.views.year),
		periodsTable(s.periods),
		durationsTable(s.durations),
	}
	table.insert(parts, `<div id="stats-tables" hidden>{table.concat(tables)}</div>`)
	for _, view in VIEWS do
		local rows = (s.views :: any)[view] :: { stats.Row }
		local labels = labelsOf(rows)
		for _, ty in TYPE_ORDER do
			local function add(
				metric: string,
				caption: string,
				series: { chart.Series },
				kind: ChartKind,
				unit: string,
				below: { chart.Series }?
			)
				table.insert(
					parts,
					figure(`{view}/{ty}/{metric}`, view, ty, caption, series, {
						id = "",
						title = caption,
						unit = unit,
						labels = labels,
						kind = kind,
						below = below,
					})
				)
			end
			add("opened", "Opened", typeSeries(rows, "opened", ty), "stacked", "issues", nil)
			add("closed", "Closed", typeSeries(rows, "closed", ty), "stacked", "issues", nil)
			add("minutes", "Minutes", typeSeries(rows, "minutes", ty), "stacked", "minutes", nil)
			add(
				"net",
				"Net issues",
				{ { key = "net", label = "Net", values = column(rows, "net", ty) } },
				"bars",
				"issues",
				nil
			)
			add(
				"lines",
				"Lines added and removed",
				typeSeries(rows, "added", ty, "Added"),
				"mirror",
				"lines",
				typeSeries(rows, "removed", ty, "Removed")
			)
		end
		local defectCount, choreCount, defectTime, choreTime = {}, {}, {}, {}
		for i, row in rows do
			defectCount[i] = row.ratios.defectCount
			choreCount[i] = row.ratios.choreCount
			defectTime[i] = row.ratios.defectTime
			choreTime[i] = row.ratios.choreTime
		end
		table.insert(
			parts,
			figure(`{view}/ratios-count`, view, "any", "Defect and chore share by count", {
				{ key = "defect", label = "Defect %", values = defectCount },
				{ key = "chore", label = "Chore %", values = choreCount },
			}, {
				id = "",
				title = "Defect and chore share by count",
				unit = "%",
				labels = labels,
				kind = "lines",
			})
		)
		table.insert(
			parts,
			figure(`{view}/ratios-time`, view, "any", "Defect and chore share by time", {
				{ key = "defect", label = "Defect %", values = defectTime },
				{ key = "chore", label = "Chore %", values = choreTime },
			}, {
				id = "",
				title = "Defect and chore share by time",
				unit = "%",
				labels = labels,
				kind = "lines",
			})
		)
	end
	local means: { [string]: { number? } } = { feature = {}, defect = {}, chore = {} }
	local notes: { [string]: { string? } } = { feature = {}, defect = {}, chore = {} }
	for i, state in STATES do
		local by = s.durations[state]
		for _, ty in { "feature", "defect", "chore" } do
			local spread = if by then (by :: any)[ty] :: stats.Spread else nil
			if spread and spread.mean ~= nil then
				means[ty][i] = spread.mean
				notes[ty][i] = `n={spread.n}`
			end
		end
	end
	table.insert(
		parts,
		figure("durations", "all", "any", "Mean days in state", {
			{ key = "feature", label = "Feature", values = means.feature, notes = notes.feature },
			{ key = "defect", label = "Defect", values = means.defect, notes = notes.defect },
			{ key = "chore", label = "Chore", values = means.chore, notes = notes.chore },
		}, {
			id = "",
			title = "Mean days in state",
			unit = "days",
			labels = STATES,
			kind = "hbars",
		})
	)
	return (string.gsub(table.concat(parts), "[\r\n]", ""))
end

function board.collect(root: string?): Model
	local base = root or store.ROOT
	local rawRafts, rawIssues = scan(base, "rafts"), scan(base, "issues")

	local raftIds: { [string]: boolean } = {}
	for _, r in rawRafts do
		raftIds[r.id] = true
	end

	local issues: { Issue } = {}
	local issueById: { [string]: Issue } = {}
	for _, i in rawIssues do
		local named = i.front.raft
		local issue: Issue = {
			id = i.id,
			kind = "issue",
			type = if TYPES[i.front.type or ""] then i.front.type else "",
			title = i.front.title or "",
			state = i.state,
			design = i.front.design or "",
			status = statusOf(i.state, i.front.design or ""),
			raft = if named and raftIds[named] then named else nil,
			dependsOn = listOf(i.front.depends_on),
			emergent = i.front.emergent == "true",
			body = i.body,
		}
		table.insert(issues, issue)
		issueById[i.id] = issue
	end

	local members: { [string]: { string } } = {}
	local loose: { [string]: { string } } = { done = {}, active = {}, waiting = {} }
	for _, issue in issues do
		if issue.raft then
			members[issue.raft] = members[issue.raft] or {}
			table.insert(members[issue.raft], issue.id)
		else
			table.insert(loose[TAB_OF_STATE[issue.state]], issue.id)
		end
	end

	local rafts: { Raft } = {}
	local raftById: { [string]: Raft } = {}
	for _, r in rawRafts do
		local raft: Raft = {
			id = r.id,
			kind = "raft",
			type = if TYPES[r.front.type or ""] then r.front.type else "",
			title = r.front.title or "",
			state = r.state,
			design = r.front.design or "",
			status = statusOf(r.state, r.front.design or ""),
			single = r.front.single == "true",
			pseudo = false,
			tab = TAB_OF_STATE[r.state],
			issues = members[r.id] or {},
			dependsOn = {},
			dependents = {},
			blockedBy = {},
			topLevel = true,
			body = r.body,
		}
		table.insert(rafts, raft)
		raftById[r.id] = raft
	end

	-- dependencies: raft -> raft through member issues, and raft -> raftless issue (blocks, never a raft dependency)
	local noRaftDependents: { [string]: { [string]: boolean } } = { done = {}, active = {}, waiting = {} }
	for _, raft in rafts do
		local deps: { [string]: boolean } = {}
		local blockers: { [string]: boolean } = {}
		for _, id in raft.issues do
			for _, dep in issueById[id].dependsOn do
				local target = issueById[dep]
				if not target then
					continue
				end
				if target.raft then
					if target.raft ~= raft.id then
						deps[target.raft] = true
					end
				else
					noRaftDependents[TAB_OF_STATE[target.state]][raft.id] = true
					if target.status ~= "done" then
						blockers[target.id] = true
					end
				end
			end
		end
		raft.dependsOn = sortedKeys(deps)
		for dep in deps do
			if raftById[dep].status ~= "done" then
				blockers[dep] = true
			end
		end
		raft.blockedBy = sortedKeys(blockers)
		raft.topLevel = #raft.blockedBy == 0
	end
	for _, raft in rafts do
		for _, dep in raft.dependsOn do
			table.insert(raftById[dep].dependents, raft.id)
		end
	end
	for _, raft in rafts do
		table.sort(raft.dependents)
	end

	-- tabs: Done and Active list every raft, Waiting only the top-level ones; each ends with its No raft entry
	local tabs =
		{ done = {}, active = {}, waiting = {} } :: { done: { string }, active: { string }, waiting: { string } }
	local pseudo: { Raft } = {}
	for _, raft in rafts do
		if raft.tab ~= "waiting" or raft.topLevel then
			table.insert(tabs[raft.tab], raft.id)
		end
	end
	local home: { [string]: string } = {}
	for _, raft in rafts do
		home[raft.id] = raft.id
		for _, id in raft.issues do
			home[id] = raft.id
		end
	end
	for _, tab: Tab in TAB_ORDER do
		if #loose[tab] == 0 then
			continue
		end
		local entry: Raft = {
			id = `none:{tab}`,
			kind = "raft",
			type = "",
			title = "No raft",
			state = "",
			design = "",
			status = "",
			single = false,
			pseudo = true,
			tab = tab,
			issues = loose[tab],
			dependsOn = {},
			dependents = sortedKeys(noRaftDependents[tab]),
			blockedBy = {},
			topLevel = true,
			body = "",
		}
		table.insert(pseudo, entry)
		table.insert(tabs[tab], entry.id)
		for _, id in entry.issues do
			home[id] = entry.id
		end
	end
	for _, entry in pseudo do
		table.insert(rafts, entry)
	end

	return {
		rafts = rafts,
		issues = issues,
		tabs = tabs,
		home = home,
		initialTab = if #tabs.active > 0 then "active" else "waiting",
		stats = statistics(base, rawIssues),
	}
end

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
	["<"] = "\\u003c",
}

local function encodeString(s: string): string
	local escaped = string.gsub(s, '[%c"\\<]', function(c: string): string
		return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
	end)
	return `"{escaped}"`
end

-- Deterministic JSON: keys sorted, empty tables as [], and < escaped so data can never end a <script>.
function board.encode(v: any): string
	local kind = typeof(v)
	if kind == "string" then
		return encodeString(v)
	elseif kind == "boolean" then
		return if v then "true" else "false"
	elseif kind == "number" then
		return tostring(v)
	elseif kind ~= "table" then
		error(`board.encode cannot write a {kind}`, 0)
	end
	local parts: { string } = {}
	if next(v) == nil then
		return "[]"
	elseif #v > 0 then
		for _, item in v do
			table.insert(parts, board.encode(item))
		end
		return `[{table.concat(parts, ",")}]`
	end
	local keys: { string } = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		table.insert(parts, `{encodeString(k)}:{board.encode(v[k])}`)
	end
	return `\{{table.concat(parts, ",")}}`
end

-- The page: the template with marked, the stats section and the model in place of its placeholders.
-- Assembled from pieces, never with gsub, so `%` or a placeholder-looking string in marked, the
-- section or the data can't be misread.
function board.render(m: Model, markedJs: string): string
	local template = fs.readFile(board.TEMPLATE_PATH)
	local markedAt, markedEnd = string.find(template, "{{MARKED}}", 1, true)
	local statsAt, statsEnd = string.find(template, "{{STATS}}", 1, true)
	local dataAt, dataEnd = string.find(template, "{{DATA}}", 1, true)
	if
		not (
			markedAt
			and markedEnd
			and statsAt
			and statsEnd
			and dataAt
			and dataEnd
			and markedEnd < statsAt
			and statsEnd < dataAt
		)
	then
		error(
			board.TEMPLATE_PATH .. " needs the MARKED, then the STATS, then the DATA placeholder, once each",
			0
		)
	end
	return table.concat({
		string.sub(template, 1, markedAt - 1),
		board.inlineMarked(markedJs),
		string.sub(template, markedEnd + 1, statsAt - 1),
		statsHtml(m.stats),
		string.sub(template, statsEnd + 1, dataAt - 1),
		board.encode(m),
		string.sub(template, dataEnd + 1),
	})
end

-- The page for the tracker under root (default: the real one), from the pinned marked.
function board.build(root: string?): string
	local markedJs = fs.readFile(board.MARKED_PATH)
	board.checkMarked(markedJs)
	return board.render(board.collect(root), markedJs)
end

return board
