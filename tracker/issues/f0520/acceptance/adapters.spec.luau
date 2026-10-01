--!strict
-- f0520 AC2: both adapters use the step rate, so the slowdown is real and smooth. The server's clock
-- steps at Session.STEP_RATE, and the client interpolates between snapshots over 1/STEP_RATE seconds. If
-- either kept the tick rate, the game would still run at full speed, or the camera would jump.
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

-- an adapter's source without comments, so a mention in a comment proves nothing
local function source(path: { string }): string
	local node: any = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	local src = string.gsub(node.Source, "%-%-[^\n]*", "")
	return src
end

return t.spec("f0520 adapters use the step rate", function(it)
	it("the server's clock is created with Session.STEP_RATE", function()
		local src = source({ "ServerScriptService", "Server", "Sessions" })
		local calls = 0
		for call in string.gmatch(src, "Session%.newClock%b()") do
			calls += 1
			t.expect(string.find(call, "^Session%.newClock%(%s*Session%.STEP_RATE%s*%)$") ~= nil).toBe(true)
		end
		t.expect(calls).toBe(1)
	end)

	it("the client's blend is View.alpha of the elapsed real time, never the tick rate", function()
		local src = source({ "StarterPlayer", "StarterPlayerScripts", "Client", "Camera" })
		local calls = 0
		for call in string.gmatch(src, "View%.interpolate%b()") do
			calls += 1
			-- the blend comes from View.alpha of the real seconds since the latest snapshot arrived, nothing else
			t.expect(
				string.find(
					call,
					"^View%.interpolate%(%s*prev%s*,%s*snap%s*,%s*View%.alpha%(%s*os%.clock%(%)%s*%-%s*arrived%s*%)%s*%)$"
				) ~= nil
			).toBe(true)
		end
		t.expect(calls).toBe(1)
	end)

	it("neither adapter uses the tick rate for pacing anywhere", function()
		t.expect((string.find(source({ "ServerScriptService", "Server", "Sessions" }), "TICK_RATE", 1, true)))
			.toBe(nil)
		t.expect(
			(
				string.find(
					source({ "StarterPlayer", "StarterPlayerScripts", "Client", "Camera" }),
					"TICK_RATE",
					1,
					true
				)
			)
		).toBe(nil)
	end)
end)
