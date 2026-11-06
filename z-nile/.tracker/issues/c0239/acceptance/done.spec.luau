--!strict
-- c0239 AC4: `./zn done` runs the affected gate. Its behaviour (the stub sees `args: --affected` on the promoted, moved
-- tree, a red gate rolls everything back and leaves the raft active) is c0074/done-gate.spec, which this issue
-- overrides and check.sh runs for AC4; this spec pins the pure decision and the gate command in the engine's text.
local fs = require("@lune/fs")
local gate = require("@scripts/tracker/gate")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local main = fs.readFile(`{root}/z-nile/engine/main.luau`)
local function says(line: string)
	if string.find(main, line, 1, true) == nil then
		error(`z-nile/engine/main.luau does not say: {line}`)
	end
end

return t.spec("c0239 done runs the affected gate", function(it)
	it("AC4: the done decision is affected (its promoted branch is c0074/done-gate's)", function()
		t.expect(gate.doneGate({})).toBe("affected")
		t.expect(gate.doneGate({ PICKMAN_DONE_GATE = "1" })).toBe("affected")
	end)

	it("AC4: done's gate command and messages", function()
		says('sh.stream("bash", { "z-nile/check.sh", "--affected" })')
		says("=== affected gate on the done tree")
		says("the affected gate fails on the done tree (rolled back); fix and retry done")
		says("done: inside a spec run, so the gate is skipped; checking the promoted specs")
		if string.find(main, 'sh.stream("bash", { "z-nile/check.sh", "--full" })', 1, true) ~= nil then
			error("done still streams the full gate")
		end
	end)
end)
