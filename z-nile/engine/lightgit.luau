--!strict
-- f0420 step 3: the light path read from git (the edge of light.luau). ONE reader: the walk (workread), `./zn done`
-- and the dispatcher all ask `lightgit.reason`, so they cannot disagree. A raft is light only when the ticket document
-- at the top layer's tip AND origin/main's copy are both light by the rule (light.luau), its dependencies are judged
-- from origin/main, and its diff, from the merge base, passes. The raft document must also say `light: true`.

local fs = require("@lune/fs")
local layergit = require("./layergit")
local light = require("./light")
local sh = require("../lib/sh")
local store = require("./store")

local lightgit = {}

export type Input = {
	single: boolean,
	members: { { id: string, path: string, originDoc: string? } }, -- path: the ticket document, in active/
	base: string?, -- the sha the layer was cut from (diffed from the merge base of it and the tip)
	tip: string?, -- the top layer's tip; nil: not built yet, so the diff is not judged
}

export type Verdict = {
	light: boolean, -- the raft document says light: true and the rule holds
	why: string?, -- why not (nil when light)
	claimed: boolean, -- the raft document says light: true
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

-- The git arguments of a ticket's diff: from the merge base of `base` and `tip` (three dots, so a main that moved
-- since the layer was cut does not count its own commits), renames as an add and a delete.
function lightgit.diffArgs(base: string, tip: string): { string }
	return { "diff", "--numstat", "--no-renames", `{base}...{tip}` }
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
			changed, diffWhy = light.judgeDiff(diffed.stdout)
		else
			return "its diff cannot be read"
		end
	end
	for _, text in { atTip, origin } do
		if text then
			local f = frontOf(text)
			local why = light.reason({
				members = { { risk = f.risk, doc = text, designReady = f.design == "ready" } },
				depsMet = depsMet,
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

-- What `./zn done` and the dispatcher ask of a raft in this checkout (the top layer's tip is the layer's branch).
function lightgit.of(raft: store.Item): Verdict
	local front = store.readFront(raft.doc)
	local claimed = front.light == "true"
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
	local why = if not claimed
		then "its raft document does not say light: true"
		else lightgit.reason({
			single = front.single == "true",
			members = members,
			base = base,
			tip = tip,
		})
	local reviewed = false
	if fs.isDir(raft.dir) then
		for _, name in fs.readDir(raft.dir) do
			if string.match(name, "^review%-%d+%.md$") then
				reviewed = true
			end
		end
	end
	return { light = claimed and why == nil, why = why, claimed = claimed, reviewed = reviewed }
end

return lightgit
