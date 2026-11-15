--!strict
-- f0234 AC2: View.readyEnd, the step a READY pause ends and play starts, folded over the frames the server sends.
-- A frame in the "ready" phase at tick n with timer k plays from n + k; every other frame keeps the last answer (so
-- the landing still shows over the step play starts in), and a frame whose numbers are not finite changes nothing.
-- Over a real run (Session.GAME_CONFIG, the frames Session.frame builds) the fold names, for every READY pause (the
-- run's start, a new life after a death, a new level, a new run after game over), the tick of its first frame in
-- play; and no frame of a pause carries a hop (the server's `hopped` is nil throughout it, a Hop intent in it
-- starts none), so the camera never adds a hop to the held eye.
local Game = require("@logic/Game")
local Hop = require("@logic/Hop")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local function play(phase: Game.Phase, timer: number): Session.PlayFrame
	return { phase = phase, level = 1, score = 0, lives = 3, timer = timer, frightened = 0 }
end

type Run = {
	s: Session.Session,
	readyEnd: number?,
	phase: Game.Phase?,
	starts: { [string]: number }, -- pauses that ended in play, by the reason of the Ready that began them
	reason: string, -- the reason of the pause under way ("start" for the run's first)
}

local function new(): Run
	local s = Session.new(Maze.layout("classic"), 1, Session.GAME_CONFIG)
	Session.join(s, "p")
	return { s = s, readyEnd = nil, phase = nil, starts = {}, reason = "start" }
end

-- one server step and the frame it sends, folded as the camera folds it
local function step(r: Run)
	for _, e in Session.step(r.s) do
		if e.kind == "Ready" then
			r.reason = e.reason or "?"
		end
	end
	local frame = Session.frame(r.s, "p")
	r.readyEnd = View.readyEnd(r.readyEnd, frame.play, frame.tick)
	if frame.play.phase == "ready" then
		t.expect(frame.hopped).toBe(nil)
		t.expect(r.readyEnd).toBe(frame.tick + frame.play.timer)
		-- a hop asked for in the pause starts none
		local ok = Session.submit(r.s, "p", Hop.INTENT)
		t.expect(ok).toBe(true)
	elseif frame.play.phase == "playing" and r.phase == "ready" then
		t.expect(r.readyEnd).toBe(frame.tick)
		r.starts[r.reason] = (r.starts[r.reason] or 0) + 1
	end
	r.phase = frame.play.phase
end

local function reach(r: Run, phase: Game.Phase)
	for _ = 1, 1000 do
		step(r)
		if r.phase == phase then
			return
		end
	end
	error(`never reached {phase}`)
end

-- in play, a hop that has reached its third step (kept through the pause that follows)
local function hopped(r: Run)
	local ok = Session.submit(r.s, "p", Hop.INTENT)
	t.expect(ok).toBe(true)
	for _ = 1, 3 do
		step(r)
	end
	t.expect(Session.frame(r.s, "p").hopped ~= nil).toBe(true)
end

return t.spec("f0234 the step each READY pause ends", function(it)
	it("a ready frame names its tick plus its timer; other phases keep the last answer", function()
		t.expect(View.readyEnd(nil, play("ready", 59), 1)).toBe(60)
		t.expect(View.readyEnd(7, play("ready", 60), 100)).toBe(160)
		local others: { Game.Phase } = { "playing", "dying", "levelclear", "gameover" }
		for _, phase in others do
			t.expect(View.readyEnd(160, play(phase :: Game.Phase, 30), 170)).toBe(160)
			t.expect(View.readyEnd(nil, play(phase :: Game.Phase, 30), 170)).toBe(nil)
		end
	end)

	it("a frame whose tick or timer is not a number keeps the last answer", function()
		t.expect(View.readyEnd(160, play("ready", 0 / 0), 100)).toBe(160)
		t.expect(View.readyEnd(160, play("ready", math.huge), 100)).toBe(160)
		t.expect(View.readyEnd(160, play("ready", 30), 0 / 0)).toBe(160)
		t.expect(View.readyEnd(nil, play("ready", 30), -math.huge)).toBe(nil)
	end)

	it("over a real run it names the first tick in play of every READY pause, none carrying a hop", function()
		local r = new()
		reach(r, "playing") -- the run's start
		t.expect(r.starts.start).toBe(1)
		t.expect(r.readyEnd).toBe(60)

		-- a new life after a death in the middle of a hop
		hopped(r)
		Session.kill(r.s, "p")
		reach(r, "ready")
		reach(r, "playing")
		t.expect((r.starts.respawn or 0) >= 1).toBe(true)

		-- a new level, cleared in the middle of a hop (Game.cleared, however the level was cleared)
		hopped(r)
		if r.phase ~= "playing" then
			reach(r, "playing")
		end
		local cleared = Game.cleared(r.s.members.p.play)
		t.expect(#cleared).toBe(1)
		reach(r, "ready")
		reach(r, "playing")
		t.expect(r.starts.level).toBe(1)

		-- a new run after game over
		while r.phase ~= "gameover" do
			if r.phase == "playing" then
				Session.kill(r.s, "p")
			end
			step(r)
		end
		local events, ok = Session.playAgain(r.s, "p")
		t.expect(ok).toBe(true)
		for _, e in events do
			if e.kind == "Ready" then
				r.reason = e.reason or "?"
			end
		end
		reach(r, "playing")
		t.expect(r.starts.again).toBe(1)
	end)
end)
