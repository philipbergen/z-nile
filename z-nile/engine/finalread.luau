--!strict
-- The edge of the ticket's final review (c0262): reads git and the tracker into finalview's inputs, writes
-- the view folder. The rules are finalview.luau's.
local finalview = require("./finalview")
local fs = require("@lune/fs")
local layergit = require("./layergit")
local process = require("@lune/process")
local sh = require("../lib/sh")
local stack = require("./stack")
local store = require("./store")
local trail = require("./trail")

local finalread = {}

export type Where = { layer: stack.Layer, tip: string, base: string }

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

local function showAt(sha: string, path: string): string?
	local r = sh.run("git", { "show", `{sha}:{path}` })
	if r.ok then
		return r.stdout
	end
	return nil
end

-- The layer's tip: the local branch when it is ahead of origin's (a worker's commits not pushed yet), else origin's.
function finalread.tipOf(layer: stack.Layer): string?
	local loc = layergit.shaOf(layer.name)
	local rem = layergit.shaOf(`origin/{layer.name}`)
	if loc and rem and loc ~= rem then
		if sh.run("git", { "merge-base", "--is-ancestor", rem, loc }).ok then
			return loc
		end
		return rem
	end
	return loc or rem
end

-- The layer of `issue`: the newest raft's layer branch for it, its tip, and the base it was built on (the tip
-- of the layer below, or main). nil when the ticket has no layer.
function finalread.where(issue: string): Where?
	local listed =
		sh.run("git", { "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes/origin" })
	if not listed.ok then
		return nil
	end
	local best: stack.Layer? = nil
	for line in string.gmatch(listed.stdout .. "\n", "([^\n]*)\n") do
		local layer = if line == "" then nil else stack.parse(line)
		if layer and layer.issue == issue and (not best or layer.raft > (best :: stack.Layer).raft) then
			best = layer
		end
	end
	if not best then
		return nil
	end
	local layer = best :: stack.Layer
	local tip = finalread.tipOf(layer)
	if not tip then
		return nil
	end
	local base = layergit.mainTip()
	if layer.position > 1 then
		for _, below in layergit.layersOf(layer.raft) do
			if below.position == layer.position - 1 then
				base = finalread.tipOf(below) or base
			end
		end
	end
	return { layer = layer, tip = tip, base = base }
end

local function capturedText(item: store.Item): string
	local commits, _ = trail.read("issues", item.id, trail.isDoc, "origin/main")
	local found = if commits then (trail.capture(commits)) else nil
	if found then
		local shown = showAt(found.sha, found.path)
		if shown then
			return shown
		end
	end
	return if fs.isFile(item.doc) then fs.readFile(item.doc) else ""
end

-- The text of `path` on origin/main, nil when it is not there.
local function onMain(path: string): string?
	return showAt("origin/main", path)
end

-- The view's files for `issue` at `at`. The judged texts (the document, the check, the acceptance specs) come from
-- origin/main's copy of the ticket's folder: the approved prep, never the branch under review. What the layer
-- changed in the design and the decision lines is shown apart, as claims (finalview.changes). A ticket that is not on
-- origin/main (created on the branch) is read at the tip.
function finalread.files(issue: string, at: Where): { [string]: string }
	local item = store.get(issue)
	local raft = at.layer.raft
	local tipDoc = showAt(at.tip, item.doc) or (if fs.isFile(item.doc) then fs.readFile(item.doc) else "")
	local mainDoc = onMain(item.doc)
	local from = if mainDoc then "origin/main" else at.tip
	local baseDoc = mainDoc or tipDoc
	local contract: { [string]: string } = {}
	local check = showAt(from, `{item.dir}/check.sh`)
	if check then
		contract["check.sh"] = check
	end
	local listed = sh.run("git", { "ls-tree", "-r", "--name-only", from, `{item.dir}/acceptance/` })
	if listed.ok then
		local prefix = `{item.dir}/acceptance/`
		for path in string.gmatch(listed.stdout .. "\n", "([^\n]+)\n") do
			local text = showAt(from, path)
			if text then
				contract["acceptance/" .. string.sub(path, #prefix + 1)] = text
			end
		end
	end
	-- three dots: from the merge base of the layer below and this layer, so main moving on does not show as a change
	local range = `{at.base}...{at.tip}`
	local names = sh.run("git", { "diff", "--name-only", range })
	local kept: { string } = { "diff", "--no-color", range, "--" }
	local any = false
	if names.ok then
		for path in string.gmatch(names.stdout .. "\n", "([^\n]+)\n") do
			if finalview.keepPath(path, issue, raft) then
				table.insert(kept, path)
				any = true
			end
		end
	end
	local diff = if any then sh.run("git", kept).stdout else ""
	local patchId = ""
	if diff ~= "" then
		local pid = sh.run("git", { "patch-id", "--stable" }, diff)
		patchId = string.match(pid.stdout, "^(%x+)") or ""
	end
	return finalview.assemble({
		id = issue,
		captured = capturedText(item),
		base = baseDoc,
		tip = tipDoc,
		contract = contract,
		diff = diff,
		patchId = patchId,
	})
end

-- The patch id of the files' diff, read back from a built view: the view id needs it, and a built view does not
-- carry it. finalread.state recomputes both from git.
local function viewIdOf(issue: string, at: Where): string
	local files = finalread.files(issue, at)
	local readme = files["README.md"] or ""
	return string.match(readme, "View: (%x+)") or ""
end

-- The ticket's final reviews: the ones committed on its layer and the ones on origin/main in its folder (a ticket
-- that went back to z-design leaves its off-course reviews on main with the re-prep, so a second off-course
-- verdict still counts after a new raft and layer). By number; the layer's copy wins a repeated number.
function finalread.reviews(issue: string, at: Where?): { finalview.Review }
	local item = store.get(issue)
	local byNumber: { [number]: finalview.Review } = {}
	for _, ref in { "origin/main", if at then at.tip else "" } do
		if ref ~= "" then
			local listed = sh.run("git", { "ls-tree", "--name-only", ref, `{item.dir}/` })
			if listed.ok then
				for path in string.gmatch(listed.stdout .. "\n", "([^\n]+)\n") do
					local n = string.match(path, "/final%-review%-(%d+)%.md$")
					if n then
						byNumber[tonumber(n) :: number] =
							finalview.parse(tonumber(n) :: number, showAt(ref, path) or "")
					end
				end
			end
		end
	end
	local out: { finalview.Review } = {}
	for _, r in byNumber do
		table.insert(out, r)
	end
	table.sort(out, function(x, y)
		return x.n < y.n
	end)
	return out
end

-- The highest review number the ticket has, on its layer or on origin/main.
function finalread.lastNumber(issue: string): number
	local last = 0
	for _, r in finalread.reviews(issue, finalread.where(issue)) do
		if r.n > last then
			last = r.n
		end
	end
	return last
end

function finalread.state(issue: string): finalview.State
	local at = finalread.where(issue)
	local reviews = finalread.reviews(issue, at)
	if #reviews == 0 then
		return {
			state = "none",
			why = if at then "no final review yet" else `{issue} has no layer`,
			latest = "",
		}
	end
	if not at then
		return finalview.state(reviews, "")
	end
	return finalview.state(reviews, viewIdOf(issue, at))
end

-- Where a view for `issue` is written: under ZN_FINAL_VIEW_ROOT, else a folder of the OS temp area. Never inside
-- a checkout, so no CLAUDE.md or AGENTS.md sits above the reviewer's working directory.
function finalread.viewDir(issue: string): string
	local root = process.env.ZN_FINAL_VIEW_ROOT
	if not root or root == "" then
		root = `{process.env.TMPDIR or "/tmp"}/zn-final`
	end
	root = string.gsub(root :: string, "/+$", "")
	return `{root}/{issue}`
end

-- Writes the view folder `dir` (replacing what was there) and returns its file list.
function finalread.write(issue: string, dir: string): { string }
	local at = finalread.where(issue) or error(`{issue} has no layer branch (R<id>/<n>/{issue}) to review`, 0)
	local files = finalread.files(issue, at)
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	local names: { string } = {}
	for path, text in files do
		if not finalview.allowed(path) then
			error(`the view holds only its fixed files: {path}`, 0)
		end
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{dir}/{parent}`)
		end
		fs.writeFile(`{dir}/{path}`, text)
		table.insert(names, path)
	end
	table.sort(names)
	return names
end

finalread.trim = trim

return finalread
