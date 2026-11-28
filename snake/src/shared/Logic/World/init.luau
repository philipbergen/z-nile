--!strict
-- World: Snake's deterministic N-player arena rules, engine-free. Plain data state mutated in place by turn/advance.
local Maps = require("./Maps")

export type Draw = Maps.Draw
export type Heading = Maps.Heading
export type Tile = Maps.Tile
export type Turn = "Left" | "Right"
export type Phase = "play" | "clear" | "over"
export type SnakeState = "ready" | "alive" | "dying" | "over"
export type Snake = {
	id: number,
	body: { Tile },
	heading: Heading,
	turns: { Turn },
	grow: number,
	lives: number,
	score: number,
	state: SnakeState,
	timer: number,
}
export type World = {
	map: number,
	layout: Maps.Layout,
	snakes: { Snake },
	apples: { Tile },
	phase: Phase,
	timer: number,
	untilStep: number,
}
export type Event =
	{ kind: "map", map: number }
	| { kind: "placed", id: number, x: number, y: number, heading: Heading }
	| { kind: "go", id: number }
	| { kind: "ate", id: number, x: number, y: number }
	| { kind: "died", id: number, x: number, y: number }
	| { kind: "over", id: number }
	| { kind: "cleared", map: number, ids: { number } }

local World = {}

World.TUNING = table.freeze({
	lives = 3,
	turnBuffer = 2,
	deathSeconds = 1.5,
	readySeconds = 2,
	clearSeconds = 2,
	appleGrow = 1,
	applePoints = 10,
	clearBonus = 100,
})

local EPS = 1e-9

local function keyOf(x: number, y: number, side: number): number
	return y * (side + 2) + x
end

local function makeBody(sp: Maps.Spawn): { Tile }
	local d = Maps.step(sp.heading)
	local body: { Tile } = table.create(Maps.TUNING.startLength)
	for i = 0, Maps.TUNING.startLength - 1 do
		body[i + 1] = { x = sp.x - d.x * i, y = sp.y - d.y * i }
	end
	return body
end

local function buildWallSet(layout: Maps.Layout): { [number]: boolean }
	local side = layout.side
	local walls: { [number]: boolean } = {}
	for _, w in layout.walls do
		for _, tile in Maps.wallTiles(w) do
			walls[keyOf(tile.x, tile.y, side)] = true
		end
	end
	return walls
end

local function topUpApples(w: World, draw: Draw)
	local target = #w.snakes + 1
	if #w.apples >= target then
		return
	end
	local side = w.layout.side
	local occ = buildWallSet(w.layout)
	for _, s in w.snakes do
		if s.state == "ready" or s.state == "alive" then
			for _, seg in s.body do
				if seg.x >= 1 and seg.x <= side and seg.y >= 1 and seg.y <= side then
					occ[keyOf(seg.x, seg.y, side)] = true
				end
			end
		end
	end
	for _, a in w.apples do
		occ[keyOf(a.x, a.y, side)] = true
	end

	while #w.apples < target do
		local free = 0
		for y = 1, side do
			for x = 1, side do
				if not occ[keyOf(x, y, side)] then
					free += 1
				end
			end
		end
		if free == 0 then
			return
		end
		local pick = draw(free)
		local seen = 0
		local placed = false
		for y = 1, side do
			for x = 1, side do
				local k = keyOf(x, y, side)
				if not occ[k] then
					seen += 1
					if seen == pick then
						occ[k] = true
						table.insert(w.apples, { x = x, y = y })
						placed = true
						break
					end
				end
			end
			if placed then
				break
			end
		end
	end
end

function World.goal(w: World): number
	return Maps.goal(w.map)
end

function World.speed(w: World): number
	return Maps.speed(w.map)
end

function World.safest(w: World, id: number): Maps.Spawn?
	local side = w.layout.side
	local stride = side + 2
	local walls = buildWallSet(w.layout)

	-- Mark tiles blocked for bodies (walls, ready/alive snakes, apples) and for ahead (walls, ready/alive snakes).
	local solid: { [number]: boolean } = table.clone(walls)
	local hasOtherHead = false
	local headQ: { number } = {}
	local headDist: { [number]: number } = {}

	for _, s in w.snakes do
		if s.state == "ready" or s.state == "alive" then
			for _, seg in s.body do
				if seg.x >= 1 and seg.x <= side and seg.y >= 1 and seg.y <= side then
					solid[keyOf(seg.x, seg.y, side)] = true
				end
			end
			if s.id ~= id and #s.body > 0 then
				local h = s.body[1]
				if h.x >= 0 and h.x <= side + 1 and h.y >= 0 and h.y <= side + 1 then
					local hk = keyOf(h.x, h.y, side)
					if headDist[hk] == nil then
						headDist[hk] = 0
						table.insert(headQ, hk)
						hasOtherHead = true
					end
				end
			end
		end
	end

	local appleSet: { [number]: boolean } = {}
	for _, a in w.apples do
		appleSet[keyOf(a.x, a.y, side)] = true
	end

	-- BFS 1: Manhattan distance to nearest other Ready/alive head (4-neighbours)
	if hasOtherHead then
		local qHead = 1
		while qHead <= #headQ do
			local cur = headQ[qHead]
			qHead += 1
			local cd = headDist[cur]
			local cx = cur % stride
			local cy = math.floor(cur / stride)
			local n1 = cur - 1
			if cx > 0 and headDist[n1] == nil then
				headDist[n1] = cd + 1
				table.insert(headQ, n1)
			end
			local n2 = cur + 1
			if cx < side + 1 and headDist[n2] == nil then
				headDist[n2] = cd + 1
				table.insert(headQ, n2)
			end
			local n3 = cur - stride
			if cy > 0 and headDist[n3] == nil then
				headDist[n3] = cd + 1
				table.insert(headQ, n3)
			end
			local n4 = cur + stride
			if cy < side + 1 and headDist[n4] == nil then
				headDist[n4] = cd + 1
				table.insert(headQ, n4)
			end
		end
	end

	-- BFS 2: Chebyshev distance to nearest wall tile or border ring (8-neighbours)
	local wallQ: { number } = {}
	local wallDist: { [number]: number } = {}
	for y = 0, side + 1 do
		for x = 0, side + 1 do
			local k = keyOf(x, y, side)
			if x == 0 or x == side + 1 or y == 0 or y == side + 1 or walls[k] then
				wallDist[k] = 0
				table.insert(wallQ, k)
			end
		end
	end
	do
		local qHead = 1
		while qHead <= #wallQ do
			local cur = wallQ[qHead]
			qHead += 1
			local cd = wallDist[cur]
			local cx = cur % stride
			local cy = math.floor(cur / stride)
			for dy = -1, 1 do
				local ny = cy + dy
				if ny >= 0 and ny <= side + 1 then
					for dx = -1, 1 do
						if dx ~= 0 or dy ~= 0 then
							local nx = cx + dx
							if nx >= 0 and nx <= side + 1 then
								local nk = ny * stride + nx
								if wallDist[nk] == nil then
									wallDist[nk] = cd + 1
									table.insert(wallQ, nk)
								end
							end
						end
					end
				end
			end
		end
	end

	local best: Maps.Spawn? = nil
	local bestHead = -1
	local bestWall = -1
	local startLen = Maps.TUNING.startLength
	local clearAhead = Maps.TUNING.clearAhead

	for y = 1, side do
		for x = 1, side do
			local k0 = keyOf(x, y, side)
			if not solid[k0] and not appleSet[k0] then
				local hd = if hasOtherHead then (headDist[k0] or 0) else 0
				local wd = wallDist[k0] or 0
				if hd > bestHead or (hd == bestHead and wd > bestWall) then
					for _, rawH in Maps.HEADINGS do
						local h: Heading = rawH :: Heading
						local d = Maps.step(h)
						local ok = true
						for i = 1, startLen - 1 do
							local bx, by = x - d.x * i, y - d.y * i
							if bx < 1 or bx > side or by < 1 or by > side then
								ok = false
								break
							end
							local bk = keyOf(bx, by, side)
							if solid[bk] or appleSet[bk] then
								ok = false
								break
							end
						end
						if ok then
							for i = 1, clearAhead do
								local ax, ay = x + d.x * i, y + d.y * i
								if
									ax < 1
									or ax > side
									or ay < 1
									or ay > side
									or solid[keyOf(ax, ay, side)]
								then
									ok = false
									break
								end
							end
						end
						if ok then
							bestHead = hd
							bestWall = wd
							best = { x = x, y = y, heading = h }
							break
						end
					end
				end
			end
		end
	end

	return best
end

function World.start(w: World, layout: Maps.Layout, draw: Draw): { Event }
	local events: { Event } = {}
	w.map = layout.map
	w.layout = layout
	w.apples = {}
	w.phase = "play"
	w.timer = 0
	w.untilStep = 1 / Maps.speed(layout.map)
	local mapEv: Event = { kind = "map", map = layout.map }
	table.insert(events, mapEv)

	for i, s in w.snakes do
		if s.state ~= "over" then
			local sp = layout.spawns[i]
			s.body = makeBody(sp)
			s.heading = sp.heading
			s.turns = {}
			s.grow = 0
			s.state = "ready"
			s.timer = World.TUNING.readySeconds
			local placedEv: Event = { kind = "placed", id = s.id, x = sp.x, y = sp.y, heading = sp.heading }
			table.insert(events, placedEv)
		end
	end

	topUpApples(w, draw)
	return events
end

function World.new(players: number, draw: Draw): (World, { Event })
	local layout = Maps.roll(1, players, draw)
	local snakes: { Snake } = table.create(players)
	for i = 1, players do
		local sp = layout.spawns[i]
		snakes[i] = {
			id = i,
			body = makeBody(sp),
			heading = sp.heading,
			turns = {},
			grow = 0,
			lives = World.TUNING.lives,
			score = 0,
			state = "ready",
			timer = World.TUNING.readySeconds,
		}
	end
	local w: World = {
		map = 1,
		layout = layout,
		snakes = snakes,
		apples = {},
		phase = "play",
		timer = 0,
		untilStep = 1 / Maps.speed(1),
	}
	local events = World.start(w, layout, draw)
	return w, events
end

function World.turn(w: World, id: number, turn: Turn): boolean
	if w.phase ~= "play" then
		return false
	end
	if turn ~= "Left" and turn ~= "Right" then
		return false
	end
	local s = w.snakes[id]
	if s == nil or (s.state ~= "ready" and s.state ~= "alive") then
		return false
	end
	if #s.turns >= World.TUNING.turnBuffer then
		return false
	end
	table.insert(s.turns, turn)
	return true
end

local function tryRespawn(w: World, s: Snake, events: { Event })
	local sp = World.safest(w, s.id)
	if sp ~= nil then
		s.body = makeBody(sp)
		s.heading = sp.heading
		s.turns = {}
		s.grow = 0
		s.state = "ready"
		s.timer = World.TUNING.readySeconds
		local ev: Event = { kind = "placed", id = s.id, x = sp.x, y = sp.y, heading = sp.heading }
		table.insert(events, ev)
	end
end

local function doStep(w: World, draw: Draw, events: { Event })
	local side = w.layout.side
	local walls = buildWallSet(w.layout)

	-- Build apple lookup (key -> index)
	local appleAt: { [number]: number } = {}
	for i, a in w.apples do
		appleAt[keyOf(a.x, a.y, side)] = i
	end

	type Move = {
		snake: Snake,
		head: Tile,
		heading: Heading,
		newBody: { Tile },
		ateIndex: number?,
		newGrow: number,
	}
	local moves: { Move } = {}
	local boardCount: { [number]: number } = {}

	-- Ready snakes stay solid on the board
	for _, s in w.snakes do
		if s.state == "ready" then
			for _, seg in s.body do
				local k = keyOf(seg.x, seg.y, side)
				boardCount[k] = (boardCount[k] or 0) + 1
			end
		end
	end

	-- 1 & 2: Compute every alive snake's move simultaneously
	for _, s in w.snakes do
		if s.state == "alive" then
			local heading: Heading = s.heading :: Heading
			if #s.turns > 0 then
				local t: Turn = table.remove(s.turns, 1) :: Turn
				heading = Maps.turn(heading, t)
			end
			local d = Maps.step(heading)
			local oldHead = s.body[1]
			local head: Tile = { x = oldHead.x + d.x, y = oldHead.y + d.y }
			local inBounds = head.x >= 1 and head.x <= side and head.y >= 1 and head.y <= side
			local ateIndex = if inBounds then appleAt[keyOf(head.x, head.y, side)] else nil
			local grow = s.grow + (if ateIndex ~= nil then World.TUNING.appleGrow else 0)
			local keepTail = grow > 0
			local newGrow = if keepTail then grow - 1 else 0
			local newLen = if keepTail then #s.body + 1 else #s.body
			local newBody: { Tile } = table.create(newLen)
			newBody[1] = head
			local copyCount = if keepTail then #s.body else #s.body - 1
			for j = 1, copyCount do
				newBody[j + 1] = s.body[j]
			end
			for _, seg in newBody do
				if seg.x >= 1 and seg.x <= side and seg.y >= 1 and seg.y <= side then
					local k = keyOf(seg.x, seg.y, side)
					boardCount[k] = (boardCount[k] or 0) + 1
				end
			end
			table.insert(moves, {
				snake = s,
				head = head,
				heading = heading,
				newBody = newBody,
				ateIndex = ateIndex,
				newGrow = newGrow,
			})
		end
	end

	-- 3 & 4: Resolve deaths simultaneously
	local eatenApples: { [number]: boolean } = {}
	local anyAppleEaten = false
	local survivors: { Move } = {}

	for _, mv in moves do
		local h = mv.head
		local dead = h.x < 1 or h.x > side or h.y < 1 or h.y > side
		if not dead then
			local hk = keyOf(h.x, h.y, side)
			if walls[hk] or (boardCount[hk] or 0) >= 2 then
				dead = true
			end
		end
		if dead then
			local s = mv.snake
			s.lives -= 1
			s.turns = {}
			s.grow = 0
			local diedEv: Event = { kind = "died", id = s.id, x = h.x, y = h.y }
			table.insert(events, diedEv)
			if s.lives <= 0 then
				s.state = "over"
				s.timer = 0
				local overEv: Event = { kind = "over", id = s.id }
				table.insert(events, overEv)
			else
				s.state = "dying"
				s.timer = World.TUNING.deathSeconds
			end
		else
			table.insert(survivors, mv)
		end
	end

	-- 5: Apply survivors' new bodies and apple eating
	for _, mv in survivors do
		local s = mv.snake
		s.heading = mv.heading
		s.body = mv.newBody
		s.grow = mv.newGrow
		if mv.ateIndex ~= nil then
			eatenApples[mv.ateIndex] = true
			anyAppleEaten = true
			s.score += World.TUNING.applePoints * w.map
			local ateEv: Event = { kind = "ate", id = s.id, x = mv.head.x, y = mv.head.y }
			table.insert(events, ateEv)
		end
	end

	if anyAppleEaten then
		local kept: { Tile } = {}
		for i, a in w.apples do
			if not eatenApples[i] then
				table.insert(kept, a)
			end
		end
		w.apples = kept
		topUpApples(w, draw)
	end

	-- 6: Check goal length
	local goal = Maps.goal(w.map)
	local clearedIds: { number } = {}
	for _, mv in survivors do
		if #mv.snake.body >= goal then
			mv.snake.score += World.TUNING.clearBonus * w.map
			table.insert(clearedIds, mv.snake.id)
		end
	end
	if #clearedIds > 0 then
		w.phase = "clear"
		w.timer = World.TUNING.clearSeconds
		local clearEv: Event = { kind = "cleared", map = w.map, ids = clearedIds }
		table.insert(events, clearEv)
	end
end

function World.advance(w: World, dt: number, draw: Draw): { Event }
	local events: { Event } = {}
	if type(dt) ~= "number" or dt ~= dt or math.abs(dt) == math.huge or dt <= 0 then
		return events
	end
	local rem = dt
	while rem > EPS and w.phase ~= "over" do
		if w.phase == "clear" then
			local slice = math.min(rem, w.timer)
			w.timer = math.max(0, w.timer - slice)
			rem -= slice
			if w.timer <= EPS then
				local nextLayout = Maps.roll(w.map + 1, #w.snakes, draw)
				local startEvents = World.start(w, nextLayout, draw)
				for _, ev in startEvents do
					table.insert(events, ev)
				end
			end
		else
			local slice = math.min(rem, w.untilStep)
			for _, s in w.snakes do
				if (s.state == "ready" or s.state == "dying") and s.timer > EPS then
					if s.timer < slice then
						slice = s.timer
					end
				end
			end
			if slice < 0 then
				slice = 0
			end
			rem -= slice
			w.untilStep -= slice
			local becameDue: { Snake } = {}
			for _, s in w.snakes do
				if (s.state == "ready" or s.state == "dying") and s.timer > EPS then
					s.timer = math.max(0, s.timer - slice)
					if s.timer <= EPS then
						s.timer = 0
						table.insert(becameDue, s)
					end
				end
			end

			local stepDue = w.untilStep <= EPS

			-- Process timers that just finished (and retry blocked respawns on step instants)
			for _, s in becameDue do
				if s.state == "dying" then
					tryRespawn(w, s, events)
				elseif s.state == "ready" then
					s.state = "alive"
					s.timer = 0
					local goEv: Event = { kind = "go", id = s.id }
					table.insert(events, goEv)
				end
			end

			if stepDue then
				for _, s in w.snakes do
					if s.state == "dying" and s.timer <= EPS then
						local alreadyTried = false
						for _, b in becameDue do
							if b == s then
								alreadyTried = true
								break
							end
						end
						if not alreadyTried then
							tryRespawn(w, s, events)
						end
					end
				end
				w.untilStep += 1 / Maps.speed(w.map)
				doStep(w, draw, events)
			end

			-- Check if every snake is over
			if w.phase == "play" then
				local allOver = true
				for _, s in w.snakes do
					if s.state ~= "over" then
						allOver = false
						break
					end
				end
				if allOver then
					w.phase = "over"
				end
			end
		end
	end
	return events
end

return World
