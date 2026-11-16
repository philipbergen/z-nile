--!strict
-- c0173 AC2: runs the replaced case of c0075's wiring.spec against fixture SETUP.md texts, without the rest of that
-- spec (whose other cases need the jail c0075 builds). It cuts the case out by its title, compiles it with fs, t,
-- root and has as its only free names (the case is written to use no others), and runs it once per scenario with
-- `fs.readFile` stubbed to return the scenario's SETUP.md. Reads one file (argument 1), writes nothing.
--   lune run harness.luau <wiring.spec.luau>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local TITLE = "a Linux host's prerequisites name the jail script"

local path = process.args[1]
if path == nil then
	print("usage: harness.luau <wiring.spec.luau>")
	process.exit(2)
end
local source = fs.readFile(path :: string)

local start = string.find(source, `it("{TITLE}", function()`, 1, true)
if start == nil then
	print(`no case "{TITLE}" in {path}`)
	process.exit(1)
end
local bodyFrom = (string.find(source, "\n", start :: number, true) :: number) + 1
local bodyTo = string.find(source, "\n\tend)", bodyFrom, true)
if bodyTo == nil then
	print("the case does not end with a tab-indented `end)`")
	process.exit(1)
end
local body = string.sub(source, bodyFrom, (bodyTo :: number) - 1)

local ROOT = "/fixture"
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- runs the case with SETUP.md = text; returns nil when it passes, else the error
local function run(text: string): string?
	local reads: { string } = {}
	local stubFs = {
		readFile = function(p: string): string
			table.insert(reads, p)
			if p ~= `{ROOT}/SETUP.md` then
				error(`the case read {p}, not {ROOT}/SETUP.md`)
			end
			return text
		end,
	}
	local stubT = {
		expect = function(actual: any)
			return {
				toBe = function(expected: any)
					if actual ~= expected then
						error(`expected {tostring(expected)}, got {tostring(actual)}`, 2)
					end
				end,
			}
		end,
	}
	local ok, err = pcall(function()
		local chunk = luau.load("local fs, t, root, has = ...\nreturn function()\n" .. body .. "\nend", {
			debugName = "case",
		})
		local fn = chunk(stubFs, stubT, ROOT, has)
		fn()
	end)
	if ok and #reads ~= 1 then
		return `read {#reads} files`
	end
	return if ok then nil else tostring(err)
end

local HEAD = "# Setting up a host\n\n```bash\nz-nile/setup.sh\n```\n\n"
local PREREQ = "## Prerequisites (manual, one time)\n"
local TABLE_HEAD = "| need | macOS | Linux |\n|---|---|---|\n| git | xcode | distro packages |\n"
local ROW = "| Spec jail (bubblewrap) | built in (sandbox-exec) | `scripts/linux-jail.sh` |\n"
local SETUPSEC = "\n## What `z-nile/setup.sh` does\n1. Rokit.\n4. **Gate**: runs `z-nile/check.sh --full`.\n"
local TROUBLE = "\n## Troubleshooting\n| symptom | fix |\n|---|---|\n"

-- name, SETUP.md text, whether the case must pass
local scenarios: { { string | boolean } } = {
	{
		"the row is in the prerequisites, Linux column",
		HEAD .. PREREQ .. TABLE_HEAD .. ROW .. SETUPSEC .. TROUBLE,
		true,
	},
	{
		"the prerequisites are the last section",
		HEAD .. SETUPSEC .. "\n" .. PREREQ .. TABLE_HEAD .. ROW,
		true,
	},
	{
		"the script is also named in the macOS cell",
		HEAD
			.. PREREQ
			.. TABLE_HEAD
			.. "| jail | `scripts/linux-jail.sh` | `scripts/linux-jail.sh` |\n"
			.. SETUPSEC,
		true,
	},
	{ "no row names the script", HEAD .. PREREQ .. TABLE_HEAD .. SETUPSEC .. TROUBLE, false },
	{
		"the script is named only in the macOS cell",
		HEAD .. PREREQ .. TABLE_HEAD .. "| jail | `scripts/linux-jail.sh` | not needed |\n" .. SETUPSEC,
		false,
	},
	{
		"the row sits after the setup section",
		HEAD .. PREREQ .. TABLE_HEAD .. SETUPSEC .. TROUBLE .. ROW,
		false,
	},
	{
		"the row is under Troubleshooting only",
		HEAD .. PREREQ .. TABLE_HEAD .. SETUPSEC .. TROUBLE .. "| jail fails | `scripts/linux-jail.sh` |\n",
		false,
	},
	{
		"the row is in the setup section, not the prerequisites",
		HEAD .. PREREQ .. TABLE_HEAD .. SETUPSEC .. ROW .. TROUBLE,
		false,
	},
	{
		"the script is named in prose, not in a table row",
		HEAD .. PREREQ .. TABLE_HEAD .. "On Linux run scripts/linux-jail.sh first.\n" .. SETUPSEC,
		false,
	},
	{
		"a line with bars that does not start with one",
		HEAD
			.. PREREQ
			.. TABLE_HEAD
			.. "jail | built in | not needed | `scripts/linux-jail.sh`\n"
			.. SETUPSEC,
		false,
	},
	{
		"the Linux cell names another script",
		HEAD .. PREREQ .. TABLE_HEAD .. "| jail | built in | `scripts/setup.sh` |\n" .. SETUPSEC,
		false,
	},
	{
		"a row with fewer than three cells",
		HEAD .. PREREQ .. TABLE_HEAD .. "| scripts/linux-jail.sh |\n" .. SETUPSEC,
		false,
	},
	{ "there is no prerequisites section", HEAD .. SETUPSEC .. TROUBLE, false },
}

local failed = 0
for _, s in scenarios do
	local err = run(s[2] :: string)
	local passes = err == nil
	-- a case that must fail has to fail on one of its own assertions, not on a crash (a nil it indexed, say)
	local good = passes == s[3]
		and (passes or string.match(err :: string, '^%[string "case"%]:%d+: expected ') ~= nil)
	if not good then
		failed += 1
	end
	print(
		`{if good then "ok  " else "FAIL"} {s[1]}: case {if passes then "passes" else "fails"}, expected {if s[3]
			then "pass"
			else "fail"}{if err and not s[3]
			then " (" .. (string.match(err, "[^\n]*") :: string) .. ")"
			else ""}`
	)
end
print(`{#scenarios - failed} of {#scenarios} scenarios as expected`)
process.exit(if failed == 0 then 0 else 1)
