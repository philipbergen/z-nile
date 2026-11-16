--!strict
-- What counts as tracker state (c0117 design reviews 002 F1, F2 and 003 F1, F4, F8, F10): the one definition every
-- guard that lets "tracker-only" changes reach `main` uses: the git wrapper, the dispatcher's publish broker, the
-- tripwire and the merge gates on a PR's fetched head. Like every guard here it catches honest
-- mistakes and casual misbehaviour; it is not a boundary against a determined agent of the same OS user (the user's
-- "Keep same user, accept detection", 2026-10-21).
--
-- It reads git's raw diff with renames off (`git diff-tree -r --raw --no-renames`), so a rename's source is a deletion
-- it sees, and every side's file mode. A change is tracker state when every path:
--   - is under a project root of the registry it is judged against (`<root>/`, with the slash) or is exactly
--     `z-nile/next`;
--   - is plain: ASCII with no quote or backslash (so no Unicode normalisation games), and no component that is empty,
--     `.`, `..` or `.git` (any case);
--   - is a regular file (100644 or 100755: no symlink, no submodule);
--   - is not git's or the dispatcher's configuration, in any case: `.gitattributes`, `.gitmodules`, `.models.toml`
--     (a setting that grants authority, a gate or a cap, is never tracker state: review 003 F4);
--   - added, doesn't differ only in case from another path of the resulting tree (macOS would overwrite it).
-- With `sequestered`, each item's sequestered files (its `check.sh` and everything under its `acceptance/`, names in
-- that exact case) are judged per item, never per blob (review 003 F1): for every item the change touches, the set of
-- its sequestered files (relative to its folder) is the same before and after, each with the same content, or, for a
-- `check.sh` whose item folder moved, the content `paths.rewrite` gives for that move (as `ready`, `stop` and `done`
-- write it); the item lies in one folder after; and only an item that has no file on the base may add them (a new
-- item's stub). A gate passes `own`, the ids whose sequestered files its PR may change.
local paths = require("./paths")

local trackerstate = {}

export type Entry = {
	oldMode: string,
	newMode: string,
	oldBlob: string,
	newBlob: string,
	status: string,
	path: string,
}
-- a tree: path -> blob
export type Tree = { [string]: string }
export type Options = {
	sequestered: boolean?,
	own: { [string]: boolean }?, -- ids whose sequestered files may change (a gate's own items)
	allow: ((path: string) -> boolean)?, -- paths accepted beyond the roots (a prep gate's skill lessons)
	only: ((path: string) -> string?)?, -- a narrower rule: why a path is not this caller's, or nil
	base: Tree?, -- the trees before and after; without them, what the entries show
	result: Tree?,
	read: ((blob: string) -> string?)?, -- a blob's content (for the rewrite of a moved check.sh)
}

trackerstate.COUNTER = "z-nile/next"
-- git's empty tree: the base of a branch that shares no history with main
trackerstate.EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
local REGULAR = { ["100644"] = true, ["100755"] = true }
local NONE = "000000"
local CONFIG = { [".gitattributes"] = true, [".gitmodules"] = true, [".models.toml"] = true }
local LIFECYCLE = { active = true, done = true, retired = true }

-- `git diff-tree -r --raw --no-renames` lines (`:<old mode> <new mode> <old blob> <new blob> <status>\t<path>`).
function trackerstate.parseRaw(text: string): ({ Entry }?, string?)
	local out: { Entry } = {}
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 1) == ":" then
			local om, nm, ob, nb, st, path = string.match(line, "^:(%d+) (%d+) (%x+) (%x+) (%u)%d*\t(.+)$")
			if not om then
				return nil, `not a raw diff line: {line}`
			end
			table.insert(out, {
				oldMode = om :: string,
				newMode = nm :: string,
				oldBlob = ob :: string,
				newBlob = nb :: string,
				status = st :: string,
				path = path :: string,
			})
		end
	end
	return out, nil
end

-- `git ls-tree -r --full-tree` lines (`<mode> <type> <blob>\t<path>`) as a tree.
function trackerstate.parseTree(text: string): Tree
	local out: Tree = {}
	for line in string.gmatch(text, "[^\n]+") do
		local blob, path = string.match(line, "^%d+ %a+ (%x+)\t(.+)$")
		if blob and path then
			out[path] = blob
		end
	end
	return out
end

local function under(path: string, roots: { string }): boolean
	if path == trackerstate.COUNTER then
		return true
	end
	for _, r in roots do
		local prefix = r .. "/"
		if string.sub(path, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

-- why `path` is not plain, or nil
local function plain(path: string): string?
	if string.find(path, "[^%w%._%-/]") then
		return "a character outside ASCII letters, digits, `.`, `_`, `-` and `/`"
	end
	for _, seg in string.split(path, "/") do
		local low = string.lower(seg)
		if seg == "" or seg == "." or seg == ".." or low == ".git" then
			return `a path component "{seg}"`
		end
	end
	return nil
end

-- The item a path belongs to: `<root>/<issues|rafts>/[active/|done/|retired/]<ID>/<rel>` -> id, its folder, rel.
function trackerstate.itemOf(path: string, roots: { string }): (string?, string?, string?)
	for _, r in roots do
		local prefix = r .. "/"
		if string.sub(path, 1, #prefix) == prefix then
			local rest = string.sub(path, #prefix + 1)
			local kind, tail = string.match(rest, "^(%a+)/(.+)$")
			if (kind == "issues" or kind == "rafts") and tail then
				local life, after = string.match(tail :: string, "^(%a+)/(.+)$")
				local lead = ""
				if life and LIFECYCLE[life :: string] then
					lead, tail = life .. "/", after
				end
				local id, rel = string.match(tail :: string, "^([%w]+)/(.+)$")
				local okId = id
					and (
						if kind == "issues"
							then string.match(id, "^[fdc]%d%d%d%d$") ~= nil
							else string.match(id, "^R%d%d%d%d$") ~= nil
					)
				if okId then
					return id, `{r}/{kind}/{lead}{id}`, rel
				end
			end
		end
	end
	return nil, nil, nil
end

local function isSequesteredRel(rel: string): boolean
	return rel == "check.sh" or string.sub(rel, 1, 11) == "acceptance/"
end

-- an item's sequestered files in a tree: rel -> { blob, dir }, and every folder the item has there
local function seqMap(
	tree: Tree,
	id: string,
	roots: { string }
): ({ [string]: { blob: string, dir: string } }, { [string]: boolean }, boolean)
	local out: { [string]: { blob: string, dir: string } } = {}
	local dirs: { [string]: boolean } = {}
	local any = false
	for path, blob in tree do
		local pid, dir, rel = trackerstate.itemOf(path, roots)
		if pid == id then
			any = true
			dirs[dir :: string] = true
			if isSequesteredRel(rel :: string) then
				out[rel :: string] = { blob = blob, dir = dir :: string }
			end
		end
	end
	return out, dirs, any
end

local function count(set: { [string]: any }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

-- Whether `entries` are tracker state against `roots`. Returns nil when they are, else why not, naming the first path.
-- `opts` may be `true` (sequestered, judged from the entries alone).
function trackerstate.judge(entries: { Entry }, roots: { string }, given: (boolean | Options)?): string?
	local opts: Options = if type(given) == "table" then given :: Options else { sequestered = given == true }
	-- the trees: given, or what the entries show (enough for the per-item rule: files they don't touch are equal)
	local base: Tree = opts.base or {}
	local result: Tree = opts.result or {}
	if not opts.base or not opts.result then
		for _, e in entries do
			if e.oldMode ~= NONE and not opts.base then
				base[e.path] = e.oldBlob
			end
			if e.newMode ~= NONE and not opts.result then
				result[e.path] = e.newBlob
			end
		end
	end
	local folded: { [string]: number } = {}
	for path in result do
		local low = string.lower(path)
		folded[low] = (folded[low] or 0) + 1
	end
	local touched: { [string]: boolean } = {}
	for _, e in entries do
		local name = string.lower(basename(e.path))
		local bad = plain(e.path)
		if bad then
			return `{e.path} is not tracker state ({bad})`
		end
		if not under(e.path, roots) and not (opts.allow and opts.allow(e.path)) then
			return `{e.path} is not tracker state (not under a project root's folder or {trackerstate.COUNTER})`
		end
		if CONFIG[name] then
			return `{e.path} is not tracker state (configuration: git's, or a setting that grants authority)`
		end
		for _, mode in { e.oldMode, e.newMode } do
			if mode ~= NONE and not REGULAR[mode] then
				return `{e.path} is not tracker state (mode {mode}: a link or a submodule)`
			end
		end
		if e.status == "A" and (folded[string.lower(e.path)] or 0) > 1 then
			return `{e.path} is not tracker state (another path differs from it only in case)`
		end
		if opts.only then
			local why = opts.only(e.path)
			if why then
				return why
			end
		end
		local id, _, rel = trackerstate.itemOf(e.path, roots)
		if opts.sequestered and id then
			local r = rel :: string
			if isSequesteredRel(string.lower(r)) and not isSequesteredRel(r) then
				return `{e.path} is a sequestered name in another case`
			end
			if isSequesteredRel(r) and not (opts.own and opts.own[id :: string]) then
				touched[id :: string] = true
			end
		end
	end
	if not next(touched) then
		return nil
	end
	-- the folders every touched item moved to (for paths.rewrite, as moveOnOrigin computes them)
	local moved: { [string]: string } = {}
	for _, e in entries do
		local id = trackerstate.itemOf(e.path, roots)
		if id and not moved[id :: string] then
			local _, before = seqMap(base, id :: string, roots)
			local _, after = seqMap(result, id :: string, roots)
			local only = next(after)
			if count(after) == 1 and not before[only :: string] then
				moved[id :: string] = only :: string
			end
		end
	end
	for id in touched do
		local before, _, existed = seqMap(base, id, roots)
		local after, afterDirs = seqMap(result, id, roots)
		if existed then
			if count(afterDirs) > 1 then
				return `{id}'s files lie in two folders after the change (its sequestered files may only move with it)`
			end
			for rel, b in before do
				local a = after[rel]
				if not a then
					return `{b.dir}/{rel} is sequestered: a step may move it with its item, never remove it`
				end
				if a.blob ~= b.blob then
					local same = false
					if rel == "check.sh" and a.dir ~= b.dir and opts.read then
						local old, new = opts.read(b.blob), opts.read(a.blob)
						same = old ~= nil and new ~= nil and paths.rewrite(old :: string, moved) == new
					end
					if not same then
						return `{a.dir}/{rel} is sequestered: a step may move it with its item, never change it`
					end
				end
			end
			for rel, a in after do
				if not before[rel] then
					return `{a.dir}/{rel} is sequestered: a step may not add one to an item that exists`
				end
			end
		end
	end
	return nil
end

export type Git = (args: { string }) -> (boolean, string)

-- The raw diff of `base..sha` through `git` (a function running git in the repository), judged with both trees.
-- Returns nil when it is tracker state, else why not (a git failure is a refusal: fail closed).
function trackerstate.check(
	git: Git,
	base: string,
	sha: string,
	roots: { string },
	given: (boolean | Options)?
): string?
	local ok, raw = git({ "diff-tree", "-r", "--raw", "--no-renames", "--no-abbrev", base, sha })
	if not ok then
		return `could not read the change {base}..{sha}`
	end
	local entries, err = trackerstate.parseRaw(raw)
	if not entries then
		return err
	end
	local opts: Options = if type(given) == "table"
		then table.clone(given :: Options)
		else { sequestered = given == true }
	local okBase, baseTree = git({ "ls-tree", "-r", "--full-tree", base })
	local okResult, resultTree = git({ "ls-tree", "-r", "--full-tree", sha })
	if not okBase or not okResult then
		return `could not read the trees of {base}..{sha}`
	end
	opts.base = trackerstate.parseTree(baseTree)
	opts.result = trackerstate.parseTree(resultTree)
	opts.read = function(blob: string): string?
		local okRead, text = git({ "cat-file", "blob", blob })
		return if okRead then text else nil
	end
	return trackerstate.judge(entries :: { Entry }, roots, opts)
end

-- Each first-parent commit of `from..to`, judged against its own parent by its parent's registry (`rootsAt`), as the
-- tripwire judges main during a run (review 003 F10: the broker judges the same way, so it never pushes what that
-- check refuses). `pass(sha)` may accept a commit that isn't tracker state (a pull request's merge into main).
-- Returns nil, or why
-- the first refused commit is refused.
function trackerstate.checkEach(
	git: Git,
	from: string,
	to: string,
	rootsAt: (ref: string) -> { string }?,
	given: (boolean | Options)?,
	pass: ((sha: string) -> boolean)?
): string?
	local ok, list = git({ "rev-list", "--reverse", "--first-parent", `{from}..{to}` })
	if not ok then
		return `could not list {from}..{to}`
	end
	for sha in string.gmatch(list, "%x+") do
		local okParent, parent = git({ "rev-parse", "--verify", "-q", `{sha}^1` })
		local base = if okParent then parent else trackerstate.EMPTY_TREE
		local roots = rootsAt(if okParent then parent else sha)
		local why = if roots
			then trackerstate.check(git, base, sha, roots :: { string }, given)
			else "the registry could not be read"
		if why and not (pass and pass(sha)) then
			return `{sha}: {why}`
		end
	end
	return nil
end

return trackerstate
