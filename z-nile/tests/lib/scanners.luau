--!strict
-- The tooling's text scanners that the hostile sweep runs (zz-arch skill, lesson scanning-loops-advance): one case per
-- public function whose loops walk a text. tests/lib/loops.luau's list names these cases in its `sweep` field. A new
-- text scanner adds its case here; tests/acceptance/c0193/scanners.spec.luau runs them all.
local hostile = require("./hostile")

local scanners = {}

local RAFT_HEAD = '#!/bin/sh\ncheck "RC0: gate" true\n'
local RAFT_RENDERED = RAFT_HEAD .. "finish\n"

scanners.CASES = {
	{
		name = "graph.stripComments",
		module = "@znile/lib/graph",
		call = "m.stripComments(text)",
		witness = { text = "a --c\nb", result = "a \nb" },
	},
	{
		name = "paths.rewrite",
		module = "@znile/engine/paths",
		call = 'm.rewrite(text, { c0001 = "z-nile/.tracker/issues/active/c0001" })',
		witness = {
			text = "see z-nile/.tracker/issues/c0001/c0001.md",
			result = "see z-nile/.tracker/issues/active/c0001/c0001.md",
		},
	},
	{
		name = "ids.rewritePaths",
		module = "@znile/engine/ids",
		call = 'm.rewritePaths(text, { c0001 = "c0002" }, { "pickman", "z-nile" })',
		witness = { text = "tests/acceptance/c0001/a.spec", result = "tests/acceptance/c0002/a.spec" },
	},
	{
		name = "ids.rewrite",
		module = "@znile/engine/ids",
		call = 'm.rewrite(text, { c0001 = "c0002" })',
		witness = { text = "c0001 and c0001", result = "c0002 and c0002" },
	},
	{
		name = "skills.oldLessonIds",
		module = "@znile/engine/skills",
		call = '#m.oldLessonIds(text, { ["zz-test/pin"] = true })',
		witness = { text = "see testing/pin and x", result = "1" },
	},
	{
		name = "skills.oldNames",
		module = "@znile/engine/skills",
		call = "#m.oldNames(text)",
		witness = { text = "the " .. "testing" .. " skill", result = "1" },
	},
	{
		name = "loops.find",
		module = "@tests/lib/loops",
		-- the text goes into a body line that names the bound n, so every text reaches writes()'s `while at do` loop
		call = '#m.find("while i < n do\\n\\tx(" .. text .. "n" .. text .. ")\\n\\ti += 1\\nend\\n")',
		witness = { text = "", result = "1" },
	},
	{
		name = "raftcheck.judge",
		module = "@znile/engine/raftcheck",
		call = `m.judge(text, {string.format("%q", RAFT_RENDERED)})`,
		prefix = RAFT_HEAD .. 'check "RC1: ',
		witness = { text = '" true\nfinish\n', result = "nil" },
	},
	{
		name = "boundcmd.check",
		module = "@znile/engine/boundcmd",
		call = "m.check(text, { background = true }).ok",
		witness = { text = "lune run probe.luau", result = "false" },
	},
	{
		-- f0437 slice 2: the deletion log of git, read line by line for the documents it names
		name = "unitsfacts.parseWithdrawn",
		module = "@znile/engine/unitsfacts",
		call = "#m.parseWithdrawn(text, {})",
		prefix = "@@\t2026-11-20\ts\nz/.tracker/issues/c0261/c0261.md\n",
		witness = { text = "z/.tracker/issues/c0262/c0262.md\n", result = "2" },
	},
	{
		name = "trace.splitLines",
		module = "@znile/engine/trace",
		call = 'table.concat(m.splitLines(text), "|")',
		witness = { text = "a\nb", result = "a|b" },
	},
} :: { hostile.Case }

-- the repository file each case's module names, by alias: `@znile/` is z-nile/, `@tests/` z-nile/tests/, `@scripts/`
-- scripts/. An alias not listed maps to "?", which no file equals, so loops.problems refuses a sweep that names it.
local ALIASES: { [string]: string } =
	{ ["@znile/"] = "z-nile/", ["@tests/"] = "z-nile/tests/", ["@scripts/"] = "scripts/" }

function scanners.files(): { [string]: string }
	local out: { [string]: string } = {}
	for _, c in scanners.CASES do
		local file = "?"
		local m: string = c.module or ""
		for alias, root in ALIASES do
			if string.sub(m, 1, #alias) == alias then
				file = root .. string.sub(m, #alias + 1) .. ".luau"
			end
		end
		out[c.name] = file
	end
	return out
end

-- The characters the scanners above compare a character with, beyond hostile.ALPHABET's: path and mention characters.
-- scanners.spec checks that every one-character literal a case's module compares is in the alphabet or on
-- `scanners.EXCEPT` (case name -> character -> why none is needed).
scanners.ALPHABET = {} :: { string }
for _, c in hostile.ALPHABET do
	table.insert(scanners.ALPHABET, c)
end
for _, c in { ".", "/", "@", "~", ")", "<", "&", ";", ">", "|", "}" } do
	table.insert(scanners.ALPHABET, c)
end
scanners.EXCEPT = {} :: { [string]: { [string]: string } }

-- the scanners' own needles: the strings their loops look for, each fed with every wider character on either side
scanners.NEEDLES = {
	"tests/acceptance/c0001",
	"z-nile/.tracker/issues/c0001",
	"pickman/",
	".claude/" .. "skills/" .. "testing" .. "/",
	"the " .. "testing" .. " skill",
	"zz-test/pin",
	"env -",
	"lune -",
	"python -",
	"grep -",
} :: { string }

-- The texts the sweep feeds each: every text of up to 4 hostile characters, every text of up to 3 characters over the
-- wider alphabet, and each scanner's own needles with every wider character on either side, so a scanner that matches
-- a needle meets the characters next to it. (A case with a guard on its input, such as a check line that must start
-- with a template, sets `prefix` on its Case; raftcheck.judge's starts with the rendered RC0 head and ends with
-- `check "RC1: `, or the sweep never reaches its loops.) Every case has a `witness`: an input and the result only the
-- scanner's work gives, so a call that never reaches the scanner's loops (a map of the wrong shape, a changed
-- signature) fails; scanners.spec requires it.
function scanners.texts(): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local function add(s: string)
		if not seen[s] then
			seen[s] = true
			table.insert(out, s)
		end
	end
	for _, s in hostile.texts() do
		add(s)
	end
	for _, s in hostile.texts(scanners.ALPHABET, 3) do
		add(s)
	end
	for _, n in scanners.NEEDLES do
		for _, c in scanners.ALPHABET do
			add(n .. c)
			add(c .. n)
		end
	end
	return out
end

return scanners
