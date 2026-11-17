--!strict
-- f0208 AC4: an invited friend reaches the inviter's portal server (ServerScriptService.Server.Invites), run from its
-- real source on a stub server. The inviter's server records the invite in the PortalInvites map (this server's job
-- and the title, for 600 s); a failing map throws nothing. A player who joins with an inviter's id as launch data, in
-- a server the inviter is not in, is sent to the inviter's server (the portal place, that job) when the invite is on
-- record for another server and they are friends; anything less sends nothing.
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any)
	:GetService("ServerScriptService")
	:FindFirstChild("Server")
	:FindFirstChild("Invites").Source

local function standin(): any
	local s: any
	s = setmetatable({}, {
		__index = function(): any
			return s
		end,
		__call = function(): any
			return nil
		end,
	})
	return s
end

local function world(): any
	local w: any = {
		errors = {},
		teleports = {},
		sets = {},
		removes = {},
		gets = {},
		data = {},
		players = {},
		friends = {},
		down = false,
		friendsFail = false,
	}
	local function spawn(fn: (...any) -> (), ...: any)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(w.errors, tostring(err))
		end
	end
	local added: { (any) -> () } = {}
	local playersService: any = {
		PlayerAdded = {
			Connect = function(_: any, fn: (any) -> ())
				table.insert(added, fn)
			end,
		},
		PlayerRemoving = { Connect = function() end },
	}
	playersService.GetPlayerByUserId = function(_: any, id: any): any
		for _, p in w.players do
			if p.Parent ~= nil and p.UserId == id then
				return p
			end
		end
		return nil
	end
	local map: any = {}
	map.SetAsync = function(_: any, key: string, value: any, expiration: number): boolean
		if w.down then
			error("memory store down")
		end
		table.insert(w.sets, { key = key, value = value, expiration = expiration })
		w.data[key] = value
		return true
	end
	map.RemoveAsync = function(_: any, key: string)
		if w.down then
			error("memory store down")
		end
		table.insert(w.removes, key)
		w.data[key] = nil
	end
	map.GetAsync = function(_: any, key: string): any
		table.insert(w.gets, key)
		if w.down then
			error("memory store down")
		end
		return w.data[key]
	end
	local services: { [string]: any } = {
		Players = playersService,
		MemoryStoreService = {
			GetHashMap = function(_: any, name: string): any
				w.mapName = name
				return map
			end,
		},
		TeleportService = {
			TeleportAsync = function(_: any, placeId: any, players: any, options: any)
				table.insert(
					w.teleports,
					{ place = placeId, players = table.clone(players), options = options }
				)
			end,
		},
	}
	local env: { [string]: any } = {}
	env.game = {
		GetService = function(_: any, name: string): any
			return services[name] or standin()
		end,
		JobId = "job-here",
		PlaceId = 100,
	}
	env.Instance = {
		new = function(class: string): any
			return { ClassName = class }
		end,
	}
	env.task = { spawn = spawn, defer = spawn, delay = function() end }
	env.require = function(spec: string): any
		local logic = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
		if logic then
			return (require :: any)("@logic/" .. logic)
		end
		local shared = string.match(spec, "^@game/ReplicatedStorage/Shared/(%w+)$")
		if shared then
			return (require :: any)("@shared/" .. shared)
		end
		return standin()
	end
	local Invites = luau.load(SOURCE, { debugName = "Invites", environment = env })()
	w.Invites = Invites
	Invites.start()
	w.added = added
	-- an offer runs in a thread of its own, as Plays spawns it: what it raises is caught as an error
	function w.offer(player: any, name: string)
		spawn(w.Invites.offer, player, name)
	end
	function w.withdraw(player: any)
		spawn(w.Invites.withdraw, player)
	end

	function w.player(id: number, launch: any): any
		local p: any = { Name = `p{id}`, UserId = id, Parent = playersService }
		p.GetJoinData = function(): any
			if launch == "throw" then
				error("no join data")
			end
			return { LaunchData = launch }
		end
		p.IsFriendsWith = function(_: any, other: number): boolean
			if w.friendsFail then
				error("web call failed")
			end
			return w.friends[`{id}-{other}`] == true or w.friends[`{other}-{id}`] == true
		end
		return p
	end
	function w.join(p: any)
		table.insert(w.players, p)
		for _, fn in added do
			spawn(fn, p)
		end
	end
	return w
end

local function clean(w: any)
	t.expect(table.concat(w.errors, "\n")).toBe("")
end

return t.spec("f0208 invites", function(it)
	it("an invite is recorded by the inviter's id: this server's job and the title, for 600 s", function()
		local w = world()
		w.offer({ UserId = 7 }, "invaders")
		t.expect(w.mapName).toBe("PortalInvites")
		t.expect(w.sets)
			.toEqual({ { key = "7", value = { job = "job-here", name = "invaders" }, expiration = 600 } })
		t.expect(w.Invites.SECONDS).toBe(600)
		clean(w)
	end)

	it("a withdrawn invite is removed from the map; a map that fails throws nothing", function()
		local w = world()
		w.offer({ UserId = 7 }, "invaders")
		w.withdraw({ UserId = 7 })
		t.expect(w.data["7"]).toBe(nil)
		t.expect(w.removes).toEqual({ "7" })
		w.down = true
		w.withdraw({ UserId = 8 })
		clean(w)
	end)

	it("an invite the map cannot take throws nothing", function()
		local w = world()
		w.down = true
		w.offer({ UserId = 7 }, "invaders")
		clean(w)
	end)

	it("an invited friend who lands elsewhere is sent to the inviter's server", function()
		local w = world()
		w.data["7"] = { job = "job-there", name = "invaders" }
		w.friends["7-8"] = true
		local friend = w.player(8, "7")
		w.join(friend)
		t.expect(#w.teleports).toBe(1)
		t.expect(w.teleports[1].place).toBe(100)
		t.expect(w.teleports[1].players).toEqual({ friend })
		t.expect(w.teleports[1].options.ClassName).toBe("TeleportOptions")
		t.expect(w.teleports[1].options.ServerInstanceId).toBe("job-there")
		clean(w)
	end)

	it("a joiner who is not the inviter's friend is sent nowhere", function()
		local w = world()
		w.data["7"] = { job = "job-there", name = "invaders" }
		w.join(w.player(8, "7"))
		t.expect(#w.teleports).toBe(0)
		w.friends["7-9"] = true
		w.friendsFail = true
		w.join(w.player(9, "7"))
		t.expect(#w.teleports).toBe(0)
		clean(w)
	end)

	it("no invite on record, one for this server, or a map that fails sends nowhere", function()
		local w = world()
		w.friends["7-8"] = true
		w.join(w.player(8, "7"))
		w.data["7"] = { job = "job-here", name = "invaders" }
		w.join(w.player(8, "7"))
		w.data["7"] = { job = "job-there", name = "tetris" }
		w.join(w.player(8, "7"))
		w.data["7"] = { job = "job-there", name = "invaders" }
		w.down = true
		w.join(w.player(8, "7"))
		t.expect(#w.teleports).toBe(0)
		clean(w)
	end)

	it("an inviter already in this server, or launch data naming no one, reads nothing", function()
		local w = world()
		w.data["7"] = { job = "job-there", name = "invaders" }
		w.friends["7-8"] = true
		local inviter = w.player(7, nil)
		w.join(inviter)
		w.join(w.player(8, "7"))
		for _, launch in { "abc", "", "0", 7, "throw", "8" } :: { any } do
			w.join(w.player(8, launch))
		end
		t.expect(#w.gets).toBe(0)
		t.expect(#w.teleports).toBe(0)
		clean(w)
	end)

	it("a friend who left before the answer is sent nowhere", function()
		local w = world()
		w.data["7"] = { job = "job-there", name = "invaders" }
		w.friends["7-8"] = true
		local friend = w.player(8, "7")
		friend.IsFriendsWith = function(): boolean
			friend.Parent = nil
			return true
		end
		w.join(friend)
		t.expect(#w.teleports).toBe(0)
		clean(w)
	end)

	it("starts once", function()
		local w = world()
		w.Invites.start()
		t.expect(#w.added).toBe(1)
		clean(w)
	end)
end)
