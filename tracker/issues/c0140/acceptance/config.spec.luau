--!strict
-- c0140 AC2: publishing is configured from the environment: no key or ids means "not configured" (a
-- green skip, never a half-made request), and the ids must be plain digits because they go in a URL.
local OpenCloud = require("@scripts/lib/opencloud")
local t = require("@tests/lib/t")

local FULL: { [string]: string? } =
	{ ROBLOX_API_KEY = "k", ROBLOX_BETA_UNIVERSE_ID = "10768553777", ROBLOX_BETA_PLACE_ID = "82331952549326" }

local function with(overrides: { [string]: string? }): { [string]: string? }
	local env: { [string]: string? } = table.clone(FULL)
	for k, v in overrides do
		env[k] = v
	end
	return env
end

return t.spec("c0140 OpenCloud.configFromEnv", function(it)
	it("reads the key and both ids", function()
		local cfg = OpenCloud.configFromEnv(FULL)
		t.expect(cfg ~= nil).toBe(true)
		t.expect((cfg :: OpenCloud.Config).apiKey).toBe("k")
		t.expect((cfg :: OpenCloud.Config).universeId).toBe("10768553777")
		t.expect((cfg :: OpenCloud.Config).placeId).toBe("82331952549326")
	end)

	it("is nil when any of the three is missing or empty", function()
		for _, name in { "ROBLOX_API_KEY", "ROBLOX_BETA_UNIVERSE_ID", "ROBLOX_BETA_PLACE_ID" } do
			t.expect(OpenCloud.configFromEnv(with({ [name] = "" }))).toBe(nil)
		end
		local missing = with({})
		missing.ROBLOX_BETA_PLACE_ID = nil
		t.expect(OpenCloud.configFromEnv(missing)).toBe(nil)
		t.expect(OpenCloud.configFromEnv({})).toBe(nil)
	end)

	it("refuses ids that are not plain digits, so nothing odd reaches a URL", function()
		for _, bad in { "1/../2", "12 34", "12a", "-5", "1.5", "0x10", "1;rm", "１２" } do
			t.expect(function()
				OpenCloud.configFromEnv(with({ ROBLOX_BETA_UNIVERSE_ID = bad }))
			end).toThrow("ROBLOX_BETA_UNIVERSE_ID")
			t.expect(function()
				OpenCloud.configFromEnv(with({ ROBLOX_BETA_PLACE_ID = bad }))
			end).toThrow("ROBLOX_BETA_PLACE_ID")
		end
	end)

	it(
		"a base override is accepted only for a loopback address, so the key can't be sent elsewhere",
		function()
			for _, ok in { "http://127.0.0.1:8080", "http://localhost:1" } do
				local cfg = OpenCloud.configFromEnv(with({ OPENCLOUD_BASE = ok }))
				t.expect((cfg :: OpenCloud.Config).base).toBe(ok)
			end
			for _, bad in
				{
					"https://example.com",
					"http://127.0.0.1.evil.com:80",
					"http://localhost.evil.com:80",
					"http://evil.com/?http://127.0.0.1:1",
					"http://127.0.0.1",
					"http://127.0.0.1:8080/",
					"http://10.0.0.1:80",
				}
			do
				t.expect(function()
					OpenCloud.configFromEnv(with({ OPENCLOUD_BASE = bad }))
				end).toThrow("loopback")
			end
			local plain = OpenCloud.configFromEnv(with({ OPENCLOUD_BASE = "" }))
			t.expect((plain :: OpenCloud.Config).base).toBe(nil) -- unset or empty: Roblox's own host
			t.expect((OpenCloud.configFromEnv(FULL) :: OpenCloud.Config).base).toBe(nil)
		end
	)

	it("the error does not repeat the key", function()
		local ok, err = pcall(
			OpenCloud.configFromEnv,
			with({ ROBLOX_API_KEY = "TOP-SECRET-KEY", ROBLOX_BETA_PLACE_ID = "x" })
		)
		t.expect(ok).toBe(false)
		t.expect((string.find(tostring(err), "TOP-SECRET-KEY", 1, true))).toBe(nil)
	end)
end)
