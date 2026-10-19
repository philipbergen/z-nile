--!strict
-- f0024 AC6: the feature module stays free of the engine, and the server adapter calls the pure
-- policy instead of inventing its own retry or store names. Both files are absent until the raft
-- builds them, so this fails on the missing file.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local LOGIC = "src/shared/Logic/Hiscores/init.luau"
local ADAPTER = "src/server/HiscoreStore.luau"

local function stripped(path: string): string
	return string.gsub(fs.readFile(path), "%-%-[^\n]*", "")
end

return t.spec("f0024 module shape", function(it)
	it("the feature is one init module and it does not touch the engine or the clock", function()
		t.expect(fs.isFile(LOGIC)).toBe(true)
		t.expect(fs.isDir("src/shared/Logic/Hiscores")).toBe(true)
		local src = fs.readFile(LOGIC)
		for _, word in { "game", "workspace", "Instance", "script", "Enum", "DataStore" } do
			t.expect((string.find(src, `%f[%w_]{word}%f[^%w_]`))).toBe(nil)
		end
		t.expect((string.find(src, "os.date", 1, true))).toBe(nil)
		t.expect((string.find(src, "os.time", 1, true))).toBe(nil)
		t.expect(string.find(src, 'ORDERED_STORE = "Hiscores"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, 'COMPANION_STORE = "HiscoreEntries"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(src, "LEVEL_CAP = 10000", 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile("src/shared/Logic/Hiscores/init.luau")).toBe(true)
	end)

	it("the adapter calls the pure drive, the modern budgets, and no environment prefix", function()
		t.expect(fs.isFile(ADAPTER)).toBe(true)
		local src = stripped(ADAPTER)
		for _, needle in
			{
				"Hiscores.drive",
				"Hiscores.once",
				"Hiscores.commit",
				"Hiscores.pack",
				"UpdateAsync",
				"GetSortedAsync(false",
				"Hiscores.ORDERED_STORE",
				"Hiscores.COMPANION_STORE",
				"Hiscores.pageAttempt",
				"Hiscores.scorePage",
				"Hiscores.storeTarget",
				"StandardRead",
				"StandardWrite",
				"OrderedWrite",
				"task.spawn",
				"os.time",
				"pcall",
				"warn",
			}
		do
			t.expect(string.find(src, needle, 1, true) ~= nil).toBe(true)
		end
		t.expect((string.find(src, "SetAsync", 1, true))).toBe(nil)
		t.expect((string.find(src, "RequestType.GetAsync", 1, true))).toBe(nil)
		t.expect((string.find(src, "SetIncrement", 1, true))).toBe(nil)
		t.expect((string.find(src, "OrderedList", 1, true))).toBe(nil)
		t.expect((string.find(src, "HiscoresBeta", 1, true))).toBe(nil)
		t.expect((string.find(src, "os.date", 1, true))).toBe(nil)
		t.expect((string.find(src, "FireClient", 1, true))).toBe(nil)
	end)
end)
