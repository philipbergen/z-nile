--!strict
-- c0306: the edge of reviewmodel: reads the review files of an item folder and judges or stamps them.

local fs = require("@lune/fs")
local process = require("@lune/process")
local reviewmodel = require("./reviewmodel")
local sh = require("../lib/sh")
local store = require("./store")

local reviewfiles = {}

-- The review files (design-review, review, final-review) of a folder, name -> text. A folder that is missing is empty.
function reviewfiles.read(dir: string): { [string]: string }
	local out: { [string]: string } = {}
	if not fs.isDir(dir) then
		return out
	end
	for _, name in fs.readDir(dir) do
		if
			(
				string.match(name, "^design%-review%-%d+%.md$")
				or string.match(name, "^review%-%d+%.md$")
				or string.match(name, "^final%-review%-%d+%.md$")
			) and fs.isFile(`{dir}/{name}`)
		then
			out[name] = fs.readFile(`{dir}/{name}`)
		end
	end
	return out
end

-- The refusal for the first review of `kind` in `dir` off the review models, or nil.
function reviewfiles.judge(dir: string, kind: string, owner: string): string?
	return reviewmodel.problem(reviewfiles.read(dir), kind, owner)
end

-- What `./zn done` judges of a marked raft: its own folder, then each member's, for code and final reviews.
function reviewfiles.judgeDone(dirs: { { id: string, dir: string } }): string?
	for _, d in dirs do
		local why = reviewfiles.judge(d.dir, "code", d.id)
		if why then
			return why
		end
	end
	return nil
end

-- Stamps the review file at `path` with the model and effort, or returns the refusal.
function reviewfiles.stampFile(path: string, model: string, effort: string?): string?
	if not fs.isFile(path) then
		return `{path} does not exist`
	end
	local stamped, why = reviewmodel.stamp(fs.readFile(path), model, effort)
	if not stamped then
		return `{path} {why}`
	end
	fs.writeFile(path, stamped)
	return nil
end

-- Whether the item whose folder this is is marked `reviews: judged`: the folder's own document,
-- `<folder>/<folder name>.md`. A folder with no document there is not marked.
function reviewfiles.markedFolder(dir: string): boolean
	local trimmed = string.gsub(dir, "/+$", "")
	local name = string.match(trimmed, "([^/]+)$")
	local doc = if name then `{trimmed}/{name}.md` else ""
	if doc == "" or not fs.isFile(doc) then
		return false
	end
	return reviewmodel.judged(store.readFront(doc))
end

-- What `./zn commit` does with the review files the commit carries (untracked, added or modified; not deleted) that
-- have no `Model:` line. Returns a refusal, or nil after stamping them (with --phase code-review and --model).
-- A review of a marked item is refused without --model under --phase code-review, and under any other phase at all;
-- an unmarked item's is left as it is without --model, and stamped with it.
function reviewfiles.commitReviews(phase: string, model: string?, effort: string?): string?
	local status = sh.run("git", { "status", "--porcelain", "--untracked-files=all" })
	if not status.ok then
		return "cannot read git status"
	end
	local unstamped: { { path: string, marked: boolean } } = {}
	for line in string.gmatch(status.stdout .. "\n", "([^\n]*)\n") do
		local xy, rest = string.match(line, "^(..) (.+)$")
		if xy and rest and not string.find(xy, "D", 1, true) then
			local path = string.match(rest, " %-> (.+)$") or rest
			local base = string.match(path, "([^/]+)$")
			if
				base
				and (string.match(base, "^review%-%d+%.md$") or string.match(base, "^final%-review%-%d+%.md$") or string.match(
					base,
					"^design%-review%-%d+%.md$"
				))
				and fs.isFile(path)
				and reviewmodel.read(fs.readFile(path)) == nil
			then
				table.insert(unstamped, {
					path = path,
					marked = #path > #base
						and reviewfiles.markedFolder(string.sub(path, 1, #path - #base - 1)),
				})
			end
		end
	end
	for _, u in unstamped do
		if u.marked and phase ~= "code-review" then
			return `{u.path} is a review: commit it with --phase code-review --model <the reviewer's model id>`
		elseif u.marked and not model then
			return `{u.path} is a review: --model <the reviewer's model id> records it`
		end
	end
	if phase == "code-review" and model then
		for _, u in unstamped do
			local why = reviewfiles.stampFile(u.path, model, effort)
			if why then
				return why
			end
		end
	end
	return nil
end

-- `--effort <level>`, else CLAUDE_EFFORT when set and not empty, else nil.
function reviewfiles.effortOption(opts: { [string]: { string } }): string?
	local typed = opts["--effort"] and opts["--effort"][1]
	if typed and typed ~= "" then
		return typed
	end
	local env = process.env.CLAUDE_EFFORT
	return if env and env ~= "" then env else nil
end

return reviewfiles
