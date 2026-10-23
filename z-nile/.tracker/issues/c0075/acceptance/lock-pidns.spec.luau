--!strict
-- c0075 AC3: inside the Linux jail a process sees pids of its own namespace, which mean other processes (or none)
-- to the runs outside it, so a guarded process there must not record its pid in the run's lock: the launcher, outside
-- (see launcher-lock.spec), holds the lock for as long as the jail lives. Without a recorded namespace (macOS, an outer
-- sandbox, a lock written by an older runner) every guarded process records its pid, as before.
local fence = require("@tests/lib/fence")
local t = require("@tests/lib/t")

return t.spec("c0075 pids in the run's lock", function(it)
	it("records a pid when the lock names no namespace", function()
		t.expect(fence.recordsPid(nil, "pid:[4026531836]")).toBe(true)
		t.expect(fence.recordsPid("", "pid:[4026531836]")).toBe(true)
	end)

	it("records a pid in the namespace the lock names", function()
		t.expect(fence.recordsPid("pid:[4026531836]", "pid:[4026531836]")).toBe(true)
	end)

	it("records nothing from another namespace", function()
		t.expect(fence.recordsPid("pid:[4026531836]", "pid:[4026532405]")).toBe(false)
	end)

	it("records a pid when this process cannot tell its namespace (no /proc)", function()
		t.expect(fence.recordsPid("pid:[4026531836]", nil)).toBe(true)
		t.expect(fence.recordsPid(nil, nil)).toBe(true)
	end)
end)
