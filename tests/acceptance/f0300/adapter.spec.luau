--!strict
-- f0300 AC2: playing again goes through the server. The place has a PlayAgain RemoteEvent; the Sessions
-- adapter relays it to Session.playAgain for the sending player's own session, and leaves the decision
-- (only at game over) to Logic. The runtime structure check on Beta knows the new remote.
local fs = require("@lune/fs")
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
	it("the place has a PlayAgain RemoteEvent beside the other remotes", function()
		t.expect(find({ "ReplicatedStorage", "Remotes", "PlayAgain" }).ClassName).toBe("RemoteEvent")
		for _, name in { "Ready", "Intent", "Snapshot" } do
			t.expect(find({ "ReplicatedStorage", "Remotes", name }).ClassName).toBe("RemoteEvent")
		end
	end)

	it("Sessions listens to PlayAgain on the server", function()
		local src = sessions()
		t.expect(string.find(src, '"PlayAgain"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "OnServerEvent", 1, true) ~= nil).toBe(true)
	end)

	it(
		"Sessions calls Session.playAgain for the sending player's own id, and nothing the client sent",
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
			t.expect(calls).toBe(1)
		end
	)

	it(
		"the PlayAgain handler takes only the sending player, and uses it for both the session and the id",
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
			t.expect(found).toBe(1)
		end
	)

	it("Sessions leaves the decision to Logic: it never looks at the phase", function()
		local src = sessions()
		t.expect((string.find(src, "gameover", 1, true))).toBe(nil)
		t.expect((string.find(src, ".phase", 1, true))).toBe(nil)
	end)

	it("the Beta runtime structure check asserts the PlayAgain remote", function()
		local text = fs.readFile("tests/runtime/structure.luau")
		t.expect(string.find(text, '"PlayAgain"', 1, true) ~= nil).toBe(true)
	end)
end)
