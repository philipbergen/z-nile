--!strict
-- Whole-tree tracker audit: every problem, never just the first. Reads the tree with plain directory listings, so a
-- malformed tree (which store.find refuses) can still be described. See c0880.
local closing = require("./closing")
local fs = require("@lune/fs")
local ids = require("./ids")
local process = require("@lune/process")
local projects = require("./projects")
local rework = require("./rework")
local rounds = require("./rounds")
local tributaries = require("./tributaries")

export type Level = "error" | "warning"
export type Problem = { level: Level, code: string, path: string, message: string }

local audit = {}

-- The problems `list` (and every store.find caller) cannot get past.
audit.ITEM_CODES = { duplicate = true, ["no-document"] = true, ["legacy-name"] = true, ["no-slug"] = true }

local KINDS = { { dir = "issues", space = "issue" }, { dir = "rafts", space = "raft" } }
local STATES = { "", "active/", "done/", "retired/" } -- retired/: rafts recombine retired (c0116), rafts only

local function front(text: string): { [string]: string }
	local out: { [string]: string } = {}
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	if block then
		for line in string.gmatch(block, "[^\n]+") do
			local k, v = string.match(line, "^([%w_]+):%s*(.-)%s*$")
			if k and v then
				out[k] = v
			end
		end
	end
	return out
end

audit.front = front

export type Found = { id: string, path: string, kind: string }

-- The project roots of the checkout at `root` (c0114), or none and the registry's problem: never a guessed root.
local function rootsOf(root: string): ({ string }, string?)
	local ok, reg = pcall(projects.load, root)
	if not ok then
		return {}, tostring(reg)
	end
	return projects.roots(reg :: projects.Registry), nil
end

-- Every item folder under every project root (relative paths), whatever state it is in. Never throws on a malformed
-- tree.
-- The one rule for which command gives back an active issue (R0050 code review 004 F1; one rule, one function): it is
-- its raft's (`./zn stop <R-id>`) exactly when that raft is in active/ with an `active-…` claim and the issue carries
-- that claim, or is an emergent issue made on the raft's branch (it carries no claim; `done` takes it with the raft).
-- Every other active issue is given back by `./zn stop <issue>`, and audit reports it. `raftDir` and `raftStatus`
-- describe the raft the issue's `raft:` names (nil when there is none, or the value is not a raft id).
function audit.raftHolds(issueFront: { [string]: string }, raftDir: string?, raftStatus: string?): boolean
	local r = issueFront.raft or ""
	if not string.match(r, "^R%d%d%d%d$") or not raftDir then
		return false
	end
	if not string.find(raftDir .. "/", "/rafts/active/", 1, true) then
		return false
	end
	-- an emergent issue is made on its active raft's branch and carries no claim: whatever the raft's status says
	if issueFront.emergent == "true" then
		return true
	end
	return raftStatus ~= nil
		and string.match(raftStatus, "^active%-") ~= nil
		and issueFront.status == raftStatus
end

function audit.scan(root: string): { Found }
	local out: { Found } = {}
	local roots, problem = rootsOf(root)
	if problem then
		error(problem, 0) -- every reader of the items (list, offline numbering, remap) refuses without the registry
	end
	for _, base in roots do
		for _, kind in KINDS do
			for _, state in STATES do
				local rel = `{base}/{kind.dir}/{state}`
				local abs = `{root}/{rel}`
				if fs.isDir(abs) then
					for _, name in fs.readDir(abs) do
						if ids.spaceOf(name) and fs.isDir(abs .. name) then
							table.insert(out, { id = name, path = rel .. name, kind = kind.space })
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.path < b.path
	end)
	return out
end

-- The files under `dir` (relative to the checkout at `root`): the tracked ones when `root` is a repository, else every
-- file on disk. Relative paths.
local function filesUnder(root: string, dir: string): { string }
	local out: { string } = {}
	local ok, r = pcall(process.exec, "git", { "ls-files", "--", dir }, { cwd = root })
	if ok and r.ok then
		for line in string.gmatch(r.stdout, "[^\n]+") do
			table.insert(out, line)
		end
		return out
	end
	local function walk(rel: string)
		local abs = `{root}/{rel}`
		if fs.isDir(abs) then
			for _, name in fs.readDir(abs) do
				walk(`{rel}/{name}`)
			end
		elseif fs.isFile(abs) then
			table.insert(out, rel)
		end
	end
	walk(dir)
	return out
end

-- c0120: what a move between roots must never leave or bring back. A retired root holds nothing but the old counter's
-- tombstone (tracker/next); a promoted-spec folder (`<home>/tests/acceptance/<id>`) sits in the home of its item's
-- project, so a branch from before the move that re-adds one at the old place is an error.
function audit.leftovers(root: string, found: { Found }, reg: projects.Registry): { Problem }
	local out: { Problem } = {}
	for _, r in reg.retired do
		for _, f in filesUnder(root, r) do
			if f ~= ids.OLD_FILE then
				table.insert(out, {
					level = "error",
					code = "old-root",
					path = f,
					message = `{r} is a retired root: it holds nothing but {ids.OLD_FILE} (see {projects.FILE})`,
				})
			end
		end
	end
	local homeById: { [string]: string } = {}
	for _, f in found do
		homeById[f.id] = projects.homeOf(reg, f.path)
	end
	-- a finished item's acceptance/ still in its done/ folder (c0120 code review 007 F5, 008 F2): done promotes it to
	-- <home>/tests/acceptance/<id>; a copy left beside the promoted one, or specs moved back, keep their text and lose
	-- their gate
	for _, f in found do
		local acc = `{f.path}/acceptance`
		if
			string.find(f.path, "/done/", 1, true)
			and fs.isDir(`{root}/{acc}`)
			and #fs.readDir(`{root}/{acc}`) > 0
		then
			local home = homeById[f.id] or "."
			local promoted = if home == "."
				then `tests/acceptance/{f.id}`
				else `{home}/tests/acceptance/{f.id}`
			table.insert(out, {
				level = "error",
				code = "spec-not-promoted",
				path = acc,
				message = if fs.isDir(`{root}/{promoted}`)
					then `{f.id} is done: its specs are both in {acc} and promoted in {promoted}: keep the promoted ones`
					else `{f.id} is done: its specs belong in {promoted}, where done promotes them`,
			})
		end
	end
	for _, p in reg.projects do
		local acc = if p.home == "." then "tests/acceptance" else `{p.home}/tests/acceptance`
		local abs = `{root}/{acc}`
		if fs.isDir(abs) then
			for _, name in fs.readDir(abs) do
				local home = homeById[name]
				if home and home ~= p.home and fs.isDir(`{abs}/{name}`) then
					local want = if home == "." then "tests/acceptance" else `{home}/tests/acceptance`
					table.insert(out, {
						level = "error",
						code = "misplaced-spec",
						path = `{acc}/{name}`,
						message = `{name}'s project keeps its promoted specs in {want}/{name}`,
					})
				end
			end
		end
	end
	return out
end

function audit.run(root: string): { Problem }
	local problems: { Problem } = {}
	local function add(level: Level, code: string, path: string, message: string)
		table.insert(problems, { level = level, code = code, path = path, message = message })
	end
	local _, regProblem = rootsOf(root)
	if regProblem then
		add("error", "registry", projects.FILE, regProblem)
		return problems -- nothing else can be read without the roots
	end
	local found = audit.scan(root)
	local byId: { [string]: { string } } = {}
	local used: { string } = {}
	for _, f in found do
		local key = f.kind .. ":" .. f.id
		byId[key] = byId[key] or {}
		table.insert(byId[key], f.path)
		table.insert(used, f.id)
		if ids.spaceOf(f.id) ~= f.kind then
			add("error", "wrong-kind", f.path, `{f.id} is not a {f.kind} id`)
		end
		local abs = `{root}/{f.path}`
		local doc = `{abs}/{f.id}.md`
		if fs.isFile(doc) then
			local fm = front(fs.readFile(doc))
			if fm.id and fm.id ~= "" and fm.id ~= f.id then
				add("error", "id-mismatch", f.path, `{f.id}.md says id: {fm.id}`)
			end
			if not fm.slug or fm.slug == "" then
				add("error", "no-slug", f.path, `{f.id}.md has no slug:`)
			end
			-- f0421: risk: is easy, normal or risky; a raft takes its members' highest and carries none
			if f.kind == "raft" and (fm.risk or "") ~= "" then
				add("error", "risk", f.path, `{f.id}.md: a raft's risk is its members' highest`)
			elseif f.kind == "issue" then
				local _, riskProblem = rounds.level(fm.risk)
				if riskProblem then
					add("error", "risk", f.path, `{f.id}.md: {riskProblem}`)
				end
			end
			-- f0420 step 3: `light: true` marks the single raft `ready <issue>` made for an easy ticket
			if f.kind == "raft" and (fm.light or "") ~= "" then
				if fm.light ~= "true" then
					add("error", "light", f.path, `{f.id}.md: light: is true or absent, not {fm.light}`)
				elseif fm.single ~= "true" then
					add("error", "light", f.path, `{f.id}.md says light: true but is not single: true`)
				else
					-- its one ticket must be risk: easy (the light rule; the walk and done judge it again)
					for _, other in found do
						if other.kind == "issue" then
							local otherDoc = `{root}/{other.path}/{other.id}.md`
							if fs.isFile(otherDoc) and front(fs.readFile(otherDoc)).raft == f.id then
								if front(fs.readFile(otherDoc)).risk ~= "easy" then
									add(
										"warning",
										"light",
										f.path,
										`{f.id}.md says light: true but its ticket {other.id} has risk: {front(
											fs.readFile(otherDoc)
										).risk or "normal"}, not easy`
									)
								end
							end
						end
					end
				end
			end
		else
			local legacy = nil
			for _, name in fs.readDir(abs) do
				if string.match(name, `^{f.id}%-.+%.md$`) then
					legacy = name
				end
			end
			if legacy then
				add("error", "legacy-name", f.path, `{legacy} uses the legacy name; run tracker.sh migrate`)
			else
				add("error", "no-document", f.path, `no {f.id}.md`)
			end
		end
	end
	for _, paths in byId do
		if #paths > 1 then
			for _, p in paths do
				local others: { string } = {}
				for _, q in paths do
					if q ~= p then
						table.insert(others, q)
					end
				end
				add("error", "duplicate", p, `the same id is also at {table.concat(others, ", ")}`)
			end
		end
	end
	-- An unfinished raft lives in its members' project (c0114, R0043 code review 006): `new raft` refuses one that spans
	-- two, and this catches one that arrives by merge, as every capture does while c0114's branch waits to land.
	-- Membership is read both ways: the raft's `issues:` list and each issue's `raft:` field. A finished raft is left as
	-- it is: R0001 spans two projects by decision (c0114 §9).
	local roots = rootsOf(root)
	local first: { [string]: { path: string, top: string, fm: { [string]: string } } } = {}
	for _, f in found do
		local key = f.kind .. ":" .. f.id
		local doc = `{root}/{f.path}/{f.id}.md`
		if not first[key] and fs.isFile(doc) then
			first[key] =
				{ path = f.path, top = projects.rootOf(f.path, roots) or "", fm = front(fs.readFile(doc)) }
		end
	end
	for key, r in first do
		local rid = string.match(key, "^raft:(.+)$")
		if rid and not string.find(r.path, "/done/", 1, true) then
			local members: { [string]: boolean } = {}
			for id in string.gmatch(r.fm.issues or "", "[fdc]%d%d%d%d") do
				members[id] = true
			end
			for k, i in first do
				local iid = string.match(k, "^issue:(.+)$")
				if iid and i.fm.raft == rid then
					members[iid] = true
				end
			end
			for id in members do
				local m = first["issue:" .. id]
				if m and m.top ~= r.top then
					add(
						"error",
						"raft-spans-projects",
						r.path,
						`{id} is in {m.top}, not {r.top}: a raft lives in its members' project`
					)
				end
			end
		end
	end
	-- c0278: a close that ./zn close did not make, or a closed issue something still holds. One rule for what counts as
	-- closed (closing.isClosed, closing.reasonOf over audit's own front, which reads malformed trees).
	local function where(path: string): string
		return if string.find(path, "/retired/", 1, true)
			then "retired"
			elseif string.find(path, "/done/", 1, true) then "done"
			elseif string.find(path, "/active/", 1, true) then "active"
			else "backlog"
	end
	local closedIds: { [string]: boolean } = {}
	for key, it in first do
		local kind, id = string.match(key, "^(%a+):(.+)$")
		local isClosed = closing.isClosed(it.fm)
		local carries = it.fm[closing.KEY] ~= nil
		if kind == "issue" then
			if isClosed then
				closedIds[id :: string] = true
			end
			if (carries and not isClosed) or (isClosed and closing.reasonOf(it.fm) == nil) then
				add(
					"error",
					"closed-mismatch",
					it.path,
					`{id}: wont_do: and a closed status go together, and only ./zn close writes them: restore both lines from origin/main, or close it with ./zn close {id} --reason "<why>"`
				)
			end
		end
		if (isClosed or carries) and (kind == "raft" or where(it.path) ~= "backlog") then
			add(
				"error",
				"closed-not-backlog",
				it.path,
				`{id} is closed outside the backlog: only a backlog issue is closed; restore its document by pull request`
			)
		end
	end
	local inRaft: { [string]: boolean } = {}
	local function heldBy(id: string, raft: string)
		if inRaft[id .. ">" .. raft] then
			return
		end
		inRaft[id .. ">" .. raft] = true
		local it = first["issue:" .. id]
		add(
			"error",
			"closed-in-raft",
			if it then it.path else id,
			`{id} is closed but {raft} holds it: empty its raft: line and drop it from {raft}'s issues: by pull request`
		)
	end
	local keys: { string } = {}
	for key in first do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local it = first[key]
		local kind, id = string.match(key, "^(%a+):(.+)$")
		local state = where(it.path)
		if kind == "issue" and closedIds[id :: string] and (it.fm.raft or "") ~= "" then
			heldBy(id :: string, it.fm.raft :: string)
		end
		if kind == "raft" and state ~= "done" and state ~= "retired" then
			for member in string.gmatch(it.fm.issues or "", "[fdc]%d%d%d%d") do
				if closedIds[member] then
					heldBy(member, id :: string)
				end
			end
		end
		if (state == "backlog" or state == "active") and not closing.isClosed(it.fm) then
			for dep in string.gmatch(it.fm.depends_on or "", "[fdc]%d%d%d%d") do
				if closedIds[dep] then
					add(
						"error",
						"closed-dependency",
						it.path,
						`{id} depends on {dep}, which is closed (won't do): drop {dep} from {id}'s depends_on by pull request`
					)
				end
			end
		end
	end
	-- f0450: what a defect fixes must exist (rework counting reads it); a defect with no `fixes:` is left to ./zn metrics
	for _, key in keys do
		local it = first[key]
		local id = string.match(key, "^issue:(.+)$")
		if id then
			for fixed in string.gmatch(it.fm.fixes or "", "[fdcR]%d%d%d%d") do
				if not first["issue:" .. fixed] and not first["raft:" .. fixed] then
					add(
						"error",
						"unknown-fixes",
						it.path,
						`{id} fixes {fixed}, which is no issue or raft: name what it fixes in fixes: (an id that exists)`
					)
				end
			end
		end
	end
	-- f0450: `shipped:` is the owner's ruling and needs its keyed line `Ruled (user, YYYY-MM-DD), shipped: no: "<words>"`
	for _, key in keys do
		local it = first[key]
		local id = string.match(key, "^issue:(.+)$")
		if id and it.fm.shipped ~= nil then
			local doc = `{root}/{it.path}/{id}.md`
			if not rework.isRuled(it.fm, if fs.isFile(doc) then fs.readFile(doc) else "") then
				add(
					"error",
					"unhonoured-shipped",
					it.path,
					if it.fm.shipped == "no"
						then `{id} has shipped: no with no line Ruled (user, YYYY-MM-DD), shipped: no: "<the owner's words>" outside a code fence: the key is ignored; only the owner's ruling, quoted on that line, drops a defect from rework`
						else `{id} has shipped: {it.fm.shipped}: shipped: must be no (the only value read) and needs the keyed Ruled line; it is ignored`
				)
			end
		end
		-- a defect that names itself, or (not being emergent) its own raft, would drop itself from the figure
		if id and it.fm.type == "defect" then
			for fixed in string.gmatch(it.fm.fixes or "", "[fdcR]%d%d%d%d") do
				if fixed == id or (fixed == it.fm.raft and it.fm.emergent ~= "true") then
					add(
						"error",
						"self-fixes",
						it.path,
						`{id} fixes {fixed}, which is itself or the raft that fixes it: fixes: names the earlier work the defect repairs (only an emergent defect fixes the open raft it was found in)`
					)
				end
			end
		end
	end
	-- one number, two issue prefixes
	local byNumber: { [number]: { Found } } = {}
	local seen: { [string]: boolean } = {}
	for _, f in found do
		if ids.spaceOf(f.id) == "issue" and f.kind == "issue" and not seen[f.id] then
			seen[f.id] = true
			local n = ids.number(f.id)
			byNumber[n] = byNumber[n] or {}
			table.insert(byNumber[n], f)
		end
	end
	for _, list in byNumber do
		if #list > 1 then
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			local names: { string } = {}
			for _, f in list do
				table.insert(names, f.id)
			end
			add("warning", "shared-number", list[1].path, `one number for {table.concat(names, ", ")}`)
		end
	end
	-- c0116: a raft given back by `release` after `new raft` stays at `new` with no member (publish never deletes): an
	-- orphan. Membership is each issue's `raft:` line, so an orphan is a backlog raft at `new` that no issue names.
	local named: { [string]: boolean } = {}
	for _, f in found do
		local doc = `{root}/{f.path}/{f.id}.md`
		if f.kind == "issue" and fs.isFile(doc) then
			local r = front(fs.readFile(doc)).raft
			if r and r ~= "" then
				named[r] = true
			end
		end
	end
	-- R0050 code review 001 F2: a backlog or active issue whose raft: names a retired or missing raft can be neither
	-- readied, unfolded nor claimed. A done issue's raft: is history and is not checked. An active issue that its raft
	-- doesn't hold (audit.raftHolds, the rule `stop <issue>` uses too: review 004 F1) is reported with `stop <issue>`.
	local raftAt: { [string]: string } = {}
	local raftPath: { [string]: string } = {}
	for _, f in found do
		if f.kind == "raft" then
			local retiredOne = string.find(f.path, "/retired/", 1, true) ~= nil
			raftAt[f.id] = if retiredOne then "retired" else "live"
			if not retiredOne then
				raftPath[f.id] = f.path
			end
		end
	end
	for _, f in found do
		local doc = `{root}/{f.path}/{f.id}.md`
		if f.kind == "issue" and not string.find(f.path, "/done/", 1, true) and fs.isFile(doc) then
			local fm = front(fs.readFile(doc))
			local rawRaft = fm.raft
			local r = rawRaft or ""
			local active = string.find(f.path, "/active/", 1, true) ~= nil
			local stop = `give it back with ./zn stop {f.id}`
			if not active then
				-- a backlog issue: unfold clears a dead raft (review 003 F1)
				local fix = `clear it with ./zn unfold {r} {f.id}`
				if r ~= "" and raftAt[r] == "retired" then
					add("error", "dead-raft", f.path, `{f.id}'s raft {r} is retired: {fix}`)
				elseif r ~= "" and raftAt[r] == nil then
					add("error", "dead-raft", f.path, `{f.id}'s raft {r} does not exist: {fix}`)
				end
			elseif rawRaft ~= nil then
				-- an active issue (a document with no raft: line at all is not one the engine writes)
				local rp = raftPath[r]
				local rs = if rp then front(fs.readFile(`{root}/{rp}/{r}.md`)).status else nil
				if not audit.raftHolds(fm, rp, rs) then
					if r == "" then
						add("error", "raftless-active", f.path, `{f.id} is in active/ with no raft: {stop}`)
					elseif raftAt[r] == "retired" then
						add("error", "dead-raft", f.path, `{f.id}'s raft {r} is retired: {stop}`)
					elseif raftAt[r] == nil then
						add("error", "dead-raft", f.path, `{f.id}'s raft {r} does not exist: {stop}`)
					else
						add(
							"error",
							"stray-active",
							f.path,
							`{f.id} is in active/, but its raft {r} doesn't hold it (not an active raft whose claim it carries): {stop}`
						)
					end
				end
			end
		end
	end
	for _, f in found do
		local doc = `{root}/{f.path}/{f.id}.md`
		local retired = string.find(f.path, "/retired/", 1, true) ~= nil
		local backlog = not retired
			and not string.find(f.path, "/active/", 1, true)
			and not string.find(f.path, "/done/", 1, true)
		if retired and f.kind ~= "raft" then
			add("error", "retired-raft", f.path, `{f.id} is in retired/: only a raft is retired`)
		elseif retired and fs.isFile(doc) and (front(fs.readFile(doc)).retired or "") == "" then
			add(
				"error",
				"retired-raft",
				f.path,
				`{f.id} is in retired/ without retired: <keeper> (only recombine retires a raft)`
			)
		end
		if f.kind == "raft" and backlog and not named[f.id] and fs.isFile(doc) then
			local st = front(fs.readFile(doc)).status or ""
			-- review 003 F6: an empty prepared raft too (an unfold of its last member): nothing can ready it
			if
				st == "new"
				or string.match(st, "^new%-")
				or st == "prepared"
				or string.match(st, "^prepared%-")
			then
				add(
					"warning",
					"orphan-raft",
					f.path,
					`{f.id} is a raft with no member (given back, or emptied by unfold): retire it with ./zn recombine <a raft of its project and type> {f.id}`
				)
			end
		end
	end
	local okReg, reg = pcall(projects.load, root)
	if okReg then
		for _, p in audit.leftovers(root, found, reg :: projects.Registry) do
			table.insert(problems, p)
		end
	end
	-- The live counter (c0114): z-nile/next once origin has moved it there, and tracker/next before. Both parsing at once
	-- is an error, because an engine from before the move would number from the old one.
	local newPath, oldPath = `{root}/{ids.FILE}`, `{root}/{ids.OLD_FILE}`
	local oldParses = fs.isFile(oldPath) and ids.parse(fs.readFile(oldPath)) ~= nil
	local livePath, liveFile = newPath, ids.FILE
	if fs.isFile(newPath) then
		if oldParses then
			add(
				"error",
				"old-counter",
				ids.OLD_FILE,
				`parses as a counter; it must stay a tombstone (the counter is {ids.FILE})`
			)
		end
	elseif oldParses then
		livePath, liveFile = oldPath, ids.OLD_FILE
		if fs.isFile(`{root}/{projects.FILE}`) then
			add(
				"warning",
				"counter-unmigrated",
				ids.OLD_FILE,
				`is still the counter: the first publish on an origin/main with {projects.FILE} moves it to {ids.FILE}`
			)
		end
	end
	if not fs.isFile(livePath) then
		add("error", "next-missing", ids.FILE, "no counter file: ids fall back to the next multiple of 10")
	else
		local c = ids.parse(fs.readFile(livePath))
		if not c then
			add("error", "next-malformed", liveFile, "expected `issue <n> <phrase>` and `raft <n> <phrase>`")
		else
			-- a counter at or below the highest number in use in its space (a warning: allocation skips used numbers)
			local function behind(space: ids.Space, n: number)
				local high = ids.highest(space, used)
				if high >= n then
					add("warning", "next-behind", liveFile, `{space} counter {n} is not above {high}, in use`)
				end
			end
			behind("issue", c.issue)
			behind("raft", c.raft)
		end
	end
	table.sort(problems, function(a, b)
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.code < b.code
	end)
	return problems
end

-- f0422: each project root's tributaries.toml defines its tributaries; a unit (a raft, or an issue in no raft; a closed
-- issue and a retired raft are no unit) names one in its own `tributary:` line, and a raft's members take their raft's
-- (their own line is ignored). Errors: a malformed file or definition, and a unit whose line names no definition. A
-- unit with no line is `unsorted` (or `earlier-work`), shown on the board, never an error. Kept apart from `run`, so a
-- fixture tree needs no such file: `./zn audit` and the gate's real-tree spec ask for both.
function audit.tributaries(root: string): { Problem }
	local problems: { Problem } = {}
	local function add(path: string, message: string)
		table.insert(problems, { level = "error", code = "tributaries", path = path, message = message })
	end
	local roots, regProblem = rootsOf(root)
	if regProblem then
		return problems -- `run` reports the registry
	end
	local first: { [string]: { path: string, top: string, fm: { [string]: string } } } = {}
	for _, f in audit.scan(root) do
		local key = f.kind .. ":" .. f.id
		local doc = `{root}/{f.path}/{f.id}.md`
		if not first[key] and fs.isFile(doc) then
			first[key] =
				{ path = f.path, top = projects.rootOf(f.path, roots) or "", fm = front(fs.readFile(doc)) }
		end
	end
	for _, base in roots do
		local file = tributaries.pathOf(base)
		local list: { tributaries.Tributary } = {}
		if fs.isFile(`{root}/{file}`) then
			local parsed, problem = tributaries.parse(fs.readFile(`{root}/{file}`))
			if not parsed then
				add(file, problem or "does not parse")
				continue -- the file is named once: the units can't be checked against a file that did not read
			end
			list = parsed
			for _, msg in tributaries.check(list) do
				add(file, msg)
			end
		end
		for key, it in first do
			local kind, id = string.match(key, "^(%a+):(.+)$")
			if it.top ~= base or string.find(it.path, "/retired/", 1, true) then
				continue
			end
			local isUnit = kind == "raft"
			if kind == "issue" and not closing.isClosed(it.fm) then
				local owner = first["raft:" .. (it.fm.raft or "")]
				isUnit = owner == nil or string.find(owner.path, "/retired/", 1, true) ~= nil
			end
			if isUnit then
				local msg = tributaries.checkUnit(list, id :: string, it.fm.tributary)
				if msg then
					add(`{it.path}/{id}.md`, msg)
				end
			end
		end
	end
	table.sort(problems, function(a, b)
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.message < b.message
	end)
	return problems
end

-- The rule `./zn ready` applies to a raft (code review 006 F1): the ids its `issues:` line lists and the issues whose
-- `raft:` line names it are the same set. Returns what disagrees, for each raft id of `rafts`, in the checkout `root`.
function audit.membership(root: string, rafts: { string }): { string }
	local out: { string } = {}
	local found = audit.scan(root)
	local listed: { [string]: { [string]: boolean } } = {}
	local members: { [string]: { [string]: boolean } } = {}
	for _, rid in rafts do
		listed[rid], members[rid] = {}, {}
	end
	for _, f in found do
		local doc = `{root}/{f.path}/{f.id}.md`
		if fs.isFile(doc) then
			local fm = front(fs.readFile(doc))
			if f.kind == "raft" and listed[f.id] then
				for id in string.gmatch(fm.issues or "", "[%w]+") do
					listed[f.id][id] = true
				end
			elseif f.kind == "issue" and fm.raft and members[fm.raft] then
				members[fm.raft][f.id] = true
			end
		end
	end
	for _, rid in rafts do
		for id in listed[rid] do
			if not members[rid][id] then
				table.insert(out, `raft {rid} lists {id}, whose raft: line does not name {rid}`)
			end
		end
		for id in members[rid] do
			if not listed[rid][id] then
				table.insert(out, `{id}'s raft: line names {rid}, which does not list it`)
			end
		end
	end
	table.sort(out)
	return out
end

function audit.format(p: Problem): string
	return `{p.level} {p.code} {p.path}: {p.message}`
end

function audit.errors(problems: { Problem }): number
	local n = 0
	for _, p in problems do
		if p.level == "error" then
			n += 1
		end
	end
	return n
end

return audit
