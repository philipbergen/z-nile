--!strict
-- f0206 AC6: the portal's boards screen (StarterPlayerScripts.Client.BoardsView), run from its real source on a stub
-- client, with a stand-in for the carousel (f0205's CarouselView: start, card(name) with its Boards slot, focused()).
-- It starts the carousel, then fills every card's Boards slot: three tabs, a header naming the title's progress
-- figure (HiscoreGames), ten row lines, a note and the "your best" line, laid out by Board.layout for the slot's size
-- with Card's glyph width, every text at the layout's one size, each column aligned and inset by its gutter, nothing
-- gamepad-selectable. One tab is chosen for every card, by a tap or by W/S, Up/Down and the triggers through one
-- ContextActionService binding between the default controls and the test purchase screen, passed on while the player
-- types. Each frame it asks the server for every card's board on the chosen tab (and a card's all-time board while its
-- best is not known), each again after REASK, or WAIT_RETRY after a wait or a pending best; every answer is read
-- through Board.parse and drawn on its own card, the player's best under every tab.
local Board = require("@logic/Board")
local Card = require("@logic/Card")
local Games = require("@shared/Games")
local HiscoreGames = require("@arcade/HiscoreGames")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local built = place.load()
local SOURCE = (built :: any)
	:GetService("StarterPlayer")
	:FindFirstChild("StarterPlayerScripts")
	:FindFirstChild("Client")
	:FindFirstChild("BoardsView").Source

local SLOT_Y = 207 -- a 1280 x 720 screen's front card: 0.9 x 720 x 0.32

type Signal = { Connect: (any, (...any) -> ()) -> any, fire: (...any) -> (), count: () -> number }

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

local function value(kind: string, ...: any): any
	return table.freeze({ kind = kind, args = table.freeze(table.pack(...)) })
end

local function enumProxy(): any
	return setmetatable({}, {
		__index = function(self: any, group: string): any
			local g = setmetatable({}, {
				__index = function(gs: any, item: string): any
					local v = table.freeze({ Name = item, EnumType = group })
					rawset(gs, item, v)
					return v
				end,
			})
			rawset(self, group, g)
			return g
		end,
	})
end

local function row(rank: number, name: string, score: number, level: number, revives: number): any
	return { rank = rank, name = name, score = score, level = level, revives = revives }
end

local function world(options: { slow: boolean?, missing: string? }?): any
	local opts: any = options or {}
	local w: any = { errors = {}, sent = {}, binds = {}, clock = 0, waiting = {}, front = "pickman" }

	local function spawn(fn: (...any) -> (), ...: any)
		local ok, err = coroutine.resume(coroutine.create(fn), ...)
		if not ok then
			table.insert(w.errors, tostring(err))
		end
	end

	local function signal(): Signal
		local fns: { (...any) -> () } = {}
		return {
			Connect = function(_: any, fn: (...any) -> ()): any
				table.insert(fns, fn)
				return { Disconnect = function() end }
			end,
			fire = function(...: any)
				for _, fn in table.clone(fns) do
					spawn(fn, ...)
				end
			end,
			count = function(): number
				return #fns
			end,
		}
	end

	local function node(className: string): any
		local props: any = { ClassName = className, Name = className }
		local children: { any } = {}
		local changed: { [string]: Signal } = {}
		local n: any
		local methods: { [string]: any } = {
			FindFirstChild = function(_: any, name: string): any
				for _, c in children do
					if c.Name == name then
						return c
					end
				end
				return nil
			end,
			GetChildren = function(): { any }
				return table.clone(children)
			end,
			IsA = function(_: any, class: string): boolean
				return className == class
			end,
			GetPropertyChangedSignal = function(_: any, prop: string): Signal
				changed[prop] = changed[prop] or signal()
				return changed[prop]
			end,
			Destroy = function(me: any)
				me.Parent = nil
			end,
			ClearAllChildren = function()
				for _, c in table.clone(children) do
					c.Parent = nil
				end
			end,
			SetAttribute = function(_: any, k: string, v: any)
				props["@" .. k] = v
			end,
			GetAttribute = function(_: any, k: string): any
				return props["@" .. k]
			end,
		}
		methods.WaitForChild = methods.FindFirstChild
		methods.FindFirstChildOfClass = function(_: any, class: string): any
			for _, c in children do
				if c.ClassName == class then
					return c
				end
			end
			return nil
		end
		methods.FindFirstChildWhichIsA = methods.FindFirstChildOfClass
		if className == "TextButton" then
			props.Activated = signal()
			props.MouseButton1Click = signal()
		end
		n = setmetatable({ children = children, changed = changed }, {
			__index = function(_: any, key: string): any
				if methods[key] then
					return methods[key]
				end
				return props[key]
			end,
			__newindex = function(_: any, key: string, v: any)
				if key == "Parent" then
					local old = props.Parent
					if old == v then
						return
					end
					if old then
						local i = table.find(old.children, n)
						if i then
							table.remove(old.children, i)
						end
					end
					props.Parent = v
					if v then
						table.insert(v.children, n)
					end
				else
					props[key] = v
				end
			end,
		})
		return n
	end
	w.node = node

	-- the carousel as f0205 gives it: a card frame per title, each with an empty Boards slot, once started
	local cards: { [string]: any } = {}
	for _, e in Games.LIST do
		if e.name ~= opts.missing then
			local card = node("Frame")
			card.Name = e.name
			local slot = node("Frame")
			slot.Name = "Boards"
			slot.AbsoluteSize = { X = 300, Y = SLOT_Y }
			slot.Parent = card
			cards[e.name] = card
		end
	end
	w.cards = cards
	w.carouselStarts = 0
	local Carousel = {
		start = function()
			w.carouselStarts += 1
		end,
		card = function(name: string): any
			if w.carouselStarts == 0 then
				return nil -- f0205: nil before start
			end
			return cards[name]
		end,
		focused = function(): string
			return w.front
		end,
		onPlay = function() end,
	}

	local remote: any = node("RemoteEvent")
	remote.Name = "Boards"
	remote.OnClientEvent = signal()
	remote.FireServer = function(_: any, ...: any)
		table.insert(w.sent, table.pack(...))
	end
	w.remote = remote
	local remotes = node("Folder")
	remotes.Name = "Remotes"
	remote.Parent = remotes
	local replicated: any = {
		WaitForChild = function(_: any, name: string): any
			assert(name == "Remotes", name)
			if opts.slow and not w.released then
				table.insert(w.waiting, coroutine.running())
				coroutine.yield()
			end
			return remotes
		end,
	}
	replicated.FindFirstChild = replicated.WaitForChild
	local heartbeat, rendered = signal(), signal()
	w.heartbeat = heartbeat
	local services: { [string]: any } = {
		ContextActionService = {
			BindActionAtPriority = function(
				_: any,
				name: string,
				fn: (...any) -> any,
				touch: boolean,
				priority: number,
				...: any
			)
				table.insert(
					w.binds,
					{ name = name, fn = fn, touch = touch, priority = priority, inputs = { ... } }
				)
			end,
			BindAction = function(_: any, name: string, fn: (...any) -> any, touch: boolean, ...: any)
				table.insert(
					w.binds,
					{ name = name, fn = fn, touch = touch, priority = nil, inputs = { ... } }
				)
			end,
			UnbindAction = function() end,
		},
		ReplicatedStorage = replicated,
		RunService = { Heartbeat = heartbeat, RenderStepped = rendered },
		UserInputService = {
			TouchSwipe = signal(),
			InputBegan = signal(),
			InputEnded = signal(),
			GetFocusedTextBox = function(): any
				return w.focused -- a TextBox the player is typing in (the chat box), nil when none
			end,
		},
		Players = { LocalPlayer = { Name = "me", UserId = 1 } },
	}
	local enum = enumProxy()
	w.Enum = enum
	local env: { [string]: any } = {}
	env.game = {
		GetService = function(_: any, name: string): any
			return services[name] or standin()
		end,
	}
	env.Enum = enum
	env.Instance = {
		new = function(class: string): any
			return node(class)
		end,
	}
	-- every UDim2 is one normalised value whatever builds it: X and Y, each a Scale and an Offset
	local function udim2(xs: number?, xo: number?, ys: number?, yo: number?): any
		return table.freeze({
			X = table.freeze({ Scale = xs or 0, Offset = xo or 0 }),
			Y = table.freeze({ Scale = ys or 0, Offset = yo or 0 }),
		})
	end
	env.UDim2 = {
		new = function(xs: number?, xo: number?, ys: number?, yo: number?): any
			return udim2(xs, xo, ys, yo)
		end,
		fromScale = function(xs: number?, ys: number?): any
			return udim2(xs, 0, ys, 0)
		end,
		fromOffset = function(xo: number?, yo: number?): any
			return udim2(0, xo, 0, yo)
		end,
	}
	env.UDim = {
		new = function(...: any): any
			return value("udim", ...)
		end,
	}
	env.Vector2 = {
		new = function(...: any): any
			return value("v2", ...)
		end,
	}
	env.Color3 = {
		new = function(...: any): any
			return value("rgb01", ...)
		end,
		fromRGB = function(...: any): any
			return value("rgb", ...)
		end,
	}
	env.task = {
		spawn = spawn,
		defer = spawn,
		delay = function() end,
		wait = function()
			return 0
		end,
	}
	env.os = {
		clock = function(): number
			return w.clock
		end,
		time = function(): number
			return 1000000
		end,
	}
	env.require = function(spec: string): any
		if spec == "./CarouselView" then
			return Carousel
		end
		local logic = string.match(spec, "^@game/ReplicatedStorage/Shared/Logic/(%w+)$")
		if logic then
			return (require :: any)("@logic/" .. logic)
		end
		local shared = string.match(spec, "^@game/ReplicatedStorage/Shared/(%w+)$")
		if shared then
			return (require :: any)("@shared/" .. shared)
		end
		local arcadeLogic = string.match(spec, "^@game/ReplicatedStorage/Arcade/Logic/(%w+)$")
		if arcadeLogic then
			return (require :: any)("@arcade/Logic/" .. arcadeLogic)
		end
		local arcade = string.match(spec, "^@game/ReplicatedStorage/Arcade/(%w+)$")
		if arcade then
			return (require :: any)("@arcade/" .. arcade)
		end
		return standin() -- a sibling adapter a later issue adds
	end
	w.View = luau.load(SOURCE, { debugName = "BoardsView", environment = env })()

	function w.release()
		w.released = true
		for _, co in w.waiting do
			local ok, err = coroutine.resume(co)
			if not ok then
				table.insert(w.errors, tostring(err))
			end
		end
		w.waiting = {}
	end
	function w.slot(name: string): any
		local s = cards[name]:FindFirstChild("Boards")
		t.expect(s ~= nil).toBe(true)
		return s
	end
	function w.part(name: string, child: string): any
		local p = w.slot(name):FindFirstChild(child)
		t.expect(p ~= nil).toBe(true) -- the slot holds it
		return p
	end
	function w.tab(name: string, id: string): any
		local b = w.part(name, "Tabs"):FindFirstChild(id)
		t.expect(b ~= nil and b.ClassName).toBe("TextButton")
		return b
	end
	function w.line(name: string, i: number): any
		local l = w.part(name, "Rows"):FindFirstChild(`Row{i}`)
		t.expect(l ~= nil and l.ClassName).toBe("Frame")
		return l
	end
	-- a line's texts in the columns' order
	function w.texts(frame: any): string
		local out = {}
		for _, c in Board.COLUMNS do
			local l = frame:FindFirstChild(c.name)
			t.expect(l ~= nil and l.ClassName).toBe("TextLabel")
			table.insert(out, l.Text)
		end
		return table.concat(out, "|")
	end
	function w.note(name: string): string
		return w.part(name, "Note").Text
	end
	-- the your-best line's texts in the columns' order, or nil while it is hidden
	function w.best(name: string): string?
		local b = w.part(name, "Best")
		t.expect(b.ClassName).toBe("Frame")
		if b.Visible == false then
			return nil
		end
		return w.texts(b)
	end
	function w.answer(...: any)
		remote.OnClientEvent.fire(...)
	end
	function w.frame(at: number?)
		if at ~= nil then
			w.clock = at
		end
		heartbeat.fire(1 / 60)
	end
	function w.press(keyName: string, state: string?): any
		local b = w.binds[1]
		local input = {
			UserInputType = enum.UserInputType[if string.sub(keyName, 1, 6) == "Button"
				then "Gamepad1"
				else "Keyboard"],
			KeyCode = enum.KeyCode[keyName],
		}
		return b.fn(Board.ACTION, enum.UserInputState[state or "Begin"], input)
	end
	function w.asks(): string
		local out = {}
		for _, s in w.sent do
			table.insert(out, `{s[1]}:{s[2]}`)
		end
		return table.concat(out, " ")
	end
	return w
end

local function started(options: { slow: boolean?, missing: string? }?): any
	local w = world(options)
	local boot = coroutine.create(function()
		w.View.start()
	end)
	local ok, err = coroutine.resume(boot)
	if not ok then
		table.insert(w.errors, tostring(err))
	end
	w.booted = coroutine.status(boot) == "dead"
	return w
end

local FOUR = { row(1, "Ada", 900, 4, 1), row(2, "me", 600, 2, 0), row(3, "Cy", 300, 1, 12) }

return t.spec("f0206 client", function(it)
	it("starts the carousel first, then fills the Boards slot it gives for each card", function()
		local w = started()
		t.expect(w.carouselStarts).toBe(1)
		for _, e in Games.LIST do
			t.expect(#w.slot(e.name).children > 0).toBe(true)
		end
		t.expect(#w.errors).toBe(0)
	end)

	it("each slot holds three tabs, a header, ten row lines, a note and a best line", function()
		local w = started()
		for _, e in Games.LIST do
			for _, id in Board.TABS do
				t.expect(w.tab(e.name, id).Text).toBe(Board.TAB_TEXT[id])
				-- never gamepad-selected, so ButtonA stays the carousel's PLAY (f0208)
				t.expect(w.tab(e.name, id).Selectable).toBe(false)
			end
			local rows = w.part(e.name, "Rows")
			t.expect(rows.ClassName).toBe("ScrollingFrame")
			t.expect(rows.Selectable).toBe(false)
			local lines = 0
			for _, c in rows.children do
				if c.ClassName == "Frame" then
					lines += 1
				end
			end
			t.expect(lines).toBe(Board.N)
			-- a long name is cut at its cell's end, never wrapped over the next line
			local name = w.line(e.name, 1):FindFirstChild("Name")
			t.expect(name ~= nil and name.TextTruncate).toBe(w.Enum.TextTruncate.AtEnd)
			t.expect(name.TextWrapped == true).toBe(false)
			t.expect(w.part(e.name, "Note").ClassName).toBe("TextLabel")
			t.expect(w.part(e.name, "Best").ClassName).toBe("Frame")
			-- each column's label at its inset place, aligned as Board says
			for _, frame in { w.part(e.name, "Header"), w.line(e.name, 1), w.line(e.name, 10) } do
				for _, c in Board.COLUMNS do
					local l = frame:FindFirstChild(c.name)
					t.expect(l.Position.X.Scale).toBeNear(c.x, 1e-9)
					t.expect(l.Size.X.Scale).toBeNear(c.width, 1e-9)
					t.expect(l.TextXAlignment).toBe(w.Enum.TextXAlignment[c.align])
				end
			end
		end
	end)

	it("the header names each title's progress figure", function()
		local w = started()
		for _, e in Games.LIST do
			local want = table.concat(Board.header(HiscoreGames[e.name].progress), "|")
			t.expect(w.texts(w.part(e.name, "Header"))).toBe(want)
		end
		t.expect(w.texts(w.part("snake", "Header"))).toBe("#|NAME|SCORE|MAP|REVIVES")
	end)

	it("before an answer every card says LOADING, shows no rows and no best, with ALL-TIME chosen", function()
		local w = started()
		for _, e in Games.LIST do
			t.expect(w.note(e.name)).toBe("LOADING")
			t.expect(w.best(e.name)).toBe(nil)
			for i = 1, Board.N do
				t.expect(w.line(e.name, i).Visible).toBe(false)
			end
			t.expect(w.tab(e.name, "all").BackgroundTransparency).toBe(0)
			t.expect(w.tab(e.name, "day").BackgroundTransparency > 0).toBe(true)
		end
	end)

	it("start returns at once while the server's remote is not there, and asks only once it is", function()
		local w = started({ slow = true })
		t.expect(w.booted).toBe(true)
		w.frame(1)
		t.expect(#w.sent).toBe(0)
		w.release()
		w.frame(2)
		t.expect(w.asks()).toBe("pickman:all snake:all invaders:all asteroids:all")
		t.expect(#w.errors).toBe(0)
	end)

	it("asks for every card's board on the chosen tab once, and not again on the next frames", function()
		local w = started()
		w.frame(1)
		w.frame(1.5)
		w.frame(10)
		t.expect(w.asks()).toBe("pickman:all snake:all invaders:all asteroids:all")
	end)

	it(
		"an answer draws its rows: the columns, a dash for no revives, the player's row marked, the best",
		function()
			local w = started()
			w.answer("pickman", "all", FOUR, 2, "ok", { score = 600, level = 2, revives = 0 })
			t.expect(w.note("pickman")).toBe("")
			t.expect(w.texts(w.line("pickman", 1))).toBe("1|Ada|900|4|1")
			t.expect(w.texts(w.line("pickman", 2))).toBe("2|me|600|2|—")
			t.expect(w.texts(w.line("pickman", 3))).toBe("3|Cy|300|1|12")
			for i = 1, 3 do
				t.expect(w.line("pickman", i).Visible).toBe(true)
			end
			t.expect(w.line("pickman", 4).Visible).toBe(false)
			t.expect(w.line("pickman", 2).BackgroundTransparency < 1).toBe(true)
			t.expect(w.line("pickman", 1).BackgroundTransparency).toBe(1)
			t.expect(w.best("pickman")).toBe("|YOUR BEST|600|2|—")
			t.expect(w.note("snake")).toBe("LOADING")
			t.expect(w.best("snake")).toBe(nil)
		end
	)

	it("an empty board says NO SCORES YET; a failed read with no rows says SCORES UNAVAILABLE", function()
		local w = started()
		w.answer("snake", "all", {}, nil, "ok", nil)
		t.expect(w.note("snake")).toBe("NO SCORES YET")
		t.expect(w.best("snake")).toBe("|YOUR BEST|—|—|—")
		w.answer("invaders", "all", {}, nil, "failed", nil)
		t.expect(w.note("invaders")).toBe("SCORES UNAVAILABLE")
		w.answer("asteroids", "all", { row(1, "Ada", 5, 1, 0) }, nil, "wait", nil)
		t.expect(w.note("asteroids")).toBe("LOADING")
	end)

	it("an answer that makes no sense changes nothing", function()
		local w = started()
		w.answer("pickman", "all", FOUR, nil, "ok", nil)
		w.answer("pickman", "all", {}, nil, "weird", nil)
		w.answer("lobby", "all", {}, nil, "ok", nil)
		w.answer(nil)
		t.expect(w.texts(w.line("pickman", 1))).toBe("1|Ada|900|4|1")
		t.expect(#w.errors).toBe(0)
	end)

	it("an answer for a card that is not in front is held and drawn on that card", function()
		local w = started()
		w.answer("invaders", "all", { row(1, "Zed", 70, 3, 0) }, nil, "ok", nil)
		t.expect(w.texts(w.line("invaders", 1))).toBe("1|Zed|70|3|—")
		t.expect(w.note("pickman")).toBe("LOADING")
	end)

	it("a tap on TODAY chooses it on every card, draws the boards held for it, and asks for them", function()
		local w = started()
		w.frame(1)
		local best = { score = 600, level = 2, revives = 0 }
		for _, e in Games.LIST do
			w.answer(e.name, "all", FOUR, 2, "ok", if e.name == "pickman" then best else nil)
		end
		w.answer("snake", "day", { row(1, "Day", 10, 1, 0) }, nil, "ok", nil)
		w.tab("pickman", "day").Activated.fire()
		for _, e in Games.LIST do
			t.expect(w.tab(e.name, "day").BackgroundTransparency).toBe(0)
			t.expect(w.tab(e.name, "all").BackgroundTransparency > 0).toBe(true)
		end
		t.expect(w.note("pickman")).toBe("LOADING")
		t.expect(w.texts(w.line("snake", 1))).toBe("1|Day|10|1|—")
		-- the your-best line stays below the board under TODAY: the player's all-time best on that title, BEST EVER
		t.expect(w.best("snake")).toBe("|BEST EVER|—|—|—")
		w.frame(1.1)
		t.expect(w.asks())
			.toBe(
				"pickman:all snake:all invaders:all asteroids:all pickman:day snake:day invaders:day asteroids:day"
			)
		w.tab("snake", "all").Activated.fire()
		t.expect(w.texts(w.line("pickman", 1))).toBe("1|Ada|900|4|1")
		t.expect(w.best("pickman")).toBe("|YOUR BEST|600|2|—")
	end)

	it("under TODAY, a card whose best is not known yet asks for its all-time board too", function()
		local w = started()
		w.answer("pickman", "all", FOUR, nil, "ok", nil) -- known: no run
		w.tab("pickman", "week").Activated.fire()
		w.frame(1)
		t.expect(w.asks())
			.toBe("pickman:week snake:week snake:all invaders:week invaders:all asteroids:week asteroids:all")
	end)

	it(
		"a pending best shows its own mark, never the dashes of no best, and is asked again after WAIT_RETRY",
		function()
			local w = started()
			w.frame(1)
			w.answer("pickman", "all", FOUR, nil, "ok", false)
			t.expect(w.best("pickman")).toBe(`|YOUR BEST|{Board.PENDING}|{Board.PENDING}|{Board.PENDING}`)
			w.frame(1 + Board.WAIT_RETRY - 0.1)
			t.expect(#w.sent).toBe(4)
			w.frame(1 + Board.WAIT_RETRY)
			t.expect(w.asks()).toBe("pickman:all snake:all invaders:all asteroids:all pickman:all")
			w.answer("pickman", "all", FOUR, nil, "ok", { score = 5, level = 1, revives = 0 })
			t.expect(w.best("pickman")).toBe("|YOUR BEST|5|1|—")
			-- a later pending answer does not forget the best
			w.answer("pickman", "all", FOUR, nil, "ok", false)
			t.expect(w.best("pickman")).toBe("|YOUR BEST|5|1|—")
		end
	)

	it("one binding below the test purchase screen's priority takes the six tab keys", function()
		local w = started()
		t.expect(#w.binds).toBe(1)
		local b = w.binds[1]
		t.expect(b.name).toBe(Board.ACTION)
		t.expect(b.touch).toBe(false)
		t.expect(b.priority).toBe(Board.PRIORITY)
		t.expect(b.priority > 2000).toBe(true)
		t.expect(b.priority < 3000).toBe(true)
		local names = {}
		for _, input in b.inputs do
			table.insert(names, `{input.EnumType}.{input.Name}`)
		end
		table.sort(names)
		t.expect(table.concat(names, " "))
			.toBe("KeyCode.ButtonL2 KeyCode.ButtonR2 KeyCode.Down KeyCode.S KeyCode.Up KeyCode.W")
	end)

	it("S chooses the next tab on the press; the release adds nothing; the binding sinks the key", function()
		local w = started()
		t.expect(w.press("S", "Begin")).toBe(w.Enum.ContextActionResult.Sink)
		t.expect(w.tab("pickman", "day").BackgroundTransparency).toBe(0)
		w.press("S", "End")
		t.expect(w.tab("pickman", "day").BackgroundTransparency).toBe(0)
	end)

	it("W goes back, round from ALL-TIME to THIS WEEK; Down, Up and the triggers step too", function()
		local w = started()
		w.press("W")
		t.expect(w.tab("snake", "week").BackgroundTransparency).toBe(0)
		w.press("Down")
		t.expect(w.tab("snake", "all").BackgroundTransparency).toBe(0)
		w.press("ButtonR2")
		t.expect(w.tab("snake", "day").BackgroundTransparency).toBe(0)
		w.press("ButtonL2")
		w.press("Up")
		t.expect(w.tab("snake", "week").BackgroundTransparency).toBe(0)
	end)

	it("while the player types in a text box the tab keys do nothing and pass on", function()
		local w = started()
		w.focused = { ClassName = "TextBox" }
		t.expect(w.press("S")).toBe(w.Enum.ContextActionResult.Pass)
		w.press("Down")
		t.expect(w.tab("pickman", "all").BackgroundTransparency).toBe(0)
		w.focused = nil
		t.expect(w.press("S")).toBe(w.Enum.ContextActionResult.Sink)
		t.expect(w.tab("pickman", "day").BackgroundTransparency).toBe(0)
	end)

	it("the same board is asked again after REASK, or WAIT_RETRY after a wait", function()
		local w = started()
		w.frame(1)
		w.frame(1 + Board.REASK - 0.1)
		t.expect(#w.sent).toBe(4)
		w.frame(1 + Board.REASK)
		t.expect(#w.sent).toBe(8)
		w.answer("pickman", "all", {}, nil, "wait", nil)
		w.frame(1 + Board.REASK + Board.WAIT_RETRY - 0.1)
		t.expect(#w.sent).toBe(8)
		w.frame(1 + Board.REASK + Board.WAIT_RETRY)
		t.expect(#w.sent).toBe(9)
		t.expect(w.sent[9][1]).toBe("pickman")
		w.answer("pickman", "all", {}, nil, "ok", nil)
		w.frame(1 + Board.REASK + 2 * Board.WAIT_RETRY)
		t.expect(#w.sent).toBe(9)
	end)

	it("a wait hurries only the board it was for", function()
		local w = started()
		w.frame(1)
		w.answer("snake", "all", {}, nil, "wait", nil)
		w.frame(1 + Board.WAIT_RETRY)
		t.expect(#w.sent).toBe(5)
		t.expect(w.sent[5][1]).toBe("snake")
		t.expect(w.sent[5][2]).toBe("all")
	end)

	it("lays the slot out by Board.layout for its size, and again when the size changes", function()
		local w = started()
		local function check(width: number, height: number)
			local l = Board.layout(width, height, Card.GLYPH)
			local header = w.part("pickman", "Header")
			t.expect(header.Position.Y.Scale).toBe(0)
			t.expect(header.Position.Y.Offset).toBeNear(l.tabs, 1e-9)
			t.expect(header.Size.Y.Offset).toBeNear(l.line, 1e-9)
			t.expect(header.Size.X.Scale).toBe(1)
			local rows = w.part("pickman", "Rows")
			t.expect(rows.Position.Y.Offset).toBeNear(l.tabs + l.line, 1e-9)
			t.expect(rows.Size.Y.Scale).toBe(0)
			t.expect(rows.Size.Y.Offset).toBeNear(l.view, 1e-9)
			t.expect(rows.Size.X.Scale).toBe(1)
			t.expect(rows.CanvasSize.Y.Offset).toBeNear(l.canvas, 1e-9)
			t.expect(rows.ScrollingEnabled).toBe(l.canvas > l.view)
			t.expect(w.line("pickman", 3).Position.Y.Offset).toBeNear(2 * l.line, 1e-9)
			t.expect(w.line("pickman", 3).Size.Y.Offset).toBeNear(l.line, 1e-9)
			local best = w.part("pickman", "Best")
			-- the best line's bottom edge is the slot's
			t.expect(best.Position.Y.Scale + best.Size.Y.Scale).toBe(1)
			t.expect(best.Position.Y.Offset + best.Size.Y.Offset).toBeNear(0, 1e-9)
			t.expect(best.Size.Y.Offset - best.Size.Y.Scale * height).toBeNear(l.line, 1e-9)
			t.expect(w.part("pickman", "Tabs").Size.Y.Offset).toBe(Board.TAB_PX)
			-- every text one size, the layout's; none scaled to its box
			local labels = { w.tab("pickman", "day"), w.part("pickman", "Note") }
			for _, frame in { header, w.line("pickman", 1), w.line("pickman", 10), best } do
				for _, c in Board.COLUMNS do
					table.insert(labels, frame:FindFirstChild(c.name))
				end
			end
			for _, label in labels do
				t.expect(label.TextSize).toBe(l.text)
				t.expect(label.TextScaled == true).toBe(false)
			end
			-- YOUR BEST from the rank's left edge to the name's right one
			local name = best:FindFirstChild("Name")
			local rank, named = Board.COLUMNS[1], Board.COLUMNS[2]
			t.expect(name.Position.X.Scale).toBeNear(rank.x, 1e-9)
			t.expect(name.Size.X.Scale).toBeNear(named.x + named.width - rank.x, 1e-9)
		end
		check(300, SLOT_Y)
		local slot = w.slot("pickman")
		slot.AbsoluteSize = { X = 200, Y = 112 } -- narrow: the width, through Card.GLYPH, sets the text size
		local resized = slot.changed.AbsoluteSize
		t.expect(resized ~= nil).toBe(true)
		resized.fire()
		check(200, 112)
		t.expect(w.part("pickman", "Rows").ScrollingEnabled).toBe(true)
	end)

	it("started twice it fills each slot once, binds once and asks once", function()
		local w = started()
		w.View.start()
		t.expect(#w.binds).toBe(1)
		local tabs = 0
		for _, c in w.slot("pickman").children do
			if c.Name == "Tabs" then
				tabs += 1
			end
		end
		t.expect(tabs).toBe(1)
		w.frame(1)
		t.expect(#w.sent).toBe(4)
		t.expect(#w.errors).toBe(0)
	end)

	it("a card the carousel does not give is left out, and the others are drawn", function()
		local w = started({ missing = "asteroids" })
		t.expect(#w.errors).toBe(0)
		t.expect(w.note("snake")).toBe("LOADING")
		w.answer("asteroids", "all", {}, nil, "ok", nil)
		t.expect(#w.errors).toBe(0)
	end)
end)
