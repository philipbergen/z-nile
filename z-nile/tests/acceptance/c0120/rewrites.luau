--!strict
-- c0120: the one rewrite finished items' check.sh files get (decided with the user, 2026-10-21: "Rewrite them too").
-- It is the user's exception to "sequestered files never change", for finished items only, in c0120's edits commit.
-- A literal path in a finished check.sh that resolved from the repository root before the move, and that does not
-- resolve from the item's home after it, becomes the path from the home to where the move put the file (or, for a file
-- the move left in place, the path from the home to it). Nothing else changes: prose, comments, a path that already
-- resolves from the home, and a path that was already stale before the move all stay as they are. Used by
-- finished.spec.luau (the rule and its fixture) and finished.luau (each finished file is its pre-move text, rewritten),
-- and once by the executor to make the rewrite (z-nile/.tracker/issues/c0120/rewrite-finished.luau).
local process = require("@lune/process")

local rewrites = {}

-- A finished file the move takes (pickman's first raft's check.sh): the commit that removed it from its old place is
-- the move, squashed into one commit or not, and its parent the tree before the move.
rewrites.MARK = "tracker/rafts/done/R0001/check.sh"

-- What a word must look like to be a literal path (the same reading as check-paths.spec.luau's): no `$`, not absolute
-- or an option, and either after `lune run` (then with .luau), a root file of a home, or under a top-level folder.
local PREFIXES =
	{ "src/", "tests/", "scripts/", "z-nile/", "pickman/", "tracker/", ".tracker/", ".github/", ".claude/" }
-- A file named alone (no folder) is a path only outside double quotes: in quotes it is a message, a case's name or
-- a grep pattern (c0099's), found by running the finished checks by hand
local FILES = {
	["default.project.json"] = true,
	["lobby.project.json"] = true,
	zn = true,
	["./zn"] = true,
	-- the repository root's own files (found by running the finished checks by hand)
	["AGENTS.md"] = true,
	["CLAUDE.md"] = true,
	["SETUP.md"] = true,
	["rokit.toml"] = true,
	["selene.toml"] = true,
	["stylua.toml"] = true,
	[".luaurc"] = true,
	[".gitignore"] = true,
}
-- A file named alone is a path only outside quotes and not right after one (c0053's `merging='zn sync…'` is a
-- pattern, c0042's `for s in "./zn board"` a list of patterns), or as the command of a command substitution, quoted
-- or not (`"$(./zn find f0014)/check.sh"`)
local function substituted(line: string, first: number): boolean
	return first > 2 and string.sub(line, first - 2, first - 1) == "$("
end
-- a top-level folder a move takes, named alone: a path only as a folder `find` searches (in prose it is a word)
local FOLDERS = { tracker = true, src = true, tests = true }

-- The words of a grep's pattern (a pattern names text, not a file: c0046's `grep -qF "./zn worktree" …`): after
-- `grep` or `rg` and its options, the first other word, or each `-e`'s; a quoted pattern runs to its closing quote.
-- `line` is the scanned line, `raw[k]` the k-th word as written and `starts[k]` its first byte.
local function patternWords(line: string, raw: { string }, starts: { number }): { [number]: boolean }
	local marked: { [number]: boolean } = {}
	local function mark(k: number)
		local s = starts[k]
		local q = if s > 1 then string.sub(line, s - 1, s - 1) else ""
		if q == '"' or q == "'" then
			local close = string.find(line, q, s, true) or (#line + 1)
			for j = k, #raw do
				if starts[j] < close then
					marked[j] = true
				end
			end
		else
			marked[k] = true
		end
	end
	for k, w in raw do
		if w == "grep" or w == "rg" or w == "egrep" then
			local j, named = k + 1, false
			while raw[j] and string.sub(raw[j], 1, 1) == "-" and raw[j] ~= "--" do
				if raw[j] == "-e" or raw[j] == "--regexp" then
					if raw[j + 1] then
						mark(j + 1)
						named = true
					end
					j += 2
				else
					j += 1
				end
			end
			if raw[j] == "--" then
				j += 1
			end
			if not named and raw[j] then
				mark(j)
			end
		end
	end
	return marked
end

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
		local words: { { w: string, first: number, last: number, quoted: boolean } } = {}
		local i = 1
		while true do
			local s, e = string.find(scanned, "[^%s\"'();|&<>`]+", i)
			if not s then
				break
			end
			local w = string.sub(scanned, s, e :: number)
			local trimmed = string.gsub(w, "[\\,]+$", "")
			-- a shell assignment's value is the word (`f=.claude/skills/testing/SKILL.md`)
			local name = string.match(trimmed, "^[%a_][%w_]*=")
			if name and #trimmed > #name then
				trimmed = string.sub(trimmed, #name + 1)
				s += #name
			end
			local _, quotes = string.gsub(string.sub(scanned, 1, s - 1), '"', "")
			table.insert(words, { w = trimmed, first = s, last = s + #trimmed - 1, quoted = quotes % 2 == 1 })
			i = (e :: number) + 1
		end
		local raw: { string } = {}
		local starts: { number } = {}
		for k, word in words do
			raw[k] = word.w
			starts[k] = word.first
		end
		local pattern = patternWords(scanned, raw, starts)
		local dir = ""
		local finding = false -- the words after `find`, before its first option, are the folders it searches
		for k, word in words do
			if pattern[k] then
				continue
			end
			local w = word.w
			local last = word.last
			-- a word that goes on with a variable: its literal folder is the path (`.claude/skills/$f/SKILL.md`)
			local dollar = string.find(w, "$", 1, true)
			if dollar and dollar > 1 then
				local folder = string.match(string.sub(w, 1, dollar - 1), "^(.*)/[^/]*$")
				if folder and folder ~= "" then
					w = folder .. "/"
					last = word.first + #w - 1
				end
			end
			if w == "find" then
				finding = true
				continue
			elseif string.sub(w, 1, 1) == "-" then
				finding = false
			end
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
			elseif
				FILES[w]
				and (
					substituted(scanned, word.first)
					or not (
						word.quoted
						or string.find(string.sub(scanned, word.first - 1, word.first - 1), "[\"']")
					)
				)
			then
				path = if w == "./zn" then "zn" else w
			elseif finding and FOLDERS[w] then
				path = w
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
					{ line = n, first = word.first, last = last, word = w, path = path, dir = dir }
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

-- The main this checkout merged, from the published tip, never the local ref (code review 008 F1: the author can move
-- refs/remotes/origin/main to an unpublished commit and merge it). `git ls-remote origin refs/heads/main` gives the tip
-- (read-only; the fence allows it); it must be a commit here (fetched), and M is `git merge-base HEAD <tip>`, an
-- ancestor of the tip by construction. Nil and why on any doubt: unreadable, not fetched, no merge-base, or a main that
-- already holds the move. The one reader of that base: AC18 (finished.luau) and override-markers.luau.
function rewrites.mainBase(top: string): (string?, string?)
	local okR, out = git(top, { "ls-remote", "origin", "refs/heads/main" })
	-- exactly one line naming refs/heads/main itself: ls-remote matches the pattern against each ref's tail, so
	-- refs/heads/a/refs/heads/main is listed too (code review 009 F5)
	local tips: { string } = {}
	if okR then
		for line in string.gmatch(out, "[^\n]+") do
			local sha = string.match(line, "^(%x+)\trefs/heads/main$")
			if sha then
				table.insert(tips, sha)
			end
		end
	end
	if #tips ~= 1 then
		return nil, "cannot read origin's main (git ls-remote origin refs/heads/main): refusing"
	end
	local tip = tips[1]
	if not git(top, { "cat-file", "-e", tip .. "^{commit}" }) then
		return nil, `origin's main {tip} is not here: run ./zn sync --fetch, then again`
	end
	local okM, base = git(top, { "merge-base", "HEAD", tip })
	base = string.gsub(base, "%s+$", "")
	if not okM or base == "" then
		return nil, `no merge-base of HEAD and origin's main {tip}: refusing`
	end
	local okMove, move = git(top, { "log", "-1", "--format=%H", "--", rewrites.MARK })
	move = string.gsub(move, "%s+$", "")
	if okMove and move ~= "" and git(top, { "merge-base", "--is-ancestor", move, base }) then
		return nil,
			"origin's main already holds the move, so the branch's own changes can't be told apart: refusing"
	end
	return base, nil
end

-- the URL `origin` resolves to (after any insteadOf), printed with every verdict: AC18 trusts the origin it resolves,
-- and a reviewer checks this line (code review 009 F4; the testing skill's "Caught only by review")
function rewrites.originUrl(top: string): string
	local ok, url = git(top, { "ls-remote", "--get-url", "origin" })
	return if ok then (string.gsub(url, "%s+$", "")) else "(none)"
end

-- The tree before the move, in the checkout at `top`: the parent of the commit that removed MARK. Nil and why when the
-- move hasn't happened (MARK is still there) or the history can't tell (a shallow clone).
function rewrites.premove(top: string): (string?, string?)
	if git(top, { "cat-file", "-e", `HEAD:{rewrites.MARK}` }) then
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

-- a root-relative path with `.` and `..` resolved (`pickman/../zn` is `zn`)
local function normal(p: string): string
	local out: { string } = {}
	for seg in string.gmatch(p, "[^/]+") do
		if seg == ".." then
			table.remove(out)
		elseif seg ~= "." then
			table.insert(out, seg)
		end
	end
	return table.concat(out, "/")
end

-- The World of the checkout at `top`, `pre` being the tree before the move: `before` reads that tree, `now` the
-- tree of `nowRev` (HEAD by default; code review 008 F4: AC18 pins it to the commit that made a file's text), and
-- `moved` the renames git finds between `pre` and the move itself.
function rewrites.world(top: string, pre: string, nowRev: string?, mainRev: string?): World
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
	-- a root path main created after the move's base counts as one the move must rewrite too (code review 010 F3:
	-- c0114's AC13 names z-nile/next, which main made at its first publish after R0043): main's tree at `mainRev`
	local mainFiles: { [string]: boolean } = {}
	if mainRev then
		local okMn, mainListing = git(top, { "ls-tree", "-r", "--name-only", mainRev })
		assert(okMn, `git ls-tree {mainRev} failed`)
		for f in string.gmatch(mainListing, "[^\n]+") do
			mainFiles[f] = true
			local d = string.match(f, "^(.*)/[^/]+$")
			while d do
				mainFiles[d] = true
				d = string.match(d, "^(.*)/[^/]+$")
			end
		end
	end
	-- the move's own renames, pre to the commit that made them (code review 006 F1): a later merge that finishes an
	-- item (done's promotion, a move to done/) must not change where a folder went
	local okM, move = git(top, { "log", "-1", "--format=%H", "--", rewrites.MARK })
	move = string.gsub(move, "%s+$", "")
	assert(okM and move ~= "", `no commit removed {rewrites.MARK}`)
	local okR, renames = git(top, { "diff", "-M", "--name-status", "--diff-filter=R", pre, move })
	assert(okR, `git diff {pre} {move} failed`)
	local map: { { old: string, new: string } } = {}
	for line in string.gmatch(renames, "[^\n]+") do
		local old, new = string.match(line, "^R%d*\t([^\t]+)\t([^\t]+)$")
		if old and new then
			table.insert(map, { old = old, new = new })
		end
	end
	-- HEAD's committed files, never the working tree (code review 007 F3: an untracked file must not change the
	-- rewrite), read once
	local nowFiles: { string }? = nil
	local nowSet: { [string]: boolean } = {}
	local function listNow(): { string }
		if not nowFiles then
			local rev = nowRev or "HEAD"
			local okN, out = git(top, { "ls-tree", "-r", "--name-only", rev })
			assert(okN, `git ls-tree {rev} failed`)
			local list: { string } = {}
			for f in string.gmatch(out, "[^\n]+") do
				table.insert(list, f)
				local d: string? = f
				while d do
					nowSet[d :: string] = true
					d = string.match(d :: string, "^(.*)/[^/]+$")
				end
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
		return files[q] == true or dirs[q] == true or mainFiles[q] == true
	end
	local function existsNow(given: string): boolean
		local p = normal(given) .. (if string.sub(given, -1) == "/" then "/" else "")
		local lua = glob(p)
		if lua then
			return anyMatch(listNow(), lua)
		end
		local q = normal(trimSlash(p))
		listNow()
		return nowSet[q] == true
	end
	local function movedTo(p: string): string?
		local q = trimSlash(p)
		local tail = ""
		local _, fixed = glob(q)
		if fixed then -- a glob moves with its literal folders
			tail = string.sub(q, #fixed + 1)
			q = fixed
		end
		-- a file: its rename. A folder: where most of its files went, if most of them moved (tracker/ keeps only its
		-- counter, so it moved; the root's scripts/lib keeps c0114's shims, so it stayed)
		local to: { [string]: number } = {}
		local movedCount = 0
		for _, m in map do
			if m.old == q then
				return m.new .. tail
			end
			if string.sub(m.old, 1, #q + 1) == q .. "/" then
				local rest = string.sub(m.old, #q + 1)
				if string.sub(m.new, -#rest) == rest then
					local prefix = string.sub(m.new, 1, #m.new - #rest)
					to[prefix] = (to[prefix] or 0) + 1
					movedCount += 1
				end
			end
		end
		local total = 0
		for f in files do
			if string.sub(f, 1, #q + 1) == q .. "/" then
				total += 1
			end
		end
		local best, bestCount = nil :: string?, 0
		for prefix, n in to do
			if n > bestCount then
				best, bestCount = prefix, n
			end
		end
		if best and movedCount * 2 > total then
			return (best :: string) .. tail
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

-- The finished criteria the user deleted (decided with the user, 2026-10-21: "delete them", Guess 17): criteria
-- that build a copy of the tree in its old shape, or run another home's specs, which no path rewrite carries. The
-- second exception to sequestration, for exactly these `check` statements: each is removed with its continuation lines
-- (a line ending in `\`), and nothing else (helpers they called stay, unused).
rewrites.DELETED = {
	["z-nile/.tracker/issues/done/c0049/check.sh"] = { "AC4", "AC5" },
	["z-nile/.tracker/issues/done/c0058/check.sh"] = { "AC9", "AC10" },
	["z-nile/.tracker/issues/done/c0076/check.sh"] = { "AC5", "AC6" },
	["z-nile/.tracker/issues/done/c0111/check.sh"] = { "AC7" },
} :: { [string]: { string } }

-- `text` without the `check "<id>: …"` statement of each id in `ids`; nil and why when an id names no such statement,
-- or more than one
function rewrites.deleteCriteria(text: string, ids: { string }): (string?, string?)
	local lines = string.split(text, "\n")
	for _, id in ids do
		local found = 0
		local kept: { string } = {}
		local i = 1
		while i <= #lines do
			if string.sub(lines[i], 1, #id + 8) == `check "{id}:` then
				found += 1
				while string.sub(lines[i], -1) == "\\" and i < #lines do
					i += 1
				end
			else
				table.insert(kept, lines[i])
			end
			i += 1
		end
		if found ~= 1 then
			return nil, `{id}: {found} check statements`
		end
		lines = kept
	end
	return table.concat(lines, "\n"), nil
end

return rewrites
