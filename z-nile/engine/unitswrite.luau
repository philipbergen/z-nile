--!strict
-- f0437 step 6, slice 2: the one writer of units.json (the app's id links and detail view). It runs from the board refresh, beside
-- themes.json, from the model that page was made from: the model already holds every document (read once), so this module reads no
-- ticket file. The reads it adds are the deletion log of git (for the withdrawn ids) and the two templates. It writes in the main
-- checkout only (a branch's tracker is not the app's), atomically and never through a link, in a pcall that never fails the
-- refresh, and writes nothing, and wakes nobody, when what the file would say is what it says.
local approvalfacts = require("./approvalfacts")
local approvewalk = require("./approvewalk")
local board = require("./board")
local fs = require("@lune/fs")
local ids = require("./ids")
local livecall = require("./livecall")
local serde = require("@lune/serde")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local unitsfacts = require("./unitsfacts")

local unitswrite = {}

unitswrite.MAX_PRIOR = 8 * 1024 * 1024 -- the largest earlier file it will read for its signature (the daemon reads 4 MiB)

-- The signatures of the file at `path` (`sig` of the content, `pre` of the inputs), when it is a regular file of its own (never a
-- link), small enough and valid; nil otherwise, so that anything else is replaced.
local function priorOf(path: string): { sig: string, pre: string }?
	if sh.run("test", { "-L", path }).ok or not fs.isFile(path) then
		return nil
	end
	local ok, text = pcall(fs.readFile, path)
	if not ok or #text > unitswrite.MAX_PRIOR then
		return nil
	end
	local decoded, got = pcall(serde.decode, "json" :: "json", text)
	if decoded and type(got) == "table" and type(got.sig) == "string" and type(got.units) == "table" then
		return { sig = got.sig, pre = if type(got.pre) == "string" then got.pre else "" }
	end
	return nil
end

-- Writes `<dir>/units.json` from the model, the deletion log and the templates, through a temporary file and a rename, unless the
-- file already says the same. Returns the path and whether it wrote.
function unitswrite.write(
	dir: string,
	model: board.Model,
	log: string,
	templates: approvalfacts.Templates,
	commit: string?,
	at: number?,
	extra: { pre: string?, map: { [string]: string }? }?
): (string, boolean)
	fs.writeDir(dir)
	local withdrawn = unitsfacts.parseWithdrawn(log, unitsfacts.existing(model), extra and extra.map)
	local units, cut = unitsfacts.units(model, templates, withdrawn)
	local facts = unitsfacts.build({
		at = at or os.time(),
		commit = commit,
		units = units,
		cut = cut,
		pre = extra and extra.pre,
	})
	local path = `{dir}/{unitsfacts.FILE}`
	local prior = priorOf(path)
	if prior and prior.sig == facts.sig and prior.pre == facts.pre then
		return path, false
	end
	sh.writeReplacing(path, unitsfacts.encode(facts))
	return path, true
end

-- True when `root` is the main checkout: git's own first worktree. Anything git cannot say is no.
local function inMainCheckout(root: string): boolean
	local top = sh.run("git", { "-C", root, "rev-parse", "--show-toplevel" })
	local list = sh.run("git", { "-C", root, "worktree", "list", "--porcelain" })
	if not top.ok or not list.ok then
		return false
	end
	local first = string.match(list.stdout, "^worktree ([^\n]+)")
	return first ~= nil and first == sh.trim(top.stdout)
end

-- The tracker folders whose deleted documents make a stub: `.tracker/` of every project and the old root `tracker/` (a test
-- fixture's `issues/` folder is no tracker). Renames are not detected: a move is a delete and an add, and an id that exists now is
-- never a stub.
local PATHSPECS = {
	":(glob)**/.tracker/issues/**",
	":(glob)**/.tracker/rafts/**",
	":(glob)tracker/issues/**",
	":(glob)tracker/rafts/**",
}

local function logArgs(root: string, format: string, limit: boolean): { string }
	local args = { "-C", root, "log", "--no-renames", "--diff-filter=D", `--format={format}` }
	if limit then
		table.insert(args, "-1")
	else
		table.insert(args, "--name-only")
	end
	table.insert(args, "--")
	for _, p in PATHSPECS do
		table.insert(args, p)
	end
	return args
end

-- The documents git remembers deleting, newest first.
local function deletionLog(root: string): string
	local r = sh.run("git", logArgs(root, "@@%x09%cs%x09%s", false))
	if not r.ok then
		error(`git log of deleted documents failed ({r.code})`, 0)
	end
	return r.stdout
end

-- The newest commit that deleted a document: one cheap call, the part of the cheap signature that says whether history changed.
local function deletionHead(root: string): string
	local r = sh.run("git", logArgs(root, "%H", true))
	return if r.ok then sh.trim(r.stdout) else ""
end

-- The compaction map (old id to new id) the engine's one reader (ids.parseMap) reads; empty when there is none.
local function compactionOf(root: string): ({ [string]: string }, string)
	for _, rel in ids.MAP_FILES do
		if fs.isFile(`{root}/{rel}`) then
			local text = fs.readFile(`{root}/{rel}`)
			return ids.parseMap(text) or {}, text
		end
	end
	return {}, ""
end

-- The cheap signature of everything the index is made from: per unit what the model holds (a hash of the body, not the preview),
-- the dropped list, the newest deletion, the templates and the compaction map. Equal means nothing needs building.
function unitswrite.inputsSig(
	model: board.Model,
	head: string,
	templatesText: string,
	mapText: string
): string
	local parts: { string } =
		{ `v{unitsfacts.VERSION}`, head, serde.hash("sha256", templatesText), serde.hash("sha256", mapText) }
	for _, i in model.issues do
		table.insert(
			parts,
			table.concat(
				{
					i.id,
					i.state,
					i.title,
					i.project,
					i.tributary,
					table.concat(i.themes, ","),
					i.raft or "",
					table.concat(i.dependsOn, ","),
					serde.hash("sha256", i.body),
				},
				"\2"
			)
		)
	end
	for _, r in model.rafts do
		table.insert(
			parts,
			table.concat(
				{
					r.id,
					r.state,
					r.title,
					r.project,
					r.tributary,
					table.concat(r.themes, ","),
					table.concat(r.issues, ","),
					table.concat(r.dependsOn, ","),
					serde.hash("sha256", r.body),
				},
				"\2"
			)
		)
	end
	for _, d in board.droppedOf(model) do
		table.insert(parts, table.concat({ d.id, d.kind, d.state, d.title, d.project, d.tributary }, "\2"))
	end
	return serde.hash("sha256", table.concat(parts, "\1"))
end

local function templatesOf(root: string): (approvalfacts.Templates, string)
	local texts: { string } = {}
	for _, rel in { "z-nile/templates/issue/doc.md", "z-nile/templates/raft/doc.md" } do
		if fs.isFile(`{root}/{rel}`) then
			table.insert(texts, fs.readFile(`{root}/{rel}`))
		end
	end
	return approvalfacts.templateComments(texts), table.concat(texts, "\0")
end

-- The board refresh's step: write the index where the live layer reads it and wake its listeners, only when it changed. Main
-- checkout only. It never fails the refresh: when it cannot write, it leaves the file that is there alone and says so in one line.
function unitswrite.refresh(root: string, model: board.Model, commit: string?)
	local dir = approvewalk.liveDir(root)
	if not dir or not inMainCheckout(root) then
		return
	end
	local ok, res = pcall(function(): boolean
		local path = `{dir}/{unitsfacts.FILE}`
		local templates, templatesText = templatesOf(root)
		local map, mapText = compactionOf(root)
		local pre = unitswrite.inputsSig(model, deletionHead(root), templatesText, mapText)
		local prior = priorOf(path)
		if prior and prior.pre == pre then
			return false -- nothing it is made from changed: nothing is built, read or written
		end
		local _, wrote =
			unitswrite.write(dir, model, deletionLog(root), templates, commit, nil, { pre = pre, map = map })
		return wrote
	end)
	if ok then
		if res then
			livecall.poke("units", "")
		end
		return
	end
	local first = string.match(tostring(res), "[^\n]+") or "unknown"
	stdio.ewrite(
		`warning: units index not written ({first}): the app's ids stay links to what the earlier index held, with the time it was made\n`
	)
end

return unitswrite
