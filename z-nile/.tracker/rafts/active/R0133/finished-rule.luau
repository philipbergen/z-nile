--!strict
-- R0133 RC1: no member's check.sh (nor the raft's own) names a path that c0120's finished rule would report once the
-- raft is in done/. c0374's spec `c0120/finished` reads every finished check.sh of every registered root, so the
-- members' own check.sh files become its input the day `./zn done` moves them (design review 001 F1, F2). The rule is
-- the one of `tests/acceptance/c0120/finished.spec.luau`'s last case as it is on the base, which is stricter than with
-- c0374's change. Reads only. Run from the project home: lune run <this file>
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("@tests/acceptance/c0120/rewrites")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function zn(args: { string }): string
	local r = process.exec(`{TOP}/zn`, args, { cwd = TOP })
	if not r.ok then
		error(`./zn {table.concat(args, " ")}: {r.stderr}`)
	end
	return r.stdout
end

local pre, why = rewrites.premove(TOP)
if not pre then
	error(`the tree before the move is not known: {why}`)
end
local world = rewrites.world(TOP, pre :: string)
local reg = projects.load(TOP, true)
local dirs: { string } = {}
for dir in string.gmatch(zn({ "members", "R0133" }), "[^\n]+") do
	table.insert(dirs, dir)
end
table.insert(dirs, (string.gsub(zn({ "find", "R0133" }), "%s+$", "")))
-- further item folders named as arguments are judged too (the proof that the rule bites: see the raft's Experiments)
for _, extra in process.args do
	table.insert(dirs, extra)
end
if #dirs < 2 then
	error("R0133 has no member")
end
local bad: { string } = {}
for _, dir in dirs do
	local file = `{dir}/check.sh`
	if not fs.isFile(`{TOP}/{file}`) then
		error(`{file} is missing`)
	end
	local home = projects.homeOf(reg, file)
	for _, l in rewrites.literals(fs.readFile(`{TOP}/{file}`)) do
		local from = if l.dir == "" then home else `{home}/{l.dir}`
		if not world.now(`{from}/{l.path}`) and world.before(l.dir .. l.path) then
			table.insert(bad, `{file}:{l.line}: {l.word} (from {home})`)
		end
	end
end
if #bad > 0 then
	print(table.concat(bad, "\n"))
	process.exit(1)
end
print(`{#dirs} check.sh files, no path the finished rule reports`)
