--!strict
local Field = require("@logic/Field")
local Pilot = require("@logic/Pilot")
local Ship = require("@logic/Ship")
local t = require("@tests/lib/t")

local CFG: Pilot.Config = {
	field = Field.CLASSIC,
	ship = Ship.CLASSIC,
	lives = 3,
	extraLifeEvery = 10000,
	shotLimit = 4,
	shotSpeed = 8,
	shotLife = 60,
	hyperspaceTicks = 30,
	hyperspaceOdds = 6,
	respawnTicks = 120,
	protectTicks = 120,
}

local function fixedDraw(v: number): Pilot.Draw
	return function(_n: number): number
		return v
	end
end

local function seqDraw(values: { number }): Pilot.Draw
	local i = 0
	return function(_n: number): number
		i += 1
		return values[i]
	end
end

return t.spec("Pilot", function(it)
	it("initialises alive at (x, y) with configured lives and no score", function()
		local p = Pilot.new(CFG, 500, 375)
		t.expect(p.ship.x).toBe(500)
		t.expect(p.ship.y).toBe(375)
		t.expect(p.shipState).toBe("alive")
		t.expect(p.timer).toBe(0)
		t.expect(p.protect).toBe(0)
		t.expect(#p.shots).toBe(0)
		t.expect(p.lives).toBe(3)
		t.expect(p.score).toBe(0)
		t.expect(p.nextExtra).toBe(10000)
		t.expect(Pilot.exposed(p)).toBe(true)
	end)

	it("sanitises controls strictly", function()
		local nilCtrl = Pilot.controls(nil)
		t.expect(nilCtrl.turn).toBe(0)
		t.expect(nilCtrl.thrust).toBe(false)
		t.expect(nilCtrl.fire).toBe(false)
		t.expect(nilCtrl.hyperspace).toBe(false)

		local badCtrl = Pilot.controls({ turn = 2, thrust = 1, fire = "yes", hyperspace = {} })
		t.expect(badCtrl.turn).toBe(0)
		t.expect(badCtrl.thrust).toBe(false)
		t.expect(badCtrl.fire).toBe(false)
		t.expect(badCtrl.hyperspace).toBe(false)

		local goodCtrl = Pilot.controls({ turn = -1, thrust = true, fire = true, hyperspace = false })
		t.expect(goodCtrl.turn).toBe(-1)
		t.expect(goodCtrl.thrust).toBe(true)
		t.expect(goodCtrl.fire).toBe(true)
		t.expect(goodCtrl.hyperspace).toBe(false)
	end)

	it("awards extra lives at every extraLifeEvery threshold", function()
		local p = Pilot.new(CFG, 500, 375)
		local events: { Pilot.Event } = {}
		Pilot.award(p, CFG, 25000, function(e)
			table.insert(events, e)
		end)
		t.expect(p.score).toBe(25000)
		t.expect(p.lives).toBe(5)
		t.expect(p.nextExtra).toBe(30000)
		t.expect(#events).toBe(2)
		t.expect(events[1].kind).toBe("ExtraLife")
		t.expect(events[1].lives).toBe(4)
		t.expect(events[2].lives).toBe(5)
	end)

	it("handles hyperspace jump, survival, and self-destruct", function()
		local p = Pilot.new(CFG, 500, 375)
		local events: { Pilot.Event } = {}
		local emit = function(e: Pilot.Event)
			table.insert(events, e)
		end
		Pilot.control(
			p,
			CFG,
			{ turn = 1, thrust = true, fire = true, hyperspace = true },
			seqDraw({ 101, 202 }),
			emit
		)
		t.expect(p.shipState).toBe("hyperspace")
		t.expect(p.ship.x).toBe(100)
		t.expect(p.ship.y).toBe(201)
		t.expect(p.ship.vx).toBe(0)
		t.expect(p.ship.vy).toBe(0)
		t.expect(p.timer).toBe(CFG.hyperspaceTicks)
		t.expect(#p.shots).toBe(0)
		t.expect(Pilot.exposed(p)).toBe(false)

		for _ = 1, CFG.hyperspaceTicks do
			local out = Pilot.clock(p, CFG, fixedDraw(2), function()
				return true
			end, emit)
			t.expect(out).toBe(false)
		end
		t.expect(p.shipState).toBe("alive")
		t.expect(events[#events].kind).toBe("HyperspaceEnd")

		p.lives = 1
		Pilot.control(
			p,
			CFG,
			{ turn = 0, thrust = false, fire = false, hyperspace = true },
			seqDraw({ 50, 60 }),
			emit
		)
		local lost = false
		for _ = 1, CFG.hyperspaceTicks do
			lost = Pilot.clock(p, CFG, fixedDraw(1), function()
				return true
			end, emit)
		end
		t.expect(lost).toBe(true)
		t.expect(p.shipState).toBe("dead")
		t.expect(p.lives).toBe(0)
		t.expect(events[#events].cause).toBe("hyperspace")
	end)

	it("respects shot limit, fires from nose, and waits for clear centre to respawn", function()
		local p = Pilot.new(CFG, 500, 375)
		local events: { Pilot.Event } = {}
		local emit = function(e: Pilot.Event)
			table.insert(events, e)
		end
		for _ = 1, 6 do
			Pilot.control(
				p,
				CFG,
				{ turn = 0, thrust = false, fire = true, hyperspace = false },
				fixedDraw(2),
				emit
			)
		end
		t.expect(#p.shots).toBe(CFG.shotLimit)

		local out = Pilot.lose(p, CFG, "rock", emit)
		t.expect(out).toBe(false)
		t.expect(p.shipState).toBe("dead")
		t.expect(p.timer).toBe(CFG.respawnTicks)

		for _ = 1, CFG.respawnTicks do
			Pilot.clock(p, CFG, fixedDraw(2), function()
				return false
			end, emit)
		end
		t.expect(p.shipState).toBe("dead")
		t.expect(p.timer).toBe(0)

		Pilot.clock(p, CFG, fixedDraw(2), function()
			return true
		end, emit)
		t.expect(p.shipState).toBe("alive")
		t.expect(p.protect).toBe(CFG.protectTicks)
		t.expect(Pilot.exposed(p)).toBe(false)
		t.expect(events[#events].kind).toBe("Respawn")
	end)
end)
