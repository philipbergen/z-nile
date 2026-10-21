--!strict
-- What `tracker.sh done` does about the full gate. Pure, no I/O. See c0074.
local gate = {}

-- "promoted" inside a spec run (PICKMAN_FENCE_SPECS=1, set by the runner's fence) unless PICKMAN_DONE_GATE=1 asks
-- for the gate anyway; "full" otherwise. The switch can only add the gate, never skip it.
function gate.doneGate(env: { [string]: string? }): string
	if env.PICKMAN_FENCE_SPECS == "1" and env.PICKMAN_DONE_GATE ~= "1" then
		return "promoted"
	end
	return "full"
end

return gate
