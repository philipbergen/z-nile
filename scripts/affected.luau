--!strict
-- Forwarder (c0114): the affected-spec selector is z-nile/affected.luau. Kept for the check.sh files and specs that
-- run `lune run scripts/affected`.
local process = require("@lune/process")

local args = { "run", "z-nile/affected", "--" }
for _, a in process.args do
	if a ~= "--" then
		table.insert(args, a)
	end
end
local r = process.exec("lune", args, { stdio = "inherit" })
process.exit(r.code)
