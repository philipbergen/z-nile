--!strict
-- The Claude Code PreToolUse hook for Bash and Monitor (c0191), run by scripts/hooks/pre-bash.sh: reads the tool call
-- (JSON on stdin: tool_name, cwd, tool_input.command, tool_input.run_in_background) and refuses a command that starts an
-- interpreter with no time limit, a loop or a follow that never ends, or a background call nothing bounds, naming the
-- wrapper to use (z-nile/engine/boundcmd). A Monitor command is bounded by the tool's own timeout, so only the
-- interpreter and detach rules apply to it. Exit 2 refuses and prints the reason for the agent; every other outcome
-- (anything unreadable, a crash) exits 0 and lets the command run: a broken seatbelt must not stop all work, and
-- `./zn reap` is the backstop for what it misses. ZN_CHECKOUT (set by pre-bash.sh) is the checkout whose `zn` the
-- reason names, because the agent may be in a scratch folder.
local boundcmd = require("./engine/boundcmd")
local process = require("@lune/process")
local projects = require("./engine/projects")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local ok, payload = pcall(function(): any
	return serde.decode("json", stdio.readToEnd())
end)
if not ok or type(payload) ~= "table" then
	process.exit(0)
end
local call = payload :: { [string]: any }
local input = call.tool_input
local command = if type(input) == "table" then (input :: { [string]: any }).command else nil
if type(command) ~= "string" then
	process.exit(0)
end
local checkout = process.env.ZN_CHECKOUT
-- the registry's homes, from the checkout the hook was told (c0244); any problem reading it leaves `homes` nil and
-- TOOLING's own entries decide, as before
local homes: { string }? = nil
if checkout ~= nil and checkout ~= "" then
	local loaded, reg = pcall(function()
		return projects.load(checkout :: string)
	end)
	if loaded then
		local list = {}
		for _, p in (reg :: projects.Registry).projects do
			table.insert(list, p.home)
		end
		homes = list
	end
end
local verdict = boundcmd.check(command :: string, {
	monitor = call.tool_name == "Monitor",
	background = (input :: { [string]: any }).run_in_background == true,
	zn = if checkout ~= nil and checkout ~= "" then `{checkout}/zn` else nil,
	checkout = if checkout ~= nil and checkout ~= "" then checkout else nil,
	cwd = if type(call.cwd) == "string" then call.cwd :: string else nil,
	homes = homes,
})
if verdict.ok then
	process.exit(0)
end
stdio.ewrite(boundcmd.explain(verdict) .. "\n")
process.exit(2)
