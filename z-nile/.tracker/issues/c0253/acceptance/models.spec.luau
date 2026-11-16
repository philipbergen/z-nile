--!strict
-- c0253 AC11: `.models.toml` names how long a raft waits for each CLI that said quota ([work.<cli>] quota_wait_minutes),
-- the closest file winning, and refuses what it cannot read.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local function refused(text: string, needle: string)
	local ok, err = pcall(models.parse, text, "x/.models.toml")
	t.expect(ok).toBe(false)
	t.expect(string.find(tostring(err), needle, 1, true) ~= nil).toBe(true)
end

return t.spec("c0253 [work.<cli>] quota_wait_minutes", function(it)
	it("AC11: is read per CLI, in seconds, the closest file winning", function()
		local root =
			models.parse("[work.claude]\nquota_wait_minutes = 10\n[work.kimi]\nquota_wait_minutes = 5\n", "a")
		local near = models.parse("[work.claude]\nquota_wait_minutes = 30\n", "b")
		t.expect(models.quotaWaits({ root })).toEqual({ claude = 600, kimi = 300 })
		t.expect(models.quotaWaits({ root, near })).toEqual({ claude = 1800, kimi = 300 })
		t.expect(models.quotaWaits({})).toEqual({})
	end)

	it(
		"AC11: refuses a CLI it does not support, an unknown key and a value that is not whole minutes",
		function()
			refused("[work.zed]\nquota_wait_minutes = 5\n", "zed")
			refused("[work.claude]\nquota_wait = 5\n", "quota_wait")
			refused("[work.claude]\nquota_wait_minutes = 0\n", "quota_wait_minutes")
			refused("[work.claude]\nquota_wait_minutes = 1.5\n", "whole number of minutes")
			refused('[work.claude]\nquota_wait_minutes = "ten"\n', "quota_wait_minutes")
			refused("work = 3\n", "[work] is a table")
		end
	)

	it("AC11: leaves a file with no [work] table as it was", function()
		local layer = models.parse("[dispatch]\nstall_seconds = 100\n", "c")
		t.expect(models.quotaWaits({ layer })).toEqual({})
		t.expect(layer.settings.stallSeconds).toBe(100)
	end)
end)
