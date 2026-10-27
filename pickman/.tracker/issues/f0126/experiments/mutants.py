# f0126 prep: the mutation check (z-design step 4). It never touches the tree it is run from: it clones this
# repository into a fresh folder under $TMPDIR, checks out BASE, applies prototype.patch and copies the acceptance
# specs in, applies each mutant to that clone's pickman/src, runs the mutant's spec file there, and deletes the clone.
# Usage, from anywhere: python3 <this file> [ids...], each a Rules and mutants row id (R4, F5b) or a group ending in * (T4*)
import os, shutil, subprocess, sys, tempfile

BASE = "dc6c8bf1"  # f0110's prototype (proto-f0110) at f0126's re-prep; base.patch then adds f0146's prototype (proto-f0146 95f005af: Pad and the controller map) and f0109's (proto-f0109's working tree on ee121ddc as of f0109's prep 4cc59ded, with its acceptance specs and game-design.md edit: the wall colours in View, the edible repaint, wallColorOf, lemon Inky). F0109_SRC and F0109_SPECS are the SHA-256 of that working tree's `git diff -- pickman/src pickman/tests/lib pickman/.tracker/game-design.md` and of f0109's prep acceptance specs concatenated (the files that will be promoted; design review 010), when base.patch was cut: while the proto-f0109 worktree exists the run refuses if either has moved (design review 009 F1), so the base is cut again first
F0109_SRC = "37bf5875258facda0265311a383f33fccebc5b8951da5517cc687afe90d56c04"
F0109_SPECS = "112f33718baacab348c93f136cbd7bf3e61b0beeafd2ba3906d4dbe35662b464"
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0126-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "pickman")

def inside_clone(path):
    real = os.path.realpath(path)
    return real.startswith(TMP + os.sep)

A = '.tracker/issues/f0126/acceptance/'
L = 'src/shared/Logic/'
C = 'src/client/'
M=[
# id, file, old, new, spec
("R1 edge interior", L+'Picks/init.luau', 'if x < 1 or y < 1 or', 'if x < 0 or y < 0 or', 'picks'),
("R2 diagonals", L+'Picks/init.luau', '''			local k = Maze.kind(m, { x = x + dx, y = y + dy })
			if k == "door" or k == "house" then''', '''			local k = Maze.kind(m, { x = x + dx, y = y + dy })
			if (k == "door" or k == "house") and (dx == 0 or dy == 0) then''', 'picks'),
("R3 walkable neighbour", L+'Picks/init.luau', '''			return true
		end
	end
	return false
end

function Picks.isMarked''', '''			return true
		end
	end
	return true
end

function Picks.isMarked''', 'picks'),
("R4 three marked", L+'Picks/init.luau', 'Picks.MARKED = 3', 'Picks.MARKED = 2', 'pick'),
("R5 seeded roll", L+'Picks/init.luau', 'local tile = options[roll(p, #options)]', 'local tile = options[1]', 'picks'),
("R6 top up", L+'Picks/init.luau', 'while #p.marked < Picks.MARKED do', 'while #p.marked == 0 do', 'picks'),
("R7 beside order", L+'Picks/init.luau', '{ heading, Maze.left(heading), Maze.right(heading), Maze.opposite(heading) }', '{ heading, Maze.right(heading), Maze.left(heading), Maze.opposite(heading) }', 'picks'),
("R8 ceil", L+'Picks/init.luau', 'math.ceil(Picks.PACES * Movement.UNITS', 'math.floor(Picks.PACES * Movement.UNITS', 'picks'),
("R9 fast ceil", L+'Picks/init.luau', 'math.ceil(whole / 2)', 'math.floor(whole / 2)', 'picks'),
("R10 uniform", L+'Picks/init.luau', 'return BOONS[roll(p, #BOONS)]', 'return BOONS[roll(p, #BOONS - 1)]', 'picks'),
("R11 open edge", L+'Maze/init.luau', 'if tile.x == 0 or tile.y == 0 or tile.x == m.width - 1 or tile.y == m.height - 1 then', 'if false then', 'maze'),
("R12 open copies", L+'Maze/init.luau', 'local grid = table.clone(gridOf(m))', 'local grid = gridOf(m)', 'maze'),
("S1 beside not ahead only", L+'Session/init.luau', 'local beside = Picks.wallBeside(member.picks, mazeOf(s, member), centre, member.move.heading)', 'local beside = Picks.wallBeside(member.picks, mazeOf(s, member), centre, member.move.heading) if beside and beside.y == 3 then beside = nil end', 'pick'),
("S2 exact duration", L+'Session/init.luau', 'if pick and s.tick >= pick.started + pick.ticks then', 'if pick and s.tick > pick.started + pick.ticks then', 'pick'),
("S3 re-mark", L+'Session/init.luau', '	Picks.mark(member.picks, mazeOf(s, member))\n	if pick.fast', '	if pick.fast', 'pick'),
("S4 resume after", L+'Session/init.luau', '''	end
	Movement.resume(mazeOf(s, member), member.move)
end''', '''	end
end''', 'pick'),
("S5 key wastes", L+'Session/init.luau', 'if member.pick and #queue > 0 then', 'if false then', 'pick'),
("S6 hop wastes", L+'Session/init.luau', 'stopPick(s, member, id, "hopped", out)', '', 'pick'),
("S7 finish first", L+'Session/init.luau', 'if pick and s.tick >= pick.started + pick.ticks then\n			finishPick(s, id, member, out)\n		end', 'if pick and s.tick >= pick.started + pick.ticks and #queue == 0 then\n			finishPick(s, id, member, out)\n		end', 'pick'),
("S8 not during hop", L+'Session/init.luau', 'and not hopping and #queue == 0 then', 'and #queue == 0 then', 'pick'),
("S9 lapses", L+'Session/init.luau', '		elseif member.armed > 0 then\n			member.armed -= 1', '		elseif member.armed > 0 then\n			member.armed -= 0', 'pick'),
("S10 pause forgets", L+'Session/init.luau', '			stopPick(s, member, id, "pause", out)\n			member.armed = 0', '			stopPick(s, member, id, "pause", out)', 'pick'),
("S11 death wastes", L+'Session/init.luau', '			stopPick(s, member, id, "pause", out)', '			', 'pick'),
("S12 holes stay on death", L+'Session/init.luau', '				if e.reason ~= "respawn" then\n					Pellets.reset(member.pellets) -- a new level or a new run: every pellet is back\n					freshMaze(s, member)\n				end', '				freshMaze(s, member)\n				if e.reason ~= "respawn" then\n					Pellets.reset(member.pellets) -- a new level or a new run: every pellet is back\n				end', 'pick'),
("S13 fresh on level", L+'Session/init.luau', '					Pellets.reset(member.pellets) -- a new level or a new run: every pellet is back\n					freshMaze(s, member)', '					Pellets.reset(member.pellets) -- a new level or a new run: every pellet is back', 'pick'),
("S14 ignore during pick", L+'Session/init.luau', '		if member.pick == nil then\n			member.armed = s.config.movement.turnBufferTicks\n		end', '		member.armed = s.config.movement.turnBufferTicks', 'pick'),
("S15 resume on waste", L+'Session/init.luau', '		table.insert(out, { kind = "PickStopped", player = id, reason = reason })\n		Movement.resume(mazeOf(s, member), member.move)', '		table.insert(out, { kind = "PickStopped", player = id, reason = reason })', 'pick'),
("B1 long hop", L+'Session/init.luau', 'member.hopTicks = if member.longHops then Hop.LONG_TICKS else Hop.TICKS', 'member.hopTicks = Hop.TICKS', 'boons'),
("B2 airborne length", L+'Session/init.luau', 'local airborne = Hop.airborne(member.hopped, s.tick, member.hopTicks)', 'local airborne = Hop.airborne(member.hopped, s.tick)', 'boons'),
("B3 long ends", L+'Session/init.luau', '	member.longHops = false\n	Picks.reset', '	Picks.reset', 'boons'),
("B4 fast spent", L+'Session/init.luau', '		member.picks.fast -= 1', '		member.picks.fast -= 0', 'boons'),
("B5 fast kept on waste", L+'Session/init.luau', '	local fast = member.picks.fast > 0\n', '	local fast = member.picks.fast > 0\n	if fast then member.picks.fast -= 1 end\n', 'boons'),
("B6 pill", L+'Session/init.luau', 'if boon == "longpill" then Picks.LONG_PILL_FACTOR else 1', 'if boon == "longpill" then Picks.LONG_PILL_FACTOR else 0', 'boons'),
("B7 longpill", L+'Picks/init.luau', 'Picks.LONG_PILL_FACTOR = 2', 'Picks.LONG_PILL_FACTOR = 1', 'boons'),
("B8 shot", L+'Session/init.luau', 'if Blaster.gain(member.blaster) then', 'if Blaster.drop(member.blaster) then', 'boons'),
("B9 pellets", L+'Session/init.luau', '		Pellets.reset(member.pellets)\n		table.insert(out, { kind = "PelletsBack"', '		table.insert(out, { kind = "PelletsBack"', 'boons'),
("B10 pill same step", L+'Session/init.luau', '		local before = #out\n		-- a pick that has stood', '		-- a pick that has stood', 'classic'),
("B11 gain no roll", L+'Blaster/init.luau', '''	if b.shots >= Blaster.MAX_SHOTS then
		return false
	end
	b.shots += 1
	return true''', '''	b.rng = (b.rng * 16807) % 2147483647
	if b.shots >= Blaster.MAX_SHOTS then
		return false
	end
	b.shots += 1
	return true''', 'boons'),
("P1 halt clears", L+'Movement/init.luau', '	s.leftCentre = false\n	clearBuffer(s)\nend', '	s.leftCentre = false\nend', 'parts'),
("P2 resume wall", L+'Movement/init.luau', 's.moving = open(m, s.tile, s.heading)\n	end\nend', 's.moving = true\n	end\nend', 'parts'),
("P3 hop default", L+'Hop/init.luau', '	return Hop.TICKS\nend', '	return Hop.LONG_TICKS\nend', 'parts'),
("P4 bad length", L+'Hop/init.luau', 'if finite(ticks) and (ticks :: number) >= 1 and ticks == math.floor(ticks :: number) then', 'if finite(ticks) and (ticks :: number) > 0 then', 'parts'),
("P5 power factor", L+'Game/init.luau', '* (factor or 1)', '* 1', 'parts'),
("P6 useMaze", L+'Ghosts/init.luau', '	set.maze = m\nend', 'end', 'parts'),
("P7 walls marked", L+'View/init.luau', 'if wall and gold[ty * m.width + tx] then', 'if false then', 'parts'),
("P8 margin copies", L+'View/init.luau', 'if wall and gold[ty * m.width + tx] then', 'if wall and x >= 0 and x < m.width and gold[ty * m.width + tx] then', 'parts'),
("P9 frameMaze", L+'View/init.luau', 'local m = Maze.opened(Maze.layout(frame.maze), opened)', 'local m = Maze.layout(frame.maze)', 'parts'),
("P10 wallsKey lists", L+'View/init.luau', '		table.insert(parts, "|")\n', '', 'parts'),
("P11 progress clamp", L+'Hud/init.luau', 'return math.clamp((shownTick - pick.started) / math.max(1, pick.ticks), 0, 1)', 'return (shownTick - pick.started) / math.max(1, pick.ticks)', 'parts'),
("P12 banner window", L+'Hud/init.luau', 'tick >= boon.tick + Hud.BOON_TICKS', 'tick > boon.tick + Hud.BOON_TICKS', 'parts'),
("P13 F key", L+'View/init.luau', '	F = "Pick",', '	G = "Pick",', 'parts'),
("A1 Controls wire", C+'Controls.luau', 'elseif action == "Pick" then\n\t\t\t\tintent:FireServer(View.PICK_INTENT)', 'elseif action == "Pick" then\n\t\t\t\tintent:FireServer("Pick")', 'adapters'),
("A2 Camera length", C+'Camera.luau', 'Hop.rise(hopped, shown, hopTicks)', 'Hop.rise(hopped, shown)', 'adapters'),
("A3 Main length", C+'Main.client.luau', '	Camera.hopTicks(frame.hopTicks)\n', '', 'adapters'),
("A4 radar maze", C+'Main.client.luau', 'DangerHud.push(snap, View.frameMaze(frame))', 'DangerHud.push(snap, Maze.layout(snap.maze))', 'adapters'),
("A5 beam maze", C+'BlastView.luau', 'draw(View.frameMaze(frame), shot.from, shot.heading)', 'draw(Maze.layout(frame.maze), shot.from, shot.heading)', 'adapters'),
("A7 HUD pick", C+'Main.client.luau', '	HudView.pick(frame.pick, frame.boon, frame.tick)\n', '', 'adapters'),
("A8 rewall", C+'Main.client.luau', 'MazeView.rewall(model, View.frameMaze(frame),', 'MazeView.rewall(model, Maze.layout(frame.maze),', 'adapters'),
]

NEW=[
("F1 contact while picking", L+'Session/init.luau', '	if kill then\n		stopPick(s, member, id, "caught", out)', '	if kill and member.pick == nil then\n		stopPick(s, member, id, "caught", out)', 'ghosts'),
("F1b ghosts freeze while picking", L+'Session/init.luau', '		if member.ghosts then\n			stepGhosts(', '		if member.ghosts and member.pick == nil then\n			stepGhosts(', 'ghosts'),
("F1c caught reason", L+'Session/init.luau', 'stopPick(s, member, id, "caught", out)', 'stopPick(s, member, id, "pause", out)', 'ghosts'),
("F1d eating wastes", L+'Session/init.luau', '	for _, name: Ghosts.Name in eaten do\n', '	if #eaten > 0 then\n		stopPick(s, member, id, "caught", out)\n	end\n	for _, name: Ghosts.Name in eaten do\n', 'eaten'),
("F2 move in the plain maze", L+'Session/init.luau', 'Movement.step(mazeOf(s, member), member.move, queue, config)', 'Movement.step(s.maze, member.move, queue, config)', 'pick'),
("F2b ghosts not told", L+'Session/init.luau', "\t\tmaze = mazeOf(s, member), -- the ghosts walk the member's maze, holes and all\n", '', 'ghosts'),
("F2c shot in the plain maze", L+'Session/init.luau', 'Blaster.target(mazeOf(s, member), from, heading, targets)', 'Blaster.target(s.maze, from, heading, targets)', 'adapters'),
("F3 new run keeps holes", L+'Session/init.luau', '	if ok then\n		freshMaze(s, member)', '	if ok then\n		member.longHops = false', 'pick'),
("F3b long hops past a level", L+'Session/init.luau', '	member.longHops = false\n	Picks.reset', '	Picks.reset', 'boons'),
("F3c new run keeps fast", L+'Session/init.luau', '		member.picks.fast = 0\n', '', 'boons'),
("F3d new run keeps boon", L+'Session/init.luau', '		member.boon = nil\n		teleport', '		teleport', 'boons'),
("F3e level drops fast", L+'Session/init.luau', '	member.longHops = false\n	Picks.reset', '	member.longHops = false\n	member.picks.fast = 0\n	Picks.reset', 'boons'),
("F4 cool-down default", L+'Session/init.luau', 'Hop.canStart(member.hopped, s.tick, member.hopTicks)', 'Hop.canStart(member.hopped, s.tick)', 'boons'),
("F4b hopping default", L+'Session/init.luau', 'local hopping = member.hopped ~= nil and s.tick < (member.hopped :: number) + member.hopTicks', 'local hopping = member.hopped ~= nil and s.tick < (member.hopped :: number) + Hop.TICKS', 'boons'),
("F5 keys do not stop the stop", L+'Session/init.luau', 'and not hopping and #queue == 0 then', 'and not hopping then', 'pick'),
("F5b lifetime 40", L+'Session/init.luau', '			member.armed = s.config.movement.turnBufferTicks', '			member.armed = 40', 'pick'),
("F5c lifetime 23", L+'Session/init.luau', '			member.armed = s.config.movement.turnBufferTicks', '			member.armed = 23', 'pick'),
("F6 dots only", L+'Session/init.luau', '		Pellets.reset(member.pellets)\n		table.insert(out, { kind = "PelletsBack"', '		local eatenPower = {}\n		for _, slot in Pellets.slots(member.pellets.maze) do\n			if slot.kind == "power" and Pellets.at(member.pellets, slot) == nil then\n				table.insert(eatenPower, slot)\n			end\n		end\n		Pellets.reset(member.pellets)\n		for _, slot in eatenPower do\n			Pellets.eat(member.pellets, slot)\n		end\n		table.insert(out, { kind = "PelletsBack"', 'boons'),
("F6b house fed", L+'Session/init.luau', '		table.insert(out, { kind = "PelletsBack", player = id })', '		table.insert(out, { kind = "PelletsBack", player = id })\n		table.insert(out, { kind = "PelletEaten", player = id, item = "pellet", points = 0 })', 'boons'),
]
NEW2 = [
("R2a Controls requires Picks", C+'Controls.luau', 'local Movement = require("@game/ReplicatedStorage/Shared/Logic/Movement")\n', 'local Movement = require("@game/ReplicatedStorage/Shared/Logic/Movement")\nlocal Picks = require("@game/ReplicatedStorage/Shared/Logic/Picks")\nlocal _ = Picks\n', 'adapters'),
("R2b the ghosts walk the shared maze", L+'Session/init.luau', '\t\tmaze = mazeOf(s, member), -- the ghosts walk', '\t\tmaze = s.maze, -- the ghosts walk', 'closed'),
("R2c new marks rolled on the holed maze", L+'Session/init.luau', '\tmember.opened = {}\n\tmember.longHops = false\n\tPicks.reset(member.picks, mazeOf(s, member))', '\tmember.longHops = false\n\tPicks.reset(member.picks, mazeOf(s, member))\n\tmember.opened = {}', 'pick'),
("R2d old marks kept", L+'Session/init.luau', '\tmember.longHops = false\n\tPicks.reset(member.picks, mazeOf(s, member))\nend', '\tmember.longHops = false\nend', 'pick'),
("R2e fire wastes the pick", L+'Session/init.luau', '		if fire then\n			shoot(s, id, member, fire, out)', '		if fire then\n			stopPick(s, member, id, "moved", out)\n			shoot(s, id, member, fire, out)', 'pick'),
("R2f a repeat does not restart", L+'Session/init.luau', '		if member.pick == nil then\n			member.armed = s.config.movement.turnBufferTicks', '		if member.pick == nil and member.armed == 0 then\n			member.armed = s.config.movement.turnBufferTicks', 'pick'),
("R2g a death says moved", L+'Session/init.luau', '			stopPick(s, member, id, "pause", out)', '			stopPick(s, member, id, "moved", out)', 'pick'),
("R2h ShotGained always", L+'Session/init.luau', '		if Blaster.gain(member.blaster) then', '		Blaster.gain(member.blaster)\n		do', 'boons'),
("R2i frame fast always false", L+'Session/init.luau', 'fast = (s.members[id].pick :: Pick).fast,', 'fast = false,', 'boons'),
]
NEW3 = [
("R3a a Pick counts toward the limit", L+'Session/init.luau', '\tif pick then\n\t\t-- a pick request', '\tif pick and #member.queue >= s.config.maxIntentsPerTick then\n\t\treturn false, "rate limited"\n\tend\n\tif pick then\n\t\t-- a pick request', 'pick'),
("R3b a pick at blue ghosts' speed", L+'Session/init.luau', 'Levels.ghostSpeed(s.config.movement.speed, member.play.level, "normal", tuning)', 'Levels.ghostSpeed(s.config.movement.speed, member.play.level, if member.play.frightened > 0 then "frightened" else "normal", tuning)', 'boons'),
("R3c a new run keeps the marks", L+'Session/init.luau', '\tif ok then\n\t\tfreshMaze(s, member)', '\tif ok then\n\t\tmember.opened = {}\n\t\tmember.longHops = false', 'pick'),
("R3d the ghosts lose the holes after a death", L+'Session/init.luau', '\t\tmaze = mazeOf(s, member), -- the ghosts walk', '\t\tmaze = if member.play.lives < (s.config.play or Game.IMMEDIATE_CONFIG).lives then s.maze else mazeOf(s, member), -- the ghosts walk', 'closed'),
("R3e the pick bar low on the screen", L+'Hud/init.luau', 'Hud.PICK_BAR_AT = 0.4', 'Hud.PICK_BAR_AT = 0.62', 'parts'),
("R3f the banner under the score", L+'Hud/init.luau', 'Hud.BOON_AT = 0.3', 'Hud.BOON_AT = 0.04', 'parts'),
("R3g the step's maze ignored", L+'Ghosts/init.luau', '\tif input.maze then\n\t\tGhosts.useMaze(set, input.maze)\n\tend\n', '', 'parts'),
("R3h a death drops the fast picks", L+'Session/init.luau', '\t\t\t\t\tfreshMaze(s, member)\n\t\t\t\tend', '\t\t\t\t\tfreshMaze(s, member)\n\t\t\t\telse\n\t\t\t\t\tmember.picks.fast = 0\n\t\t\t\tend', 'boons'),
("R3i a death drops the boon", L+'Session/init.luau', '\t\t\t\t\tfreshMaze(s, member)\n\t\t\t\tend', '\t\t\t\t\tfreshMaze(s, member)\n\t\t\t\telse\n\t\t\t\t\tmember.boon = nil\n\t\t\t\tend', 'boons'),
("R3j a death ends the long hops", L+'Session/init.luau', '\t\t\t\t\tfreshMaze(s, member)\n\t\t\t\tend', '\t\t\t\t\tfreshMaze(s, member)\n\t\t\t\telse\n\t\t\t\t\tmember.longHops = false\n\t\t\t\tend', 'boons'),
]
NEW4 = [
("T4a a new level drops the boon", L+'Session/init.luau', '\tmember.opened = {}\n\tmember.longHops = false\n', '\tmember.opened = {}\n\tmember.longHops = false\n\tmember.boon = nil\n', 'boons'),
("T4b a pick at level 1's speed always", L+'Session/init.luau', 'Levels.ghostSpeed(s.config.movement.speed, member.play.level, "normal", tuning)', 'Levels.ghostSpeed(s.config.movement.speed, 1, "normal", tuning)', 'boons'),
("T4c MazeView marks nothing", C+'MazeView.luau', 'for _, r in View.walls(m, nil, marked) do', 'for _, r in View.walls(m, nil, nil) do', 'views'),
("T4d HudView never lays the bar out", C+'HudView.luau', '\t\tpickBar.Position = UDim2.fromOffset(barBox.x, barBox.y)\n\t\tpickBar.Size = UDim2.fromOffset(barBox.w, barBox.h)\n\t\tbanner.Position = UDim2.fromOffset(boonBox.x, boonBox.y)\n\t\tbanner.Size = UDim2.fromOffset(boonBox.w, boonBox.h)\n', '', 'views'),
("T4e HudView moves the bar off its box", C+'HudView.luau', 'pickBar.Position = UDim2.fromOffset(barBox.x, barBox.y)', 'pickBar.Position = UDim2.fromOffset(barBox.x, barBox.y + 30)', 'views'),
("T4f HudView boxes without the inset", C+'HudView.luau', 'local barBox, boonBox = Hud.pickBox(l), Hud.boonBox(l)', 'local barBox, boonBox = Hud.pickBox(Hud.layout(sw, sh)), Hud.boonBox(Hud.layout(sw, sh))', 'views'),
("T4g Main rebuilds the walls every frame", C+'Main.client.luau', 'if model and key ~= wallsKey then', 'if model then', 'views'),
]
NEW5 = [
("T5a HudView places the bar only once", C+'HudView.luau', '\tif pickBar and banner then\n', '\tif pickBar and banner and pickBar.Position == nil then\n', 'views'),
("T5b Main rebuilds only for the holes", C+'Main.client.luau', '\tlocal key = View.wallsKey(frame)', '\tlocal key = frame.maze .. #(if frame.walls then frame.walls.opened else {})', 'views'),
]
NEW6 = [
("U1 PICK right of JUMP", L+'Touch/init.luau', '\treturn { x = fire.x - box.margin - fire.w, y = fire.y, w = fire.w, h = fire.h }', '\tlocal hop = Touch.hopRect(box)\n\treturn { x = hop.x + hop.w + box.margin, y = fire.y, w = fire.w, h = fire.h }', 'touch'),
("U2 no pick zone", L+'Touch/init.luau', '\tif inside(pick, x, y) then\n\t\treturn "pick"\n\tend\n', '', 'touch'),
("U3 the pick on the lift", L+'Touch/init.luau', '\t\t\t\telseif zone == "pick" then\n\t\t\t\t\ttable.insert(effects, { kind = "pick" })\n', '', 'touch'),
("U4 Controls drops the pick effect", C+'Controls.luau', '\t\t\telseif effect.kind == "pick" then\n\t\t\t\tintent:FireServer(View.PICK_INTENT) -- the PICK button (f0126), as F and Y send it\n', '', 'controls'),
("U5 Controls hands no pick rectangle", C+'Controls.luau', '\t\t\tpick = placed and placed.pick,\n', '', 'controls'),
("U6 Y not bound", L+'Pad/init.luau', '\tButtonY = "Pick", -- the wall pick (f0126; user, 2026-10-25: "Y / triangle")\n', '', 'controls'),
("U7 the PICK frame not placed", C+'HudView.luau', '\tplace(pickButton, placed.pick, l.textSize)\n', '', 'controls'),
("U8 the PICK frame on every screen", C+'HudView.luau', 'pickButton = button("Pick", "PICK", GOLD, gui)', 'pickButton = button("Pick", "PICK", GOLD, gui)\n\tif pickButton then\n\t\tpickButton.frame.Visible = true\n\tend', 'controls'),
("U9 the PICK button fires", C+'Controls.luau', 'intent:FireServer(View.PICK_INTENT) -- the PICK button (f0126), as F and Y send it', 'fire() -- the PICK button (f0126), as F and Y send it', 'controls'),
("U11 the PICK frame without the inset", C+'HudView.luau', '\tplace(pickButton, placed.pick, l.textSize)\n', '\tplace(pickButton, Touch.buttons(Hud.layout(sw, sh)).pick, l.textSize)\n', 'controls'),
("U12 the PICK frame placed once", C+'HudView.luau', '\tplace(pickButton, placed.pick, l.textSize)\n', '\tif pickButton and pickButton.frame.Position == nil then\n\t\tplace(pickButton, placed.pick, l.textSize)\n\tend\n', 'controls'),
("U13 every tap on the right sends the pick", C+'Controls.luau', '\t\t\telseif effect.kind == "look" then\n', '\t\t\telseif effect.kind == "look" then\n\t\t\t\tintent:FireServer(View.PICK_INTENT)\n', 'controls'),
("U14 PICK checked before the snap, FIRE and JUMP", L+'Touch/init.luau', '\tif inside(snap, x, y) then\n\t\treturn "snap"\n\tend\n', '\tif inside(pick, x, y) then\n\t\treturn "pick"\n\tend\n\tif inside(snap, x, y) then\n\t\treturn "snap"\n\tend\n', 'touch'),
("U15 a closed rectangle", L+'Touch/init.luau', '\tif inside(pick, x, y) then\n\t\treturn "pick"\n\tend\n', '\tif pick and x >= pick.x and y >= pick.y and x <= pick.x + pick.w and y <= pick.y + pick.h then\n\t\treturn "pick"\n\tend\n', 'touch'),
("U16 a missing rectangle picks at the old place", C+'Controls.luau', '\t\t\tpick = placed and placed.pick,\n', '\t\t\tpick = (placed and placed.pick) or { x = 520, y = 300, w = 70, h = 70 },\n', 'controls'),
("U17 F and Y do not pick on the press", C+'Controls.luau', '\t\t\telseif action == "Pick" then\n\t\t\t\tintent:FireServer(View.PICK_INTENT)\n', '\t\t\telseif action == "Pick" then\n', 'controls'),
("U18 the PICK frame takes input", C+'HudView.luau', 'pickButton = button("Pick", "PICK", GOLD, gui)', 'pickButton = button("Pick", "PICK", GOLD, gui)\n\tif pickButton then\n\t\tpickButton.frame.Active = true\n\tend', 'controls'),
("U19 the PICK frame captioned FIRE", C+'HudView.luau', 'button("Pick", "PICK", GOLD, gui)', 'button("Pick", "FIRE", GOLD, gui)', 'controls'),
("U20 the PICK frame cyan", C+'HudView.luau', 'button("Pick", "PICK", GOLD, gui)', 'button("Pick", "PICK", CYAN, gui)', 'controls'),
("U21 the pick bar down among the buttons", L+'Hud/init.luau', 'Hud.PICK_BAR_AT = 0.4', 'Hud.PICK_BAR_AT = 0.85', 'touch'),
("V1 marked walls not gold", L+'View/init.luau', '\t\telseif marked then View.WALL_MARKED_COLOR\n', '', 'parts'),
("V2 marked walls green while edible", L+'View/init.luau', '\t\telseif marked then View.WALL_MARKED_COLOR\n\t\telseif edible then View.WALL_EDIBLE_COLOR\n', '\t\telseif edible then View.WALL_EDIBLE_COLOR\n\t\telseif marked then View.WALL_MARKED_COLOR\n', 'parts'),
("V3 the repaint skips the marked walls", C+'MazeView.luau', 'if (child.Name == "Wall" or child.Name == "MarkedWall") and child:IsA("BasePart") then\n\t\t\tchild.Color = wallColorOf(model, child.Name == "MarkedWall")', 'if child.Name == "Wall" and child:IsA("BasePart") then\n\t\t\tchild.Color = wallColorOf(model, false)', 'views'),
("V6 the pick timed by the untuned ghosts", L+'Session/init.luau', 'local ghost = Levels.ghostSpeed(s.config.movement.speed, member.play.level, "normal", tuning)', 'local ghost = Levels.ghostSpeed(s.config.movement.speed, member.play.level, "normal")', 'classic'),
("V7 the walls in a sub-model", C+'MazeView.luau', '\t\tif r.marked == true then\n\t\t\tpart(model, "MarkedWall"', '\t\tlocal sub = model:FindFirstChild("Walls") or Instance.new("Model")\n\t\tsub.Name = "Walls"\n\t\tsub.Parent = model\n\t\tif r.marked == true then\n\t\t\tpart(sub, "MarkedWall"', 'views'),
("V8 the rebuild leaves the old walls", C+'MazeView.luau', '\t\tif child.Name == "Wall" or child.Name == "MarkedWall" then\n\t\t\tchild:Destroy()', '\t\tif child.Name == "Wall" then\n\t\t\tchild:Destroy()', 'views'),
("V9 a ghost near the gold", L+'View/init.luau', 'inky = table.freeze({ r = 230, g = 255, b = 0 })', 'inky = table.freeze({ r = 255, g = 230, b = 0 })', 'parts'),
("V10 the frightened look near the gold", L+'View/init.luau', 'View.FRIGHTENED_COLOR = table.freeze({ r = 33, g = 33, b = 255 } :: Rgb)', 'View.FRIGHTENED_COLOR = table.freeze({ r = 255, g = 200, b = 0 } :: Rgb)', 'parts'),
("V4 a rebuild ignores the edible time", C+'MazeView.luau', 'View.wallColor(model:GetAttribute("Lit") == true, model:GetAttribute("Edible") == true, marked)', 'View.wallColor(model:GetAttribute("Lit") == true, false, marked)', 'views'),
("V5 the stop capped only at a walking speed", L+'Session/init.luau', 'if beside and distance <= config.speed then', 'if beside and distance <= config.speed and config.speed <= 34 then', 'pick'),
("U10 Touch.buttons without the pick", L+'Touch/init.luau', '\t\tpick = Touch.pickRect(box),\n', '', 'touch'),
]
M = M + NEW + NEW2 + NEW3 + NEW4 + NEW5 + NEW6

# Correct variants (design review 005 F2): each is a right change a later issue may make to an adapter; the specs
# that load it must stay green.
CORRECT = [
("C1 Main requires one more Logic feature", C+'Main.client.luau', 'local View = require("@game/ReplicatedStorage/Shared/Logic/View")\n', 'local View = require("@game/ReplicatedStorage/Shared/Logic/View")\nlocal _Lobby = require("@game/ReplicatedStorage/Shared/Logic/Lobby")\n', 'views'),
("C2 Main requires a new adapter", C+'Main.client.luau', 'local View = require("@game/ReplicatedStorage/Shared/Logic/View")\n', 'local View = require("@game/ReplicatedStorage/Shared/Logic/View")\nlocal _New = require("./NewView")\n', 'views'),
("C3 Main asks for another service", C+'Main.client.luau', 'local View = require("@game/ReplicatedStorage/Shared/Logic/View")\n', 'local View = require("@game/ReplicatedStorage/Shared/Logic/View")\nlocal _Players = game:GetService("Players")\n', 'views'),
("C4 HudView sizes the banner by scale first", C+'HudView.luau', '\t\tl.Name = "Boon"\n', '\t\tl.Name = "Boon"\n\t\tl.Size = UDim2.fromScale(0.5, 0.08)\n', 'views'),
("C5 MazeView collects the old walls before destroying them", C+'MazeView.luau', '\tfor _, child in model:GetChildren() do\n\t\tif child.Name == "Wall" or child.Name == "MarkedWall" then\n\t\t\tchild:Destroy()\n\t\tend\n\tend\n', '\tlocal old = {}\n\tfor _, child in model:GetChildren() do\n\t\tif child.Name == "Wall" or child.Name == "MarkedWall" then\n\t\t\ttable.insert(old, child)\n\t\tend\n\tend\n\tfor _, child in old do\n\t\tchild:Destroy()\n\tend\n', 'views'),
("C6 f0109 tunes its green again (whatever it is, one step redder)", L+'View/init.luau', 'View.WALL_EDIBLE_COLOR = table.freeze({ r = ', 'View.WALL_EDIBLE_COLOR = table.freeze({ r = 1 + ', 'views'),
("C7 f0109 tunes its green again (parts)", L+'View/init.luau', 'View.WALL_EDIBLE_COLOR = table.freeze({ r = ', 'View.WALL_EDIBLE_COLOR = table.freeze({ r = 1 + ', 'parts'),
]

def f0109_moved():
    tree = os.path.join(os.path.dirname(REPO), "proto-f0109") if os.path.basename(os.path.dirname(REPO)) == ".worktree" else os.path.join(REPO, ".worktree", "proto-f0109")
    if not os.path.isdir(tree):
        print("note: no proto-f0109 worktree; the base's f0109 is as recorded", flush=True)
        return None
    import glob, hashlib
    diff = subprocess.run(["git", "-C", tree, "diff", "--", "pickman/src", "pickman/tests/lib", "pickman/.tracker/game-design.md"], capture_output=True, check=True).stdout
    prep = os.path.join(os.path.dirname(tree), "prep-white-ghost-green-walls", "pickman/.tracker/issues/f0109/acceptance")
    specs = b"".join(open(f, "rb").read() for f in sorted(glob.glob(os.path.join(prep if os.path.isdir(prep) else os.path.join(tree, "pickman/tests/acceptance/f0109"), "*.luau"))))
    moved = []
    if hashlib.sha256(diff).hexdigest() != F0109_SRC:
        moved.append("its source")
    if hashlib.sha256(specs).hexdigest() != F0109_SPECS:
        moved.append("its specs")
    return moved or None

def main():
    moved = f0109_moved()
    if moved:
        sys.exit("refusing: proto-f0109 has moved (" + ", ".join(moved) + ") since base.patch was cut; cut the base again (E12)")
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    subprocess.run(["git", "-C", CLONE, "checkout", "--quiet", BASE], check=True)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "base.patch")], check=True)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "prototype.patch")], check=True)
    dest = os.path.join(HOME, A)
    os.makedirs(dest, exist_ok=True)
    for name in os.listdir(os.path.join(HERE, "..", "acceptance")):
        shutil.copy(os.path.join(HERE, "..", "acceptance", name), dest)
    # the unmutated prototype first: f0126's specs and f0109's own all pass, or no mutant result means anything
    names = sorted(os.listdir(dest))
    base_specs = [A + n for n in names if n.endswith(".spec.luau")]
    f0109 = os.path.join(HOME, "tests/acceptance/f0109")
    base_specs += ["tests/acceptance/f0109/" + n for n in sorted(os.listdir(f0109)) if n.endswith(".spec.luau")] if os.path.isdir(f0109) else []
    out = subprocess.run(["lune", "run", "tests/run", "--"] + base_specs, cwd=HOME, capture_output=True, text=True, timeout=900).stdout
    summary = [l for l in out.split("\n") if " passed, " in l]
    print("BASELINE".ljust(30), summary[-1] if summary else out[-300:], flush=True)
    if " 0 failed" not in out:
        sys.exit("refusing: the unmutated prototype fails: " + "; ".join(l for l in out.split("\n") if l.startswith("FAIL"))[:600])
    only = sys.argv[1:]
    for mid, rel, old, new, spec in M + [(c[0], c[1], c[2], c[3], c[4]) for c in CORRECT]:
        name = mid.split(" ")[0]
        if only and not any(name == o or (o.endswith("*") and name.startswith(o[:-1])) for o in only):
            continue
        f = os.path.join(HOME, rel)
        if not inside_clone(f):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        if src.count(old) != 1:
            print(mid.ljust(30), "ANCHOR", src.count(old))
            continue
        open(f, "w").write(src.replace(old, new))
        try:
            out = subprocess.run(["lune", "run", "tests/run", "--", A + spec + ".spec.luau"], cwd=HOME,
                                 capture_output=True, text=True, timeout=600).stdout
        finally:
            open(f, "w").write(src)
        correct = name.startswith("C") and name[1:].isdigit()
        if "could not load" in out or "syntax error" in out:
            verdict = "LOAD ERROR"
        elif correct:
            verdict = "green (correct variant)" if " 0 failed" in out else "RED: a correct variant fails"
        elif " 0 failed" in out:
            verdict = "SURVIVED"
        else:
            fails = [l for l in out.split("\n") if l.startswith("FAIL")]
            verdict = "killed: " + (fails[0].split(":: ")[-1][:70] if fails else "")
        print(mid.ljust(30), verdict, flush=True)

try:
    main()
finally:
    shutil.rmtree(TMP, ignore_errors=True)
