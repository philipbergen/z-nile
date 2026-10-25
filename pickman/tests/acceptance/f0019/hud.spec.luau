--!strict
-- f0180 AC1: Hud.model turns the replicated play record into what the HUD shows: the score as digits,
-- the level, the lives left (the one in play included) and the share of the power period still to run.
local Hud = require("@logic/Hud")
local Levels = require("@logic/Levels")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local function play(over: { [string]: any }?): Session.PlayFrame
	local p: any = { phase = "playing", level = 1, score = 0, lives = 3, timer = 0, frightened = 0 }
	local changes: { [string]: any } = over or {}
	for k, v in changes do
		p[k] = v
	end
	return p
end

return t.spec("f0180 Hud.model", function(it)
	it("shows the score as plain digits", function()
		t.expect(Hud.model(play({ score = 0 })).score).toBe("0")
		t.expect(Hud.model(play({ score = 12340 })).score).toBe("12340")
		t.expect(Hud.model(play({ score = 1234560 })).score).toBe("1234560")
	end)

	it("shows the level as LEVEL n", function()
		t.expect(Hud.model(play({ level = 1 })).level).toBe("LEVEL 1")
		t.expect(Hud.model(play({ level = 17 })).level).toBe("LEVEL 17")
	end)

	it("shows the lives left, the one in play included", function()
		t.expect(Hud.model(play({ lives = 3 })).lives).toBe(3)
		t.expect(Hud.model(play({ lives = 4 })).lives).toBe(4)
		t.expect(Hud.model(play({ phase = "gameover", lives = 0 })).lives).toBe(0)
	end)

	it("power is the share of the level's frightened time still to run", function()
		local full = Levels.frightenedTicks(1, Session.TICK_RATE)
		t.expect(full).toBe(180)
		t.expect(Hud.model(play({ frightened = full })).power).toBe(1)
		t.expect(Hud.model(play({ frightened = 90 })).power).toBeNear(0.5, 1e-9)
		t.expect(Hud.model(play({ frightened = 1 })).power).toBeNear(1 / 180, 1e-9)
		t.expect(Hud.model(play({ frightened = 0 })).power).toBe(0)
	end)

	it("power is measured against the current level's frightened time", function()
		-- level 18 has one second of frightened time: 30 ticks
		t.expect(Hud.model(play({ level = 18, frightened = 15 })).power).toBeNear(0.5, 1e-9)
		-- level 4 has three seconds: 90 ticks
		t.expect(Hud.model(play({ level = 4, frightened = 45 })).power).toBeNear(0.5, 1e-9)
	end)

	it("a level with no frightened time shows no power, whatever the counter says", function()
		t.expect(Hud.model(play({ level = 17, frightened = 0 })).power).toBe(0)
		t.expect(Hud.model(play({ level = 25, frightened = 5 })).power).toBe(0)
	end)

	it("power never exceeds 1", function()
		t.expect(Hud.model(play({ level = 2, frightened = 1000 })).power).toBe(1)
	end)

	it("follows the record it is given: every field changes with it", function()
		local a = Hud.model(play({ score = 50, level = 2, lives = 2, frightened = 75 }))
		t.expect(a).toEqual({ score = "50", level = "LEVEL 2", lives = 2, power = 0.5 })
	end)

	it("leaves the record unchanged", function()
		local p = play({ score = 10, frightened = 30 })
		local before = table.clone(p)
		Hud.model(p)
		t.expect(p).toEqual(before)
	end)
end)
