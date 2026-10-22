--!strict
-- c0120, JC1's group 3 (code review 004 F4): every changed spot of a promoted spec carries a `-- c0120 override:`
-- marker, in the hunk or within NEAR lines above it. Prints each hunk without one and fails; read-only. Run from the
-- repository root, naming the renames commit (the promoted specs' text before the overrides):
--   lune run z-nile/.tracker/issues/c0120/override-markers.luau -- <renames commit> [<head>]
local process = require("@lune/process")

local NEAR = 3
local MARK = "-- c0120 override:"

local args: { string } = {}
for _, a in process.args do
	if a ~= "--" then
		table.insert(args, a)
	end
end
local base = args[1] or error("usage: override-markers.luau -- <renames commit> [<head>]")
local head = args[2] or "HEAD"

local function git(argv: { string }): string
	local r = process.exec("git", argv)
	assert(r.ok, `git {table.concat(argv, " ")} failed: {r.stderr}`)
	return r.stdout
end

local ACC = { "pickman/tests/acceptance", "z-nile/tests/acceptance" }
local function diffOf(argv: { string }): string
	local r = process.exec("git", argv)
	-- `git diff` of two blobs exits 1 when they differ
	assert(r.ok or r.code == 1, `git {table.concat(argv, " ")} failed: {r.stderr}`)
	return r.stdout
end
-- A spec promoted since the renames commit (a `done` merged in, code review 006 F1 (c)) is judged against its text in
-- its item's folder before the move, so only c0120's own edits need markers: its hunks are a blob diff from there.
local pre = (string.gsub(git({ "rev-parse", base .. "^" }), "%s+$", ""))
local preTree = git({ "ls-tree", "-r", "--name-only", pre })
local function before(id: string, rest: string): string?
	for path in string.gmatch(preTree, "[^\n]+") do
		local i, r = string.match(path, "/([fdcR]%d%d%d%d)/acceptance/(.+)$")
		if i == id and r == rest then
			return path
		end
	end
	return nil
end
local parts: { string } = {}
local argvMain = { "diff", "-U0", "-M", base, head, "--" }
local status = diffOf({ "diff", "--name-status", "-M", base, head, "--", ACC[1], ACC[2] })
for line in string.gmatch(status, "[^\n]+") do
	local st, path = string.match(line, "^(%a)%d*\t([^\t]+)$")
	local id, rest = if path then string.match(path, "/tests/acceptance/([fdcR]%d%d%d%d)/(.+)$") else nil, nil
	local old = if st == "A" and id then before(id, rest :: string) else nil
	if old then
		local blob = diffOf({ "diff", "-U0", `{pre}:{old}`, `{head}:{path}` })
		table.insert(parts, `+++ b/{path}\n` .. (string.gsub(blob, "^.-\n%+%+%+ [^\n]*\n", "")))
		table.insert(argvMain, `:(exclude){path}`)
	end
end
for _, d in ACC do
	table.insert(argvMain, d)
end
local diff = diffOf(argvMain) .. "\n" .. table.concat(parts, "\n")
local bad: { string } = {}
local hunks = 0
local file = ""
local lines: { string } = {}
for line in string.gmatch(diff, "[^\n]*") do
	local f = string.match(line, "^%+%+%+ b/(.*)$")
	if f then
		file = f
		lines = string.split(git({ "show", `{head}:{f}` }), "\n")
	else
		local start, count = string.match(line, "^@@ %-%S+ %+(%d+),?(%d*) @@")
		if start then
			hunks += 1
			local first = tonumber(start) :: number
			local n = if count == "" then 1 else tonumber(count) :: number
			local last = if n == 0 then first else first + n - 1
			-- the statement the hunk is in starts where no line above goes on into it (a line ending in `,`, `(`, `{` or
			-- `..`, or the hunk's line starting with `.`, `)` or `}`): a marker belongs above that statement, never
			-- inside its argument list (code review 005 F6)
			local stmt = first
			while stmt > 1 and lines[stmt - 1] and lines[stmt] do
				local above = string.gsub(lines[stmt - 1], "%s+$", "")
				local this = lines[stmt]
				local goesOn = string.match(above, "[,({]$") ~= nil
					or string.match(above, "%.%.$") ~= nil
					or string.match(this, "^%s*[%.%)}]") ~= nil
				if not goesOn or string.match(above, "^%s*%-%-") then
					break
				end
				stmt -= 1
			end
			local found = false
			for i = math.max(1, stmt - NEAR), math.max(last, first) do
				if lines[i] and string.find(lines[i], MARK, 1, true) then
					found = true
					break
				end
			end
			if not found then
				table.insert(bad, `{file}:{first}`)
			end
		end
	end
end
-- a marker never sits inside a call's argument list, as its first argument (code review 005 F6; a marker inside a
-- comment's sentence is for review: a marker's own text may run on to a second comment line)
local misplaced: { string } = {}
local files = git({
	"diff",
	"--name-only",
	"-M",
	base,
	head,
	"--",
	"pickman/tests/acceptance",
	"z-nile/tests/acceptance",
})
for f in string.gmatch(files, "[^\n]+") do
	local ls = string.split(git({ "show", `{head}:{f}` }), "\n")
	for i, l in ls do
		if string.find(l, MARK, 1, true) and string.match(l, "^%s*%-%-") then
			local prev = ls[i - 1] or ""
			local nextLine = ls[i + 1] or ""
			local isComment = function(x: string): boolean
				return string.match(x, "^%s*%-%-") ~= nil and not string.find(x, MARK, 1, true)
			end
			local _ = nextLine
			if string.match(prev, "%($") and not isComment(prev) then
				table.insert(misplaced, `{f}:{i}: inside an argument list`)
			end
		end
	end
end
if #bad > 0 or #misplaced > 0 then
	print(table.concat(bad, "\n"))
	print(table.concat(misplaced, "\n"))
	print(
		`override-markers: {#bad} of {hunks} hunks have no "{MARK}" within {NEAR} lines; {#misplaced} markers misplaced`
	)
	process.exit(1)
end
print(`override-markers: all {hunks} hunks are marked (within {NEAR} lines)`)
