--!strict
-- f0145 AC3 and AC2 (design review 001 F1, F7): a run's end reaches the hiscore through the real adapters. Sessions
-- and Submits run from their real sources on a stub engine, with a HiscoreStore that records each submit. A player
-- who leaves in the last life's dying pause, in an open continue offer or in a held one has their run end
-- (Session.leave) and submitted exactly once within Hiscores.LEAVE_STEPS, carrying the lives lost; and HiscoreStore's
-- real source writes a submit's lives into the stored row.
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
	submits: { { any } },
	sessions: any,
	player: any,
	step: (n: number) -> (),
	leave: () -> (),
}

local function run(): Run
	local submits: { { any } } = {}
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
			table.insert(submits, { ... })
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
		sessions = sessions,
		player = player,
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

-- the session of the run's player, with the offer on, played to the given point of its last life
local function toLastLife(r: Run): Session.Session
	local s = r.sessions.session(r.player) :: Session.Session
	Session.allowOffer(s, "7")
	for _ = 1, 3 do
		for _ = 1, 400 do
			if Session.frame(s, "7").play.phase == "playing" then
				break
			end
			r.step(1)
		end
		Session.kill(s, "7")
		if Session.frame(s, "7").play.lives > 0 then
			r.step(1)
		end
	end
	return s
end

return t.spec("f0145 a run's end reaches the hiscore", function(it)
	it("a player who leaves in the last dying pause is submitted once, with the lives lost", function()
		local r = run()
		local s = toLastLife(r)
		t.expect(Session.frame(s, "7").play.phase).toBe("dying")
		r.leave()
		r.step(Hiscores.LEAVE_STEPS)
		t.expect(#r.submits).toBe(1)
		t.expect(r.submits[1][6]).toBe(3)
	end)

	it("a player who leaves in an open offer is submitted once, with the lives lost", function()
		local r = run()
		local s = toLastLife(r)
		for _ = 1, 200 do
			if Session.offering(s, "7") then
				break
			end
			r.step(1)
		end
		t.expect(Session.offering(s, "7")).toBe(true)
		r.leave()
		r.step(Hiscores.LEAVE_STEPS)
		t.expect(#r.submits).toBe(1)
		t.expect(r.submits[1][6]).toBe(3)
	end)

	it("a player who leaves in a held offer (a purchase screen open) is submitted once", function()
		local r = run()
		local s = toLastLife(r)
		for _ = 1, 200 do
			if Session.offering(s, "7") then
				break
			end
			r.step(1)
		end
		Session.hold(s, "7", true)
		r.leave()
		r.step(Hiscores.LEAVE_STEPS)
		t.expect(#r.submits).toBe(1)
		t.expect(r.submits[1][6]).toBe(3)
	end)

	it("HiscoreStore's real source writes a submit's lives into the stored row", function()
		local rows: { any } = {}
		local services: { [string]: any } = {
			DataStoreService = {
				GetDataStore = function(_: any, name: string, _scope: string?): any
					return {
						UpdateAsync = function(_: any, _key: string, fn: (any) -> any): any
							local made = fn(nil)
							if name == Hiscores.COMPANION_STORE then
								table.insert(rows, made)
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
			require = logic,
		}
		local store = luau.load(HISCORE_STORE, { environment = env, debugName = "HiscoreStore" })() :: any
		store.submit("7", "Ada", 800, 3, 1, 6)
		t.expect(#rows >= 1).toBe(true)
		for _, row in rows do
			t.expect(row.lives).toBe(6)
		end
	end)
end)
