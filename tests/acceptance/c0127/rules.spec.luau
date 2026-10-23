--!strict
-- c0127 AC1: the rule that decides whether a recorded pid still holds the test lock, and the start id it reads. A
-- live pid holds unless the start id recorded beside it differs from its start id now (a reused pid); no recorded
-- id, or an id that can't be read now, leaves it holding. fence.startOf reads the kernel's own record of when a
-- process started (sysctl on macOS, /proc on Linux, through perl, never the clock): the same process always gives
-- the same id, wherever specs run (inside the jail on macOS, unjailed on Linux CI).
local fence = require("@tests/lib/fence")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

return t.spec("c0127 the reused-pid rule", function(it)
	it("a live pid holds unless its recorded start id differs from its start id now", function()
		t.expect(fence.holds(false, nil, nil)).toBe(false)
		t.expect(fence.holds(false, "5.1", "5.1")).toBe(false)
		t.expect(fence.holds(true, nil, "5.1")).toBe(true) -- nothing recorded (an older runner): it holds
		t.expect(fence.holds(true, "5.1", nil)).toBe(true) -- the id can't be read now: it holds
		t.expect(fence.holds(true, "5.1", "5.1")).toBe(true)
		t.expect(fence.holds(true, "5.1", "5.2")).toBe(false) -- another process under the same pid
		t.expect(fence.holds(true, "6.1", "5.1")).toBe(false) -- whichever is later
	end)

	it("startOf answers nil for what is not a pid and for a process that has exited", function()
		t.expect(fence.startOf("not-a-pid")).toBe(nil)
		t.expect(fence.startOf("")).toBe(nil)
		t.expect(fence.startOf("12x")).toBe(nil)
		local dead = trim(process.exec("sh", { "-c", "echo $$" }).stdout)
		t.expect(fence.startOf(dead)).toBe(nil)
	end)

	it("startOf gives a process the same id every time, and a later process another", function()
		local me = trim(process.exec("sh", { "-c", "echo $PPID" }).stdout) -- this Lune
		local child = trim(process.exec("sh", { "-c", "sleep 20 >/dev/null 2>&1 & echo $!" }).stdout)
		local first, again, mine = fence.startOf(child), fence.startOf(child), fence.startOf(me)
		process.exec("kill", { child })
		t.expect({ read = first ~= nil, same = first == again, other = first ~= mine and mine ~= nil })
			.toEqual({
				read = true,
				same = true,
				other = true,
			})
	end)
end)
