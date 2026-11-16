--!strict
-- c0156 AC2: the two whole-file pins (c0128's golden.spec and c0103's narrowed.spec) take the rule from the one shared
-- module and carry no copy of it, and pickman reaches that module through its re-export. These are reads of source
-- text, because "the rule lives once" is a statement about the source; that the pins' verdicts are wired is kills.luau's
-- (AC7), the rule's is AC1's. Needles that would read as a require are built by concatenation.
local fs = require("@lune/fs")
local pin = require("@tests/lib/pin")
local renamed = require("@tests/lib/renamed")
local scripted = require("./scripted")

local TOP = scripted.top()
local has = scripted.has
local REQ = "requ" .. "ire("

-- spelled in two parts so a compaction does not rewrite the paths; the ids are mapped through the compaction map
local ACC = "pickman/tests/" .. "acceptance/"
local ACC_HOME = "tests/" .. "acceptance/"
local PINS = {
	{ ACC .. renamed.id("c0103") .. "/narrowed.spec.luau", "c0103's narrowed.spec" },
	{ ACC .. renamed.id("c0128") .. "/golden.spec.luau", "c0128's golden.spec" },
}

local forward = fs.readFile(`{TOP}/pickman/tests/lib/pin.luau`)
scripted.check("pickman's pin.luau is --!strict", string.sub(forward, 1, 9) == "--!strict")
-- its code lines (the lines that are neither blank nor comments) are the one re-export, so no comment or second return
-- can stand in for it or shadow it
local code: { string } = {}
for _, line in string.split(forward, "\n") do
	if string.find(line, "%S") and string.sub(string.gsub(line, "^%s+", ""), 1, 2) ~= "--" then
		table.insert(code, line)
	end
end
scripted.check(
	"pickman's pin.luau is the one line that re-exports the shared module",
	#code == 1 and code[1] == "return " .. REQ .. '"../../../z-nile/tests/lib/pin")'
)
scripted.check("the shared module is there", fs.isFile(`{TOP}/z-nile/tests/lib/pin.luau`))

for _, pinned in PINS do
	local path, name = pinned[1], pinned[2]
	local text = fs.readFile(`{TOP}/{path}`)
	scripted.check(`{name} requires the shared rule`, has(text, REQ .. '"@tests/lib/pin")'))
	scripted.check(`{name} hashes through pin.digest`, has(text, "pin.digest("))
	scripted.check(`{name} builds its mutants with pin.joined`, has(text, "pin.joined("))
	scripted.check(
		`{name} collapses no whitespace itself`,
		not has(text, '"%s+"') and not has(text, '"[ ' .. "\\t" .. ']+"')
	)
	scripted.check(`{name} hashes nothing itself`, not has(text, "serde"))
	scripted.check(
		`{name} defines no normaliser or join helper`,
		not has(text, "function normalise") and not has(text, "function joined")
	)
end

-- the digests prep computed (c0103's DIGEST, c0128's D24 and D26) are the ones in the pins, and each pinned file still
-- hashes to its value, so a pinned file cannot change together with its constant. This script runs at c0156's `done`
-- only (it is no spec, and the gate does not rerun a finished item's check.sh): a later narrowing of a pinned file
-- updates the pin's digest and leaves this finished check as the record of today's bytes. Each verdict is also the one
-- comparison the Design prescribes, read through the pin rule's own normaliser: kills.luau proves the wiring for every
-- mutant it derives, and this fixes what the verdict compares, which no black-box edit can.
type Pinned = { spec: number, constant: string, digest: string, id: string, file: string }
local PINNED: { Pinned } = {
	{
		spec = 1,
		constant = "DIGEST",
		digest = "ed27eb8bf258d9019129336876becd8133428099b4653d7b6546fcc5db052be6",
		id = "f0014",
		file = "/keys.spec.luau",
	},
	{
		spec = 2,
		constant = "D24",
		digest = "7f791c55bab7441df495cc59a1ed1989ff6daa6494e0719e748ef38bd66b992b",
		id = "f0024",
		file = "/adapter.spec.luau",
	},
	{
		spec = 2,
		constant = "D26",
		digest = "744eeb0f1d525ee47f52c01dd8cab3c4bcd511fd2edf28919f894712f64cbfc6",
		id = "f0026",
		file = "/adapters.spec.luau",
	},
}
for _, row in PINNED do
	local pinSpec = PINS[row.spec]
	local source = fs.readFile(`{TOP}/{pinSpec[1]}`)
	local held = string.match(source, `local {row.constant} = "(%x+)"`)
	scripted.check(
		`{pinSpec[2]} holds {row.constant} = the digest prep computed for {row.id}`,
		held == row.digest
	)
	local pinned = fs.readFile(`{TOP}/pickman/{ACC_HOME}{renamed.id(row.id)}{row.file}`)
	scripted.check(`{row.id}'s file still hashes to it`, pin.digest(pinned) == row.digest)
end

type Verdict = { spec: number, fn: string, constant: string }
local VERDICTS: { Verdict } = {
	{ spec = 1, fn = "exactly", constant = "DIGEST" },
	{ spec = 2, fn = "exactly24", constant = "D24" },
	{ spec = 2, fn = "exactly26", constant = "D26" },
}
for _, v in VERDICTS do
	local pinSpec = PINS[v.spec]
	local normalised = pin.normalise(fs.readFile(`{TOP}/{pinSpec[1]}`))
	local body = `local function {v.fn}(text: string): boolean\n return pin.digest(text) == {v.constant}\nend`
	scripted.check(
		`{pinSpec[2]}'s {v.fn} is the one comparison, pin.digest(text) == {v.constant}`,
		has(normalised, body)
	)
end

scripted.finish()
