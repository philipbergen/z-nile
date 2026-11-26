--!strict
-- The CPU-time limit a detached net needs (R0138 review 003 F1). `./zn run --time T` and the spec runner's jail put
-- `ulimit -t` (soft and hard) on their command, every child inherits it, and a hard limit cannot be raised from inside.
-- A net kicked from under a short `./zn run` would run every process of its suite under that limit, so the kick refuses
-- to start one. The floor is what a normal gate gives each spec: the spec runner's default, which tests/lib/fence.specCpu
-- spells itself (the runner's fixture copies carry fence.luau alone, so it cannot require this module): a spec pins the two together.
local cpulimit = {}

cpulimit.SPEC_DEFAULT = 1200

-- Whether the hard CPU limit `hard` (the text `ulimit -Ht` prints) gives at least `floor` seconds: "unlimited" does,
-- a whole number does when it is not below the floor, anything else does not (the net is not started on a limit it cannot read).
function cpulimit.ok(hard: string, floor: number): boolean
	if hard == "unlimited" then
		return true
	end
	if not string.match(hard, "^%d+$") then
		return false
	end
	return (tonumber(hard) :: number) >= floor
end

-- The line the kick prints when it does not start a net.
function cpulimit.refusal(hard: string, floor: number): string
	return `watch-net: not started: this command runs under a CPU limit of {hard} s per process, the net needs {floor} s: run ./zn watch-kick from a shell without a short ./zn run around it`
end

return cpulimit
