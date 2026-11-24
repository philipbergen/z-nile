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
local livecall = require("./livecall")
local serde = require("@lune/serde")
local sh = require("../lib/sh")
local stdio = require("@lune/stdio")
local unitsfacts = require("./unitsfacts")

local unitswrite = {}

unitswrite.MAX_PRIOR = 8 * 1024 * 1024 -- the largest earlier file it will read for its signature (the daemon reads 4 MiB)

-- The signature of the file at `path`, when it is a regular file of its own (never a link), small enough and valid; nil otherwise,
-- so that anything else is replaced.
local function priorSig(path: string): string?
	if sh.run("test", { "-L", path }).ok or not fs.isFile(path) then
		return nil
	end
	local ok, text = pcall(fs.readFile, path)
	if not ok or #text > unitswrite.MAX_PRIOR then
		return nil
	end
	local decoded, got = pcall(serde.decode, "json" :: "json", text)
	if decoded and type(got) == "table" and type(got.sig) == "string" and type(got.units) == "table" then
		return got.sig
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
	at: number?
): (string, boolean)
	fs.writeDir(dir)
	local withdrawn = unitsfacts.parseWithdrawn(log, unitsfacts.existing(model))
	local units, cut = unitsfacts.units(model, templates, withdrawn)
	local facts = unitsfacts.build({ at = at or os.time(), commit = commit, units = units, cut = cut })
	local path = `{dir}/{unitsfacts.FILE}`
	if priorSig(path) == facts.sig then
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

-- The documents git remembers deleting (a move is a rename, so -M leaves it out), newest first.
local function deletionLog(root: string): string
	local r = sh.run("git", {
		"-C",
		root,
		"log",
		"-M",
		"--diff-filter=D",
		"--name-only",
		"--format=@@%x09%cs%x09%s",
		"--",
		"*/issues/*",
		"*/rafts/*",
	})
	if not r.ok then
		error(`git log of deleted documents failed ({r.code})`, 0)
	end
	return r.stdout
end

local function templatesOf(root: string): approvalfacts.Templates
	local texts: { string } = {}
	for _, rel in { "z-nile/templates/issue/doc.md", "z-nile/templates/raft/doc.md" } do
		if fs.isFile(`{root}/{rel}`) then
			table.insert(texts, fs.readFile(`{root}/{rel}`))
		end
	end
	return approvalfacts.templateComments(texts)
end

-- The board refresh's step: write the index where the live layer reads it and wake its listeners, only when it changed. Main
-- checkout only. It never fails the refresh: when it cannot write, it leaves the file that is there alone and says so in one line.
function unitswrite.refresh(root: string, model: board.Model, commit: string?)
	local dir = approvewalk.liveDir(root)
	if not dir or not inMainCheckout(root) then
		return
	end
	local ok, res = pcall(function(): boolean
		local _, wrote = unitswrite.write(dir, model, deletionLog(root), templatesOf(root), commit)
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
