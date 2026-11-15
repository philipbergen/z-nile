--!strict
-- c0245 AC7 (run by check.sh only, while this issue's acceptance folder is sequestered; not a spec, so the suite never
-- runs it and a later change to the pinned file needs no edit here): c0191's promoted boundcmd.spec is exactly the
-- reviewed narrowing. One TOOLING case changes, `cd .. && lune run tests/run` from z-nile/ (a root runner, which no
-- longer counts) to `cd .. && lune run pickman/tests/run` (a cd that stays in the checkout keeps the match), and nothing
-- else. Pinned whole by the SHA-256 of its exact text, item ids masked and line endings made LF, nothing else
-- normalised (zz-test/narrowing-pins-the-whole-file). Run from the z-nile home (ac.sh cds there).
local fs = require("@lune/fs")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")

-- spelled in two parts so a compaction does not rewrite it; the id is mapped through the compaction map
local PINNED = "tests/" .. "acceptance/" .. renamed.id("c0191") .. "/boundcmd.spec.luau"
-- the reviewed text: origin/main's blob eff8e1c70bc26f2a5e912ce9dcd7eb11ab5ceda8 with the one line changed
local SHA = "88b9f233db20f6bff21c3e8ed545adb8d719eb6284d2a346d04cbcdf80e03a42"
local OLD = '{ command = "cd .. && lune run tests/run", cwd = CHECKOUT .. "/z-nile", ok = true },'
local NEW = '{ command = "cd .. && lune run pickman/tests/run", cwd = CHECKOUT .. "/z-nile", ok = true },'

local function exact(path: string): string
	local text = string.gsub(fs.readFile(path), "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

local function count(text: string, part: string): number
	local n, at = 0, 1
	for _ = 1, #text do
		local s, e = string.find(text, part, at, true)
		if s == nil then
			break
		end
		n += 1
		at = (e :: number) + 1
	end
	return n
end

if not fs.isFile(PINNED) then
	print(`{PINNED} is missing`)
	process.exit(1)
end
local text = exact(PINNED)
local problems: { string } = {}
if count(text, OLD) ~= 0 then
	table.insert(problems, "the root-runner case is still there")
end
if count(text, NEW) ~= 1 then
	table.insert(problems, `the narrowed case appears {count(text, NEW)} times, not once`)
end
local got = serde.hash("sha256", text)
if got ~= SHA then
	table.insert(problems, `{PINNED} is not the reviewed narrowing: sha256 {got}, want {SHA}`)
end
if #problems > 0 then
	print(table.concat(problems, "\n"))
	process.exit(1)
end
print(`{PINNED}: the reviewed narrowing`)
