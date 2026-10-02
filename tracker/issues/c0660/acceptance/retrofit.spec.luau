--!strict
-- c0660: the twelve older fixture specs run git and tracker.sh only through `@tests/lib/fixture`. Raw git is left
-- only where it can't touch a repository by mistake: finding the root (`rev-parse`), listing it (`ls-files`), and
-- creating a fixture at a named path (`init`, `clone`). No raw tracker.sh, and no process.exec of a computed
-- command (a generic runner would bypass the helper).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local SPECS = {
	"tests/acceptance/c0010/tracker-lifecycle.spec.luau",
	"tests/acceptance/c0041/worktree.spec.luau",
	"tests/acceptance/c0050/clone.spec.luau",
	"tests/acceptance/c0060/changed.spec.luau",
	"tests/acceptance/c0070/done-order.spec.luau",
	"tests/acceptance/c0330/locator.spec.luau",
	"tests/acceptance/c0360/deferred.spec.luau",
	"tests/acceptance/c0420/naming.spec.luau",
	"tests/acceptance/c0430/workstreams.spec.luau",
	"tests/acceptance/c0440/launch.spec.luau",
	"tests/acceptance/c0480/start-depends.spec.luau",
	"tests/tooling/worktree-fetch.spec.luau",
}
local RAW_GIT_OK = { ["rev-parse"] = true, ["ls-files"] = true, ["init"] = true, ["clone"] = true }
local HELPER = "@tests/lib/" .. "fixture" -- built by concatenation: not a require of this file (graph scanner)

-- Every violation in one spec, as "file: what".
local function violations(path: string): { string }
	local out: { string } = {}
	-- one line, single spaces: calls formatted over several lines read the same
	local text = string.gsub(fs.readFile(path), "%s+", " ")
	if not string.find(text, HELPER, 1, true) then
		table.insert(out, `{path}: does not use {HELPER}`)
	end
	for first in string.gmatch(text, 'process%.exec%( ?"git", ?{ ?"([^"]*)"') do
		if not RAW_GIT_OK[first] then
			table.insert(out, `{path}: raw git {first}`)
		end
	end
	for arg in string.gmatch(text, 'process%.exec%( ?"git", ?([%a_][%w_%.]*)') do
		table.insert(out, `{path}: raw git with computed arguments ({arg})`)
	end
	for name in string.gmatch(text, "process%.exec%( ?([%a_][%w_%.]*) ?,") do
		table.insert(out, `{path}: process.exec of a computed command ({name})`)
	end
	if string.find(text, "process%.create") then
		table.insert(out, `{path}: process.create`)
	end
	for name in string.gmatch(text, 'local ([%a_][%w_]*) ?= ?require%("@lune/process"%)') do
		if name ~= "process" then
			table.insert(out, `{path}: the process module under another name ({name})`)
		end
	end
	for name in string.gmatch(text, "local ([%a_][%w_]*) ?= ?process[ ;]") do
		table.insert(out, `{path}: the process module under another name ({name})`)
	end
	if string.find(text, 'process%.exec%( ?"b?a?sh", ?{ ?"%-c"') then
		table.insert(out, `{path}: a raw shell command string (run it through the helper in a fixture)`)
	end
	for _, pattern in
		{ 'process%.exec%( ?"bash", ?{ ?"scripts/tracker%.sh"', 'process%.exec%( ?"[^"]*tracker%.sh"' }
	do
		if string.find(text, pattern) then
			table.insert(out, `{path}: raw tracker.sh`)
		end
	end
	return out
end

return t.spec("c0660 older fixture specs use the fixture helper", function(it)
	it("every listed spec exists", function()
		for _, path in SPECS do
			t.expect(fs.isFile(path)).toBe(true)
		end
	end)

	it("no listed spec runs git or tracker.sh outside the fixture helper", function()
		local all: { string } = {}
		for _, path in SPECS do
			for _, v in violations(path) do
				table.insert(all, v)
			end
		end
		if #all > 0 then
			error(`{#all} raw git or tracker.sh calls:\n  ` .. table.concat(all, "\n  "))
		end
	end)

	it(
		"the scan catches raw git, computed commands, raw tracker.sh, shell strings and process aliases",
		function()
			local probe = ".cache/c0660-retrofit-probe.luau"
			fs.writeDir(".cache")
			fs.writeFile(
				probe,
				'local x = "'
					.. HELPER
					.. '"\nprocess.exec("git", { "commit" })\nprocess.exec(cmd, args)\n'
					.. 'process.exec(\n\t"bash",\n\t{ "scripts/tracker.sh", "new" }\n)\n'
					.. 'local p = require("@lune/process")\nprocess.create("git", { "commit" })\nprocess.exec("sh", { "-c", "git commit" })\n'
			)
			local found = violations(probe)
			fs.removeFile(probe)
			t.expect(#found).toBe(6)
		end
	)
end)
