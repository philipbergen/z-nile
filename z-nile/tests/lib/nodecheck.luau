--!strict
-- Node runs the page's tests. A bare run without it skips them and says so; the gate (check.sh exports ZN_MEASURE_KIND around its
-- run) fails instead, naming what to install, so the page is never left untested by accident (f0437 slice 2, review F16).
local process = require("@lune/process")

local nodecheck = {}

-- Whether the node tests can run. `present` and `gate` are what the caller found; it raises under the gate when node is missing.
function nodecheck.available(present: boolean, gate: boolean): boolean
	if present then
		return true
	end
	if gate then
		error(
			"node is missing and the gate runs the page's tests with it: install node 22 or later (the page tests under z-nile/tests/tooling/*.node.js)",
			0
		)
	end
	print("SKIPPED: node is not installed, so the page's tests did not run")
	return false
end

-- The check for a spec: looks for node and for the gate's variable.
function nodecheck.ok(): boolean
	local which = process.exec("sh", { "-c", "command -v node" })
	return nodecheck.available(which.ok, process.env.ZN_MEASURE_KIND ~= nil)
end

return nodecheck
