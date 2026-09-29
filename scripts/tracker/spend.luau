--!strict
-- Spend accounting: per-issue spend.md rows written into the same commit they describe.
-- Lines come from the staged diff (tracker/ and promoted tests/acceptance/ excluded: prep work). Minutes are explicit (--time) or the
-- wall-clock since the previous commit, capped to absorb idle gaps; multi-issue commits split
-- minutes in proportion to lines added.
local fs = require("@lune/fs")
local sh = require("../lib/sh")
local store = require("./store")

local spend = {}

spend.IDLE_CAP_MINUTES = 45

export type Share = { id: string, added: number, removed: number, minutes: number, how: string }
export type Totals = { added: number, removed: number, minutes: number, commits: number }

type FileStat = { path: string, added: number, removed: number }

function spend.stagedStats(): { FileStat }
	local out: { FileStat } = {}
	local text = sh.git({
		"diff",
		"--cached",
		"--numstat",
		"--",
		".",
		":(exclude)tracker",
		":(exclude)tests/acceptance",
	})
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

-- Split staged lines and the given minutes across issues.
-- `how` is "explicit" | "focus" | "raft" (who picked the issues); per-file ownership refines it.
function spend.attribute(issues: { store.Item }, stats: { FileStat }, minutes: number, how: string): { Share }
	local shares: { [string]: Share } = {}
	local order: { string } = {}
	for _, issue in issues do
		shares[issue.id] = { id = issue.id, added = 0, removed = 0, minutes = 0, how = how }
		table.insert(order, issue.id)
	end
	local owned: { [string]: { string } } = {}
	for _, issue in issues do
		owned[issue.id] = spend.ownedPaths(issue)
	end
	for _, stat in stats do
		local owners: { string } = {}
		if #issues > 1 then
			for _, id in order do
				for _, prefix in owned[id] do
					if string.sub(stat.path, 1, #prefix) == prefix then
						table.insert(owners, id)
						break
					end
				end
			end
		end
		if #owners == 0 then
			owners = order
		end
		for _, id in owners do
			shares[id].added += stat.added / #owners
			shares[id].removed += stat.removed / #owners
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
	local out: { Share } = {}
	for _, id in order do
		local s = shares[id]
		local weight = if totalAdded > 0 then s.added / totalAdded else 1 / #order
		s.minutes = round1(minutes * weight)
	end
	apportion("added", sumAdded)
	apportion("removed", sumRemoved)
	for _, id in order do
		local s = shares[id]
		if #order > 1 and how ~= "explicit" then
			s.how = `{how}+proportional`
		end
		table.insert(out, s)
	end
	return out
end

local HEADER =
	"| # | when | commit | +lines | -lines | minutes | attribution |\n|---|---|---|---|---|---|---|\n"

function spend.readTotals(dir: string): Totals
	local path = `{dir}/spend.md`
	local t: Totals = { added = 0, removed = 0, minutes = 0, commits = 0 }
	if not fs.isFile(path) then
		return t
	end
	local text = fs.readFile(path)
	local a, r, m, c =
		string.match(text, "<!%-%- totals: added=(%d+) removed=(%d+) minutes=([%d%.]+) commits=(%d+) %-%->")
	if a and r and m and c then
		t.added, t.removed, t.minutes, t.commits =
			tonumber(a) :: number, tonumber(r) :: number, tonumber(m) :: number, tonumber(c) :: number
	end
	return t
end

local function totalsLine(t: Totals): string
	return string.format(
		"\n**Total:** +%d / -%d lines, %.1f agent-minutes over %d commits\n<!-- totals: added=%d removed=%d minutes=%.1f commits=%d -->\n",
		t.added,
		t.removed,
		t.minutes,
		t.commits,
		t.added,
		t.removed,
		t.minutes,
		t.commits
	)
end

function spend.appendRow(issue: store.Item, share: Share, subject: string)
	local path = `{issue.dir}/spend.md`
	local t = spend.readTotals(issue.dir)
	local rows = ""
	if fs.isFile(path) then
		rows = string.match(fs.readFile(path), "|%-%-%-|[^\n]*\n(.-)\n+%*%*Total") or ""
		rows = string.gsub(rows, "%s+$", "")
		if rows ~= "" then
			rows ..= "\n"
		end
	end
	t.added += share.added
	t.removed += share.removed
	t.minutes = round1(t.minutes + share.minutes)
	t.commits += 1
	local safeSubject = string.gsub(subject, "|", "/")
	rows ..= string.format(
		"| %d | %s | %s | %d | %d | %.1f | %s |\n",
		t.commits,
		os.date("!%Y-%m-%d %H:%M", os.time()),
		safeSubject,
		share.added,
		share.removed,
		share.minutes,
		share.how
	)
	local title = store.readFront(issue.doc).title or issue.id
	fs.writeFile(path, `# Spend: {issue.id} {title}\n\n{HEADER}{rows}{totalsLine(t)}`)
end

-- Raft spend.md: a summary table over every issue that names this raft (members and emergent).
function spend.writeRaft(raft: store.Item)
	local lines = {
		`# Spend: {raft.id} {store.readFront(raft.doc).title or ""}`,
		"",
		"| issue | type | emergent | +lines | -lines | minutes | commits |",
		"|---|---|---|---|---|---|---|",
	}
	local sum: Totals = { added = 0, removed = 0, minutes = 0, commits = 0 }
	for _, issue in store.members(raft.id) do
		local t = spend.readTotals(issue.dir)
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
				t.commits
			)
		)
		sum.added += t.added
		sum.removed += t.removed
		sum.minutes = round1(sum.minutes + t.minutes)
		sum.commits = math.max(sum.commits, t.commits)
	end
	fs.writeFile(`{raft.dir}/spend.md`, table.concat(lines, "\n") .. "\n" .. totalsLine(sum))
end

return spend
