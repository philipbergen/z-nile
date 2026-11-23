--!strict
-- f0420 step 3: the ONE decision whether `./zn ready <issue>` would take an issue in no raft down the light path, made
-- from a tree snapshot (`paths`, `read`): the publish's own (what ready publishes against) or origin/main's (what the
-- walk reads). `ready` and `work next` both ask `lightready.check`, so the walk never answers `ready <issue>` for a
-- ticket that `ready` then refuses. It holds the light rule (light.luau) and the facts around it: the ticket is
-- prepared in the backlog and in no raft, no raft that is not done lists it (z-raft is grouping it), and the readiness
-- facts ready checks (a check line, an open design-review finding, a stale approval) hold.

local easy = require("./easy")
local fs = require("@lune/fs")
local light = require("./light")
local publish = require("./publish")
local raftplan = require("./raftplan")
local readycheck = require("./readycheck")
local readyfacts = require("./readyfacts")
local sh = require("../lib/sh")
local statusLib = require("./status")
local store = require("./store")

local lightready = {}

export type Check = {
	why: string?, -- why the ticket takes no light path (nil: it does)
	reviewed: boolean?, -- c0435: the ticket has a design review on the snapshot (nil: not read)
	groupedBy: string?, -- the raft that lists it and is not done: z-raft is grouping it
}

local function frontOf(text: string): { [string]: string }
	local out: { [string]: string } = {}
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-") or ""
	for line in string.gmatch(block .. "\n", "([^\n]*)\n") do
		local k, v = string.match(line, "^([%w_]+):[ ]*(.*)$")
		if k and v then
			out[k] = (string.gsub(v, "%s+$", ""))
		end
	end
	return out
end

local function stateOf(path: string): string
	return if string.find(path, "/active/", 1, true)
		then "active"
		elseif string.find(path, "/done/", 1, true) then "done"
		else "backlog"
end

local function docPath(paths: { string }, id: string): string?
	for _, p in paths do
		local pid, rel = publish.itemPath(p)
		if pid == id and rel == `{id}.md` then
			return p
		end
	end
	return nil
end

-- origin/main as a snapshot: every path and a reader.
function lightready.originView(): ({ string }, (string) -> string?)
	local listed = sh.run("git", { "ls-tree", "-r", "--name-only", "origin/main" })
	local paths: { string } = {}
	if listed.ok then
		for p in string.gmatch(listed.stdout, "[^\n]+") do
			table.insert(paths, p)
		end
	end
	local cache: { [string]: string? } = {}
	local function read(p: string): string?
		if cache[p] == nil then
			local shown = sh.run("git", { "show", `origin/main:{p}` })
			cache[p] = if shown.ok then shown.stdout else ""
		end
		local got = cache[p] :: string
		return if got == "" then nil else got
	end
	return paths, read
end

local function checkText(): string
	local path = "z-nile/templates/raft/check.sh"
	return if fs.isFile(path) then fs.readFile(path) else 'check "RC0: light"\n'
end

function lightready.check(id: string, paths: { string }, read: (string) -> string?): Check
	local doc = docPath(paths, id)
	local text = if doc then read(doc) else nil
	if not doc or not text then
		return { why = `{id} is not on origin/main` }
	end
	local front = frontOf(text)
	local at = statusLib.effective(front, stateOf(doc))
	if stateOf(doc) ~= "backlog" or at ~= "prepared" then
		return { why = `it is {at} in {stateOf(doc)}, not prepared in the backlog` }
	end
	if (front.raft or "") ~= "" then
		return { why = `{id} already belongs to {front.raft}` }
	end
	for _, p in paths do
		local rid, rrel = publish.itemPath(p)
		if rid and string.match(rid, "^R%d%d%d%d$") and rrel == `{rid}.md` and stateOf(p) ~= "done" then
			local rt = read(p)
			if rt and table.find(store.idList(frontOf(rt).issues), id) then
				return { why = `{id} is listed by {rid}: z-raft is grouping it`, groupedBy = rid }
			end
		end
	end
	local unmet = false
	local deps: { { id: string, state: string } } = {}
	for _, dep in store.idList(front.depends_on) do
		local dp = docPath(paths, dep)
		local state = if dp then stateOf(dp) else "missing"
		if state ~= "done" then
			unmet = true
		end
		table.insert(deps, { id = dep, state = state })
	end
	-- the readiness facts, from the same snapshot
	local folder = string.sub(doc, 1, #doc - #id - 4)
	local files: { [string]: string } = {}
	local prefix = folder .. "/"
	for _, p in paths do
		if string.sub(p, 1, #prefix) == prefix then
			local rel = string.sub(p, #prefix + 1)
			if raftplan.isDesignFile(rel, id) or rel == "approval.md" or rel == "guesses.md" then
				local body = read(p)
				if body then
					files[rel] = body
				end
			end
		end
	end
	local rule = light.reason({
		members = {
			{
				risk = front.risk,
				doc = text,
				designReady = front.design == "ready",
				check = files["check.sh"],
			},
		},
		depsMet = not unmet,
		designReviewed = easy.hasDesignReview(files),
		reviews = easy.reviewTexts(files),
	})
	local reviewed = easy.hasDesignReview(files)
	if rule then
		return { why = rule, reviewed = reviewed }
	end
	local refused = readyfacts.lightFrom({
		id = id,
		design = front.design or "",
		doc = text,
		deps = deps,
		files = files,
		specs = readycheck.specs(files, {}),
		approval = files["approval.md"],
		approvalFile = `{folder}/approval.md`,
	}, "R0000", checkText())
	if refused then
		return { why = refused, reviewed = reviewed }
	end
	return { reviewed = reviewed }
end

return lightready
