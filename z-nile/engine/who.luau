--!strict
-- c0280: the history of one ticket, read from git and the record. The one reader of `./zn who` and of the board
-- (c0284). Git is read here: the item's life on the mainline (one `git log` through trail), every author's email (one
-- `git log --format=%ae`), the Co-Authored-By values of each merge's second parent, and the document's status word and
-- `raft:` after each of its commits (ONE `git cat-file --batch` for any number of commits, so the board reads every
-- item's in the same process). The pure functions of provenance turn it into entries.
local process = require("@lune/process")

local provenance = require("./provenance")
local sh = require("../lib/sh")
local store = require("./store")
local trail = require("./trail")

local who = {}

local function git(args: { string }): string?
	local r = process.exec("git", args)
	return if r.ok then r.stdout else nil
end

-- the names `trail.read` is asked for: an item's document and its record
function who.want(name: string): boolean
	return trail.isDoc(name) or name == "provenance.md"
end

-- The history `who` reads: the published mainline (`origin/main`), else this checkout's `HEAD`. A worktree's own
-- unpublished commits are not history yet, and a branch's `done` commit is no merge.
function who.head(): string
	return if process.exec("git", { "rev-parse", "--verify", "-q", "origin/main" }).ok
		then "origin/main"
		else "HEAD"
end

-- Every commit author's email on `head`, lower-cased: a person is whoever commits, so a Co-Authored-By trailer with one
-- of these is a person's, not an agent's (E4). One `git log` for the whole history.
function who.people(head: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for email in string.gmatch(git({ "log", "--format=%ae", head }) or "", "[^\n]+") do
		out[string.lower(email)] = true
	end
	return out
end

-- The document's status word and `raft:` after each of `commits`' document changes (an add or a modify; a delete has
-- none), keyed `<sha>:<path>`, from one `git cat-file --batch` for all of them.
function who.fronts(commits: { trail.Commit }): { [string]: provenance.Front }
	local specs: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, c in commits do
		local key = `{c.sha}:{c.path}`
		if
			c.doc
			and c.status ~= "D"
			and not seen[key]
			and string.match(c.path, "/provenance%.md$") == nil
		then
			seen[key] = true
			table.insert(specs, key)
		end
	end
	local out: { [string]: provenance.Front } = {}
	if #specs == 0 then
		return out
	end
	local r = sh.run("git", { "cat-file", "--batch" }, table.concat(specs, "\n") .. "\n")
	local text, pos = r.stdout, 1
	for _, key in specs do
		local eol = string.find(text, "\n", pos, true)
		if not eol then
			break
		end
		local header = string.sub(text, pos, eol - 1)
		pos = eol + 1
		local size = tonumber(string.match(header, "^%x+ %a+ (%d+)$") or "")
		if size then
			local body = string.sub(text, pos, pos + size - 1)
			pos += size + 1
			local front = store.parseFront(body)
			out[key] = { status = front.status or "", raft = front.raft or "" }
		end
	end
	return out
end

-- Sets `sideTrailers` on every merge commit of `life`: the Co-Authored-By values of its second parent (the top layer of
-- a `--no-ff` landing, which `./zn finish` committed with the agent's trailer). One `git log -1` per merge.
function who.sideTrailers(life: { trail.Commit })
	for _, c in life do
		local parents = c.parents or {}
		if #parents >= 2 and c.sideTrailers == nil then
			local values: { string } = {}
			local text = git({
				"log",
				"-1",
				"--format=%(trailers:key=Co-Authored-By,valueonly,unfold,separator=%x1f)",
				parents[2],
			}) or ""
			for value in string.gmatch(text, "[^\31\n]+") do
				table.insert(values, value)
			end
			for _, other in life do
				if other.sha == c.sha then
					other.sideTrailers = values
				end
			end
		end
	end
end

-- The note a cut or an ambiguous life carries, as `capture` prints it; "" for a plain life.
function who.mark(notes: { trail.Cut }, ambiguous: boolean): provenance.Mark
	local parts: { string } = {}
	for _, note in notes do
		table.insert(parts, `history before {note.sha} not followed: it changed {note.file}`)
	end
	if ambiguous then
		table.insert(parts, "ambiguous: two items held this id at once")
	end
	return { note = table.concat(parts, "; "), cut = #notes > 0 }
end

-- Reads `id`'s life on `head`, the mainline: the commits (side trailers set) and the note of a cut or ambiguous life; or
-- nil and why when the id has no history there.
function who.life(id: string, head: string): ({ trail.Commit }?, provenance.Mark, string?)
	local kind = if string.sub(id, 1, 1) == "R" then "rafts" else "issues"
	local commits, notes = trail.read(kind, id, who.want, head, nil, true)
	local hasDoc = false
	local seen: { trail.Commit } = commits or {}
	for _, c in seen do
		hasDoc = hasDoc or c.doc
	end
	if commits == nil or not hasDoc then
		return nil, { note = "", cut = false }, `no history for {id} on {head}`
	end
	who.sideTrailers(commits)
	return commits, who.mark(notes, trail.ambiguous(commits)), nil
end

-- The history of one item as entries, oldest first: the git side from `life` (`who.life`'s answer), the stored `rows`
-- and the spend rows `spend` (file order), `fronts` from `who.fronts` (for the board: one call for every item).
function who.entries(
	life: { trail.Commit },
	people: { [string]: boolean },
	rows: { provenance.Row },
	spend: { provenance.Spend },
	fronts: { [string]: provenance.Front },
	mark: provenance.Mark
): { provenance.Entry }
	local derived = provenance.select(life, people, fronts, mark)
	return provenance.merge(derived, rows, provenance.workerOf(provenance.workerRow(spend)))
end

return who
