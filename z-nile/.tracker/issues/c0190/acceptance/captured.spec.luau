--!strict
-- c0190: c0183's step-2 issues are captured in their projects. Each listed issue exists exactly once in its project's
-- root (backlog, active/ or done/), with its type, found by its slug, never by its id (a compaction or a renumber
-- changes ids, never slugs); its depends_on holds at least the issues the list implies (prep may add more); and its
-- Problem quotes the user and points at its section of the project's game-design.md, or at the arcade's
-- architecture.md. This spec is promoted and runs in every later gate, so it pins only what a later prep keeps: the
-- issue, its type and project, the captured dependencies and the captured Problem's quote and pointer (z-design:
-- prep only adds detail). These specs run from z-nile/: the checkout is read from its top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local store = require("@znile/engine/store")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

type Entry = { key: string, project: string, prefix: string, slug: string, deps: { string } }

local GAME = "game-design.md"
local ARCH = "arcade/.tracker/architecture.md"
-- the issues the step-2 list names, in its order; deps name a key of this list or a pickman slug ("pickman:<slug>")
local LIST: { Entry } = {
	{ key = "A1", project = "arcade", prefix = "f", slug = "hiscores-with-revives", deps = {} },
	{ key = "K1", project = "pickman", prefix = "c", slug = "switch-to-arcade-hiscores", deps = { "A1" } },
	{ key = "A2", project = "arcade", prefix = "f", slug = "shared-travel", deps = {} },
	{ key = "K2", project = "pickman", prefix = "c", slug = "switch-to-arcade-travel", deps = { "A2" } },
	{ key = "A3", project = "arcade", prefix = "f", slug = "paid-play-and-receipts", deps = {} },
	{
		key = "K3",
		project = "pickman",
		prefix = "c",
		slug = "switch-to-arcade-paid-play",
		deps = { "A3", "pickman:paid-play-and-continues", "pickman:boards-show-revives" },
	},
	{ key = "A4", project = "arcade", prefix = "f", slug = "input-and-look-cores", deps = {} },
	{ key = "K4", project = "pickman", prefix = "c", slug = "switch-to-arcade-input-cores", deps = { "A4" } },
	{ key = "P1", project = "portal", prefix = "f", slug = "game-carousel", deps = { "A3" } },
	{ key = "P2", project = "portal", prefix = "f", slug = "boards-per-game", deps = { "A1", "P1" } },
	{ key = "P3", project = "portal", prefix = "f", slug = "free-game-timer", deps = { "A3", "P1" } },
	{ key = "P4", project = "portal", prefix = "f", slug = "play-buttons", deps = { "A2", "A3", "P1" } },
	{ key = "P5", project = "portal", prefix = "f", slug = "portal-start-place", deps = { "Z3", "P4" } },
	{ key = "Z3", project = "portal", prefix = "c", slug = "n-place-deploy", deps = {} },
	{ key = "S1", project = "snake", prefix = "f", slug = "arena-maps-growth", deps = {} },
	{ key = "S2", project = "snake", prefix = "f", slug = "shared-snake-arena", deps = { "S1" } },
	{ key = "S3", project = "snake", prefix = "f", slug = "snake-first-person-view", deps = { "S1" } },
	{ key = "S4", project = "snake", prefix = "f", slug = "boost-golden-apples-crumbs", deps = { "S1" } },
	{
		key = "S5",
		project = "snake",
		prefix = "f",
		slug = "snake-scores-and-revives",
		deps = { "S1", "A1", "A2", "A3" },
	},
	{ key = "I1", project = "invaders", prefix = "f", slug = "invaders-classic-rules", deps = {} },
	{ key = "I2", project = "invaders", prefix = "f", slug = "invaders-two-players", deps = { "I1" } },
	{ key = "I3", project = "invaders", prefix = "f", slug = "invaders-cannon-view", deps = { "I1" } },
	{
		key = "I4",
		project = "invaders",
		prefix = "f",
		slug = "invaders-scores-and-revives",
		deps = { "I1", "A1", "A2", "A3" },
	},
	{ key = "T1", project = "asteroids", prefix = "f", slug = "asteroids-classic-rules", deps = {} },
	{ key = "T2", project = "asteroids", prefix = "f", slug = "asteroids-two-players", deps = { "T1" } },
	{ key = "T3", project = "asteroids", prefix = "f", slug = "asteroids-cockpit-view", deps = { "T1" } },
	{
		key = "T4",
		project = "asteroids",
		prefix = "f",
		slug = "asteroids-scores-and-revives",
		deps = { "T1", "A1", "A2", "A3" },
	},
}

-- the start of the user's request, which every captured Problem quotes
local QUOTE = '"I want to branch out into multiple games'

type Found = { id: string, doc: string }

local function registry(): projects.Registry
	local reg, err = projects.parse(fs.readFile(`{TOP}/z-nile/projects.toml`))
	t.expect(err).toBe(nil)
	return reg :: projects.Registry
end

-- every issue of `project` whose slug is `slug`, across its backlog, active/ and done/
local function bySlug(reg: projects.Registry, project: string, slug: string): { Found }
	local p = projects.named(reg, project)
	if not p then
		error(`{project} is not registered`)
	end
	local out: { Found } = {}
	for _, sub in { "", "active/", "done/" } do
		local dir = `{TOP}/{p.root}/issues/{sub}`
		if fs.isDir(dir) then
			for _, id in fs.readDir(dir) do
				local doc = `{dir}{id}/{id}.md`
				if store.isIssueId(id) and fs.isFile(doc) and store.readFront(doc).slug == slug then
					table.insert(out, { id = id, doc = doc })
				end
			end
		end
	end
	return out
end

-- the one issue an entry names; errors name the entry when there is none or more than one
local function one(reg: projects.Registry, project: string, slug: string, what: string): Found
	local found = bySlug(reg, project, slug)
	if #found ~= 1 then
		error(`{what}: {#found} issues with slug {slug} in {project}, expected 1`, 0)
	end
	return found[1]
end

local function problemOf(doc: string): string
	local text = fs.readFile(doc)
	local problem = string.match(text, "\n## Problem\n(.-)\n## ")
	if not problem then
		error(`{doc} has no Problem section`, 0)
	end
	return problem
end

return t.spec("c0190 the arcade's step-2 issues are captured", function(it)
	it("AC1: each listed issue exists once in its project, with its type", function()
		local reg = registry()
		local wrong: { string } = {}
		for _, e in LIST do
			local ok, f = pcall(one, reg, e.project, e.slug, e.key)
			if not ok then
				table.insert(wrong, tostring(f))
			elseif string.sub((f :: Found).id, 1, 1) ~= e.prefix then
				table.insert(wrong, `{e.key}: {(f :: Found).id} is not a {e.prefix} issue`)
			end
		end
		if #wrong > 0 then
			error(table.concat(wrong, "\n"), 0)
		end
	end)

	it("AC2: each issue's depends_on holds the issues the list implies", function()
		local reg = registry()
		local byKey: { [string]: Entry } = {}
		for _, e in LIST do
			byKey[e.key] = e
		end
		local wrong: { string } = {}
		for _, e in LIST do
			local f = one(reg, e.project, e.slug, e.key)
			local have: { [string]: boolean } = {}
			for _, id in store.idList(store.readFront(f.doc).depends_on) do
				have[id] = true
			end
			for _, d in e.deps do
				local slug = string.match(d, "^pickman:(.+)$")
				local dep = if slug
					then one(reg, "pickman", slug, d)
					else one(reg, byKey[d].project, byKey[d].slug, d)
				if not have[dep.id] then
					table.insert(wrong, `{e.key} ({f.id}) does not depend on {d} ({dep.id})`)
				end
			end
		end
		if #wrong > 0 then
			error(table.concat(wrong, "\n"), 0)
		end
	end)

	it("AC3: each Problem quotes the user and points at its design", function()
		local reg = registry()
		local wrong: { string } = {}
		for _, e in LIST do
			local f = one(reg, e.project, e.slug, e.key)
			local problem = problemOf(f.doc)
			local first = string.sub(e.key, 1, 1)
			local pointer = if first == "S"
					or first == "I"
					or first == "T"
					or first == "P"
				then `\`{e.project}/.tracker/{GAME}\``
				else `\`{ARCH}\``
			if not string.find(problem, QUOTE, 1, true) then
				table.insert(wrong, `{e.key} ({f.id}): no quote of the user`)
			end
			if not string.find(problem, pointer, 1, true) then
				table.insert(wrong, `{e.key} ({f.id}): no pointer to {pointer}`)
			end
		end
		if #wrong > 0 then
			error(table.concat(wrong, "\n"), 0)
		end
	end)
end)
