--!strict
-- f0186 AC3: a run's revives reach the stored hiscore through the real adapters. Sessions and Submits run from their
-- real sources on a stub engine (f0145's runs.spec world), with a HiscoreStore that records each submit: Submits
-- passes the submission's revives as HiscoreStore.submit's seventh argument (after f0145's lives), nil for a run
-- without one, also for a player who leaves after a continue. HiscoreStore's real source writes a submit's revives
-- into every stored row and into the run's entry on the top-10 list.
local Hiscores = require("@logic/Hiscores")
local Session = require("@logic/Session")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local gamePlace = place.load()

local function sourceAt(path: { string }): string
	local node: any = gamePlace
	for _, part in path do
		node = node and node:FindFirstChild(part)
	end
	assert(node, `no {table.concat(path, ".")}`)
	return node.Source
end

local SESSIONS = sourceAt({ "ServerScriptService", "Server", "Sessions" })
local SUBMITS = sourceAt({ "ServerScriptService", "Server", "Submits" })
local HISCORE_STORE = sourceAt({ "ServerScriptService", "Server", "HiscoreStore" })

type Signal = { Connect: (any, (...any) -> ()) -> (), fire: (...any) -> () }
local function signal(): Signal
	local fns: { (...any) -> () } = {}
	return {
		Connect = function(_: any, fn: (...any) -> ())
			table.insert(fns, fn)
		end,
		fire = function(...: any)
			for _, fn in fns do
				fn(...)
			end
		end,
	}
end

local function logic(spec: string): any
	local name = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/([%w_]+)$")
	return (require :: any)("@logic/" .. assert(name, spec))
end

type Run = {
	submits: { { n: number, args: { any } } },
	session: () -> Session.Session,
	step: (n: number) -> (),
	leave: () -> (),
}

local function run(): Run
	local submits: { { n: number, args: { any } } } = {}
	local heartbeat, removing = signal(), signal()
	local remotes: { [string]: any } = {}
	for _, name in { "Ready", "Intent", "Snapshot" } do
		remotes[name] = { OnServerEvent = signal(), FireClient = function() end }
	end
	local services: { [string]: any } = {
		Players = { PlayerRemoving = removing },
		ReplicatedStorage = {
			WaitForChild = function(_: any, _n: string): any
				return {
					WaitForChild = function(_: any, name: string): any
						return assert(remotes[name], name)
					end,
				}
			end,
		},
		RunService = { Heartbeat = heartbeat },
	}
	local recorder = {
		submit = function(...: any)
			table.insert(submits, { n = select("#", ...), args = { ... } })
		end,
		pending = function(): number
			return 0
		end,
	}
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				return assert(services[name], name)
			end,
			BindToClose = function() end,
		},
		require = function(spec: string): any
			if spec == "./HiscoreStore" then
				return recorder
			end
			return logic(spec)
		end,
	}
	local submitsModule = luau.load(SUBMITS, { environment = env, debugName = "Submits" })() :: any
	local sessions = luau.load(SESSIONS, { environment = env, debugName = "Sessions" })() :: any
	sessions.start(submitsModule)
	local player: any = { UserId = 7, Name = "Ada", DisplayName = "Ada", Parent = {} }
	remotes.Ready.OnServerEvent.fire(player)
	local r: Run
	r = {
		submits = submits,
		session = function(): Session.Session
			return sessions.session(player) :: Session.Session
		end,
		step = function(n: number)
			for _ = 1, n do
				heartbeat.fire(1 / Session.STEP_RATE)
			end
		end,
		leave = function()
			player.Parent = nil
			removing.fire(player)
		end,
	}
	return r
end

-- step the run, killing the player whenever they play, until the run is in `phase`
local function reach(r: Run, phase: string)
	local s = r.session()
	for _ = 1, 2000 do
		local now = Session.frame(s, "7").play.phase
		if now == phase then
			return
		end
		if now == "playing" then
			Session.kill(s, "7")
		end
		r.step(1)
	end
	error(`never reached {phase}`)
end

return t.spec("f0186 a run's revives reach the stored hiscore", function(it)
	it("Submits hands HiscoreStore the run's revives after the lives; none is nil", function()
		local r = run()
		Session.allowOffer(r.session(), "7")
		reach(r, "offer")
		local _, ok = Session.continue(r.session(), "7")
		t.expect(ok).toBe(true)
		reach(r, "offer")
		Session.continue(r.session(), "7")
		reach(r, "offer")
		Session.decline(r.session(), "7")
		r.step(1)
		t.expect(#r.submits).toBe(1)
		t.expect(r.submits[1].n >= 7).toBe(true)
		t.expect(r.submits[1].args[7]).toBe(2)
		t.expect(r.submits[1].args[6]).toBe(9) -- f0145's lives lost: 3 a life set, 3 sets
		local plain = run()
		Session.allowOffer(plain.session(), "7")
		reach(plain, "offer")
		Session.decline(plain.session(), "7")
		plain.step(1)
		t.expect(#plain.submits).toBe(1)
		t.expect(plain.submits[1].args[7]).toBe(nil)
	end)

	it("a player who leaves after a continue is submitted once, with that revive", function()
		local r = run()
		Session.allowOffer(r.session(), "7")
		reach(r, "offer")
		Session.continue(r.session(), "7")
		reach(r, "offer")
		r.leave()
		r.step(Hiscores.LEAVE_STEPS)
		t.expect(#r.submits).toBe(1)
		t.expect(r.submits[1].args[7]).toBe(1)
	end)

	it(
		"HiscoreStore's real source writes a submit's revives into every stored row and the list entry",
		function()
			local function write(...: any): ({ any }, { any })
				local rows: { any } = {}
				local lists: { any } = {}
				local services: { [string]: any } = {
					DataStoreService = {
						GetDataStore = function(_: any, name: string, _scope: string?): any
							return {
								UpdateAsync = function(_: any, _key: string, fn: (any) -> any): any
									local made = fn(nil)
									if name == Hiscores.COMPANION_STORE then
										table.insert(rows, made)
									elseif name == Hiscores.TOP_STORE then
										table.insert(lists, made)
									end
									return made
								end,
								GetAsync = function(): any
									return nil
								end,
							}
						end,
						GetOrderedDataStore = function(_: any, _name: string, _scope: string?): any
							return {
								UpdateAsync = function(_: any, _key: string, fn: (any) -> any): any
									return fn(nil)
								end,
								GetSortedAsync = function(): any
									return {
										GetCurrentPage = function(): { any }
											return {}
										end,
									}
								end,
							}
						end,
						GetRequestBudgetForRequestType = function(): number
							return 100
						end,
					},
				}
				local env: { [string]: any } = {
					game = {
						GetService = function(_: any, name: string): any
							return assert(services[name], name)
						end,
						JobId = "job",
					},
					Enum = setmetatable({}, {
						__index = function(_: any, g: string): any
							return setmetatable({}, {
								__index = function(_: any, i: string): string
									return `{g}.{i}`
								end,
							})
						end,
					}),
					task = {
						spawn = function(fn: () -> ())
							fn()
						end,
						wait = function(): number
							return 0
						end,
					},
					warn = function(...: any)
						error(table.concat({ ... }, " "))
					end,
					require = logic,
				}
				local store =
					luau.load(HISCORE_STORE, { environment = env, debugName = "HiscoreStore" })() :: any
				store.submit(...)
				return rows, lists
			end
			local rows, lists = write("7", "Ada", 800, 3, 1, 6, 2)
			t.expect(#rows).toBe(3) -- all-time, today, this week
			for _, row in rows do
				t.expect(row.revives).toBe(2)
			end
			t.expect(#lists >= 1).toBe(true)
			local entry = (lists[#lists] :: { any })[1]
			t.expect(entry.userId).toBe("7")
			t.expect(entry.revives).toBe(2)
			local plainRows, plainLists = write("7", "Ada", 800, 3, 1, 6)
			for _, row in plainRows do
				t.expect(row.revives).toBe(nil)
			end
			t.expect((plainLists[#plainLists] :: { any })[1].revives).toBe(nil)
		end
	)
end)
