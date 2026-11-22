--!strict
-- d0439: a process owned by "nobody" shows a negative user id in `ps` (-2 on macOS). The reaper's parser must read
-- that line as a process that is not ours, not name it a problem: one unreadable line makes the quiet reaper skip
-- everything (on 2026-11-21 it did nothing from 08:29 on).
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

return t.spec("d0439 the reaper reads a negative user id", function(it)
	it("a line with user id -2 is a process, with that owner, and no problem is named", function()
		local text = table.concat({
			"18827     1    -2 02:00:49   0:00.02 Sat Nov 21 08:29:11 2026     /usr/libexec/somed",
			"   10     1     0 05-17:14:35  83:38.18 Mon Oct 26 11:28:38 2026 /sbin/launchd",
		}, "\n")
		local procs, problems = reap.parse(text)
		t.expect(#problems).toBe(0)
		t.expect(#procs).toBe(2)
		t.expect(procs[1].pid).toBe(18827)
		t.expect(procs[1].uid).toBe(-2)
		t.expect(procs[1].command).toBe("/usr/libexec/somed")
	end)

	it("a line that is not a ps line is still named", function()
		local _, problems = reap.parse("18827 1 -x 02:00 0:00.02 Sat Nov 21 08:29:11 2026 /x\nnot a ps line")
		t.expect(#problems).toBe(2)
	end)
end)
