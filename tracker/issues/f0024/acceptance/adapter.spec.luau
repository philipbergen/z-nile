--!strict
-- f0024 AC6: the feature module stays free of the engine, and the server adapter calls the pure
-- policy instead of inventing its own retry, dedupe or store names. The adapter's real source runs here on a
-- stub `game` (its own small stub, not tests/lib/fakeengine): a DataStoreService whose UpdateAsync stores
-- whatever the transform returns, an immediate task.spawn, and a fixed os.time. Both files are absent until
-- the raft builds them, so this fails on the missing file.
local Hiscores = require("@logic/Hiscores")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local LOGIC = "src/shared/Logic/Hiscores/init.luau"
local ADAPTER = "src/server/HiscoreStore.luau"
local HISCORES = "@game/ReplicatedStorage/Shared/Logic/Hiscores"

local FRI = 1792108800

local function stripped(path: string): string
	return string.gsub(fs.readFile(path), "%-%-[^\n]*", "")
end

type Store = { name: string, scope: string, data: { [string]: any }, updates: number }
type World = {
	store: any,
	stores: { [string]: Store },
	budgets: { string },
	warnings: number,
	sortedFails: boolean,
	heard: { { any } },
}

local function world(): World
	local w: World = {
		store = nil,
		stores = {},
		budgets = {},
		warnings = 0,
		sortedFails = false,
		heard = {},
	}
	local function open(kind: string, name: string, scope: string?): any
		local id = `{kind}|{name}|{scope or "global"}`
		local found = w.stores[id]
		if found == nil then
			found = { name = name, scope = scope or "global", data = {}, updates = 0 }
			w.stores[id] = found
		end
		local s = found :: Store
		return {
			GetAsync = function(_: any, key: string): any
				return s.data[key]
			end,
			UpdateAsync = function(_: any, key: string, transform: (any) -> any): any
				s.updates += 1
				local nextValue = transform(s.data[key])
				if nextValue ~= nil then
					s.data[key] = nextValue
				end
				return nextValue
			end,
			GetSortedAsync = function(_: any, ascending: boolean, size: number): any
				if w.sortedFails then
					error("stub: sorted read failed", 0)
				end
				local list: { { key: string, value: number } } = {}
				for key, value in s.data do
					table.insert(list, { key = key, value = value })
				end
				table.sort(list, function(a, b)
					if ascending then
						return a.value < b.value
					end
					return a.value > b.value
				end)
				while #list > size do
					table.remove(list)
				end
				return {
					GetCurrentPage = function(_: any): any
						return list
					end,
				}
			end,
		}
	end
	local dataStores = {
		GetDataStore = function(_: any, name: string, scope: string?): any
			return open("companion", name, scope)
		end,
		GetOrderedDataStore = function(_: any, name: string, scope: string?): any
			return open("ordered", name, scope)
		end,
		GetRequestBudgetForRequestType = function(_: any, kind: any): number
			table.insert(w.budgets, tostring(kind))
			return 100
		end,
	}
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				assert(name == "DataStoreService", `stub: game:GetService("{name}") is not modelled`)
				return dataStores
			end,
		},
		require = function(spec: string): any
			assert(spec == HISCORES, `stub: no module for {spec}`)
			return Hiscores
		end,
		Enum = setmetatable({}, {
			__index = function(_: any, group: string): any
				return setmetatable({}, {
					__index = function(_: any, item: string): string
						return `{group}.{item}`
					end,
				})
			end,
		}),
		task = {
			spawn = function(fn: (...any) -> (), ...: any)
				fn(...)
			end,
			wait = function(_seconds: number?) end,
		},
		os = {
			time = function(): number
				return FRI
			end,
		},
		warn = function()
			w.warnings += 1
		end,
	}
	local chunk = luau.load(fs.readFile(ADAPTER), { environment = env, debugName = "HiscoreStore" })
	w.store = chunk()
	w.store.listen(function(userId: string, run: number, rank: number)
		table.insert(w.heard, { userId, run, rank } :: { any })
	end)
	return w
end

-- what the store of that name and scope holds; empty when the adapter never opened it
local function ordered(w: World, scope: string): { [string]: any }
	local s = w.stores[`ordered|Hiscores|{scope}`]
	return if s then s.data else {}
end

local function companion(w: World, scope: string): { [string]: any }
	local s = w.stores[`companion|HiscoreEntries|{scope}`]
	return if s then s.data else {}
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
	end)

	it("the adapter calls the pure drive, the modern budgets, and no environment prefix or dedupe", function()
		t.expect(fs.isFile(ADAPTER)).toBe(true)
		local src = stripped(ADAPTER)
		for _, needle in
			{
				"Hiscores.drive",
				"UpdateAsync",
				"GetSortedAsync(false",
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
		-- the transforms are the ones drive passes; the adapter has no copy of the policy, and no run dedupe
		for _, banned in
			{
				"Hiscores.once",
				"Hiscores.commit",
				"Hiscores.pack",
				"SetAsync",
				"RequestType.GetAsync",
				"SetIncrement",
				"OrderedList",
				"HiscoresBeta",
				"os.date",
				"FireClient",
			}
		do
			t.expect((string.find(src, banned, 1, true))).toBe(nil)
		end
	end)

	it("two submits for one user id and run both drive, and the better one is stored", function()
		local w = world()
		w.store.submit("7", "Ada", 50, 2, 1)
		w.store.submit("7", "Ada", 80, 3, 1)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(80, 3))
		t.expect((companion(w, "all")["7"] or {}).score).toBe(80)
		t.expect(ordered(w, "day:2026-10-16")["7:2026-10-16"]).toBe(Hiscores.pack(80, 3))
		t.expect(ordered(w, "week:2026-10-12")["7:2026-10-12"]).toBe(Hiscores.pack(80, 3))
		t.expect(#w.heard).toBe(2)
		t.expect(w.heard[2]).toEqual({ "7", 1, 1 } :: { any })
		t.expect(w.warnings).toBe(0)
	end)

	it("the ordered write is drive's max: a higher value already stored stays", function()
		local w = world()
		w.store.submit("9", "Old", 1, 1, 1)
		-- another server's better run reached the ordered key first; its companion is not here yet
		ordered(w, "all")["7"] = Hiscores.pack(8000, 1)
		w.store.submit("7", "Ada", 5000, 2, 1)
		t.expect((companion(w, "all")["7"] or {}).score).toBe(5000)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(8000, 1))
		t.expect(ordered(w, "day:2026-10-16")["7:2026-10-16"]).toBe(Hiscores.pack(5000, 2))
	end)

	it("a lower submit rewrites neither the row nor the ordered key", function()
		local w = world()
		w.store.submit("7", "Ada", 50, 2, 1)
		w.store.submit("7", "Nope", 10, 9, 2)
		t.expect((companion(w, "all")["7"] or {}).name).toBe("Ada")
		t.expect((companion(w, "all")["7"] or {}).score).toBe(50)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(50, 2))
	end)

	it("stores are the shared names scoped by period, budgets are the modern request types", function()
		local w = world()
		w.store.submit("7", "Ada", 50, 2, 1)
		local names: { string } = {}
		for _, s in w.stores do
			table.insert(names, `{s.name}|{s.scope}`)
		end
		table.sort(names)
		t.expect(names).toEqual({
			"HiscoreEntries|all",
			"HiscoreEntries|day:2026-10-16",
			"HiscoreEntries|week:2026-10-12",
			"Hiscores|all",
			"Hiscores|day:2026-10-16",
			"Hiscores|week:2026-10-12",
		})
		t.expect(#w.budgets > 0).toBe(true)
		for _, kind in w.budgets do
			local known = kind == "DataStoreRequestType.StandardRead"
				or kind == "DataStoreRequestType.StandardWrite"
				or kind == "DataStoreRequestType.OrderedWrite"
			t.expect(known).toBe(true)
		end
	end)

	it("no rank is heard when the board cannot be read, and the write still happens", function()
		local w = world()
		w.sortedFails = true
		w.store.submit("7", "Ada", 50, 2, 1)
		t.expect(ordered(w, "all")["7"]).toBe(Hiscores.pack(50, 2))
		t.expect(#w.heard).toBe(0)
	end)
end)
