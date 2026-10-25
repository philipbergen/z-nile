--!strict
-- Spend accounting: per-issue spend.md rows written into the same commit they describe.
-- Lines come from the staged diff (every project root excluded; on the done commit also the promoted
-- tests/acceptance/ specs, which are prep work). Minutes are explicit (--time) or the
-- wall-clock since the previous commit, capped to absorb idle gaps; multi-issue commits split
-- minutes in proportion to lines added.
local fs = require("@lune/fs")
local ledger = require("./ledger")
local projects = require("./projects")
local sh = require("../lib/sh")
local store = require("./store")

local spend = {}

spend.IDLE_CAP_MINUTES = 45

export type Share = {
	id: string,
	added: number,
	removed: number,
	minutes: number,
	how: string,
	tokens: number?,
}
export type Totals = { added: number, removed: number, minutes: number, records: number, tokens: number }

type FileStat = { path: string, added: number, removed: number }

-- `excludeAcceptance`: on the done commit, promoted acceptance specs (prep work) are not spend.
function spend.stagedStats(excludeAcceptance: boolean?): { FileStat }
	local out: { FileStat } = {}
	-- every project root's documents are tracker state, not code (c0114)
	local args = { "diff", "--cached", "--numstat", "--", "." }
	for _, r in store.roots() do
		table.insert(args, `:(exclude){r}`)
	end
	if excludeAcceptance then
		-- every project's promoted specs (c0120: pickman's are pickman/tests/acceptance)
		for _, a in projects.acceptanceRoots(projects.load()) do
			table.insert(args, `:(exclude){a}`)
		end
	end
	local text = sh.git(args)
	for line in string.gmatch(text, "[^\n]+") do
		local a, r, path = string.match(line, "^(%S+)\t(%S+)\t(.+)$")
		if a and r and path then
			table.insert(out, { path = path, added = tonumber(a) or 0, removed = tonumber(r) or 0 })
		end
	end
	return out
end

-- Paths an issue claims in its "Touched modules" section (backticked, one per bullet).
function spend.ownedPaths(issue: store.Item): { string }
	local text = string.gsub(fs.readFile(issue.doc), "<!%-%-.-%-%->", "")
	local section = string.match(text, "\n#+%s*Touched modules[^\n]*\n(.-)\n#") or ""
	local out: { string } = {}
	for path in string.gmatch(section, "`([^`]+)`") do
		if string.find(path, "/", 1, true) then
			table.insert(out, (string.gsub(path, "%s+.*$", "")))
		end
	end
	return out
end

-- Wall-clock minutes since the last commit on this branch, capped.
function spend.elapsedMinutes(): number
	local last = tonumber(sh.git({ "log", "-1", "--format=%ct" })) or os.time()
	local minutes = (os.time() - last) / 60
	return math.min(spend.IDLE_CAP_MINUTES, math.max(0, minutes))
end

local function round1(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

-- The prep branch's own lines: each member's check.sh, acceptance/ and experiments/, plus the raft's
-- check.sh when `raft` is given. A missing path is ignored. The owner map is each member's directory;
-- the raft check.sh is unowned, so attribute splits it evenly.
function spend.prepStats(items: { store.Item }, raft: store.Item?): ({ FileStat }, { [string]: { string } })
	local owners: { [string]: { string } } = {}
	local paths: { string } = {}
	for _, issue in items do
		owners[issue.id] = { issue.dir }
		table.insert(paths, `{issue.dir}/check.sh`)
		table.insert(paths, `{issue.dir}/acceptance`)
		table.insert(paths, `{issue.dir}/experiments`)
	end
	if raft then
		table.insert(paths, `{raft.dir}/check.sh`)
	end
	local out: { FileStat } = {}
	for _, path in paths do
		local r = sh.run("git", { "diff", "--numstat", "origin/main...HEAD", "--", path })
		if r.ok then
			for line in string.gmatch(r.stdout, "[^\n]+") do
				local a, removed, p = string.match(line, "^(%S+)\t(%S+)\t(.+)$")
				if a and removed and p then
					table.insert(
						out,
						{ path = p, added = tonumber(a) or 0, removed = tonumber(removed) or 0 }
					)
				end
			end
		end
	end
	return out, owners
end

-- Split lines, minutes and optional tokens across issues.
-- `how` is "explicit" | "focus" | "raft" | "spend" (who picked the issues); per-file ownership refines it.
-- `owners`, when given, replaces the Touched-modules prefixes. Tokens, when given, split like minutes and
-- sum exactly (largest remainder; equal fractions go to the smaller id). Minutes stay rounded to tenths.
function spend.attribute(
	issues: { store.Item },
	stats: { FileStat },
	minutes: number,
	how: string,
	tokens: number?,
	owners: { [string]: { string } }?
): { Share }
	local shares: { [string]: Share } = {}
	local order: { string } = {}
	for _, issue in issues do
		shares[issue.id] = { id = issue.id, added = 0, removed = 0, minutes = 0, how = how }
		table.insert(order, issue.id)
	end
	local owned: { [string]: { string } } = {}
	if owners then
		for _, issue in issues do
			owned[issue.id] = owners[issue.id] or {}
		end
	elseif #issues > 1 then
		for _, issue in issues do
			owned[issue.id] = spend.ownedPaths(issue)
		end
	end
	for _, stat in stats do
		local who: { string } = {}
		if #issues > 1 then
			for _, id in order do
				for _, prefix in owned[id] do
					if string.sub(stat.path, 1, #prefix) == prefix then
						table.insert(who, id)
						break
					end
				end
			end
		end
		if #who == 0 then
			who = order
		end
		for _, id in who do
			shares[id].added += stat.added / #who
			shares[id].removed += stat.removed / #who
		end
	end
	local totalAdded = 0
	for _, id in order do
		totalAdded += shares[id].added
	end
	-- Round with the largest-remainder method so per-issue lines sum exactly to the diff.
	local function apportion(field: string, total: number)
		local floors, rest = 0, {}
		for _, id in order do
			local v = (shares[id] :: any)[field]
			floors += math.floor(v)
			table.insert(rest, { id = id, frac = v - math.floor(v) });
			(shares[id] :: any)[field] = math.floor(v)
		end
		table.sort(rest, function(a, b)
			return if a.frac == b.frac then a.id < b.id else a.frac > b.frac
		end)
		for i = 1, total - floors do
			local id = rest[i].id;
			(shares[id] :: any)[field] += 1
		end
	end
	local sumAdded, sumRemoved = 0, 0
	for _, stat in stats do
		sumAdded += stat.added
		sumRemoved += stat.removed
	end
	local tokenParts: { { id: string, frac: number } } = {}
	local tokenFloors = 0
	for _, id in order do
		local s = shares[id]
		local weight = if totalAdded > 0 then s.added / totalAdded else 1 / #order
		s.minutes = round1(minutes * weight)
		if tokens ~= nil then
			local exact = tokens * weight
			local fl = math.floor(exact)
			tokenFloors += fl
			s.tokens = fl
			table.insert(tokenParts, { id = id, frac = exact - fl })
		end
	end
	if tokens ~= nil then
		table.sort(tokenParts, function(a, b)
			return if a.frac == b.frac then a.id < b.id else a.frac > b.frac
		end)
		for i = 1, tokens - tokenFloors do
			local id = tokenParts[i].id
			shares[id].tokens = (shares[id].tokens or 0) + 1
		end
	end
	apportion("added", sumAdded)
	apportion("removed", sumRemoved)
	local out: { Share } = {}
	for _, id in order do
		local s = shares[id]
		if #order > 1 and how ~= "explicit" then
			s.how = `{how}+proportional`
		end
		table.insert(out, s)
	end
	return out
end

function spend.readTotals(dir: string): Totals
	local path = `{dir}/spend.md`
	if not fs.isFile(path) then
		return { added = 0, removed = 0, minutes = 0, records = 0, tokens = 0 }
	end
	local parsed, err = ledger.parse(fs.readFile(path))
	if not parsed then
		error(`{path} does not parse: {err}`, 0)
	end
	return ledger.sum(parsed.rows)
end

function spend.appendRow(issue: store.Item, share: Share, subject: string, phase: string?)
	local path = `{issue.dir}/spend.md`
	local existing = if fs.isFile(path) then fs.readFile(path) else nil
	local title = store.readFront(issue.doc).title or issue.id
	local row: ledger.Row = {
		when = os.date("!%Y-%m-%d %H:%M", os.time()) :: string,
		subject = subject,
		added = share.added,
		removed = share.removed,
		minutes = share.minutes,
		how = share.how,
		phase = phase or "build",
		tokens = share.tokens,
	}
	fs.writeFile(path, ledger.append(existing, issue.id, title, row))
end

-- Raft spend.md: a summary over every issue that names this raft (members and emergent), plus each
-- phase that has records. A snapshot written by commit and done; metrics reads the members.
function spend.writeRaft(raft: store.Item)
	local lines = {
		`# Spend: {raft.id} {store.readFront(raft.doc).title or ""}`,
		"",
		"| issue | type | emergent | +lines | -lines | minutes | tokens |",
		"|---|---|---|---|---|---|---|",
	}
	local all: { ledger.Row } = {}
	for _, issue in store.members(raft.id) do
		local path = `{issue.dir}/spend.md`
		local rows: { ledger.Row } = {}
		if fs.isFile(path) then
			local parsed, err = ledger.parse(fs.readFile(path))
			if not parsed then
				error(`{path} does not parse: {err}`, 0)
			end
			rows = parsed.rows
		end
		local t = ledger.sum(rows)
		local emergent = store.readFront(issue.doc).emergent == "true"
		table.insert(
			lines,
			string.format(
				"| %s | %s | %s | %d | %d | %.1f | %d |",
				issue.id,
				store.typeOf(issue),
				if emergent then "yes" else "",
				t.added,
				t.removed,
				t.minutes,
				t.tokens
			)
		)
		for _, row in rows do
			table.insert(all, row)
		end
	end
	local sum = ledger.sum(all)
	table.insert(
		lines,
		string.format(
			"\n**Total:** +%d / -%d lines, %.1f agent-minutes, %d tokens over %d records",
			sum.added,
			sum.removed,
			sum.minutes,
			sum.tokens,
			sum.records
		)
	)
	table.insert(
		lines,
		string.format(
			"<!-- totals: added=%d removed=%d minutes=%.1f records=%d tokens=%d -->",
			sum.added,
			sum.removed,
			sum.minutes,
			sum.records,
			sum.tokens
		)
	)
	table.insert(lines, "")
	table.insert(lines, "| phase | +lines | -lines | minutes | tokens |")
	table.insert(lines, "|---|---|---|---|---|")
	local by = ledger.byPhase(all)
	for _, phase in ledger.PHASES do
		local t = by[phase]
		if t.records > 0 then
			table.insert(
				lines,
				string.format("| %s | %d | %d | %.1f | %d |", phase, t.added, t.removed, t.minutes, t.tokens)
			)
		end
	end
	fs.writeFile(`{raft.dir}/spend.md`, table.concat(lines, "\n") .. "\n")
end

return spend
