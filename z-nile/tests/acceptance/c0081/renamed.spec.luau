--!strict
-- c0870: @tests/lib/renamed maps an id written before a compaction to the id it has now, through
-- tracker/compaction.txt, so specs that pin real tracker items (c0410's rounds, repo-fence's exemptions for c0640)
-- hold before and after the user's one-time compaction.
local fs = require("@lune/fs")
local ids = require("@scripts/tracker/ids")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

return t.spec("c0870 renamed ids", function(it)
	it("maps through the given map text", function()
		local map = "# tracker.sh compact, 2026-10-05, from origin/main abc\nR0010 R0001\nc0640 c0058\n"
		t.expect(renamed.id("c0640", map)).toBe("c0058")
		t.expect(renamed.id("R0010", map)).toBe("R0001")
	end)

	it("an id the map does not name is returned as it is", function()
		t.expect(renamed.id("c0999", "c0640 c0058\n")).toBe("c0999")
	end)

	it("a malformed map is an error, not a silent identity", function()
		t.expect(function()
			renamed.id("c0640", "c0640 f0058\n")
		end).toThrow("compaction")
	end)

	it(
		"without map text it reads the real tracker/compaction.txt, or maps nothing when there is none",
		function()
			-- c0120 override: specs run from z-nile's home, so the real map is read from the checkout's top
			local top = (
				string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
			)
			local map = `{top}/{ids.MAP_FILE}`
			local text = if fs.isFile(map) then fs.readFile(map) else nil
			local want = if text
				then (ids.parseMap(text) :: { [string]: string }).R0010 or "R0010"
				else "R0010"
			t.expect(renamed.id("R0010")).toBe(want)
		end
	)
end)
