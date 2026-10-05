--!strict
-- c0880: the gate audits the real tracker tree. Once promoted, this runs in every full gate (CI on every pull request,
-- every raft's check.sh), so a duplicate id, a folder without its document or a lost counter file fails the gate.
-- Read-only: it only reads files under tracker/.
local audit = require("@scripts/tracker/audit")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0880 the real tracker tree passes the audit", function(it)
	it("has no errors", function()
		local lines: { string } = {}
		for _, p in audit.run(root) do
			if p.level == "error" then
				table.insert(lines, audit.format(p))
			end
		end
		t.expect(table.concat(lines, "\n")).toBe("")
	end)
end)
