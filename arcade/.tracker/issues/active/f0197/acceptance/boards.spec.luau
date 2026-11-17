--!strict
-- f0197 AC4: one generic server adapter, `src/server/Boards.luau`, for every place. `Boards.open(prefix)` is one
-- title's boards: its handle writes finished runs (with their revives) to that title's stores only and answers board
-- requests on a remote the place made. The adapter's real source runs here on a stub `game` of this spec's own: a
-- DataStoreService whose UpdateAsync stores what the transform returns, a Players service, remotes that record what
-- they fire, an immediate (or held) task.spawn and a fixed os.time. The file is absent until the raft builds it, so
-- this fails on the missing file.
local Hiscores = require("@logic/Hiscores")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local ADAPTER = "src/server/Boards.luau"
local LOGIC_ROOT = "@game/ReplicatedStorage/Arcade/Logic/"
local FRI = 1792108800 -- 2026-10-16, a Friday: day "day:2026-10-16", week "week:2026-10-12"
local SCOPES = { "all", "day:2026-10-16", "week:2026-10-12" }

type Store = { kind: string, name: string, scope: string, data: { [string]: any }, reads: number }
type World = {
	Boards: any,
	stores: { [string]: Store },
	sortedFails: boolean,
	topFails: boolean,
	hold: boolean,
	spawned: { () -> () },
	warnings: number,
	removing: { (any) -> () },
}
type Remote = { handlers: { (any, any) -> () }, fired: { { any } }, stub: any }

local function world(): World
	local w: World = {
		Boards = nil,
		stores = {},
		sortedFails = false,
		topFails = false,
		hold = false,
		spawned = {},
		warnings = 0,
		removing = {},
	}
	local function open(kind: string, name: string, scope: string?): any
		local id = `{kind}|{name}|{scope or "global"}`
		local found = w.stores[id]
		if found == nil then
			found = { kind = kind, name = name, scope = scope or "global", data = {}, reads = 0 }
			w.stores[id] = found
		end
		local s = found :: Store
		return {
			GetAsync = function(_: any, key: string): any
				s.reads += 1
				if w.topFails and string.find(s.name, "HiscoreTop", 1, true) then
					error("stub: list read failed", 0)
				end
				return s.data[key]
			end,
			UpdateAsync = function(_: any, key: string, transform: (any) -> any): any
				local nextValue = transform(s.data[key])
				if nextValue ~= nil then
					s.data[key] = nextValue
				end
				return nextValue
			end,
			GetSortedAsync = function(_: any, ascending: boolean, size: number): any
				s.reads += 1
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
	local services: { [string]: any } = {
		DataStoreService = {
			GetDataStore = function(_: any, name: string, scope: string?): any
				return open("companion", name, scope)
			end,
			GetOrderedDataStore = function(_: any, name: string, scope: string?): any
				return open("ordered", name, scope)
			end,
			GetRequestBudgetForRequestType = function(_: any, _kind: any): number
				return 100
			end,
		},
		Players = {
			PlayerRemoving = {
				Connect = function(_: any, fn: (any) -> ())
					table.insert(w.removing, fn)
				end,
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
			if spec == LOGIC_ROOT .. "Hiscores" then
				return Hiscores
			end
			-- another library feature loads as itself, so a correct later require keeps this spec green
			local feature = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
			assert(feature ~= nil, `stub: no module for {spec}`)
			return (require :: any)(`@logic/{feature}`)
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
				if w.hold then
					table.insert(w.spawned, fn)
				else
					fn()
				end
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
		warn = function()
			w.warnings += 1
		end,
	}
	t.expect(fs.isFile(ADAPTER)).toBe(true)
	local chunk = luau.load(fs.readFile(ADAPTER), { environment = env, debugName = "Boards" })
	w.Boards = chunk()
	return w
end

local function remote(): Remote
	local r: Remote = { handlers = {}, fired = {}, stub = nil }
	r.stub = {
		OnServerEvent = {
			Connect = function(_: any, fn: (any, any) -> ())
				table.insert(r.handlers, fn)
			end,
		},
		FireClient = function(_: any, player: any, ...: any)
			table.insert(r.fired, table.pack(player, ...))
		end,
	}
	return r
end

local function player(userId: number): any
	return { UserId = userId, Parent = {} }
end

-- one fired answer's values, nils included: (player, id, rows, rank, failed, best)
local function values(fired: any): ...any
	return table.unpack(fired, 1, fired.n)
end

-- a player asks for a board on the remote; returns what the remote fired for it
local function ask(r: Remote, who: any, id: any): { any }
	local before = #r.fired
	for _, fn in r.handlers do
		fn(who, id)
	end
	local out: { any } = {}
	for i = before + 1, #r.fired do
		table.insert(out, r.fired[i])
	end
	return out
end

local function data(w: World, kind: string, name: string, scope: string): { [string]: any }
	local s = w.stores[`{kind}|{name}|{scope}`]
	return if s then s.data else {}
end

local function names(w: World): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, s in w.stores do
		if next(s.data) ~= nil and not seen[s.name] then
			seen[s.name] = true
			table.insert(out, s.name)
		end
	end
	table.sort(out)
	return out
end

return t.spec("f0197 Boards adapter", function(it)
	it(
		"AC4: open names a title's stores from its prefix, one handle per prefix, and a bad prefix errors",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			t.expect(w.Boards.open("Snake")).toBe(snake)
			local pickman = w.Boards.open("")
			t.expect(pickman == snake).toBe(false)
			t.expect(snake.names.top).toBe("SnakeHiscoreTop")
			t.expect(pickman.names.ordered).toBe("Hiscores")
			t.expect((pcall(w.Boards.open, "snake"))).toBe(false)
			t.expect((pcall(w.Boards.open, "Sn ake"))).toBe(false)
		end
	)

	it(
		"AC4: a title's run is written to its own stores only: every board, the list, and none of pickman's",
		function()
			local w = world()
			w.Boards.open("Snake").submit("7", "Ada", 120, 3, 2, 1)
			t.expect(names(w)).toEqual({ "SnakeHiscoreEntries", "SnakeHiscoreTop", "SnakeHiscores" })
			for _, scope in SCOPES do
				local key = if scope == "all" then "7" else `7:{string.match(scope, ":(.+)$")}`
				t.expect(data(w, "companion", "SnakeHiscoreEntries", scope)[key].score).toBe(120)
				t.expect(data(w, "ordered", "SnakeHiscores", scope)[key]).toBe(Hiscores.pack(120, 3))
			end
			w.Boards.open("").submit("8", "Bea", 50, 2, 0, 1)
			t.expect(names(w)).toEqual({
				"HiscoreEntries",
				"HiscoreTop",
				"Hiscores",
				"SnakeHiscoreEntries",
				"SnakeHiscoreTop",
				"SnakeHiscores",
			})
			t.expect(data(w, "companion", "HiscoreEntries", "all")["8"].score).toBe(50)
			t.expect(data(w, "companion", "HiscoreEntries", "all")["7"]).toBe(nil)
		end
	)

	it("AC4: every row and the run's list entry record the revives the run used", function()
		local w = world()
		w.Boards.open("Invaders").submit("7", "Ada", 300, 4, 2, 3)
		for _, scope in SCOPES do
			for _, row in data(w, "companion", "InvadersHiscoreEntries", scope) do
				t.expect(row.revives).toBe(2)
				t.expect(row.level).toBe(4)
			end
		end
		local list = data(w, "companion", "InvadersHiscoreTop", Hiscores.TOP_SCOPE)[Hiscores.TOP_KEY]
		t.expect(#list).toBe(1)
		t.expect(list[1].id).toBe(`7:{FRI}:3:job-1`)
		t.expect(list[1].revives).toBe(2)
		t.expect(data(w, "companion", "InvadersHiscoreEntries", "all")["7"].run).toBe(`7:{FRI}:3:job-1`)
	end)

	it(
		"AC4: a submit is pending until its write ends, per title, and the listener hears the run's place",
		function()
			local w = world()
			w.hold = true
			local snake, asteroids = w.Boards.open("Snake"), w.Boards.open("Asteroids")
			local heard: { { any } } = {}
			snake.listen(function(userId: string, run: number, rank: number?, missed: number?)
				table.insert(heard, { userId, run, rank or 0, missed or 0 } :: { any })
			end)
			snake.submit("7", "Ada", 120, 3, 0, 2)
			t.expect(snake.pending()).toBe(1)
			t.expect(asteroids.pending()).toBe(0)
			local fn = table.remove(w.spawned, 1) :: () -> ()
			fn()
			t.expect(snake.pending()).toBe(0)
			t.expect(heard).toEqual({ { "7", 2, 1, 0 } :: { any } })
		end
	)

	it(
		"AC4: serve answers all with the list's rows and revives, the rank, and the asker's best with revives",
		function()
			local w = world()
			local snake = w.Boards.open("Snake")
			snake.submit("7", "Ada", 120, 3, 2, 1)
			snake.submit("8", "Bea", 90, 2, 0, 1)
			local r = remote()
			snake.serve(r.stub)
			local ada = player(7)
			local got = ask(r, ada, "all")
			t.expect(#got).toBe(1)
			local who, id, rows, rank, failed, best = values(got[1])
			t.expect(who).toBe(ada)
			t.expect(id).toBe("all")
			t.expect(rows).toEqual({
				{ rank = 1, name = "Ada", score = 120, level = 3, revives = 2 },
				{ rank = 2, name = "Bea", score = 90, level = 2, revives = 0 },
			})
			t.expect(rank).toBe(1)
			t.expect(failed).toBe(false)
			t.expect(best).toEqual({ score = 120, level = 3, revives = 2 })
		end
	)

	it("AC4: serve answers day and week with the per-player rows and their revives, and no best", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		snake.submit("7", "Ada", 120, 3, 2, 1)
		local r = remote()
		snake.serve(r.stub)
		-- the asker's best is held from their all-time answer, and still never sent with day or week
		local ada = player(7)
		ask(r, ada, "all")
		for _, id in { "day", "week" } do
			local got = ask(r, ada, id)
			t.expect(#got).toBe(1)
			local _, said, rows, rank, failed, best = values(got[1])
			t.expect(said).toBe(id)
			t.expect(rows).toEqual({ { rank = 1, name = "Ada", score = 120, level = 3, revives = 2 } })
			t.expect(rank).toBe(1)
			t.expect(failed).toBe(false)
			t.expect(best).toBe(nil)
		end
	end)

	it(
		"AC4: rows and list entries stored before f0197 (pickman's, with no revives) answer revives 0",
		function()
			local w = world()
			local pickman = w.Boards.open("")
			-- seed what today's pickman build stores: rows and a list without revives
			local companion = w.stores
			local function seed(kind: string, name: string, scope: string, key: string, value: any)
				local id = `{kind}|{name}|{scope}`
				companion[id] = companion[id]
					or { kind = kind, name = name, scope = scope, data = {}, reads = 0 }
				companion[id].data[key] = value
			end
			local old = { name = "Old", userId = "5", score = 70, level = 2 }
			seed("companion", "HiscoreEntries", "day:2026-10-16", "5:2026-10-16", old)
			seed("ordered", "Hiscores", "day:2026-10-16", "5:2026-10-16", Hiscores.pack(70, 2))
			seed("companion", "HiscoreEntries", "all", "5", old)
			seed("companion", "HiscoreTop", "all", "runs", {
				{ id = "5:1:1:j", name = "Old", userId = "5", score = 70, level = 2, at = 1 },
			})
			local r = remote()
			pickman.serve(r.stub)
			local _, _, allRows, _, _, best = values(ask(r, player(5), "all")[1])
			t.expect(allRows).toEqual({ { rank = 1, name = "Old", score = 70, level = 2, revives = 0 } })
			t.expect(best).toEqual({ score = 70, level = 2, revives = 0 })
			local _, _, dayRows = values(ask(r, player(5), "day")[1])
			t.expect(dayRows).toEqual({ { rank = 1, name = "Old", score = 70, level = 2, revives = 0 } })
		end
	)

	it("AC4: serve ignores any id but all, day or week, and a failed read answers once, failed", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		local r = remote()
		snake.serve(r.stub)
		for _, bad in { "month", 1, {}, nil } :: { any } do
			t.expect(#ask(r, player(7), bad)).toBe(0)
		end
		w.sortedFails = true
		local got = ask(r, player(7), "day")
		t.expect(#got).toBe(1)
		local _, id, rows, _, failed = values(got[1])
		t.expect(id).toBe("day")
		t.expect(rows).toEqual({})
		t.expect(failed).toBe(true)
	end)

	it("AC4: a list that cannot be read is a failed all-time answer", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		snake.submit("7", "Ada", 120, 3, 0, 1)
		w.topFails = true
		local r = remote()
		snake.serve(r.stub)
		local _, _, rows, _, failed = values(ask(r, player(9), "all")[1])
		t.expect(rows).toEqual({})
		t.expect(failed).toBe(true)
	end)

	it("AC4: a board read is shared for CACHE_TTL, and two titles never share a read or a row", function()
		local w = world()
		local snake, invaders = w.Boards.open("Snake"), w.Boards.open("Invaders")
		snake.submit("7", "Ada", 120, 3, 1, 1)
		invaders.submit("8", "Bea", 40, 2, 0, 1)
		local rs, ri = remote(), remote()
		snake.serve(rs.stub)
		invaders.serve(ri.stub)
		local day = w.stores["ordered|SnakeHiscores|day:2026-10-16"]
		local before = day.reads
		ask(rs, player(1), "day")
		ask(rs, player(2), "day")
		t.expect(day.reads - before).toBe(1)
		local _, _, snakeRows = values(ask(rs, player(3), "day")[1])
		local _, _, invadersRows = values(ask(ri, player(3), "day")[1])
		t.expect(#snakeRows).toBe(1)
		t.expect(snakeRows[1].name).toBe("Ada")
		t.expect(#invadersRows).toBe(1)
		t.expect(invadersRows[1].name).toBe("Bea")
	end)

	it("AC4: a player's best is forgotten when they leave, and read again when they ask", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		snake.submit("7", "Ada", 120, 3, 1, 1)
		local r = remote()
		snake.serve(r.stub)
		local entries = w.stores["companion|SnakeHiscoreEntries|all"]
		local ada = player(7)
		ask(r, ada, "all")
		local reads = entries.reads
		ask(r, ada, "all")
		t.expect(entries.reads).toBe(reads)
		t.expect(#w.removing >= 1).toBe(true)
		for _, fn in w.removing do
			fn(ada)
		end
		ask(r, ada, "all")
		t.expect(entries.reads).toBe(reads + 1)
	end)

	it("AC4: each title's listener hears only its own runs", function()
		local w = world()
		local snake, asteroids = w.Boards.open("Snake"), w.Boards.open("Asteroids")
		local heard: { string } = {}
		snake.listen(function(userId: string)
			table.insert(heard, `snake:{userId}`)
		end)
		asteroids.listen(function(userId: string)
			table.insert(heard, `asteroids:{userId}`)
		end)
		asteroids.submit("7", "Ada", 120, 3, 0, 1)
		t.expect(heard).toEqual({ "asteroids:7" })
		snake.submit("8", "Bea", 90, 2, 0, 1)
		t.expect(heard).toEqual({ "asteroids:7", "snake:8" })
	end)

	it("AC4: a run outside the figures' ranges is refused with a warning and writes nothing", function()
		local w = world()
		local snake = w.Boards.open("Snake")
		snake.submit("7", "Ada", 120, 3, 1, 1)
		t.expect(w.warnings).toBe(0)
		local written = names(w)
		local w2 = world()
		local again = w2.Boards.open("Snake")
		again.submit("7", "Ada", 120, 0, 0, 1) -- a progress figure below 1
		t.expect(w2.warnings).toBe(1)
		again.submit("8", "Bea", 90, 2, -1, 1) -- a bad revives count
		t.expect(w2.warnings).toBe(2)
		t.expect(names(w2)).toEqual({})
		t.expect(again.pending()).toBe(0)
		t.expect(#written).toBe(3)
	end)
end)
