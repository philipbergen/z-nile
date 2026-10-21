--!strict
-- c0120: the one rewrite finished items' check.sh files get (decided with the user, 2026-10-21: "Rewrite them too").
-- It is the user's exception to "sequestered files never change", for finished items only, in c0120's edits commit.
-- A literal path in a finished check.sh that resolved from the repository root before the move, and that does not
-- resolve from the item's home after it, becomes the path from the home to where the move put the file (or, for a file
-- the move left in place, the path from the home to it). Nothing else changes: prose, comments, a path that already
-- resolves from the home, and a path that was already stale before the move all stay as they are. Used by
-- finished.spec.luau (the rule and its fixture) and finished.luau (each finished file is its pre-move text, rewritten),
-- and once by the executor to make the rewrite (z-nile/.tracker/issues/c0120/rewrite-finished.luau).
local fs = require("@lune/fs")
local process = require("@lune/process")

local rewrites = {}

-- A finished file the move takes (pickman's first raft's check.sh): the commit that removed it from its old place is
-- the move, squashed into one commit or not, and its parent the tree before the move.
rewrites.MARK = "tracker/rafts/done/R0001/check.sh"

-- What a word must look like to be a literal path (the same reading as check-paths.spec.luau's): no `$`, not absolute
-- or an option, and either after `lune run` (then with .luau), a root file of a home, or under a top-level folder.
local PREFIXES =
	{ "src/", "tests/", "scripts/", "z-nile/", "pickman/", "tracker/", ".tracker/", ".github/", ".claude/" }
local FILES = { ["default.project.json"] = true, ["lobby.project.json"] = true, zn = true, ["./zn"] = true }

export type Literal = { line: number, first: number, last: number, word: string, path: string, dir: string }

-- The literal paths of `text` with where each word sits: its line, its first and last byte in that line, the word as
-- written, the path it names (with .luau after `lune run`), and the folder an earlier `cd` on the line moved to.
function rewrites.literals(text: string): { Literal }
	local out: { Literal } = {}
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if string.match(line, "^%s*#") then
			continue
		end
		-- the scanned part: a trailing comment and a check's label (prose) are blanked, keeping every byte's place
		local scanned = string.gsub(line, "(%s#%s.*)$", function(c: string): string
			return string.rep(" ", #c)
		end)
		local ls, le = string.find(scanned, '^%s*check%s+"[^"]*"')
		if ls then
			local q = string.find(scanned, '"', 1, true) :: number
			scanned = string.sub(scanned, 1, q - 1)
				.. string.rep(" ", (le :: number) - q + 1)
				.. string.sub(scanned, (le :: number) + 1)
		end
		local words: { { w: string, first: number, last: number } } = {}
		local i = 1
		while true do
			local s, e = string.find(scanned, "[^%s\"'();|&<>`]+", i)
			if not s then
				break
			end
			local w = string.sub(scanned, s, e :: number)
			local trimmed = string.gsub(w, "[\\,]+$", "")
			table.insert(words, { w = trimmed, first = s, last = s + #trimmed - 1 })
			i = (e :: number) + 1
		end
		local dir = ""
		for k, word in words do
			local w = word.w
			if k > 1 and words[k - 1].w == "cd" and not string.find(w, "$", 1, true) then
				dir = w .. "/"
				continue
			end
			if string.find(w, "$", 1, true) or string.sub(w, 1, 1) == "/" or string.sub(w, 1, 1) == "-" then
				continue
			end
			local path: string? = nil
			if
				k > 2
				and words[k - 2].w == "lune"
				and words[k - 1].w == "run"
				and string.find(w, "/", 1, true)
			then
				path = if string.match(w, "%.luau$") then w else w .. ".luau"
			elseif FILES[w] then
				path = if w == "./zn" then "zn" else w
			else
				for _, p in PREFIXES do
					if string.sub(w, 1, #p) == p and #w > #p then
						path = w
					end
				end
			end
			if path then
				table.insert(
					out,
					{ line = n, first = word.first, last = word.last, word = w, path = path, dir = dir }
				)
			end
		end
	end
	return out
end

-- `to` (a path from the repository root) as seen from the folder `from` (also from the root; "" is the root itself)
function rewrites.relative(from: string, to: string): string
	local a: { string } = {}
	for seg in string.gmatch(from, "[^/]+") do
		table.insert(a, seg)
	end
	local b: { string } = {}
	for seg in string.gmatch(to, "[^/]+") do
		table.insert(b, seg)
	end
	local i = 1
	while i <= #a and i <= #b and a[i] == b[i] do
		i += 1
	end
	local out: { string } = {}
	for _ = i, #a do
		table.insert(out, "..")
	end
	for k = i, #b do
		table.insert(out, b[k])
	end
	return table.concat(out, "/")
end

-- What the rewrite needs to know about the repository: whether a root-relative path (a glob matches one file) existed
-- before the move and exists now, and where the move put a root-relative path (nil when it stayed).
export type World = {
	before: (path: string) -> boolean,
	now: (path: string) -> boolean,
	moved: (path: string) -> string?,
}

local function git(top: string, args: { string }): (boolean, string)
	local r = process.exec("git", args, { cwd = top })
	return r.ok, r.stdout
end

local function trimSlash(p: string): string
	return (string.gsub(p, "/+$", ""))
end

-- a glob as a Lua pattern over a whole path (`*` within one segment), and its literal part: the folders before the
-- first segment with a `*`; nil for a path without `*`
local function glob(p: string): (string?, string?)
	if not string.find(p, "*", 1, true) then
		return nil, nil
	end
	local lua = "^" .. string.gsub(string.gsub(p, "[%.%-%+%?%[%]%^%$%(%)%%]", "%%%0"), "%*", "[^/]*") .. "$"
	local fixed: { string } = {}
	for seg in string.gmatch(p, "[^/]+") do
		if string.find(seg, "*", 1, true) then
			break
		end
		table.insert(fixed, seg)
	end
	return lua, table.concat(fixed, "/")
end

-- The tree before the move, in the checkout at `top`: the parent of the commit that removed MARK. Nil and why when the
-- move hasn't happened (MARK is still there) or the history can't tell (a shallow clone).
function rewrites.premove(top: string): (string?, string?)
	if fs.isFile(`{top}/{rewrites.MARK}`) then
		return nil, `{rewrites.MARK} is still in the tree: the move hasn't happened`
	end
	local ok, sha = git(top, { "log", "-1", "--format=%H", "--", rewrites.MARK })
	sha = string.gsub(sha, "%s+$", "")
	if not ok or sha == "" then
		return nil, `no commit removed {rewrites.MARK}: the history is shallow or the move hasn't happened`
	end
	local okP, parent = git(top, { "rev-parse", "--verify", "-q", sha .. "^" })
	parent = string.gsub(parent, "%s+$", "")
	if not okP or parent == "" then
		return nil, `the move {sha} has no parent in this history`
	end
	return parent, nil
end

-- The World of the checkout at `top`, `pre` being the tree before the move: `before` reads that tree, `now` the
-- working tree, and `moved` the renames git finds between them.
function rewrites.world(top: string, pre: string): World
	local okL, listing = git(top, { "ls-tree", "-r", "--name-only", pre })
	assert(okL, `git ls-tree {pre} failed`)
	local files: { [string]: boolean } = {}
	local dirs: { [string]: boolean } = {}
	for f in string.gmatch(listing, "[^\n]+") do
		files[f] = true
		local d = string.match(f, "^(.*)/[^/]+$")
		while d do
			dirs[d] = true
			d = string.match(d, "^(.*)/[^/]+$")
		end
	end
	local okR, renames = git(top, { "diff", "-M", "--name-status", "--diff-filter=R", pre, "HEAD" })
	assert(okR, `git diff {pre} HEAD failed`)
	local map: { { old: string, new: string } } = {}
	for line in string.gmatch(renames, "[^\n]+") do
		local old, new = string.match(line, "^R%d*\t([^\t]+)\t([^\t]+)$")
		if old and new then
			table.insert(map, { old = old, new = new })
		end
	end
	-- the working tree's files (tracked and untracked, ignored ones aside), read once, for globs
	local nowFiles: { string }? = nil
	local function listNow(): { string }
		if not nowFiles then
			local okN, out = git(top, { "ls-files", "-co", "--exclude-standard" })
			assert(okN, "git ls-files failed")
			local list: { string } = {}
			for f in string.gmatch(out, "[^\n]+") do
				table.insert(list, f)
			end
			nowFiles = list
		end
		return nowFiles :: { string }
	end
	-- does a path in `list` (or a folder above one) match the Lua pattern?
	local function anyMatch(list: { string }, lua: string): boolean
		for _, f in list do
			local d: string? = f
			while d do
				if string.match(d :: string, lua) then
					return true
				end
				d = string.match(d :: string, "^(.*)/[^/]+$")
			end
		end
		return false
	end
	local beforeList: { string } = {}
	for f in files do
		table.insert(beforeList, f)
	end
	local function existsBefore(p: string): boolean
		local lua = glob(p)
		if lua then
			return anyMatch(beforeList, lua)
		end
		local q = trimSlash(p)
		return files[q] == true or dirs[q] == true
	end
	local function existsNow(p: string): boolean
		local lua = glob(p)
		if lua then
			return anyMatch(listNow(), lua)
		end
		local q = trimSlash(p)
		return fs.isFile(`{top}/{q}`) or fs.isDir(`{top}/{q}`)
	end
	local function movedTo(p: string): string?
		local q = trimSlash(p)
		local tail = ""
		local _, fixed = glob(q)
		if fixed then -- a glob moves with its literal folders
			tail = string.sub(q, #fixed + 1)
			q = fixed
		end
		for _, m in map do
			if m.old == q then
				return m.new .. tail
			end
			if string.sub(m.old, 1, #q + 1) == q .. "/" then
				local rest = string.sub(m.old, #q + 1)
				if string.sub(m.new, -#rest) == rest then
					return string.sub(m.new, 1, #m.new - #rest) .. tail
				end
			end
		end
		return nil
	end
	return { before = existsBefore, now = existsNow, moved = movedTo }
end

-- `text` (a finished check.sh) rewritten for its item's home `home` ("pickman", "z-nile").
function rewrites.rewrite(text: string, home: string, world: World): string
	local lits = rewrites.literals(text)
	local byLine: { [number]: { Literal } } = {}
	for _, l in lits do
		byLine[l.line] = byLine[l.line] or {}
		table.insert(byLine[l.line], l)
	end
	local out: { string } = {}
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		local list = byLine[n]
		if list then
			-- right to left, so earlier bytes keep their places
			table.sort(list, function(x: Literal, y: Literal): boolean
				return x.first > y.first
			end)
			for _, l in list do
				local seenFrom = if l.dir == "" then home else `{home}/{l.dir}`
				local fromHome = `{seenFrom}/{l.path}`
				if world.before(l.dir .. l.path) and not world.now(fromHome) then
					local target = world.moved(l.dir .. l.path) or (l.dir .. l.path)
					local new = rewrites.relative(seenFrom, trimSlash(target))
					if string.sub(l.word, -1) == "/" then
						new ..= "/"
					end
					if
						l.path ~= l.word
						and string.sub(new, -5) == ".luau"
						and string.sub(l.word, -5) ~= ".luau"
					then
						new = string.sub(new, 1, -6) -- `lune run tests/run` names no .luau
					end
					-- a file in the home itself is named ./<file>: a bare word in a command's place would be looked up
					-- in PATH
					if not string.find(new, "/", 1, true) then
						new = "./" .. new
					end
					line = string.sub(line, 1, l.first - 1) .. new .. string.sub(line, l.last + 1)
				end
			end
		end
		table.insert(out, line)
	end
	-- gmatch over text .. "\n" yields one line more when the text ends with a newline, so the join ends as it did
	return table.concat(out, "\n")
end

return rewrites
