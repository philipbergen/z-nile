--!strict
-- The game place's Bests adapter (f0148; R0094 code review 001 F2): `Bests.reached` runs for every step of every
-- session, so it asks the engine for the DataStore only when a run reached a level. The real source runs on a stub
-- whose GetDataStore counts its calls and always fails, as in a place that cannot reach DataStores.
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function sourceOf(path: { string }): string
	local node: any = gamePlace
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	assert(node, `{table.concat(path, ".")} in the built place`)
	return node.Source
end

-- the adapter on an engine whose DataStoreService never opens a store; `opens.n` counts the tries
local function boot(): (any, { n: number })
	local opens = { n = 0 }
	local signal = {
		Connect = function(_: any, _fn: (...any) -> ()): any
			return { Disconnect = function() end }
		end,
	}
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, _name: string): any
				opens.n += 1
				error("stub: DataStores cannot be reached", 0)
			end,
		},
		Players = {
			PlayerAdded = signal,
			PlayerRemoving = signal,
			GetPlayers = function(): { any }
				return {}
			end,
		},
	}
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], `the adapter asks for {name}`)
			end,
		},
		require = function(path: string): any
			local feature = string.match(path, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
			assert(feature, `the adapter requires {path}`)
			return (require :: any)("@logic/" .. feature)
		end,
		task = {
			spawn = function(fn: (...any) -> (), ...: any)
				local ok, err = coroutine.resume(coroutine.create(fn), ...)
				if not ok then
					error(err, 0)
				end
			end,
			wait = function(seconds: number?): number
				return seconds or 0.03
			end,
		},
	}
	local source = sourceOf({ "ServerScriptService", "Server", "Bests" })
	return luau.load(source, { debugName = "Bests", environment = env })(), opens
end

return t.spec("the game place's Bests opens the store only for a level reached", function(it)
	it("a step with no level reached never asks for the store, however many steps there are", function()
		local bests, opens = boot()
		local quiet: { { any } } = {
			{},
			{ { kind = "Boosted", player = "7" } },
			{ { kind = "Ready", reason = "start", player = "7", level = 1 } },
			{ { kind = "Ready", reason = "level", player = 7, level = 2 } }, -- a player that is no key
		}
		for _ = 1, 25 do
			for _, events in quiet do
				bests.reached(events)
			end
		end
		t.expect(opens.n).toBe(0)
	end)

	it(
		"a level reached asks once, and a store that cannot be opened is no error and is asked again next time",
		function()
			local bests, opens = boot()
			local reached = { { kind = "Ready", reason = "level", player = "7", level = 2 } }
			bests.reached(reached)
			t.expect(opens.n).toBe(1)
			bests.reached({})
			t.expect(opens.n).toBe(1)
			bests.reached(reached)
			t.expect(opens.n).toBe(2)
		end
	)
end)
