--!strict
-- Boards: a title is served on one remote per place (R0121 review 001 F2). `Boards.open` hands every caller in a
-- place the same handle, and a board's waiters are the handle's, so a second `serve` on the same remote must not
-- answer a request twice, and one on another remote must fail at once rather than lose answers. The adapter's real
-- source runs on a stub `game` whose stores are empty.
local Hiscores = require("@logic/Hiscores")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local ADAPTER = "src/server/Boards.luau"
local FRI = 1792108800

local function load(): any
	local store = {
		GetAsync = function(_: any, _key: string): any
			return nil
		end,
		UpdateAsync = function(_: any, _key: string, transform: (any) -> any): any
			return transform(nil)
		end,
		GetSortedAsync = function(_: any, _ascending: boolean, _size: number): any
			return {
				GetCurrentPage = function(_: any): any
					return {}
				end,
			}
		end,
	}
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, _name: string, _scope: string?): any
				return store
			end,
			GetOrderedDataStore = function(_: any, _name: string, _scope: string?): any
				return store
			end,
			GetRequestBudgetForRequestType = function(_: any, _kind: any): number
				return 100
			end,
		},
		Players = {
			PlayerRemoving = {
				Connect = function(_: any, _fn: (any) -> ()) end,
			},
		},
	}
	local env: { [string]: any } = {
		game = {
			JobId = "job-1",
			GetService = function(_: any, name: string): any
				return assert(services[name], `stub: game:GetService("{name}") is not modelled`)
			end,
		},
		require = function(spec: string): any
			assert(spec == "@game/ReplicatedStorage/Arcade/Logic/Hiscores", `stub: no module for {spec}`)
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
			spawn = function(fn: () -> ())
				fn()
			end,
			wait = function(_seconds: number?): number
				return 0
			end,
		},
		os = {
			time = function(): number
				return FRI
			end,
		},
		warn = function() end,
	}
	return luau.load(fs.readFile(ADAPTER), { environment = env, debugName = "Boards" })()
end

type Remote = { handlers: { (any, any) -> () }, fired: number, stub: any }

local function remote(): Remote
	local r: Remote = { handlers = {}, fired = 0, stub = nil }
	r.stub = {
		OnServerEvent = {
			Connect = function(_: any, fn: (any, any) -> ())
				table.insert(r.handlers, fn)
			end,
		},
		FireClient = function(_: any, _player: any)
			r.fired += 1
		end,
	}
	return r
end

local function ask(r: Remote, id: string)
	local who = { UserId = 7, Parent = {} }
	for _, fn in r.handlers do
		fn(who, id)
	end
end

return t.spec("Boards serve", function(it)
	it("serving a title twice on the same remote answers each request once", function()
		local Boards = load()
		local snake = Boards.open("Snake")
		local r = remote()
		snake.serve(r.stub)
		snake.serve(r.stub)
		t.expect(#r.handlers).toBe(1)
		for _, id in { "all", "day", "week" } do
			local before = r.fired
			ask(r, id)
			t.expect(r.fired - before).toBe(1)
		end
	end)

	it("serving a title on a second remote is an error, and another title may use that remote", function()
		local Boards = load()
		local snake = Boards.open("Snake")
		local first, second = remote(), remote()
		snake.serve(first.stub)
		local ok, err = pcall(function()
			Boards.open("Snake").serve(second.stub)
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "SnakeHiscores is already served", 1, true) ~= nil).toBe(true)
		t.expect(#second.handlers).toBe(0)
		Boards.open("Invaders").serve(second.stub)
		t.expect(#second.handlers).toBe(1)
		ask(second, "all")
		t.expect(second.fired).toBe(1)
		ask(first, "all")
		t.expect(first.fired).toBe(1)
	end)
end)
