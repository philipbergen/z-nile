--!strict
-- f0025 AC3: Sessions steps inside Session.advance, submits from that step's events, and parks a
-- departing player so the dying pause still runs. Play again is optional: f0065 may delete it.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local PATH = "src/server/Sessions.luau"

local function source(): string
	return string.gsub(fs.readFile(PATH), "%-%-[^\n]*", "")
end

return t.spec("f0025 Sessions wiring", function(it)
	it("the clock, the frame and the config stay as they are", function()
		local src = source()
		local clocks = 0
		for call in string.gmatch(src, "Session%.newClock%b()") do
			clocks += 1
			t.expect(string.find(call, "^Session%.newClock%(%s*Session%.STEP_RATE%s*%)$") ~= nil).toBe(true)
		end
		t.expect(clocks).toBe(1)
		local created = 0
		for call in string.gmatch(src, "Session%.new%b()") do
			created += 1
			t.expect(string.find(call, "Session%.GAME_CONFIG%s*%)$") ~= nil).toBe(true)
		end
		t.expect(created >= 1).toBe(true)
		t.expect(string.find(src, ":FireClient%(%s*[%w_%.]+%s*,%s*Session%.frame%(") ~= nil).toBe(true)
		t.expect((string.find(src, "Session.snapshot(", 1, true))).toBe(nil)
		t.expect((string.find(src, "PlayerAdded", 1, true))).toBe(nil)
		t.expect((string.find(src, "TICK_RATE", 1, true))).toBe(nil)
		t.expect(string.find(src, "Ready", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "OnServerEvent", 1, true) ~= nil).toBe(true)
	end)

	it("Ready starts a run, and play again is at most the sender's own session", function()
		local src = source()
		t.expect(string.find(src, "Hiscores.newRun()", 1, true) ~= nil).toBe(true)
		local calls = 0
		for call in string.gmatch(src, "Session%.playAgain%b()") do
			calls += 1
			t.expect(
				string.find(
					call,
					"^Session%.playAgain%(%s*[%w_]+%s*,%s*tostring%(%s*[%w_]+%.UserId%s*%)%s*%)$"
				) ~= nil
			).toBe(true)
		end
		t.expect(calls <= 1).toBe(true)
		local agains = 0
		for _ in string.gmatch(src, "Hiscores%.onAgain%b()") do
			agains += 1
		end
		if calls == 1 then
			t.expect(agains).toBe(1)
			t.expect(string.find(src, "if ok then", 1, true) ~= nil).toBe(true)
		else
			t.expect(agains).toBe(0)
		end
	end)

	it("GameOver is stepped inside advance, and the frame is sent only while the player is here", function()
		local src = source()
		t.expect(string.find(src, "GameOver", 1, true) ~= nil).toBe(true)
		t.expect((string.find(src, "gameover", 1, true))).toBe(nil)
		t.expect((string.find(src, ".phase", 1, true))).toBe(nil)
		t.expect((string.find(src, "task.wait", 1, true))).toBe(nil)
		t.expect((string.find(src, "task.delay", 1, true))).toBe(nil)
		local advances = 0
		for _ in string.gmatch(src, "Session%.advance%b()") do
			advances += 1
		end
		t.expect(advances).toBe(1)
		local advanceAt = string.find(src, "Session.advance", 1, true)
		local steps = 0
		local pendingHere = false
		for call in string.gmatch(src, "Hiscores%.onStep%b()") do
			steps += 1
			local at = string.find(src, call, 1, true)
			t.expect(advanceAt ~= nil and at ~= nil and advanceAt < at).toBe(true)
			t.expect(string.find(call, "events", 1, true) ~= nil).toBe(true)
			if string.find(call, "false", 1, true) then
				pendingHere = true
			end
		end
		t.expect(steps >= 2).toBe(true)
		t.expect(pendingHere).toBe(true)
		t.expect(string.find(src, "local events = Session.step", 1, true) ~= nil).toBe(true)
		local flat = string.gsub(src, "%s+", " ")
		local hereAt = string.find(flat, "if here then", 1, true)
		local frameAt = string.find(flat, "Session.frame", 1, true)
		t.expect(hereAt ~= nil and frameAt ~= nil and hereAt < frameAt).toBe(true)
		local submits = 0
		for call in string.gmatch(src, "HiscoreStore%.submit%b()") do
			submits += 1
			t.expect(string.find(call, "submission", 1, true) ~= nil).toBe(true)
		end
		t.expect(submits >= 1).toBe(true)
		t.expect(string.find(src, "Hiscores.cleanName", 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "DisplayName", 1, true) ~= nil).toBe(true)
	end)

	it("leaving nils the live session and parks the run for the same advance loop", function()
		local body = string.match(source(), "PlayerRemoving:Connect%(function%b()(.-)\n%s*end%)")
		t.expect(body ~= nil).toBe(true)
		local handler = body :: string
		t.expect(string.find(handler, "sessions[player] = nil", 1, true) ~= nil).toBe(true)
		t.expect(string.find(handler, "pending", 1, true) ~= nil).toBe(true)
	end)

	it("Ranks does not FireClient a player whose Parent is nil", function()
		t.expect(fs.isFile("src/server/Ranks.luau")).toBe(true)
		local ranks = string.gsub(fs.readFile("src/server/Ranks.luau"), "%-%-[^\n]*", "")
		local parentAt = string.find(ranks, "Parent ~= nil", 1, true)
		local fireAt = string.find(ranks, "FireClient", 1, true)
		t.expect(parentAt ~= nil and fireAt ~= nil and parentAt < fireAt).toBe(true)
	end)
end)
