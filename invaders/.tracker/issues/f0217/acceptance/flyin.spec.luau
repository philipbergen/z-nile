--!strict
-- f0217 AC2: the fly-in. Each wave flies in from the field's east side (x = W, player 1's right) along the
-- midline, in single file, one flyer every 2 ticks at 6 units a tick, and peels off alternately to player 1's group
-- and player 2's: each flyer runs west along the midline to its place's column, then turns toward its own player
-- to its place. Places fill column by column from the west, front row first. The fly-in takes about 3 s; the aliens
-- can be shot on the way; no group marches or fires until both are formed (event Formed).
local Classic = require("@logic/Classic")
local Formation = require("@logic/Formation")
local Mystery = require("@logic/Mystery")
local TwoPlayer = require("@logic/TwoPlayer")
local t = require("@tests/lib/t")

local CFG = TwoPlayer.CONFIG
local C = Classic.CONFIG
local W = C.fieldWidth
local D = CFG.fieldDepth

-- the kinds of the events this issue defines, in order (a kind a later issue adds is not this spec's)
local KINDS = {}
for _, k in
	{
		"PlayerFire",
		"BarrierHit",
		"AlienHit",
		"MysteryHit",
		"ExtraLife",
		"GroupClear",
		"WaveClear",
		"CannonHit",
		"GameOver",
	}
do
	KINDS[k] = true
end
for _, k in
	{ "March", "Advance", "AlienFire", "MysteryAppear", "MysteryLeave", "Respawn", "WaveStart", "Formed" }
do
	KINDS[k] = true
end

local function kinds(events: { TwoPlayer.Event }): { string }
	local out = {}
	for _, e in events do
		if KINDS[e.kind] then
			table.insert(out, e.kind)
		end
	end
	return out
end

-- only the events of the kinds this issue defines, in order
local function known(events: { TwoPlayer.Event }): { TwoPlayer.Event }
	local out = {}
	for _, e in events do
		if KINDS[e.kind] then
			table.insert(out, e)
		end
	end
	return out
end

local function has(events: { TwoPlayer.Event }, kind: string, player: number?): boolean
	for _, e in events do
		if e.kind == kind and (player == nil or e.player == player) then
			return true
		end
	end
	return false
end

-- each flyer's place, in the field's frame
local function place(g: TwoPlayer.Match, fl: TwoPlayer.Flyer): (number, number, number, number)
	return TwoPlayer.fieldBox(g, fl.player, Formation.box(g.sides[fl.player].run.formation, fl.row, fl.col))
end

local function clearAll(g: TwoPlayer.Match)
	for _, side in g.sides do
		local f = side.run.formation
		for row = 1, f.config.rows do
			for col = 1, f.config.cols do
				Formation.kill(f, row, col)
			end
		end
	end
	g.flyers = {}
end

local function overlap(a: { number }, b: { number }): boolean
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

return t.spec("f0217 fly-in", function(it)
	it(
		"starts each wave with every alien flying in, 2 ticks apart, to player 1's group and player 2's in turn",
		function()
			local g = TwoPlayer.new(1)
			t.expect(CFG.flyIn.gap).toBe(2)
			t.expect(#g.flyers).toBe(80)
			local seen = { {}, {} }
			for k, fl in g.flyers do
				t.expect(fl.start).toBe((k - 1) * CFG.flyIn.gap)
				t.expect(fl.player).toBe(if k % 2 == 1 then 1 else 2)
				local key = fl.row * 100 + fl.col
				t.expect(seen[fl.player][key]).toBe(nil)
				seen[fl.player][key] = true
			end
			for p = 1, 2 do
				local n = 0
				for _ in seen[p] do
					n += 1
				end
				t.expect(n).toBe(40)
				t.expect(#g.sides[p].waiting).toBe(40)
				for _, w in g.sides[p].waiting do
					t.expect(w).toBe(true)
				end
			end
		end
	)

	it("fills each group column by column from the field's west, front row first", function()
		local g = TwoPlayer.new(1)
		local lastX = { -1, -1 }
		local lastRow = { 0, 0 }
		for _, fl in g.flyers do
			local x0 = place(g, fl)
			local p = fl.player
			if x0 == lastX[p] then
				t.expect(fl.row).toBe(lastRow[p] + 1)
			else
				t.expect(x0 > lastX[p]).toBe(true)
				t.expect(fl.row).toBe(1)
			end
			lastX[p], lastRow[p] = x0, fl.row
		end
	end)

	it(
		"brings them in from the east side along the midline, then turns each toward its own player",
		function()
			t.expect(CFG.flyIn.speed).toBe(6)
			t.expect(CFG.flyIn.lane).toBe(D // 2 - 4)
			local g = TwoPlayer.new(1)
			for _, fl in g.flyers do
				-- before it starts it waits just off the east side, in the lane
				local x0, d0 = TwoPlayer.flyerBox(g, fl)
				t.expect(x0).toBe(W)
				t.expect(d0).toBe(CFG.flyIn.lane)
			end
			local turned, landed = 0, 0
			for _ = 1, 400 do
				local before = table.clone(g.flyers)
				TwoPlayer.step(g, nil)
				for _, fl in before do
					if table.find(g.flyers, fl) == nil then
						-- it left the stream this tick (nothing is shot here): exactly in its place, and that place
						-- no longer waiting
						landed += 1
						local x0, d0, x1, d1, arrived = TwoPlayer.flyerBox(g, fl)
						t.expect({ x0, d0, x1, d1 }).toEqual({ place(g, fl) })
						t.expect(arrived).toBe(true)
						local f = g.sides[fl.player].run.formation
						t.expect(g.sides[fl.player].waiting[(fl.row - 1) * f.config.cols + fl.col])
							.toBe(false)
					end
				end
				for _, fl in g.flyers do
					local x0, d0, x1, d1 = TwoPlayer.flyerBox(g, fl)
					local px0, pd0 = place(g, fl)
					t.expect(x1 - x0).toBe(12)
					t.expect(d1 - d0).toBe(8)
					if d0 == CFG.flyIn.lane then
						-- on the midline, heading west, never past its column
						t.expect(x0 >= px0 and x0 <= W).toBe(true)
						t.expect((W - x0) % CFG.flyIn.speed == 0 or x0 == px0).toBe(true)
					else
						-- turned: in its column, between the midline and its place, on its own player's side
						turned += 1
						t.expect(x0).toBe(px0)
						if fl.player == 1 then
							t.expect(d0 < CFG.flyIn.lane and d0 > pd0).toBe(true)
						else
							t.expect(d0 > CFG.flyIn.lane and d0 < pd0).toBe(true)
						end
					end
				end
				if g.phase == "playing" then
					break
				end
			end
			t.expect(turned > 0).toBe(true)
			t.expect(landed).toBe(80)
			t.expect(g.phase).toBe("playing")
		end
	)

	it("keeps them in single file along the midline, and apart once they turn", function()
		-- (at a turn the flyer behind may touch the turning one's corner for a tick: no rule reads it)
		local g = TwoPlayer.new(1)
		for _ = 1, 400 do
			TwoPlayer.step(g, nil)
			local boxes: { { number } } = {}
			for _, fl in g.flyers do
				local x0, d0, x1, d1 = TwoPlayer.flyerBox(g, fl)
				if x0 < W and (d0 == CFG.flyIn.lane or d1 <= CFG.flyIn.lane or d0 >= CFG.flyIn.lane + 8) then
					for _, b in boxes do
						t.expect(overlap(b, { x0, d0, x1, d1 })).toBe(false)
					end
					table.insert(boxes, { x0, d0, x1, d1 })
				end
			end
			if g.phase == "playing" then
				break
			end
		end
	end)

	it("forms both groups in about 3 s, every alien in its place, in every wave", function()
		local g = TwoPlayer.new(1)
		for wave = 1, 9 do
			t.expect(g.wave).toBe(wave)
			t.expect(g.phase).toBe("flyin")
			local ticks, formed = 0, nil
			while g.phase == "flyin" and ticks < 1000 do
				ticks += 1
				local e = known(TwoPlayer.step(g, nil))
				if has(e, "Formed") then
					formed = e
				end
			end
			-- 2.5 s to 3.5 s at 60 ticks a second
			t.expect(ticks >= 2.5 * Classic.TICK_RATE and ticks <= 3.5 * Classic.TICK_RATE).toBe(true)
			t.expect(formed ~= nil).toBe(true)
			for _, ev in formed :: { TwoPlayer.Event } do
				if ev.kind == "Formed" then
					t.expect(ev.wave).toBe(wave)
				end
			end
			t.expect(g.phase).toBe("playing")
			t.expect(#g.flyers).toBe(0)
			for p = 1, 2 do
				local f = g.sides[p].run.formation
				t.expect(f.live).toBe(40)
				t.expect(f.d).toBe(Classic.waveDepth(wave))
				t.expect(f.x).toBe(50)
				for _, w in g.sides[p].waiting do
					t.expect(w).toBe(false)
				end
			end
			clearAll(g)
			while g.phase ~= "flyin" do
				TwoPlayer.step(g, nil)
			end
		end
	end)

	it("lets either player shoot the aliens as they fly in, for the shooter's score", function()
		-- every shooter at every group: flyer 1 is player 1's, flyer 2 player 2's, both still on the midline
		for _, shooter in { 1, 2 } do
			for _, which in { 1, 2 } do
				local g = TwoPlayer.new(1)
				for _ = 1, 8 do
					TwoPlayer.step(g, nil)
				end
				local fl = g.flyers[which]
				local x0, d0 = TwoPlayer.flyerBox(g, fl)
				t.expect(d0).toBe(CFG.flyIn.lane)
				-- a shot two units short of the lane, from the shooter's side, where the flyer will be after its
				-- next move (shots are in the shooter's frame; the flyers in the field's)
				local fx = x0 - CFG.flyIn.speed + 5
				local fd = if shooter == 1 then CFG.flyIn.lane - 2 else CFG.flyIn.lane + 8 + 1
				local sx, sd = TwoPlayer.toField(g, shooter, fx, fd)
				g.sides[shooter].run.shot = { x = sx, d = sd }
				local e = known(TwoPlayer.step(g, nil))
				t.expect(kinds(e)).toEqual({ "AlienHit" })
				t.expect(e[1].player).toBe(fl.player)
				t.expect(e[1].shooter).toBe(shooter)
				t.expect(e[1].row).toBe(fl.row)
				t.expect(e[1].col).toBe(fl.col)
				t.expect(e[1].points).toBe(10)
				t.expect(g.sides[shooter].run.score).toBe(10)
				t.expect(g.sides[3 - shooter].run.score).toBe(0)
				t.expect(g.sides[shooter].run.shot).toBe(nil)
				t.expect(g.sides[fl.player].run.formation.live).toBe(39)
				t.expect(table.find(g.flyers, fl)).toBe(nil)
				while g.phase == "flyin" do
					TwoPlayer.step(g, nil)
				end
				t.expect(Formation.isAlive(g.sides[fl.player].run.formation, fl.row, fl.col)).toBe(false)
				t.expect(g.sides[fl.player].run.formation.live).toBe(39)
			end
		end
	end)

	it("lets either player's shot through a place of either group whose alien is still on its way", function()
		for _, shooter in { 1, 2 } do
			for _, q in { 1, 2 } do
				local g = TwoPlayer.new(1)
				TwoPlayer.step(g, nil)
				local f = g.sides[q].run.formation
				-- the group's front-left place in the field, crossed from the shooter's side
				local bx0, bd0, _, bd1 = TwoPlayer.fieldBox(g, q, Formation.box(f, 1, 1))
				local fd = if shooter == 1 then bd0 - 1 else bd1
				local sx, sd = TwoPlayer.toField(g, shooter, bx0 + 5, fd)
				g.sides[shooter].run.shot = { x = sx, d = sd }
				local e = known(TwoPlayer.step(g, nil))
				t.expect(has(e, "AlienHit")).toBe(false)
				t.expect(f.live).toBe(40)
				local shot = g.sides[shooter].run.shot
				t.expect(shot ~= nil).toBe(true)
				t.expect((shot :: Classic.Shot).d).toBe(sd + C.shotSpeed)
			end
		end
	end)

	it("holds every march, alien shot and ship until both groups are formed, then lets them go", function()
		local g = TwoPlayer.new(1)
		local x, d = g.sides[1].run.formation.x, g.sides[1].run.formation.d
		local events = {}
		while g.phase == "flyin" do
			for p = 1, 2 do
				g.sides[p].run.reloadElapsed = 1000
				g.sides[p].run.formation.elapsed = 1000
			end
			g.mystery.elapsed = Mystery.CLASSIC.every
			for _, e in TwoPlayer.step(g, nil) do
				table.insert(events, e)
			end
		end
		t.expect(has(events, "March")).toBe(false)
		t.expect(has(events, "Advance")).toBe(false)
		t.expect(has(events, "AlienFire")).toBe(false)
		t.expect(has(events, "MysteryAppear")).toBe(false)
		local ks = kinds(events)
		t.expect(ks[#ks]).toBe("Formed")
		for p = 1, 2 do
			t.expect(g.sides[p].run.formation.x).toBe(x)
			t.expect(g.sides[p].run.formation.d).toBe(d)
			t.expect(#g.sides[p].run.bombs).toBe(0)
		end
		local after = TwoPlayer.step(g, nil)
		for p = 1, 2 do
			t.expect(has(after, "March", p)).toBe(true)
			t.expect(has(after, "AlienFire", p)).toBe(true)
		end
		t.expect(has(after, "MysteryAppear")).toBe(true)
	end)

	it("lets the cannons move and fire during the fly-in", function()
		local g = TwoPlayer.new(1)
		local e = TwoPlayer.step(g, { { move = 1, fire = true }, { move = 1, fire = true } })
		t.expect(g.phase).toBe("flyin")
		for p = 1, 2 do
			t.expect(g.sides[p].run.cannon).toBe(C.cannonStart + 1)
			t.expect(g.sides[p].run.shot ~= nil).toBe(true)
			t.expect(has(e, "PlayerFire", p)).toBe(true)
		end
	end)
end)
