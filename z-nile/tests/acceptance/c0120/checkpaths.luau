--!strict
-- The literal paths a check.sh names, and the scan of every unfinished item's check.sh (c0120 AC11's rule, moved here
-- from its spec by c0141 so it can be tested on its own). A path is read from the item's project home; one under the
-- item's own Touched modules (or a raft member's), which its work will create, is exempt. c0141: the exemption
-- compares the path's repository-relative form (home plus the path, `.` and `..` folded) with what each Touched entry
-- names, read in one convention per document, from its text (`owned`). A path that climbs above the checkout is never
-- exempt.
-- It lives in c0120's promoted folder (c0141 design review 001 F3), so it stays under "never edit promoted specs".
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")

local checkpaths = {}

export type Item = { dir: string, id: string, raft: string }
export type Scan = { bad: { string }, checked: number, found: number, byHome: { [string]: number } }

-- `path` as written in a check.sh read from the home `home` ("." for the checkout's top), as a path from the
-- checkout's top with `.` and `..` folded; nil when it climbs above the top
function checkpaths.repoPath(home: string, path: string): string?
	local parts: { string } = {}
	local full = if home == "." or home == "" then path else `{home}/{path}`
	for seg in string.gmatch(full, "[^/]+") do
		if seg == ".." then
			if #parts == 0 then
				return nil
			end
			table.remove(parts)
		elseif seg ~= "." then
			table.insert(parts, seg)
		end
	end
	return table.concat(parts, "/")
end

-- the repository-relative paths one document's Touched entries name, the document being in `home` (c0141 design
-- review 002 F1: the convention is the document's, never the disk's): when any entry starts with a registered
-- project's home (`homes`, from the registry), every entry of that document is read from the checkout's top
-- (`z-nile/skills`, `.models.toml`, `AGENTS.md`); otherwise every entry is read from the home, and a root path is
-- written `../AGENTS.md`. An entry that climbs above the checkout names nothing.
function checkpaths.owned(home: string, entries: { string }, homes: { string }): { string }
	local fromTop = false
	for _, e in entries do
		local first = string.match((string.gsub(e, "^%./", "")), "^([^/]+)")
		if first and table.find(homes, first) then
			fromTop = true
		end
	end
	local out: { string } = {}
	for _, e in entries do
		local reading = if fromTop then checkpaths.repoPath(".", e) else checkpaths.repoPath(home, e)
		if reading then
			table.insert(out, reading)
		end
	end
	return out
end

local PREFIXES =
	{ "src/", "tests/", "scripts/", "z-nile/", "pickman/", "tracker/", ".tracker/", ".github/", ".claude/" }
-- A file named alone (no folder) is a path only outside double quotes: in quotes it is a message, a case's name or
-- a grep pattern (c0099's), found by running the finished checks by hand
local FILES = {
	["default.project.json"] = true,
	["lobby.project.json"] = true,
	zn = true,
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

-- The quoting of every byte of a check.sh, read once. `ctx[i]` is 0 at the top level and a fresh number inside each
-- single-quoted string (a `bash -c '…'` script is a context of its own; the `'"'"'`, `'\''` and `'"$X"'` splices
-- continue the same script); `dq[i]` is true inside double quotes of that context, and not inside a `$(…)` in them,
-- where quotes are quotes again. A heredoc body, a `$'…'` string and a comment (a `#` that begins a word at the top
-- level outside quotes, marked in `comment`) change nothing. A backslash escapes the next byte outside single
-- quotes, and inside a script every byte but `'`.
type Quoting = { ctx: { number }, dq: { boolean }, comment: { boolean } }
local function quoting(text: string): Quoting
	local ctx: { number }, dq: { boolean }, comment: { boolean } = {}, {}, {}
	local cur, count, inDq, saved = 0, 0, false, false
	local levels: { { saved: boolean, depth: number } } = {}
	local pending: { { word: string, dash: boolean } } = {}
	local i, n = 1, #text
	local function mark(from: number, to: number)
		for k = from, math.min(to, n) do
			ctx[k], dq[k] = cur, inDq
		end
	end
	while i <= n do
		local c = string.sub(text, i, i)
		ctx[i], dq[i] = cur, inDq
		if c == "\n" and #pending > 0 then
			-- the heredoc bodies that began on this line: to the line that is the word
			local j = i + 1
			for _, h in pending do
				while j <= n do
					local e = string.find(text, "\n", j, true) or (n + 1)
					local body = string.sub(text, j, e - 1)
					mark(j, e)
					j = e + 1
					if (if h.dash then string.gsub(body, "^\t+", "") else body) == h.word then
						break
					end
				end
			end
			pending = {}
			i = j
			continue
		end
		if
			c == "#"
			and cur == 0
			and not inDq
			and (i == 1 or string.find(string.sub(text, i - 1, i - 1), "[%s;|&(]"))
		then
			while i <= n and string.sub(text, i, i) ~= "\n" do
				ctx[i], dq[i], comment[i] = cur, inDq, true
				i += 1
			end
			continue
		elseif c == "\\" and i < n and not (cur ~= 0 and string.sub(text, i + 1, i + 1) == "'") then
			mark(i + 1, i + 1)
			i += 2
			continue
		elseif c == "$" and string.sub(text, i + 1, i + 1) == "'" and cur == 0 and not inDq then
			local k = i + 2
			while k <= n and string.sub(text, k, k) ~= "'" do
				k += if string.sub(text, k, k) == "\\" then 2 else 1
			end
			mark(i, k)
			i = k + 1
			continue
		elseif c == "$" and string.sub(text, i + 1, i + 1) == "(" then
			table.insert(levels, { saved = inDq :: boolean, depth = 0 })
			inDq = false
			mark(i + 1, i + 1)
			i += 2
			continue
		elseif c == "(" and #levels > 0 and not inDq then
			levels[#levels].depth += 1
		elseif c == ")" and #levels > 0 and not inDq then
			if levels[#levels].depth == 0 then
				local level = table.remove(levels) :: { saved: boolean, depth: number }
				i += 1
				inDq = level.saved
				continue
			end
			levels[#levels].depth -= 1
		elseif
			c == "<"
			and string.sub(text, i + 1, i + 1) == "<"
			and string.sub(text, i + 2, i + 2) ~= "<"
			and string.sub(text, i - 1, i - 1) ~= "<"
			and cur == 0
			and not inDq
		then
			local j = i + 2
			local dash = string.sub(text, j, j) == "-"
			if dash then
				j += 1
			end
			local _, e = string.find(text, "^%s*[\\\"']?[%w_%.%-]+[\"']?", j)
			if e then
				local word = string.match(string.sub(text, j, e), "[%w_%.%-]+") :: string
				table.insert(pending, { word = word, dash = dash })
				mark(i + 1, e)
				i = e + 1
				continue
			end
		elseif c == "'" and cur == 0 and not inDq then
			count += 1
			cur, saved, inDq = count, inDq, false
		elseif c == "'" and cur ~= 0 then
			-- a splice keeps the script: `'"…"'` (a double-quoted piece between two quotes) or `'\''`
			local skip = 0
			if string.sub(text, i + 1, i + 1) == '"' then
				local close = string.find(text, '"', i + 2, true)
				if close and string.sub(text, close + 1, close + 1) == "'" then
					skip = close + 1 - i
				end
			elseif string.sub(text, i + 1, i + 3) == "\\''" then
				skip = 3
			end
			if skip > 0 then
				mark(i + 1, i + skip)
				i += skip + 1
				continue
			end
			cur, inDq = 0, saved
		elseif c == '"' then
			inDq = not inDq
		end
		i += 1
	end
	return { ctx = ctx, dq = dq, comment = comment }
end

-- Is the word at byte `pos` of `text` a shell keyword there: in the context `ctxWanted`, outside double quotes and
-- comments, and at the start of a command (after `;`, `&`, `|`, `(`, `{`, a newline, or `do`, `then`, `else`)?
local function keywordAt(text: string, q: Quoting, pos: number, ctxWanted: number): boolean
	if q.ctx[pos] ~= ctxWanted or q.dq[pos] or q.comment[pos] then
		return false
	end
	local k = pos - 1
	while k >= 1 and string.find(string.sub(text, k, k), "[ \t]") do
		k -= 1
	end
	if k < 1 then
		return true
	end
	if string.find(string.sub(text, k, k), "[;&|(){\n]") then
		return true
	end
	local before = string.sub(text, 1, k)
	return string.find(before, "%f[%w_]do$") ~= nil
		or string.find(before, "%f[%w_]then$") ~= nil
		or string.find(before, "%f[%w_]else$") ~= nil
end

-- Does a positional parameter (`$1`, `"$@"`, `"${2}"`, or a `for` variable over `"$@"`) stand in `token`?
local function positional(token: string, loopVars: { [string]: boolean }): boolean
	if string.find(token, '^"?%${?[%d@*]') then
		return true
	end
	local name = string.match(token, '^"?%${?([%a_][%w_]*)')
	return name ~= nil and loopVars[name] == true
end

-- the names of the functions a check.sh defines that search text: a body that passes one of its positional parameters
-- (or a `for w in "$@"` variable) as the pattern of a grep, egrep or rg, or as an argument to another such function
-- (c0292's and c0256's `has`, c0264's `words` and `has_all`, `g() { grep -qF -e "$1" "$2" … }`). A function that greps
-- its own output (`passes() { … | grep -q " 0 failed"; }`) or names grep in a message is none.
local function searchHelpers(text: string, q: Quoting): { [string]: boolean }
	local bodies: { [string]: string } = {}
	local bodyAt: { [string]: number } = {} -- the byte of each body's opening brace
	for at, name in string.gmatch(text, "()([%a_][%w_]*)%s*%(%)%s*{") do
		local open = string.find(text, "{", at, true) :: number
		local depth, k = 0, open
		while k <= #text do
			local ch = string.sub(text, k, k)
			if ch == "{" then
				depth += 1
			elseif ch == "}" then
				depth -= 1
				if depth == 0 then
					break
				end
			end
			k += 1
		end
		bodies[name :: string] = string.sub(text, open + 1, k - 1)
		bodyAt[name :: string] = open
	end
	local found: { [string]: boolean } = {}
	local changed = true
	while changed do
		changed = false
		for name, body in bodies do
			if not found[name] then
				local loopVars: { [string]: boolean } = {}
				for var in string.gmatch(body, '%f[%w_]for%s+([%a_][%w_]*)%s+in%s+"?%$[@*]') do
					loopVars[var] = true
				end
				local hit = false
				for _, cmd in { "grep", "egrep", "rg" } do
					for at2, tail in string.gmatch(body, "()%f[%w_]" .. cmd .. "%f[^%w_]([^;|&)\n]*)") do
						local abs2 = (bodyAt[name] :: number) + ((at2 :: any) :: number)
						if q.ctx[abs2] ~= q.ctx[bodyAt[name]] or q.dq[abs2] or q.comment[abs2] then
							continue
						end
						local last: string?, patternTaken = nil, false
						for token in string.gmatch(tail, "%S+") do
							if string.sub(token, 1, 1) == "-" and token ~= "--" then
								last = token
							elseif last == "-e" or last == "--regexp" or not patternTaken then
								if token ~= "--" then
									hit = hit or positional(token, loopVars)
									patternTaken = true
								end
								last = nil
							end
						end
					end
				end
				if not hit then
					for other in found do
						if other ~= name then
							for at2, tail in
								string.gmatch(body, "()%f[%w_]" .. other .. "%f[^%w_]([^;|&)\n]*)")
							do
								local abs2 = (bodyAt[name] :: number) + ((at2 :: any) :: number)
								if q.ctx[abs2] ~= q.ctx[bodyAt[name]] or q.dq[abs2] or q.comment[abs2] then
									continue
								end
								for token in string.gmatch(tail, "%S+") do
									hit = hit or positional(token, loopVars)
								end
							end
						end
					end
				end
				if hit then
					found[name] = true
					changed = true
				end
			end
		end
	end
	return found
end

-- words after which the next word is a command (`check "label"` runs the command that follows its label)
local INTRODUCERS = {
	["then"] = true,
	["do"] = true,
	["else"] = true,
	["if"] = true,
	["elif"] = true,
	["while"] = true,
	["until"] = true,
	["!"] = true,
	["{"] = true,
	["}"] = true,
	["time"] = true,
	["xargs"] = true,
	["env"] = true,
	["command"] = true,
	["exec"] = true,
	["check"] = true,
	["nice"] = true,
	["nohup"] = true,
	["sudo"] = true,
}
local COMMAND_BREAK = "[;|&(){\n]"

-- Is the use of `$name` at byte `at` of `body` only text to match? A glob pattern around it (`*"$f"*`), the pattern of a
-- grep (the first word that is no option, or the word after `-e`; the file operand is a use), or a message of an echo
-- (more than one word) or the format of a printf. An argument that echo or printf prints (`echo "$f"`,
-- `printf '%s\n' "$f"`) is a value, a path the check runs.
local function matchedUse(body: string, at: number, len: number): boolean
	local before = string.sub(body, 1, at - 1)
	local after = string.sub(body, at + len)
	if (string.find(before, '%*"?$') ~= nil) and string.find(after, '^"?%*') ~= nil then
		return true
	end
	local from = 1
	for p in string.gmatch(before, "()" .. COMMAND_BREAK) do
		from = ((p :: any) :: number) + 1
	end
	local words: { string } = {}
	for w in string.gmatch(string.sub(before, from), "[^%s\"']+") do
		table.insert(words, w)
	end
	while words[1] and (INTRODUCERS[words[1]] or words[1] == "&&" or words[1] == "||") do
		table.remove(words, 1)
	end
	local head = words[1]
	if head == "echo" then
		local args = 1 -- the use itself
		for j = 2, #words do
			if string.sub(words[j], 1, 1) ~= "-" then
				args += 1
			end
		end
		local rest = string.match(after, "^[^;|&)\n]*") or ""
		for w in string.gmatch(rest, "[^%s\"']+") do
			if string.sub(w, 1, 1) ~= "-" then
				args += 1
			end
		end
		return args >= 2
	elseif head == "printf" then
		-- the format is the first argument: the use is text only inside it
		local segment = string.match(string.sub(before, from), "printf%s+(.*)$") or ""
		segment = string.gsub(segment, "^%-%S*%s+", "")
		local qc = string.sub(segment, 1, 1)
		if qc == '"' or qc == "'" then
			return string.find(segment, qc, 2, true) == nil
		end
		return string.find(segment, "%s") == nil
	elseif head == "grep" or head == "egrep" or head == "rg" then
		-- the use is the pattern (text) right after `-e`/`--regexp`, or as the first operand when no option gave a
		-- pattern; once `-e PAT` has given one, the first operand is a file, and so is `-f`'s (R0112 review 001 F1)
		local operands, given = 0, false
		local last: string? = nil
		for j = 2, #words do
			if last == "-e" or last == "--regexp" then
				given = true
			elseif string.sub(words[j], 1, 1) ~= "-" then
				operands += 1
			end
			last = words[j]
		end
		if last == "-e" or last == "--regexp" then
			return true
		end
		if last == "--file" or (last ~= nil and string.match(last, "^%-%a*f$") ~= nil) then
			return false
		end
		return operands == 0 and not given
	end
	return false
end

-- a `for NAME in WORDS; do BODY done` whose body uses `$NAME` only as text to match: its WORDS are text (c0193's list
-- of engine files a lesson must name). `pos` is the byte of the `for`; the body ends at the loop's own `done`: loops
-- inside it counted, and a `done` in quotes, a comment or as an argument (`./zn done`) is no keyword.
local function textOnlyLoop(text: string, q: Quoting, pos: number, name: string): boolean
	local depth, bodyEnd = 0, #text
	local forCtx = q.ctx[pos]
	for at, word in string.gmatch(string.sub(text, pos), "()([%a_][%w_]*)") do
		local abs = pos + (at :: number) - 1
		if keywordAt(text, q, abs, forCtx) then
			if word == "for" or word == "while" or word == "until" then
				depth += 1
			elseif word == "done" then
				depth -= 1
				if depth == 0 then
					bodyEnd = abs - 1
					break
				end
			end
		end
	end
	local body = string.sub(text, pos, bodyEnd)
	local uses = 0
	for _, form in { "${" .. name .. "}", "$" .. name } do
		local from = 1
		while true do
			local a = string.find(body, form, from, true)
			if not a then
				break
			end
			uses += 1
			if not matchedUse(body, a, #form) then
				return false
			end
			from = a + #form
		end
	end
	return uses > 0
end

-- the literal paths of a check.sh, in order (a path may repeat); `root` marks a path read from the repository root
-- (a command after `cd "$ZN_ROOT"`), else it is read from the item's home
type Lit = { path: string, root: boolean }
-- a directory frame: whether the command runs from the root, and the folders a cd took it through. A subshell or a
-- command substitution pushes a copy of its parent's frame; a script (single-quoted) starts from the top-level one
type Frame = { root: boolean, dir: string }
local function literals(text: string): { Lit }
	local out: { Lit } = {}
	local q = quoting(text)
	local helpers = searchHelpers(text, q)
	local stacks: { [number]: { Frame } } = { [0] = { { root = false, dir = "" } } }
	local function stackOf(ctxNow: number): { Frame }
		local stack = stacks[ctxNow]
		if not stack then
			local parent = stacks[0][#stacks[0]]
			stack = { { root = parent.root, dir = parent.dir } }
			stacks[ctxNow] = stack
		end
		return stack
	end
	local funcs: { { isFunc: boolean, ctx: number, saved: Frame } } = {} -- open `{` groups
	local caseDepth = 0
	local call: string? = nil -- a search helper's call: its quoted arguments are text, until the command ends
	local callCtx, callDq = 0, false
	local listEnd = 0 -- the end of a text-only `for` list, as a byte of the text
	local continued = false
	local offset = 0 -- the byte before the current line
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local base = offset
		offset += #line + 1
		local wasContinued = continued
		continued = string.sub(line, -1) == "\\"
		-- Two cuts. The words keep main's reading: a line that starts with `#` has none, and ` # ` ends them (also in a
		-- heredoc body or a script). The parentheses (frames) stop only at a real comment: where the quoting pass marks
		-- one, or a ` # ` outside quotes in a script; a ` # ` inside quotes hides no parenthesis.
		local full = line
		local parenCut = #full + 1
		for k = 1, #full do
			if q.comment[base + k] then
				parenCut = k
				break
			end
		end
		local hash = string.find(full, "%s#%s")
		if hash and hash < parenCut and q.ctx[base + hash] ~= 0 and not q.dq[base + hash] then
			parenCut = hash
		end
		local wordCut = math.min(parenCut, hash or (#full + 1))
		if string.find(full, "^%s*#") then
			wordCut, parenCut = 1, 1
		end
		local plain = string.sub(full, 1, parenCut - 1) -- what the parentheses are read from
		line = string.sub(full, 1, wordCut - 1)
		-- a check's label is prose, not a command, wherever `check` stands (but not after `--check`)
		line = string.gsub(
			line,
			'^(%s*check%s+)("[^"]*")',
			(function(a: string, b: string): string
				return a .. string.rep(" ", #b)
			end) :: any
		)
		line = string.gsub(
			line,
			'([%s;&|(]check%s+)("[^"]*")',
			(function(a: string, b: string): string
				return a .. string.rep(" ", #b)
			end) :: any
		)
		local words: { string } = {}
		local raws: { string } = {}
		local starts: { number } = {}
		local ends: { number } = {}
		local sep: { boolean } = {}
		local at = 1
		while true do
			local s, e = string.find(line, "[^%s\"'();|&<>`]+", at)
			if not s then
				break
			end
			local gap = string.sub(line, at, s - 1)
			local broken = string.find(gap, "[;|&()`]") ~= nil
			table.insert(sep, if #words == 0 then (not wasContinued) or broken else broken)
			at = (e :: number) + 1
			table.insert(starts, s)
			table.insert(ends, e :: number)
			local w = string.sub(line, s, e :: number)
			table.insert(raws, w)
			local word = string.gsub(w, "[\\,]+$", "")
			-- a shell assignment's value is the word (`f=.claude/skills/testing/SKILL.md`)
			local name = string.match(word, "^[%a_][%w_]*=")
			if name and #word > #name then
				word = string.sub(word, #name + 1)
			end
			-- a word that goes on with a variable: its literal folder is the path
			local dollar = string.find(word, "$", 1, true)
			if dollar and dollar > 1 then
				local folder = string.match(string.sub(word, 1, dollar - 1), "^(.*)/[^/]*$")
				if folder and folder ~= "" then
					word = folder .. "/"
				end
			end
			table.insert(words, word)
		end
		-- the words that are text: a grep's pattern, an echo's message, a search helper's quoted arguments, a code span
		local pattern: { [number]: boolean } = {}
		local message: { [number]: boolean } = {}
		local commandAt: { boolean } = {}
		local caseStart = caseDepth
		local caseAt: { number } = {} -- how many `case` bodies are open after each word
		-- code spans: the words between an opening and a closing backslash-backtick of one double-quoted argument
		local ticks: { number } = {}
		for tick in string.gmatch(line, "()\\`") do
			table.insert(ticks, tick :: number)
		end
		for k = 1, #ticks - 1, 2 do
			if q.dq[base + ticks[k]] then
				for i = 1, #words do
					if starts[i] > ticks[k] and starts[i] < ticks[k + 1] then
						pattern[i] = true
					end
				end
			end
		end
		for i, w in words do
			local s = starts[i]
			local abs = base + s
			local prev = words[i - 1]
			local assignment = string.find(raws[i - 1] or "", "^[%a_][%w_]*=") ~= nil
			local command = sep[i]
				or (prev ~= nil and (INTRODUCERS[prev] == true or string.find(prev, "^%-[%a]*c$") ~= nil))
				or (assignment and commandAt[i - 1] == true)
				or (prev ~= nil and string.find(prev, "^%d+[smhd]?$") ~= nil and words[i - 2] == "timeout")
			commandAt[i] = command
			if call and (sep[i] or (q.ctx[abs] ~= callCtx and q.ctx[abs] == 0)) then
				call = nil
			end
			if call and (q.dq[abs] ~= callDq or q.ctx[abs] ~= callCtx) then
				pattern[i] = true
			end
			if command and call == nil and helpers[w] then
				call, callCtx, callDq = w, q.ctx[abs], q.dq[abs]
			end
			-- grep and rg: the pattern; echo and printf: a message of several words
			local unquoted = not string.find(string.sub(line, s - 1, s - 1), "[\"']")
			if (command or unquoted) and (w == "grep" or w == "egrep" or w == "rg") then
				local j, named = i + 1, false
				while words[j] and string.sub(words[j], 1, 1) == "-" and words[j] ~= "--" do
					if words[j] == "-e" or words[j] == "--regexp" then
						if words[j + 1] then
							pattern[j + 1] = true
							named = true
						end
						j += 2
					else
						j += 1
					end
				end
				if words[j] == "--" then
					j += 1
				end
				if not named and words[j] then
					pattern[j] = true
				end
			elseif command and (w == "echo" or w == "printf") then
				local j = i + 1
				while words[j] and string.sub(words[j], 1, 1) == "-" do
					j += 1
				end
				if words[j] then
					pattern[j] = true
					message[j] = true
				end
			elseif command and w == "for" and words[i + 2] == "in" then
				if textOnlyLoop(text, q, abs, words[i + 1]) then
					listEnd = abs + (string.find(string.sub(text, abs), "[;\n]") or #text)
				end
			elseif command and w == "case" then
				caseDepth += 1
			elseif command and w == "esac" then
				caseDepth -= 1
			end
			caseAt[i] = caseDepth
		end
		-- quoted words follow the marked word to the closing quote (a message or a pattern runs to its closing quote);
		-- an echo's message stops where a command substitution starts, and a message of one word is a value
		for i = 1, #words do
			if pattern[i] then
				local s = starts[i]
				local qc = if s > 1 then string.sub(line, s - 1, s - 1) else ""
				if qc == '"' or qc == "'" then
					local close = string.find(line, qc, s, true) or (#line + 1)
					local sub = string.find(line, "$(", s, true)
					local tickAt = string.find(line, "`", s, true)
					for _, stop in { sub, tickAt } do
						if message[i] and stop and stop < close then
							close = stop
						end
					end
					for j = i, #words do
						if starts[j] < close then
							pattern[j] = true
						end
					end
				end
			end
		end
		-- one-word messages are values (`echo tests/acceptance/c0077/x.spec.luau` returns a path)
		for i in words do
			local before = words[i - 1]
			if pattern[i] and (before == "echo" or before == "printf") then
				local s = starts[i]
				local qc = if s > 1 then string.sub(line, s - 1, s - 1) else ""
				local quoted = qc == '"' or qc == "'"
				local close = if quoted then (string.find(line, qc, s, true) or #line + 1) else ends[i] + 1
				local count = 0
				for j = i, #words do
					if starts[j] < close then
						count += 1
					end
				end
				if count == 1 and (not quoted or string.sub(line, ends[i] + 1, ends[i] + 1) == qc) then
					pattern[i] = nil
				end
			end
		end
		-- the path reading, in order with the groups that push and pop a directory frame
		local nextParen = 1
		local parens: { number } = {}
		for k = 1, #plain do
			local ch = string.sub(plain, k, k)
			if ch == "(" or ch == ")" then
				table.insert(parens, k)
			end
		end
		local function applyParens(upto: number)
			while parens[nextParen] and parens[nextParen] < upto do
				local k = parens[nextParen]
				nextParen += 1
				if not q.dq[base + k] then
					local stack = stackOf(q.ctx[base + k])
					if string.sub(plain, k, k) == "(" then
						local top = stack[#stack]
						table.insert(stack, { root = top.root, dir = top.dir })
					else
						-- a `)` that ends a `case` pattern closes nothing
						local prefix = string.sub(plain, 1, k - 1)
						local open = caseStart
						for w2 = 1, #words do
							if starts[w2] < k then
								open = caseAt[w2]
							end
						end
						local isPattern = open > 0
							and (
								string.find(prefix, ";;%s*[^;()]*$") ~= nil
								or string.find(prefix, "%f[%w_]in%s+[^;()]*$") ~= nil
								or string.find(prefix, "^%s*[^;()]*$") ~= nil
							)
						if not isPattern and #stack > 1 then
							table.remove(stack)
						end
					end
				end
			end
		end
		local dir = "" -- a `cd <dir>` earlier on the line: the words after it are relative to <dir>
		local finding = false -- the words after `find`, before its first option, are the folders it searches
		for i, w in words do
			local s = starts[i]
			local abs = base + s
			applyParens(s)
			local stack = stackOf(q.ctx[abs])
			if w == "{" then
				local isFunc = string.find(string.sub(line, 1, s - 1), "%)%s*$") ~= nil
				local top = stack[#stack]
				table.insert(
					funcs,
					{ isFunc = isFunc, ctx = q.ctx[abs], saved = { root = top.root, dir = top.dir } }
				)
			elseif w == "}" then
				local group = table.remove(funcs)
				if group and group.isFunc then
					stack[#stack] = group.saved
				end
			end
			local path: string? = nil
			if pattern[i] or abs < listEnd then
				continue
			end
			if w == "find" then
				finding = true
				continue
			elseif string.sub(w, 1, 1) == "-" then
				finding = false
			end
			if words[i - 1] == "cd" then
				local cdInDq = q.dq[base + starts[i - 1]] == true
				local sub = string.match(w, "^%$ZN_ROOT/?(.*)$")
				if
					w == "$"
					and words[i + 1] == "git"
					and words[i + 2] == "rev-parse"
					and words[i + 3] == "--show-toplevel"
				then
					sub = ""
				end
				-- a cd that goes on after the named form (`"$ZN_ROOT"/sub`, `$ZN_ROOT/$X`, `…toplevel)/sub`) is no root cd
				if
					sub
					and (
						string.find(sub, "$", 1, true)
						or string.find(string.sub(line, ends[i] + 1, ends[i] + 2), '^"?/')
					)
				then
					continue
				end
				if
					w == "$"
					and sub == ""
					and string.find(string.sub(line, ends[i + 3] + 1, ends[i + 3] + 4), '^%)"?/')
				then
					continue
				end
				if sub and not cdInDq then
					stack[#stack] = { root = true, dir = if sub == "" then "" else sub .. "/" }
					continue
				elseif sub then
					continue
				elseif not string.find(w, "$", 1, true) then
					if stack[#stack].root and not cdInDq then
						stack[#stack].dir ..= w .. "/"
					else
						dir = w .. "/"
					end
					continue
				end
			end
			if
				not string.find(w, "$", 1, true)
				and string.sub(w, 1, 1) ~= "/"
				and string.sub(w, 1, 1) ~= "-"
			then
				if words[i - 2] == "lune" and words[i - 1] == "run" and string.find(w, "/", 1, true) then
					path = if string.match(w, "%.luau$") then w else w .. ".luau"
				elseif
					(
						FILES[w]
						and (
							substituted(line, starts[i])
							or not (
								select(2, string.gsub(string.sub(line, 1, starts[i] - 1), '"', ""))
										% 2
									== 1
								or string.find(string.sub(line, starts[i] - 1, starts[i] - 1), "[\"']")
							)
						)
					) or (finding and FOLDERS[w])
				then
					path = w
				else
					for _, p in PREFIXES do
						if string.sub(w, 1, #p) == p and #w > #p then
							path = w
						end
					end
				end
			end
			if path then
				local frame = stack[#stack]
				if frame.root then
					table.insert(out, { path = frame.dir .. path, root = true })
				else
					table.insert(out, { path = dir .. path, root = false })
				end
			end
		end
		applyParens(#plain + 2)
	end
	return out
end

-- does `path` (relative to the home `home`, in the checkout at `base`) exist? A glob needs one match in its folder.
local function present(base: string, home: string, path: string): boolean
	local full = base .. (if home == "." then path else `{home}/{path}`)
	if not string.find(full, "*", 1, true) then
		return fs.isFile(full) or fs.isDir(full)
	end
	local dir, pat = string.match(full, "^(.*)/([^/]*)$")
	if not dir or string.find(dir, "*", 1, true) or not fs.isDir(dir) then
		return false
	end
	local lua = "^"
		.. string.gsub(string.gsub(pat :: string, "[%.%-%+%?%[%]%^%$%(%)%%]", "%%%0"), "%*", ".*")
		.. "$"
	for _, name in fs.readDir(dir) do
		if string.match(name, lua) then
			return true
		end
	end
	return false
end

-- the Touched modules entries of an item document
local function touched(doc: string): { string }
	local out: { string } = {}
	local text = if fs.isFile(doc) then fs.readFile(doc) else ""
	local section = string.match(text, "\n### Touched modules\n(.-)\n#") or ""
	for path in string.gmatch(section, "\n?%- `([^`]+)`") do
		table.insert(out, (string.gsub(path, "/+$", "")))
	end
	return out
end
local function under(path: string, own: { string }): boolean
	for _, o in own do
		if
			path == o
			or string.sub(path, 1, #o + 1) == o .. "/"
			or string.sub(o, 1, #path + 1) == path .. "/"
		then
			return true
		end
	end
	return false
end

-- every unfinished item folder under every current root of the checkout at `base` ("" or "<dir>/"): { dir, id, raft },
-- with `dir` relative to that checkout
local function items(base: string): { Item }
	local out: { Item } = {}
	local reg = projects.load(if base == "" then "." else string.sub(base, 1, -2), true)
	for _, r in projects.roots(reg) do
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/" } do
				local rel = `{r}/{kind}/{state}`
				if fs.isDir(base .. rel) then
					for _, id in fs.readDir(base .. rel) do
						if string.match(id, "^[fdcR]%d%d%d%d$") then
							local doc = `{base}{rel}{id}/{id}.md`
							local raft = if fs.isFile(doc)
								then string.match(fs.readFile(doc), "\nraft:%s*(R%d%d%d%d)") or ""
								else ""
							table.insert(out, { dir = rel .. id, id = id, raft = raft })
						end
					end
				end
			end
		end
	end
	return out
end

-- The scan, over the checkout at `base`: every path an unfinished check.sh names that is missing from its home and not
-- its own work; how many check.sh files it read, and how many it found (the restamped aside); and, per home, how many.
local function scan(base: string, skip: (text: string) -> boolean): Scan
	local reg = projects.load(if base == "" then "." else string.sub(base, 1, -2), true)
	local all = items(base)
	local homes: { string } = {}
	for _, r in projects.roots(reg) do
		local folder = projects.folderOf(r)
		if folder then
			table.insert(homes, folder)
		end
	end
	local byRaft: { [string]: { { string } } } = {}
	for _, i in all do
		if i.raft ~= "" then
			byRaft[i.raft] = byRaft[i.raft] or {}
			table.insert(byRaft[i.raft], touched(`{base}{i.dir}/{i.id}.md`))
		end
	end
	local out: Scan = { bad = {}, checked = 0, found = 0, byHome = {} }
	for _, i in all do
		local file = `{i.dir}/check.sh`
		if fs.isFile(base .. file) then
			local text = fs.readFile(base .. file)
			if not skip(text) then
				out.found += 1
				local home = projects.homeOf(reg, file)
				-- each document read by its own convention: the item's, and for a raft each member's
				local own = checkpaths.owned(home, touched(`{base}{i.dir}/{i.id}.md`), homes)
				local memberDocs: { { string } } = byRaft[i.id] or {}
				for _, memberEntries in memberDocs do
					for _, o in checkpaths.owned(home, memberEntries, homes) do
						table.insert(own, o)
					end
				end
				for _, lit in literals(text) do
					local from = if lit.root then "." else home
					local at = checkpaths.repoPath(from, lit.path)
					if not present(base, from, lit.path) and not (at and under(at, own)) then
						table.insert(
							out.bad,
							`{file}: {lit.path} (from {if lit.root then "the repository root" else home})`
						)
					end
				end
				out.checked += 1
				out.byHome[home] = (out.byHome[home] or 0) + 1
			end
		end
	end
	table.sort(out.bad)
	return out
end

checkpaths.literals = literals
checkpaths.quoting = quoting
checkpaths.present = present
checkpaths.touched = touched
checkpaths.under = under
checkpaths.items = items
checkpaths.scan = scan

return checkpaths
