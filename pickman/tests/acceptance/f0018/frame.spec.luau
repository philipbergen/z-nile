--!strict
-- f0170 AC4: Session.frame is what the server replicates: the v1 snapshot, untouched, plus the play
-- state. The v1 snapshot itself keeps exactly its fields.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local plain = require("@tests/lib/plain")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "###############", "#            P#", "###############" }, "corridor")
local RULES: Session.Config =
	{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, play = Game.CLASSIC_CONFIG }

local function keys(v: any): { string }
	local out = {}
	for k in v do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

local function has(list: { string }, key: string): boolean
	return table.find(list, key) ~= nil
end

return t.spec("f0170 Session.frame", function(it)
	it("carries every field of the snapshot unchanged, plus a play record", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		for _ = 1, 70 do
			Session.step(s)
		end
		local snap = Session.snapshot(s, "p")
		local frame = Session.frame(s, "p")
		t.expect(frame.v).toBe(snap.v)
		t.expect(frame.tick).toBe(snap.tick)
		t.expect(frame.maze).toBe(snap.maze)
		t.expect(frame.player).toEqual(snap.player)
		t.expect(type(frame.play)).toBe("table")
	end)

	it("the play record has the phase, level, score, lives, timer and frightened time", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		local play = Session.frame(s, "p").play
		t.expect(play.phase).toBe("ready")
		t.expect(play.level).toBe(1)
		t.expect(play.score).toBe(0)
		t.expect(play.lives).toBe(3)
		t.expect(play.timer).toBe(60)
		t.expect(play.frightened).toBe(0)
		local k = keys(play)
		for _, field in { "phase", "level", "score", "lives", "timer", "frightened" } do
			t.expect(has(k, field)).toBe(true)
		end
	end)

	it("later issues may add fields: the contract is that these ones exist, with these types", function()
		local frame: any = Session.frame(
			(function()
				local s = Session.new(CORRIDOR, 1)
				Session.join(s, "p")
				return s
			end)(),
			"p"
		)
		for _, field in { "v", "tick" } do
			t.expect(type(frame[field])).toBe("number")
		end
		t.expect(type(frame.maze)).toBe("string")
		for _, field in { "level", "score", "lives", "timer", "frightened" } do
			t.expect(type(frame.play[field])).toBe("number")
		end
		t.expect(type(frame.play.phase)).toBe("string")
	end)

	it("is plain data that round-trips through JSON", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		for _ = 1, 65 do
			Session.step(s)
		end
		Session.kill(s, "p")
		local frame = Session.frame(s, "p")
		-- c0153: plain data, and a JSON round trip within 1e-9 (Lune's JSON decoder can return a number one ulp off)
		t.expect({ plain.roundTrip(frame, 1e-9) }).toEqual({ true })
	end)

	it("is a fresh table: changing it does not change the session", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		local frame = Session.frame(s, "p")
		frame.play.score = 99999
		frame.play.lives = 99
		frame.player.x = 99
		local again = Session.frame(s, "p")
		t.expect(again.play.score).toBe(0)
		t.expect(again.play.lives).toBe(3)
		t.expect(again.player.x).toBe(13)
	end)

	it("an unknown player is an error, as for snapshot", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		t.expect(function()
			Session.frame(s, "nobody")
		end).toThrow("unknown player")
	end)

	it("the v1 snapshot is unchanged: exactly its four fields, version 1", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		local snap = Session.snapshot(s, "p")
		t.expect(Session.SNAPSHOT_VERSION).toBe(1)
		t.expect(keys(snap)).toEqual({ "maze", "player", "tick", "v" })
		t.expect(keys(snap.player)).toEqual({ "heading", "jumpTick", "moving", "x", "y" })
	end)

	it("the play record follows the run: dying, then a new attempt", function()
		local s = Session.new(CORRIDOR, 1, RULES)
		Session.join(s, "p")
		for _ = 1, 70 do
			Session.step(s)
		end
		Session.kill(s, "p")
		local dying = Session.frame(s, "p").play
		t.expect(dying.phase).toBe("dying")
		t.expect(dying.lives).toBe(2)
		t.expect(dying.timer).toBe(45)
		for _ = 1, 45 do
			Session.step(s)
		end
		local ready = Session.frame(s, "p").play
		t.expect(ready.phase).toBe("ready")
		t.expect(ready.timer).toBe(60)
	end)
end)
