--!strict
-- The lobby screen's layout with a Board remote: the board buttons never cover START GAME, the title or the
-- list, and everything stays on screen, from a phone held sideways to a desktop window.
local Lobby = require("@logic/Lobby")
local Travel = require("@logic/Travel")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

type Node = { [string]: any }

local function node(className: string): Node
	local n: Node = { ClassName = className, Name = className, kids = {} }
	n.Activated = { Connect = function() end }
	n.OnClientEvent = { Connect = function() end }
	n.FireServer = function() end
	n.WaitForChild = function(self: Node, name: string): any
		return self[name]
	end
	n.FindFirstChild = function(self: Node, name: string): any
		return self[name]
	end
	return setmetatable(n, {
		__newindex = function(self: Node, key: string, value: any)
			rawset(self, key, value)
			if key == "Parent" and value ~= nil then
				table.insert(value.kids, self)
			end
		end,
	}) :: any
end

local function boot(): Node
	local remotes = node("Folder")
	remotes.StartGame, remotes.Status, remotes.Board =
		node("RemoteEvent"), node("RemoteEvent"), node("RemoteEvent")
	local storage = node("Folder")
	storage.Remotes = remotes
	local gui = node("Folder")
	local player = node("Player")
	player.PlayerGui = gui
	local env: { [string]: any } = {
		game = {
			GetService = function(_: any, name: string): any
				return if name == "Players" then { LocalPlayer = player } else storage
			end,
		},
		require = function(spec: string): any
			return if string.find(spec, "Travel", 1, true) then Travel else Lobby
		end,
		Instance = { new = node },
		Enum = setmetatable({}, {
			__index = function(): any
				return setmetatable({}, {
					__index = function(_: any, item: string): string
						return item
					end,
				})
			end,
		}),
		UDim2 = {
			new = function(xs: number, xo: number, ys: number, yo: number): any
				return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
			end,
			fromScale = function(x: number, y: number): any
				return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }
			end,
		},
		Vector2 = {
			new = function(x: number, y: number): any
				return { X = x, Y = y }
			end,
		},
		Color3 = {
			new = function(): any
				return {}
			end,
			fromRGB = function(): any
				return {}
			end,
		},
		task = { delay = function() end },
	}
	luau.load(fs.readFile("src/lobby/client/LobbyView.luau"), { environment = env, debugName = "LobbyView" })()
		.start()
	return gui.kids[1].kids[1] -- the backdrop
end

type Rect = { x0: number, y0: number, x1: number, y1: number }

local function rect(n: Node, w: number, h: number): Rect
	local size, pos, anchor = n.Size, n.Position, n.AnchorPoint
	local sx, sy = size.X.Scale * w + size.X.Offset, size.Y.Scale * h + size.Y.Offset
	local x = pos.X.Scale * w + pos.X.Offset - (if anchor then anchor.X else 0) * sx
	local y = pos.Y.Scale * h + pos.Y.Offset - (if anchor then anchor.Y else 0) * sy
	return { x0 = x, y0 = y, x1 = x + sx, y1 = y + sy }
end

local function apart(a: Rect, b: Rect): boolean
	return a.x1 <= b.x0 or b.x1 <= a.x0 or a.y1 <= b.y0 or b.y1 <= a.y0
end

return t.spec("Lobby screen layout", function(it)
	for _, screen in { { 844, 390 }, { 1920, 1080 } } do
		local w, h = screen[1], screen[2]
		it(`the board buttons clear START GAME, the title and the list on {w}x{h}, all on screen`, function()
			local backdrop = boot()
			local byName: { [string]: Node } = {}
			for _, kid in backdrop.kids do
				byName[kid.Name] = kid
			end
			local start = rect(byName.Start, w, h)
			local others = { start, rect(byName.Title, w, h), rect(byName.Rows, w, h) }
			local buttons = 0
			for name, kid in byName do
				if string.sub(name, 1, 5) == "Board" then
					buttons += 1
					local r = rect(kid, w, h)
					for _, other in others do
						t.expect(apart(r, other)).toBe(true)
					end
					t.expect(r.x0 >= 0 and r.x1 <= w and r.y0 >= 0 and r.y1 <= h).toBe(true)
					t.expect(r.y1 - r.y0 >= Lobby.BUTTON_MIN_PX).toBe(true)
				end
			end
			t.expect(buttons).toBe(3)
			t.expect(start.y1 <= h).toBe(true)
		end)
	end
end)
