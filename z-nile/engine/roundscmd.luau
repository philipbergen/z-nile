--!strict
-- f0421: where an item's reviews stand. `roundscmd.stepFor` is the one reader of an issue's or a raft's review folder
-- (the dispatcher files its next round from it) and `./zn rounds <id> [--kind design|code|final]` prints it in one line.
-- A level is the item's `risk:` (a raft's: its members' highest; a member whose document cannot be read makes it at least
-- normal), the maximum is the level's under the limits it is given, and the latest round is judged by rounds.latest.
local fs = require("@lune/fs")
local models = require("./models")
local rounds = require("./rounds")
local sh = require("../lib/sh")
local store = require("./store")

local roundscmd = {}

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

-- The files of `dir` whose names start with `prefix`, as name -> text.
local function filesWith(dir: string, prefix: string, into: { [string]: string })
	if fs.isDir(dir) then
		for _, f in fs.readDir(dir) do
			if string.sub(f, 1, #prefix) == prefix and fs.isFile(`{dir}/{f}`) then
				into[f] = fs.readFile(`{dir}/{f}`)
			end
		end
	end
end

-- The kind of review `mode` names (zz-review's mode: design, code or final); anything else is design.
function roundscmd.kindOf(mode: string?): string
	return if mode == "code" then "code" elseif mode == "final" then "final" else "design"
end

-- The risk level of `item` read in `cwd`: its `risk:` (a raft's: its members' highest; a member whose document cannot be
-- read makes it at least normal). A bad `risk:` raises. `./zn rounds` and `./zn model --for` read it here.
function roundscmd.levelOf(item: store.Item, cwd: string): rounds.Level
	local docPath = `{cwd}/{item.doc}`
	local risks: { string } = {}
	local unreadable = 0
	local owners: { string } = { item.id }
	if item.kind == "raft" then
		if fs.isFile(docPath) then
			owners = store.idList(store.readFront(docPath).issues)
		else
			owners = {}
			unreadable += 1 -- a missing raft document is an unreadable member: the level is at least normal
		end
	end
	for _, owner in owners do
		local own = if owner == item.id then item else store.find(owner)
		if own and fs.isFile(`{cwd}/{own.doc}`) then
			local risk = store.readFront(`{cwd}/{own.doc}`).risk or ""
			local lvl, problem = rounds.level(risk)
			if not lvl then
				error(`{owner}: {problem}`, 0)
			end
			table.insert(risks, risk)
		else
			unreadable += 1
		end
	end
	return rounds.forMembers(risks, unreadable) :: rounds.Level
end

-- The step for `item`'s `kind` of review, read in `cwd` (the folder the item's files are read in: a worktree).
-- `limitsOf` gives the limits; it is called with the item's directory. A bad `risk:` raises.
function roundscmd.stepFor(
	item: store.Item,
	kind: string,
	cwd: string,
	limitsOf: (string) -> rounds.Limits
): (rounds.Step, rounds.Round?)
	local docPath = `{cwd}/{item.doc}`
	local doc = if fs.isFile(docPath) then fs.readFile(docPath) else ""
	local level = roundscmd.levelOf(item, cwd)
	local max = rounds.max(limitsOf(item.dir), if kind == "design" then "design" else "code", level)
	local files: { [string]: string } = {}
	filesWith(`{cwd}/{item.dir}`, rounds.KINDS[kind][1], files)
	filesWith(`{cwd}/{item.dir}`, rounds.KINDS[kind][2], files)
	local latest = rounds.latest(files, kind, doc, function(issueId: string): boolean
		local found = store.find(issueId)
		return found ~= nil and found.kind == "issue" and found.state == "backlog"
	end)
	return rounds.next(latest, max), latest
end

-- The one line `./zn rounds` prints.
function roundscmd.line(id: string, kind: string, step: rounds.Step, latest: rounds.Round?): string
	local reviewPrefix, refutePrefix = rounds.KINDS[kind][1], rounds.KINDS[kind][2]
	local num = string.format("%03d", step.number)
	local ofMax = ` of at most {step.max}`
	if step.kind == "file" then
		if latest == nil then
			return `{id} {kind}: no review yet; run {kind} review round 1{ofMax}`
		end
		return `{id} {kind}: round {latest.number} answered; run {kind} review round {step.number}{ofMax}`
	elseif step.kind == "answer" then
		return `{id} {kind}: answer {reviewPrefix}{num}.md in {refutePrefix}{num}.md (every finding gets a line)`
	elseif step.kind == "malformed" or step.kind == "rule" then
		return `{id} {kind}: {step.reason or ""}`
	end
	if step.atMaximum then
		local stage = if kind == "design" then "design" else "build"
		return `{id} {kind}: {reviewPrefix}{num}.md settled at the maximum (round {step.number} of {step.max}) with {step.atMaximum} serious findings answered: record it as a guess (./zn guess {id} --step {stage}) so the owner sees it at approval`
	end
	return `{id} {kind}: settled at round {step.number}`
end

-- ./zn rounds <issue-or-raft-id> [--kind design|code|final]: the step the review is at, in one line (read-only).
function roundscmd.run(pos: { string }, opts: { [string]: { string } })
	local id = pos[1]
	if not id then
		error("usage: rounds <issue-or-raft-id> [--kind design|code|final]", 0)
	end
	local item = store.get(id)
	local kind = (opts["--kind"] and opts["--kind"][1]) or (if item.kind == "raft" then "code" else "design")
	if rounds.KINDS[kind] == nil then
		error(`rounds: --kind is design, code or final, not {kind}`, 0)
	end
	local step, latest = roundscmd.stepFor(item, kind, ".", function(dir: string): rounds.Limits
		-- main's files, as the dispatcher and `work next` read them: a working-tree .models.toml never counts
		return models.rounds(models.walkAt(dir, function(rel: string): string?
			local shown = sh.run("git", { "show", `origin/main:{rel}` })
			return if shown.ok then shown.stdout else nil
		end, function(): boolean
			return false
		end))
	end)
	print(trim(roundscmd.line(id, kind, step, latest)))
end

return roundscmd
