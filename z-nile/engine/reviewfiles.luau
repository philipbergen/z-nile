--!strict
-- c0306: the edge of reviewmodel: reads the review files of an item folder and judges or stamps them.

local fs = require("@lune/fs")
local process = require("@lune/process")
local reviewmodel = require("./reviewmodel")

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
