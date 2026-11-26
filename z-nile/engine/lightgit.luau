--!strict
-- f0420 step 3: the light path read from git (the edge of light.luau). ONE reader: the walk (workread), `./zn done`
-- and the dispatcher all ask `lightgit.reason`, so they cannot disagree. A raft is light only when the ticket document
-- at the top layer's tip AND origin/main's copy are both light by the rule (light.luau), its dependencies are judged
-- from origin/main, and its diff, from the merge base, passes. The raft document must also say `light: true`.

local easy = require("./easy")
local fs = require("@lune/fs")
local layergit = require("./layergit")
local light = require("./light")
local projects = require("./projects")
local sh = require("../lib/sh")
local store = require("./store")

local lightgit = {}

export type Input = {
	single: boolean,
	members: { { id: string, path: string, originDoc: string? } }, -- path: the ticket document, in active/
	base: string?, -- the sha the layer was cut from (diffed from the merge base of it and the tip)
	tip: string?, -- the top layer's tip; nil: not built yet, so the diff is not judged
	finals: { string }?, -- c0435: the texts of the raft's final-review files (a `Level:` line may raise the ticket)
}

export type Verdict = {
	light: boolean, -- the raft document says light: true and the rule holds
	why: string?, -- why not (nil when light)
	claimed: boolean, -- the raft document says light: true
	levelProblem: string?, -- c0435: a final review's Level line holds no level: done refuses outright
	raised: string?, -- c0435: a review's `Level:` raised the ticket (the full path), whatever light says
	reviewed: boolean, -- the raft's folder holds a review-NNN.md (a code review was run)
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

local function show(ref: string, path: string): string?
	local shown = sh.run("git", { "show", `{ref}:{path}` })
	return if shown.ok then shown.stdout else nil
end

local function listOf(value: string?): { string }
	local out: { string } = {}
	for id in string.gmatch(value or "", "[fdc]%d%d%d%d") do
		table.insert(out, id)
	end
	return out
end

-- Whether a raft is MARKED light: any copy of its document it is given says `light: true`. The walk, `done`, the
-- dispatcher and `./zn model` all decide it here, with origin/main's copy (what `ready <issue>` published, which a
-- branch cannot remove) and the layer's copy, so deleting the line on a branch unmarks nothing.
function lightgit.marked(copies: { string? }): boolean
	for _, text in copies do
		if text and frontOf(text).light == "true" then
			return true
		end
	end
	return false
end

-- The same, reading the two copies of the raft document at `path` (origin/main's and the working tree's).
function lightgit.markedAt(path: string): boolean
	return lightgit.marked({ show("origin/main", path), if fs.isFile(path) then fs.readFile(path) else nil })
end

-- The registered project homes of a registry text (their check.sh files are protected).
function lightgit.homesOf(registry: string): { string }
	local out: { string } = {}
	local reg = projects.parse(registry)
	local list: { projects.Project } = if reg then reg.projects else {}
	for _, p in list do
		local home = (string.gsub(p.home, "/+$", ""))
		if home ~= "" and home ~= "." then
			table.insert(out, home)
		end
	end
	return out
end

-- The git arguments of a ticket's diff: from the merge base of `base` and `tip` (three dots, so a main that moved
-- since the layer was cut does not count its own commits), renames as an add and a delete.
function lightgit.diffArgs(base: string, tip: string): { string }
	return { "diff", "--numstat", "--no-renames", `{base}...{tip}` }
end

-- c0435: the design-review files of a ticket's folder at the given refs (name -> text), the union of what each holds.
local function designFiles(folder: string, refs: { string }): { [string]: string }
	local out: { [string]: string } = {}
	for _, ref in refs do
		local listed = sh.run("git", { "ls-tree", "--name-only", ref, `{folder}/` })
		if listed.ok then
			for path in string.gmatch(listed.stdout, "[^\n]+") do
				local name = string.match(path, "([^/]+)$") or ""
				if string.match(name, "^design%-review%-%d+%.md$") and out[name] == nil then
					out[name] = show(ref, path) or ""
				end
			end
		end
	end
	return out
end

-- nil when the one rule says the raft's ticket is light, else why not. Everything is read from git.
function lightgit.reason(input: Input): string?
	if not input.single then
		return "it is not a single raft"
	end
	if #input.members ~= 1 then
		return "its raft has more than one ticket"
	end
	local m = input.members[1]
	local origin = m.originDoc or show("origin/main", m.path)
	local atTip = if input.tip then show(input.tip :: string, m.path) else nil
	if not origin and not atTip then
		return `{m.id}'s document cannot be read`
	end
	local root = string.match(m.path, "^(.-)/issues/") or ""
	local front = frontOf(origin or atTip :: string)
	local depsMet = true
	for _, dep in listOf(front.depends_on) do
		local landed = sh.run("git", { "cat-file", "-e", `origin/main:{root}/issues/done/{dep}/{dep}.md` })
		if not landed.ok then
			depsMet = false
		end
	end
	local changed: number? = nil
	local diffWhy: string? = nil
	if input.tip and input.base then
		local diffed = sh.run("git", lightgit.diffArgs(input.base, input.tip))
		if diffed.ok then
			changed, diffWhy =
				light.judgeDiff(diffed.stdout, lightgit.homesOf(show("origin/main", projects.FILE) or ""))
		else
			return "its diff cannot be read"
		end
	end
	local folder = string.match(m.path, "^(.*)/[^/]+$") or ""
	-- c0435: a design review counts only when origin/main holds it (a file added on the branch removes nothing)
	local reviewFiles = designFiles(folder, { "origin/main" })
	local reviews = easy.reviewTexts(reviewFiles)
	for _, text in input.finals or {} :: { string } do
		table.insert(reviews, text)
	end
	local check = show("origin/main", `{folder}/check.sh`)
	for _, text in { atTip, origin } do
		if text then
			local f = frontOf(text)
			local why = light.reason({
				members = { { risk = f.risk, doc = text, designReady = f.design == "ready", check = check } },
				depsMet = depsMet,
				designReviewed = easy.hasDesignReview(reviewFiles),
				reviews = reviews,
				changed = changed,
				diffWhy = diffWhy,
			})
			if why then
				return why
			end
		end
	end
	return nil
end

-- c0435: the level a light raft's final reviews raised its ticket to, read from the top layer's tip (the Level line lives
-- on the layer branch, which the main checkout does not hold). Nil: not marked light, no layer, or nothing raised.
function lightgit.raisedOf(raft: store.Item): (string?, string?)
	if not lightgit.markedAt(raft.doc) then
		return nil, nil
	end
	local layers = layergit.layersOf(raft.id)
	if #layers == 0 then
		return nil, nil
	end
	local tip = layergit.layerTip(layers[#layers])
	if not tip then
		return nil, nil
	end
	local texts: { string } = {}
	local listed = sh.run("git", { "ls-tree", "--name-only", tip, `{raft.dir}/` })
	if listed.ok then
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if string.match(path, "/final%-review%-%d+%.md$") then
				table.insert(texts, show(tip, path) or "")
			end
		end
	end
	return easy.raised(texts)
end

-- What `./zn done` and the dispatcher ask of a raft in this checkout (the top layer's tip is the layer's branch).
function lightgit.of(raft: store.Item): Verdict
	local front = store.readFront(raft.doc)
	local claimed = lightgit.markedAt(raft.doc)
	local members: { { id: string, path: string, originDoc: string? } } = {}
	for _, m in store.members(raft.id) do
		table.insert(members, { id = m.id, path = m.doc })
	end
	local tip: string? = nil
	local base: string? = nil
	local layers = layergit.layersOf(raft.id)
	if #layers > 0 then
		tip = layergit.layerTip(layers[#layers])
		base = (layergit.raftBase(raft.id))
	end
	local reviewed = false
	local finals: { string } = {}
	if fs.isDir(raft.dir) then
		for _, name in fs.readDir(raft.dir) do
			if string.match(name, "^review%-%d+%.md$") then
				reviewed = true
			end
			if string.match(name, "^final%-review%-%d+%.md$") then
				table.insert(finals, fs.readFile(`{raft.dir}/{name}`))
			end
		end
	end
	local why = if not claimed
		then "its raft document does not say light: true"
		else lightgit.reason({
			single = front.single == "true",
			members = members,
			base = base,
			tip = tip,
			finals = finals,
		})
	local raised, levelProblem = nil, nil
	if claimed then
		raised, levelProblem = easy.raised(finals)
	end
	return {
		levelProblem = levelProblem,
		light = claimed and why == nil,
		why = why,
		claimed = claimed,
		raised = raised,
		reviewed = reviewed,
	}
end

return lightgit
