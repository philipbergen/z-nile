--!strict
-- f0300 AC2: the server stays thin. Any call the Sessions adapter makes to Session.playAgain is for the
-- sending player's own session, and it leaves the decision (only at game over) to Logic.
-- Narrowed by c0063: the PlayAgain remote and its handler are no longer required (f0065 replaces them).
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function find(path: { string }): any
	local node = game
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- the adapter's source without comments, so a mention in a comment proves nothing
local function sessions(): string
	local src = string.gsub(find({ "ServerScriptService", "Server", "Sessions" }).Source, "%-%-[^\n]*", "")
	return src
end

return t.spec("f0300 play again on the server", function(it)
	it("the place keeps its Ready, Intent and Snapshot RemoteEvents", function()
		for _, name in { "Ready", "Intent", "Snapshot" } do
			t.expect(find({ "ReplicatedStorage", "Remotes", name }).ClassName).toBe("RemoteEvent")
		end
	end)

	it(
		"any Session.playAgain call in Sessions is for the sending player's own id, and nothing the client sent",
		function()
			local calls = 0
			for call in string.gmatch(sessions(), "Session%.playAgain%b()") do
				calls += 1
				t.expect(
					string.find(
						call,
						"^Session%.playAgain%(%s*[%w_]+%s*,%s*tostring%(%s*[%w_]+%.UserId%s*%)%s*%)$"
					) ~= nil
				).toBe(true)
			end
			t.expect(calls <= 1).toBe(true)
		end
	)

	it(
		"a handler that plays again takes only the sending player, and uses it for both the session and the id",
		function()
			local found = 0
			for rawParams, rawBody in
				string.gmatch(sessions(), "OnServerEvent:Connect%(function(%b())(.-)\n%s*end%)")
			do
				local params, body = rawParams :: string, rawBody :: string
				if string.find(body, "Session.playAgain(", 1, true) then
					found += 1
					local name = string.match(params, "^%(%s*([%w_]+)%s*:?%s*[%w_]*%s*%)$")
					t.expect(name ~= nil).toBe(true)
					local who = name :: string
					t.expect(string.find(body, "%[%s*" .. who .. "%s*%]") ~= nil).toBe(true)
					t.expect(string.find(body, "tostring%(%s*" .. who .. "%.UserId%s*%)") ~= nil).toBe(true)
				end
			end
			t.expect(found <= 1).toBe(true)
		end
	)

	it("Sessions leaves the decision to Logic: it never looks at the phase", function()
		local src = sessions()
		t.expect((string.find(src, "gameover", 1, true))).toBe(nil)
		t.expect((string.find(src, ".phase", 1, true))).toBe(nil)
	end)
end)
