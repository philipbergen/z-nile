--!strict
-- The scanning-loop rule's lint (zz-arch skill, lesson scanning-loops-advance), pure over texts, and its reviewed list.
-- A `while` or `repeat` loop is provably advancing when all of these hold: its condition is `V < B`, `V <= B`, `V > B`
-- or `V >= B` with V a plain name and B a number, a name or `#name`; the loop's own top level steps V on every pass
-- (`V += n` or `V = V + n`, `-` for a `>` condition, n a positive literal, or `V = scan.advance(V, next)`) before any
-- `continue`; no other statement in the body, at any depth, assigns V except further steps in the same direction; and the body never writes B (a line holding B alone, a `table.` call before it, an assignment to the owner of a dotted B), and opens no long bracket (`[[`, `--[[`: the lint cannot tell code from text there).
-- A loop that reads text is never proven: the proof sees only the loop's own lines, and a scanner is where that is not
-- enough, so it is listed, with the case that sweeps it. Every other loop is on `loops.ALLOWED`, in file order, with why it ends (and, for a loop that reads text, the
-- scanners case that sweeps it). Indentation is tabs (stylua, the gate), so a loop ends at the first line at or
-- above its own indent, which must be `end` (`until …` for a `repeat`); anything else is a loop whose end was not found.
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")

local loops = {}

export type Loop = { line: number, header: string, advances: boolean, scansText: boolean }
export type Allowed = { loop: string, why: string, sweep: (string | boolean)? }

-- the lesson every problem names, and the fix
local LESSON = "zz-arch/scanning-loops-advance"
local FIX =
	"step its position by a literal at the loop's top level, or through scan.advance(i, next), or list the loop in z-nile/tests/lib/loops.luau with why it ends"

local TEXT_CALLS =
	{ "string.find", "string.sub", "string.match", "string.byte", ":find(", ":sub(", ":match(", ":byte(" }

local function readsText(line: string): boolean
	for _, call in TEXT_CALLS do
		if string.find(line, call, 1, true) then
			return true
		end
	end
	return false
end

-- is the call that `s` opens with `scan.advance(` closed by the last character of `s` and by nothing earlier?
local function closesAtEnd(s: string): boolean
	local open = string.find(s, "scan.advance(", 1, true)
	if not open then
		return false
	end
	local depth = 1
	for i = open + #"scan.advance(", #s do
		local c = string.sub(s, i, i)
		if c == "(" then
			depth += 1
		elseif c == ")" then
			depth -= 1
			if depth == 0 then
				return i == #s
			end
		end
	end
	return false
end

-- is `stmt` (a statement at the loop's top level) a step of `v` in the direction of the loop's condition?
local function steps(stmt: string, v: string, up: boolean): boolean
	local s = string.gsub(stmt, "%s+%-%-.*$", "")
	if up then
		return string.match(s, `^{v} %+= [1-9]%d*$`) ~= nil
			or string.match(s, `^{v} = {v} %+ [1-9]%d*$`) ~= nil
			or (string.match(s, `^{v} = scan%.advance%({v}, `) ~= nil and closesAtEnd(s))
	end
	return string.match(s, `^{v} %-= [1-9]%d*$`) ~= nil or string.match(s, `^{v} = {v} %- [1-9]%d*$`) ~= nil
end

-- Stylua wraps a long value and leaves the operator at the end of the line. A trailing space makes that
-- operator visible to a pattern that needs one character after `=`. A comparison still does not match.
local function padded(fragment: string): string
	return fragment .. " "
end

-- does `line` assign `v`? Any assignment operator counts, including a compound one, a typed local or for
-- declaration, and an operator stylua left at the end of the line. The `=` must not be part of a comparison;
-- a name that merely appears in a comparison or an index does not count.
local function assigns(line: string, v: string): boolean
	local lhs = string.match(padded(line), "^%s*(.-)[^=~<>]=([^=])")
	if not lhs then
		return false
	end
	local targets = string.gsub(lhs, "%b[]", "")
	return string.find(targets, `%f[%w_]{v}%f[^%w_]`) ~= nil
end

-- does `line` write the bound `name` (a name or a dotted path): assign it or one of its fields, call a table function
-- or a method on it?
local function writes(line: string, name: string): boolean
	-- Stylua puts a call's argument, or a method's receiver, on a line of its own: the bound alone on a line is a write
	-- (final review 001 F1). So is any assignment to the owner of a dotted bound (`opts = ...` under `opts.max`).
	local alone = string.gsub(string.gsub(string.match(line, "^%s*(.-)%s*$") :: string, "^#", ""), ",$", "")
	if alone == name then
		return true
	end
	local owner = string.match(name, "^([%a_][%w_]*)%.")
	if owner and assigns(line, owner) then
		return true
	end
	local at = string.find(line, name, 1, true)
	while at do
		local before = if at > 1 then string.sub(line, at - 1, at - 1) else ""
		local after = string.sub(line, at + #name)
		if not string.match(before, "[%w_%.]") and not string.match(after, "^[%w_]") then
			if
				string.match(padded(after), "^[^=]-[%+%-]?=[^=]")
				and not string.find(string.sub(line, 1, at - 1), "=", 1, true)
			then
				return true
			end
			if
				string.match(after, "^:")
				or string.find(string.sub(line, 1, at - 1), "table%.[a-z]+%(") ~= nil
			then
				return true
			end
		end
		at = string.find(line, name, at + 1, true)
	end
	return assigns(line, name)
end

-- The line after the loop that starts at `n` (indent `ind`) ends it: the first non-blank line at or above `ind`, which
-- must be `end` (`until …` for a repeat). Returns that line's number, or nil when the end is not found.
local function endOf(lines: { string }, n: number, ind: string, isRepeat: boolean): number?
	for k = n + 1, #lines do
		local l = lines[k]
		if string.match(l, "^%s*$") then
			continue
		end
		local lead = string.match(l, "^\t*") :: string
		if #lead <= #ind then
			if
				#lead == #ind
				and not isRepeat
				and (l == ind .. "end" or string.match(l, "^" .. ind .. "end%s+%-%-"))
			then
				return k
			end
			if #lead == #ind and isRepeat and string.sub(l, 1, #ind + 5) == ind .. "until" then
				return k
			end
			return nil
		end
	end
	return nil
end

-- Every `while` and `repeat` loop in `text`, in order, each with whether it provably advances and whether its header
-- or body reads text. A body whose end cannot be found counts as reading text, so an unread body fails closed too.
function loops.find(text: string): { Loop }
	local lines = string.split(text, "\n")
	local out: { Loop } = {}
	for n, line in lines do
		local ind = string.match(line, "^\t*") :: string
		local rest = string.sub(line, #ind + 1)
		local isWhile = rest == "while" or string.sub(rest, 1, 6) == "while "
		local isRepeat = rest == "repeat" or string.sub(rest, 1, 7) == "repeat "
		if isWhile or isRepeat then
			-- A trailing comment is not the line's shape. `-- read to the end` must not hide the body.
			local header = string.gsub(rest, "%s+%-%-.*$", "")
			local oneLine = string.match(header, " end$") ~= nil
			local last = if oneLine then nil else endOf(lines, n, ind, isRepeat)
			local reads = readsText(rest) or (not oneLine and last == nil)
			local advances = false
			local v: string?, op: string?, bound: string? = nil, nil, nil
			if isWhile and not oneLine then
				v, op, bound = string.match(rest, "^while ([%a_][%w_]*) ([<>]=?) (.+) do$")
			end
			local plainBound = bound ~= nil
				and (string.match(bound, "^%d+$") ~= nil or string.match(bound, "^#?[%a_][%w_%.]*$") ~= nil)
			if bound and string.sub(bound, 1, 5) == "math." then
				plainBound = false -- math.huge and the like are no bound at all
			end
			local boundName = if bound and plainBound then string.match(bound, "^#?(.-)$") else nil
			local assigned, stepped, sawContinue, writesBound, longBracket = 0, false, false, false, false
			if last then
				for k = n + 1, last - 1 do
					local l = lines[k]
					if readsText(l) then
						reads = true
					end
					if string.find(l, "%[=*%[") then
						longBracket = true -- a line inside a block comment or a long string is not code (final review 001 F2)
					end
					if string.match(l, "%f[%w_]continue%f[^%w_]") then
						sawContinue = true
					end
					if v and op and assigns(l, v) then
						local stmt = string.match(l, "^%s*(.-)%s*$") :: string
						-- another step in the same direction (a branch that takes a value) cannot hold the loop back
						if not steps(stmt, v, string.sub(op, 1, 1) == "<") then
							assigned += 1
						end
					end
					if boundName and not string.match(boundName, "^%d+$") and writes(l, boundName) then
						writesBound = true
					end
					local body = string.match(l, "^" .. ind .. "\t([^\t].*)$")
					if
						v
						and op
						and body
						and not sawContinue
						and steps(body, v, string.sub(op, 1, 1) == "<")
					then
						stepped = true
					end
				end
				advances = stepped
					and assigned == 0
					and plainBound
					and not writesBound
					and not longBracket
					and not reads
			end
			table.insert(out, { line = n, header = rest, advances = advances, scansText = reads })
		end
	end
	return out
end

-- The problems with the loops of one file: `allowed` is its entries of loops.ALLOWED (nil for none), `sweeps` the
-- scanners cases, each with the file of its module. Each loop that does not provably advance must be the next entry, in file order, with a
-- reason; a loop that reads text names the case that sweeps it, or `false` (the reason says why none is needed).
function loops.problems(
	file: string,
	text: string,
	allowed: { Allowed }?,
	sweeps: { [string]: string }
): { string }
	local list = allowed or {}
	local out: { string } = {}
	local k = 0
	for _, l in loops.find(text) do
		if l.advances then
			continue
		end
		k += 1
		local a = list[k]
		local where = `{file}:{l.line}: loop "{l.header}"`
		if not a then
			table.insert(
				out,
				`{where} does not provably advance and is not on loops.ALLOWED ({LESSON}): {FIX}`
			)
		elseif a.loop ~= l.header then
			table.insert(
				out,
				`{where} is not the listed loop "{a.loop}" (the entries of {file} are in file order, {LESSON})`
			)
		else
			if #string.gsub(a.why, "%s+", " ") < 12 then
				table.insert(
					out,
					`{where}: its loops.ALLOWED entry gives no reason (why it ends or advances)`
				)
			end
			if l.scansText then
				local s = a.sweep
				-- `true` is not a case name and not the explicit `false`. A cast would let it through the type.
				if s ~= false and type(s) ~= "string" then
					table.insert(
						out,
						`{where} reads text: its entry names the scanners case that sweeps it, or false ({LESSON})`
					)
				elseif type(s) == "string" and not sweeps[s] then
					table.insert(
						out,
						`{where}: its entry names the scanners case "{s}", which does not exist`
					)
				elseif type(s) == "string" and sweeps[s] ~= file then
					table.insert(
						out,
						`{where}: its entry names the scanners case "{s}", whose module is {sweeps[s]}, not this file`
					)
				end
			end
		end
	end
	for i = k + 1, #list do
		table.insert(
			out,
			`{file}: loops.ALLOWED lists "{list[i].loop}", which is no longer there: remove the entry`
		)
	end
	return out
end

-- The checkout that holds this harness: three folders above z-nile/tests/lib/loops.luau. Specs run from a project's
-- home (c0120), so the scan reads the checkout from here, with root-relative paths.
loops.TOP = string.match(debug.info(1, "s"), "^(.*)/[^/]+/[^/]+/[^/]+/[^/]+$") or "."
-- the folders whose .luau files the lint covers, and the ones inside them it skips: tracker documents (every project
-- root of the registry), promoted specs (never edited) and fixtures, vendored code, and every .cache
loops.ROOTS = { "z-nile", "scripts", "pickman/scripts" }
loops.SKIP =
	{ ["z-nile/tests/acceptance"] = true, ["z-nile/tests/fixtures"] = true, ["z-nile/vendor"] = true } :: {
		[string]: boolean,
	}
for _, r in projects.roots(projects.load(loops.TOP)) do
	loops.SKIP[r] = true
end

-- The text of every .luau file the lint covers except a spec (`*.spec.luau`), keyed by its root-relative path.
function loops.files(): { [string]: string }
	local out: { [string]: string } = {}
	local function walk(dir: string)
		if not fs.isDir(`{loops.TOP}/{dir}`) then
			return
		end
		for _, name in fs.readDir(`{loops.TOP}/{dir}`) do
			local path = `{dir}/{name}`
			if loops.SKIP[path] or name == ".cache" then
				continue
			elseif fs.isDir(`{loops.TOP}/{path}`) then
				walk(path)
			elseif string.match(name, "%.luau$") and not string.match(name, "%.spec%.luau$") then
				out[path] = fs.readFile(`{loops.TOP}/{path}`)
			end
		end
	end
	for _, r in loops.ROOTS do
		walk(r)
	end
	return out
end

-- The loops that do not provably advance, per file in file order (zz-arch skill, lesson scanning-loops-advance): the
-- header as written, why the loop ends or advances, and for a loop that reads text the scanners case that sweeps it
-- (tests/lib/scanners.luau) or false with the reason none is needed. A reviewer reads every new entry.
loops.ALLOWED = {
	["pickman/scripts/cicd.luau"] = {
		{
			loop = "while index <= #args do",
			why = "every branch steps index by 1 or 2, or exits the process",
		},
	},
	["pickman/scripts/lib/lease.luau"] = {
		{
			loop = "while true do",
			why = "redact returns early on an empty key, so each pass cuts rest past a non-empty match",
			sweep = false,
		},
		{
			loop = "while i <= #raw do",
			why = "base64 over bytes: i += 3 at the top of every pass",
			sweep = false,
		},
		{
			loop = "while true do",
			why = "the request loop returns unless the answer is transient, and attempt reaches 5",
		},
	},
	["pickman/scripts/lib/opencloud.luau"] = {
		{
			loop = "while true do",
			why = "returns unless transient, and attempt and the spent seconds grow each retry",
		},
		{
			loop = "while true do",
			why = "polls until the task ends or waited (grown by poll each pass) reaches the timeout",
		},
	},
	["z-nile/engine/board.luau"] = {
		{
			loop = "while keeperOf[keeper] and hops < 100 do",
			why = "follows the retired-keeper chain, growing hops to its cap of 100",
		},
	},
	["z-nile/engine/boardview.luau"] = {
		{
			loop = "while w <= last do",
			why = "addDays advances w by one week on every pass until last",
		},
	},
	["z-nile/engine/boundcmd.luau"] = {
		{
			loop = "repeat",
			why = "normalization repeats until its text is stable",
		},
		{
			loop = "while i <= n do",
			why = "every branch returns, breaks, or advances i through the input",
			sweep = "boundcmd.check",
		},
		{
			loop = "while i <= n and string.sub(text, i, i) ~= '\"' do",
			why = "every branch returns, breaks, or advances i to the closing quote or input end",
			sweep = "boundcmd.check",
		},
		{
			loop = "while j <= n and depth > 0 do",
			why = "j advances through the input and the loop also ends at depth zero",
			sweep = "boundcmd.check",
		},
		{
			loop = "while j <= n and depth > 0 do",
			why = "j advances through the input and the loop also ends at depth zero",
			sweep = "boundcmd.check",
		},
		{
			loop = "while i <= #words do",
			why = "every branch returns, breaks, or advances i through the finite words",
			sweep = "boundcmd.check",
		},
		{
			loop = "while i <= #words do",
			why = "every branch returns, breaks, or advances i through the finite words",
			sweep = "boundcmd.check",
		},
		{
			loop = "while k <= #args do",
			why = "every branch returns, breaks, or advances k through the finite arguments",
			sweep = "boundcmd.check",
		},
		{
			loop = "while k <= #args do",
			why = "every branch returns, breaks, or advances k through the finite arguments",
			sweep = "boundcmd.check",
		},
		{
			loop = "while i <= #args do",
			why = "every branch returns, breaks, or advances i through the finite arguments",
			sweep = "boundcmd.check",
		},
		{
			loop = "while i <= #lines do",
			why = "every branch returns, breaks, or advances i through the finite lines",
			sweep = "boundcmd.check",
		},
	},
	["z-nile/engine/broker.luau"] = {
		{
			loop = "while waited < broker.WAIT_SECONDS do",
			why = "returns on an answer, otherwise waited grows to the 600-second bound",
		},
	},
	["z-nile/engine/dispatcher.luau"] = {
		{
			loop = "while running do",
			why = "the heartbeat ends when its returned stop closure clears running",
		},
		{
			loop = "while fs.isFile(`{dir}/answered-{n}.md`) do",
			why = "n grows until the first absent answer file",
		},
		{
			loop = "while true do",
			why = "breaks when mkdir claims a unique folder, otherwise n raises past 1000",
		},
	},
	["z-nile/engine/ids.luau"] = {
		{
			loop = "while true do",
			why = "breaks when find fails; i moves past a non-empty match",
			sweep = "ids.rewritePaths",
		},
	},
	["z-nile/engine/main.luau"] = {
		{
			loop = "while i <= #args do",
			why = "the command line: every branch steps i by 1 or 2 or exits, and args is finite",
			sweep = false,
		},
		{
			loop = "while true do",
			why = "old is `<id>@<hash>`, never empty, and at moves past each match",
			sweep = false,
		},
		{
			loop = "while i <= #a and i <= #b and a[i] == b[i] do",
			why = "the common-prefix walk: i grows by 1 every pass and the lists are finite",
		},
		{
			loop = "while not rebasing.ok and H.takeDerivedSpend() do",
			why = "c0248: each pass settles a stop whose only conflicts are raft spend.md files and continues the rebase, which replays one more commit of a finite range; a stop with any other conflict ends it",
		},
		{
			loop = "while #remaining > 0 do",
			why = "each pass removes one id from remaining, or returns on a cycle",
		},
		{
			loop = "while n <= #paths do",
			why = "n grows and the local batch text cursor advances or breaks",
			sweep = false,
		},
		{
			loop = "while at ~= nil and at.ppid > 1 and #self < 64 do",
			why = "follows parent records with the ancestry list capped at 64",
		},
		{
			loop = "repeat",
			why = "breaks when no processes remain or the two-second deadline arrives",
		},
	},
	["z-nile/engine/paths.luau"] = {
		{
			loop = "while true do",
			why = "breaks when no root matches; pos moves past the match",
			sweep = "paths.rewrite",
		},
		{
			loop = "while true do",
			why = "from moves past each match of a non-empty needle",
			sweep = "paths.rewrite",
		},
	},
	["z-nile/engine/publish.luau"] = {
		{
			loop = "repeat",
			why = "`until true`: a block that runs once and leaves it early by break",
			sweep = false,
		},
	},
	["z-nile/engine/raftcheck.luau"] = {
		{
			loop = "while true do",
			why = "the RC0 head search advances at past each match or breaks",
			sweep = "raftcheck.judge",
		},
		{
			loop = "while j <= #text do",
			why = "the word scanner increments j or returns",
			sweep = "raftcheck.judge",
		},
		{
			loop = "while i <= #text do",
			why = "judge consumes whitespace, comments, finish, or check lines, or returns",
			sweep = "raftcheck.judge",
		},
		{
			loop = "while j <= #text do",
			why = "consumes words or whitespace, breaks at newline, and rejects a word that does not advance",
			sweep = "raftcheck.judge",
		},
	},
	["z-nile/engine/raftplan.luau"] = {
		{
			loop = "while parent[k] ~= k do",
			why = "path halving up a finite union-find forest that has no cycle",
		},
	},
	["z-nile/engine/reap.luau"] = {
		{
			loop = "while at ~= 1 do",
			why = "follows parent pids, returning false on a broken chain or after 64 steps",
		},
		{
			loop = "while grew do",
			why = "grew is reset and set only by a newly added descendant of a finite process list",
		},
	},
	["z-nile/engine/runner.luau"] = {
		{
			loop = "while waited < (grace or 2) do",
			why = "returns when the group disappears, otherwise waited reaches grace",
		},
		{
			loop = "while true do",
			why = "the process stdout reader breaks at EOF on a nil or empty chunk",
			sweep = false,
		},
		{
			loop = "while true do",
			why = "the local shrinking stream buffer breaks without a newline or consumes through it",
			sweep = false,
		},
		{
			loop = "while true do",
			why = "the process stderr reader breaks at EOF on a nil or empty chunk",
			sweep = false,
		},
		{
			loop = "while not (outDone and errDone) do",
			why = "reader tasks set both flags, and stop, quota, cap, or stall paths break",
		},
		{
			loop = "while not (outDone and errDone) and waited < 2 do",
			why = "the reader drain is bounded by two seconds",
		},
	},
	["z-nile/engine/skills.luau"] = {
		{
			loop = "while true do",
			why = "pos moves past a match of a non-empty needle",
			sweep = "skills.oldLessonIds",
		},
		{
			loop = "while true do",
			why = "pos moves past a match of a non-empty needle",
			sweep = "skills.oldNames",
		},
	},
	["z-nile/engine/stack.luau"] = {
		{
			loop = "while #left > 0 do",
			why = "removes one selected id per pass or returns on a dependency cycle",
		},
	},
	["z-nile/engine/stats.luau"] = {
		{
			loop = "while yy < lastY or (yy == lastY and mm <= lastM) do",
			why = "addMonths moves (yy, mm) a month on every pass",
		},
	},
	["z-nile/engine/trace.luau"] = {
		{
			loop = "while pos <= len do",
			why = "splitLines sets pos past the next newline or breaks",
			sweep = "trace.splitLines",
		},
		{
			loop = "while i <= n do",
			why = "literal non-empty needles `<!--` and `-->`; each pass advances past a closer or breaks",
			sweep = false,
		},
		{
			loop = "while true do",
			why = "the literal non-empty needle `|`; each pass advances past a pipe or breaks",
			sweep = false,
		},
	},
	["z-nile/engine/trail.luau"] = {
		{
			loop = "while i >= 1 do",
			why = "the inner loop always takes sorted[i] itself (its sha is sha), so i falls by 1 or more",
			sweep = false,
		},
		{
			loop = "while i >= 1 and sorted[i].sha == sha do",
			why = "i falls by 1 on every pass, so the group ends at the first commit with another sha or at 0",
			sweep = false,
		},
	},
	["z-nile/engine/watchcmd.luau"] = {
		{
			loop = "while true do",
			why = "the local helper returns on a match decision or sets from past the non-empty pin",
			sweep = false,
		},
	},
	["z-nile/engine/wrapper.luau"] = {
		{
			loop = "while i <= #args do",
			why = "the finite argument walk increments i by one or two, or returns",
			sweep = false,
		},
		{
			loop = "while i <= #args do",
			why = "the finite argument walk increments i by one or two, or returns",
			sweep = false,
		},
		{
			loop = "while i <= #rest do",
			why = "the finite API option walk advances through every option and value",
			sweep = false,
		},
	},
	["z-nile/lib/graph.luau"] = {
		{
			loop = "while i <= #a and i <= #b and a[i] == b[i] do",
			why = "the common-prefix walk: i grows by 1 every pass and the lists are finite",
		},
		{
			loop = "while true do",
			why = "at loses its last folder each pass and the loop breaks at /",
			sweep = false,
		},
		{
			loop = 'while d ~= "." and d ~= "" and string.sub(d, 1, 2) ~= ".." do',
			why = "dirname shortens d each pass",
			sweep = false,
		},
		{
			loop = "while i <= n do",
			why = "every branch moves i past the token it took",
			sweep = "graph.stripComments",
		},
		{
			loop = "while j <= n do",
			why = "every branch moves j by 1 or 2 or breaks",
			sweep = "graph.stripComments",
		},
		{ loop = "while #stack > 0 do", why = "pops one file per pass and pushes only files not seen yet" },
	},
	["z-nile/specs.luau"] = {
		{
			loop = 'while args[1] == "--" do',
			why = "removes one leading separator per pass",
		},
	},
	["z-nile/tests/lib/cleanup.luau"] = {
		{
			loop = "while head <= #queue and #out < MAX_LISTED do",
			why = "a breadth-first walk: head grows by 1 every pass over a finite tree, and the list is capped by MAX_LISTED",
		},
		{
			loop = "while true do",
			why = "returns on success or a vanished tree, and raises once the bound has passed",
		},
	},
	["z-nile/tests/lib/fence.luau"] = {
		{
			loop = 'while not process.exec("mkdir", { lock }).ok do',
			why = "waited grows 0.1 each pass and the run gives up at the limit",
		},
		{ loop = 'while up and up ~= "" do', why = "up loses its last folder each pass", sweep = false },
	},
	["z-nile/tests/lib/fixture.luau"] = {
		{
			loop = 'while args[i] and string.sub(args[i], 1, 1) == "-" do',
			why = "the last statement steps i by 1 or 2",
			sweep = false,
		},
	},
	["z-nile/tests/lib/hostile.luau"] = {
		{ loop = 'while #lines > 0 and lines[#lines] == "" do', why = "pops the last line on every pass" },
	},
	["z-nile/tests/lib/loops.luau"] = {
		{
			loop = "while at do",
			why = "every find starts at at + 1, so at grows on every pass or the find returns nil",
			sweep = "loops.find",
		},
	},
	["z-nile/tests/lib/place.luau"] = {
		{
			loop = "while node.Parent ~= nil do",
			why = "assigns node to its parent until the root",
		},
	},
	["z-nile/tests/run.luau"] = {
		{
			loop = "while i <= #args do",
			why = "the command line: every branch steps i by 1 or 2 or exits, and args is finite",
			sweep = false,
		},
		{
			loop = "while running > 0 do",
			why = "waits for the lane workers, each of which ends with its spec file's process",
		},
	},
} :: { [string]: { Allowed } }

return loops
