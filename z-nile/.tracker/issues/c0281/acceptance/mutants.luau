--!strict
-- c0281 AC2 and AC3: tests/tooling/board-review.spec, run against mutants of engine/board.luau. Every mutant that keeps the
-- round-file rule away from `boardview.rounds` (a filter before it, in any spelling; a folder left out; a count of
-- board.luau's own; a call the spec cannot see) turns the spec red on an assertion (AC2), and every edit that keeps the
-- behaviour and only adds the text the old source pin forbade leaves it green (AC3: the pin is a spy now, not a scan).
-- Run by check.sh only (`lune run "$A/mutants.luau"`, from z-nile's home; never by the gate: it copies the engine and
-- runs the spec once per mutant). Everything it writes is under `$TMPDIR/c0281-mutants.XXXXXX`, made by mktemp outside
-- the repository (zz-test lesson check-scripts-copy-trees-outside-the-repo: no jailed spec of a concurrent run can reach
-- it, and git finds no repository there), and removed on every exit, an error included.
local fs = require("@lune/fs")
local process = require("@lune/process")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local HOME = trim(process.exec("pwd", { "-P" }).stdout)
local TOP = string.match(HOME, "^(.*)/[^/]+$") :: string
local SPEC = "tests/tooling/board-review.spec.luau"
-- `mutants` (AC2) or `equivalents` (AC3): which family runs after the unmutated copy (both run with no argument)
local ONLY: string? = nil
for _, a in process.args do
	if a ~= "--" then -- lune keeps the `--` when the script is named by an absolute path
		ONLY = a
	end
end
assert(ONLY == nil or ONLY == "mutants" or ONLY == "equivalents", "the argument is mutants or equivalents")
assert(
	fs.isFile(`{HOME}/engine/board.luau`) and fs.isFile(`{HOME}/{SPEC}`) and fs.isFile(`{TOP}/.luaurc`),
	"run from z-nile's home"
)

-- the fixture: one folder under $TMPDIR, every write checked against it
local TMP = string.gsub(process.env.TMPDIR or "/tmp", "/+$", "")
local made = process.exec("mktemp", { "-d", `{TMP}/c0281-mutants.XXXXXX` })
assert(made.ok, made.stderr)
local FX = trim(made.stdout)
local PREFIX = `{TMP}/c0281-mutants.`
local function inside(path: string): string
	assert(
		string.sub(path, 1, #PREFIX) == PREFIX and not string.find(path, "/%.%./"),
		`outside the fixture: {path}`
	)
	return path
end
local function copy(from: string, to: string)
	local r = process.exec("cp", { "-R", from, inside(to) })
	assert(r.ok, r.stderr)
end
local FH = `{FX}/z-nile` -- the fixture's z-nile home

-- The runner: board.luau must load (a mutant that does not compile kills nothing), then every case of the spec runs in
-- order, and boardview.rounds must be the module's own function again when they are done (a spy that stays installed
-- would answer every later reader).
-- never literal require text in this file: the repository's require scanner would read it (spelled through REQ)
local REQ = "req" .. "uire"
local RUN = [==[
--!strict
local ok, err = pcall(function()
	return __REQ__("@znile/engine/board")
end)
if not ok then
	print("LOADFAIL\t" .. string.gsub(tostring(err), "\n", " "))
	return
end
local boardview = __REQ__("@znile/engine/boardview")
local own = boardview.rounds
local spec = __REQ__("./tests/tooling/board-review.spec")
for _, case in spec.cases do
	local passed, e = pcall(case.fn)
	if passed then
		print("PASS\t" .. case.name)
	else
		print("FAIL\t" .. case.name .. "\t" .. (string.gsub(tostring(e), "\n", " ")))
	end
end
print(if rawequal(boardview.rounds, own) then "RESTORED" else "LEAKED")
]==]
-- the copy: what the spec and board.luau load, and the runner
local function build()
	for _, d in { "engine", "lib", "vendor", "tests/lib", "tests/tooling" } do
		fs.writeDir(inside(`{FH}/{d}`))
	end
	copy(`{TOP}/.luaurc`, `{FX}/.luaurc`)
	copy(`{HOME}/.luaurc`, `{FH}/.luaurc`)
	for _, d in { "engine", "lib", "vendor", "tests/lib" } do
		copy(`{HOME}/{d}/.`, `{FH}/{d}`)
	end
	copy(`{HOME}/{SPEC}`, `{FH}/{SPEC}`)
	fs.writeFile(inside(`{FH}/run.luau`), (string.gsub(RUN, "__REQ__", REQ)))
end

local ORIGINAL = fs.readFile(`{HOME}/engine/board.luau`)

type Outcome = { load: string?, cases: number, failed: { string }, restored: boolean }
local function runWith(source: string): Outcome
	fs.writeFile(inside(`{FH}/engine/board.luau`), source)
	local r = process.exec("lune", { "run", "run" }, { cwd = FH })
	local out: Outcome = { load = nil, cases = 0, failed = {}, restored = false }
	for line in string.gmatch(r.stdout, "[^\n]+") do
		local tag, rest = string.match(line, "^(%u+)\t?(.*)$")
		if tag == "LOADFAIL" then
			out.load = rest
		elseif tag == "PASS" then
			out.cases += 1
		elseif tag == "FAIL" then
			out.cases += 1
			table.insert(out.failed, rest or "")
		elseif tag == "RESTORED" then
			out.restored = true
		end
	end
	if not r.ok and out.load == nil then
		out.load = `the run failed: {r.stderr}`
	end
	return out
end

-- A mutant is an exact replacement of text that board.luau holds once; a missing or repeated anchor fails the check
-- (the mutant would be no mutant).
local function replaceOnce(src: string, old: string, new: string): string
	local at = string.find(src, old, 1, true)
	assert(at, `anchor not found in engine/board.luau: {old}`)
	assert(not string.find(src, old, at + 1, true), `anchor found twice in engine/board.luau: {old}`)
	return string.sub(src, 1, at - 1) .. new .. string.sub(src, at + #old)
end

-- Every occurrence of `old`, which board.luau must hold exactly `count` times (a rename).
local function replaceAll(src: string, old: string, new: string, count: number): string
	local parts = string.split(src, old)
	assert(#parts - 1 == count, `engine/board.luau holds {#parts - 1} of {old}, not {count}`)
	return table.concat(parts, new)
end

local RF_HEAD = "local function reviewFiles(dir: string, into: { string })\n"
-- reviewFiles as it is on main (c0118): every entry of the folder, as `<dir>/<name>`
local RF = RF_HEAD
	.. "\tif not fs.isDir(dir) then\n\t\treturn\n\tend\n"
	.. "\tfor _, name in fs.readDir(dir) do\n\t\ttable.insert(into, `{dir}/{name}`)\n\tend\nend\n"
local function reviewFilesKeeping(keep: string, before: string?): (string) -> string
	return function(src: string): string
		return replaceOnce(
			src,
			RF,
			(before or "")
				.. RF_HEAD
				.. "\tif not fs.isDir(dir) then\n\t\treturn\n\tend\n"
				.. "\tfor _, name in fs.readDir(dir) do\n\t\tif "
				.. keep
				.. " then\n\t\t\ttable.insert(into, `{dir}/{name}`)\n\t\tend\n\tend\nend\n"
		)
	end
end
local OWN = "reviewFiles(rawRaftById[raft.id].dir, files[raft.id])"
local MEMBERS = "reviewFiles(i.dir, files[issue.raft])"
local RETIRED = "reviewFiles(r.dir, files[keeper])"
local CHAIN = "while keeperOf[keeper] and hops < 100 do"
local CALL = "local design, code = boardview.rounds(files[raft.id])"
local REQUIRE = "local boardview = " .. REQ .. '("./boardview")\n'

local MUTANTS: { { name: string, apply: (string) -> string } } = {
	{
		name = "a filter in reviewFiles spelled with [-] (R0083 code review 002 F2)",
		apply = reviewFilesKeeping(
			'string.match(name, "^design[-]review[-]%d+%.md$") or string.match(name, "^review[-]%d+%.md$")'
		),
	},
	{
		name = "a prefix filter in reviewFiles with :sub (R0083 code review 003 F1, Mf)",
		apply = reviewFilesKeeping('name:sub(1, 7) == "review-" or name:sub(1, 14) == "design-review-"'),
	},
	{
		name = "a helper above reviewFiles with single-quoted patterns (R0083 code review 003 F1, Mg)",
		apply = reviewFilesKeeping(
			"isRound(name)",
			"local function isRound(n: string): boolean\n\treturn string.match(n, '^review[-]%d+%.md$') ~= nil"
				.. " or string.match(n, '^design[-]review[-]%d+%.md$') ~= nil\nend\n\n"
		),
	},
	{
		name = "only the Markdown files of a folder",
		apply = reviewFilesKeeping('name:sub(-3) == ".md"'),
	},
	{
		name = "only the files of a folder, never a folder in it",
		apply = reviewFilesKeeping("fs.isFile(`{dir}/{name}`)"),
	},
	{
		name = "names chosen by their first byte (r or d)",
		apply = reviewFilesKeeping("(string.byte(name, 1) == 114 or string.byte(name, 1) == 100)"),
	},
	{
		name = "the members' folders left out",
		apply = function(src: string): string
			return replaceOnce(src, MEMBERS, "local _ = i.dir")
		end,
	},
	{
		name = "the retired rafts' folders left out",
		apply = function(src: string): string
			return replaceOnce(src, RETIRED, "local _ = r.dir")
		end,
	},
	{
		name = "a retired raft's keeper followed one hop only",
		apply = function(src: string): string
			return replaceOnce(src, CHAIN, "while false and keeperOf[keeper] and hops < 100 do")
		end,
	},
	{
		name = "a backlog raft's own folder left out",
		apply = function(src: string): string
			return replaceOnce(src, OWN, `if rawRaftById[raft.id].state ~= "backlog" then {OWN} end`)
		end,
	},
	{
		name = "members' folders kept only outside the backlog",
		apply = function(src: string): string
			return replaceOnce(src, MEMBERS, `if i.state ~= "backlog" then {MEMBERS} end`)
		end,
	},
	{
		name = "the rafts retired into a backlog keeper left out",
		apply = function(src: string): string
			return replaceOnce(src, RETIRED, `if rawRaftById[keeper].state ~= "backlog" then {RETIRED} end`)
		end,
	},
	{
		name = "the list deduplicated by base name before the call",
		apply = function(src: string): string
			return replaceOnce(
				src,
				CALL,
				"local kept, names = {}, {}\n\t\tfor _, p in files[raft.id] do\n"
					.. "\t\t\tlocal n = string.match(p, '([^/]+)$') or p\n"
					.. "\t\t\tif not names[n] then\n\t\t\t\tnames[n] = true\n\t\t\t\ttable.insert(kept, p)\n"
					.. "\t\t\tend\n\t\tend\n\t\tlocal design, code = boardview.rounds(kept)"
			)
		end,
	},
	{
		name = "a filter at the call site, in a helper beside it",
		apply = function(src: string): string
			return replaceOnce(
				src,
				CALL,
				"local kept = {}\n\t\tfor _, p in files[raft.id] do\n\t\t\tif string.find(string.match(p, '[^/]+$') or p, 'review', 1, true) then\n"
					.. "\t\t\t\ttable.insert(kept, p)\n\t\t\tend\n\t\tend\n"
					.. "\t\tlocal design, code = boardview.rounds(kept)"
			)
		end,
	},
	{
		name = "boardview.rounds called, but the raft's rounds counted by board.luau's own copy of the rule",
		apply = function(src: string): string
			return replaceOnce(
				src,
				CALL,
				"local _ = boardview.rounds(files[raft.id])\n\t\tlocal design, code, seen = 0, 0, {}\n"
					.. "\t\tfor _, p in files[raft.id] do\n\t\t\tlocal n = string.match(p, '([^/]+)$') or p\n"
					.. "\t\t\tif not seen[p] then\n\t\t\t\tseen[p] = true\n"
					.. "\t\t\t\tif string.match(n, '^design[-]review[-]%d+%.md$') then\n\t\t\t\t\tdesign += 1\n"
					.. "\t\t\t\telseif string.match(n, '^review[-]%d+%.md$') then\n\t\t\t\t\tcode += 1\n"
					.. "\t\t\t\tend\n\t\t\tend\n\t\tend"
			)
		end,
	},
	{
		name = "boardview.rounds captured when board.luau loads, so a later reader of the module never sees the call",
		apply = function(src: string): string
			local s = replaceOnce(src, REQUIRE, REQUIRE .. "local roundsOf = boardview.rounds\n")
			return replaceOnce(s, CALL, "local design, code = roundsOf(files[raft.id])")
		end,
	},
}

-- Edits that keep the behaviour: some add what the old source pin forbade (a round pattern in a string literal of
-- board.luau, a match call in reviewFiles' body), some respell what it required (the call, the helper's name, the
-- loop's form), and one hands the rule a path twice (the rule dedups by path).
local EQUIVALENTS: { { name: string, apply: (string) -> string } } = {
	{
		name = "an unused string literal holding a round-file pattern",
		apply = function(src: string): string
			return replaceOnce(src, REQUIRE, REQUIRE .. 'local _ROUND = "^review%-%d+%.md$"\n')
		end,
	},
	{
		name = "a match call in reviewFiles that filters nothing",
		apply = function(src: string): string
			return replaceOnce(
				src,
				RF,
				RF_HEAD
					.. "\tif not fs.isDir(dir) or string.match(dir, '^$') then\n\t\treturn\n\tend\n"
					.. "\tfor _, name in fs.readDir(dir) do\n\t\ttable.insert(into, `{dir}/{name}`)\n\tend\nend\n"
			)
		end,
	},
	{
		name = "the call spelled through an index, still on the module table at call time",
		apply = function(src: string): string
			return replaceOnce(src, CALL, 'local design, code = boardview["rounds"](files[raft.id])')
		end,
	},
	{
		name = "reviewFiles renamed",
		apply = function(src: string): string
			return replaceAll(src, "reviewFiles", "entriesOf", 4)
		end,
	},
	{
		name = "reviewFiles' loop written with an index",
		apply = function(src: string): string
			return replaceOnce(
				src,
				RF,
				RF_HEAD
					.. "\tif not fs.isDir(dir) then\n\t\treturn\n\tend\n"
					.. "\tlocal names = fs.readDir(dir)\n\tfor i = 1, #names do\n"
					.. '\t\ttable.insert(into, dir .. "/" .. names[i])\n\tend\nend\n'
			)
		end,
	},
	{
		name = "the members' folders listed twice",
		apply = function(src: string): string
			return replaceOnce(src, MEMBERS, `{MEMBERS}\n\t\t\t{MEMBERS}`)
		end,
	},
}

local function say(s: string)
	print(s)
end

local function judge(problems: { string })
	build()
	local base = runWith(ORIGINAL)
	if base.load then
		table.insert(problems, `the unmutated copy does not run: {base.load}`)
	elseif #base.failed > 0 or base.cases == 0 then
		table.insert(problems, `the unmutated copy is not green: {table.concat(base.failed, " | ")}`)
	elseif not base.restored then
		table.insert(problems, "the spec leaves boardview.rounds replaced after its cases")
	else
		say(`base: {base.cases} cases passed, boardview.rounds restored`)
	end

	if #problems == 0 then
		local mutants: { { name: string, apply: (string) -> string } } = if ONLY == "equivalents"
			then {}
			else MUTANTS
		for _, m in mutants do
			local ok, mutated = pcall(m.apply, ORIGINAL)
			if not ok then
				table.insert(problems, `mutant "{m.name}": {mutated}`)
				continue
			end
			local o = runWith(mutated)
			local killed = false
			for _, f in o.failed do
				if string.find(f, "expected ", 1, true) then
					killed = true
				end
			end
			if o.load then
				table.insert(problems, `mutant "{m.name}" does not load: {o.load}`)
			elseif not killed then
				table.insert(problems, `mutant "{m.name}" survives: no case fails on an assertion`)
			else
				say(`killed: {m.name}`)
			end
		end
		local equivalents: { { name: string, apply: (string) -> string } } = if ONLY == "mutants"
			then {}
			else EQUIVALENTS
		for _, e in equivalents do
			local ok, edited = pcall(e.apply, ORIGINAL)
			if not ok then
				table.insert(problems, `equivalent "{e.name}": {edited}`)
				continue
			end
			local o = runWith(edited)
			if o.load then
				table.insert(problems, `equivalent "{e.name}" does not load: {o.load}`)
			elseif #o.failed > 0 then
				table.insert(
					problems,
					`equivalent "{e.name}" turns the spec red: {table.concat(o.failed, " | ")}`
				)
			else
				say(`green: {e.name}`)
			end
		end
	end
end

local problems: { string } = {}
local finished = xpcall(judge, function(err: any)
	table.insert(problems, `the check stopped: {err}`)
end, problems)
assert(finished or #problems > 0, "a failed check names its problem")
if string.sub(FX, 1, #PREFIX) == PREFIX and fs.isDir(FX) then
	fs.removeDir(FX)
end
for _, p in problems do
	print(`FAIL: {p}`)
end
process.exit(if #problems == 0 then 0 else 1)
