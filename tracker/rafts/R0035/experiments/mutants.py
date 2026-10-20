#!/usr/bin/env python3
# Mutation check for R0035 (prep). Usage: python3 mutants.py <scratch worktree with prototype.patch applied> [ids...]
# Applies the edit in the prototype worktree, runs the spec, and requires that the named case FAILs with an
# assertion ("expected ..."), then restores the file with git checkout.
import subprocess, sys, json, re

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."  # a scratch worktree with prototype.patch applied and the acceptance specs present
A = "tracker/issues/{}/acceptance/{}.spec.luau"
BL = "src/shared/Logic/Blaster/init.luau"
SE = "src/shared/Logic/Session/init.luau"
GH = "src/shared/Logic/Ghosts/init.luau"
VI = "src/shared/Logic/View/init.luau"
AW = "src/shared/Logic/Awareness/init.luau"
HU = "src/shared/Logic/Hud/init.luau"

M = [
 # f0100 Blaster
 ("B1", BL, "if dropped and b.shots < Blaster.MAX_SHOTS then", "if dropped and b.shots <= Blaster.MAX_SHOTS then", A.format("f0100","blaster"), "a drop while three are held is lost"),
 ("B2", BL, "local dropped = b.rng % 100 < Blaster.DROP_PERCENT", "local dropped = true", A.format("f0100","blaster"), "about half of the rolls drop"),
 ("B3", BL, "local dropped = b.rng % 100 < Blaster.DROP_PERCENT", "local dropped = b.rng % 100 < 75", A.format("f0100","blaster"), "about half of the rolls drop"),
 ("B4", BL, "function Blaster.drop(b: Blaster): boolean\n", "function Blaster.drop(b: Blaster): boolean\n\tif b.shots >= Blaster.MAX_SHOTS then\n\t\treturn false\n\tend\n", A.format("f0100","blaster"), "the roll is made even when full"),
 ("B5", BL, "return { shots = 0, rng = (s * 48271 + 11) % (MODULUS - 1) + 1 }", "return { shots = 0, rng = 12345 }", A.format("f0100","blaster"), "different seeds roll differently"),
 ("B6", BL, "\tif b.shots <= 0 then\n\t\treturn false\n\tend\n\tb.shots -= 1", "\tb.shots -= 1", A.format("f0100","blaster"), "spending takes one shot"),
 ("B7", BL, "function Blaster.reset(b: Blaster)\n\tb.shots = 0", "function Blaster.reset(b: Blaster)\n\tb.shots = b.shots", A.format("f0100","blaster"), "a reset empties"),
 ("B8", BL, "if raw == INTENTS[h] then", "if string.lower(raw) == string.lower(INTENTS[h]) then", A.format("f0100","blaster"), "the four fire intents"),
 ("B9", BL, "\t\tif not Maze.passable(m, nextTile, \"player\") then\n\t\t\tbreak", "\t\tif not Maze.passable(m, nextTile, \"player\") then\n\t\t\ttable.insert(out, nextTile)\n\t\t\tbreak", A.format("f0100","blaster"), "runs to the last open tile"),
 ("B10", BL, "if not Maze.passable(m, nextTile, \"player\") then", "if not Maze.passable(m, nextTile, \"ghost\") then", A.format("f0100","blaster"), "a door stops it"),
 ("B11", BL, "\t\tif nextTile.x == from.x and nextTile.y == from.y then\n\t\t\tbreak\n\t\tend\n", "", A.format("f0100","blaster"), "a wrapping row carries it round once"),
 ("B12", BL, "local out: { Maze.Tile } = { { x = from.x, y = from.y } }", "local out: { Maze.Tile } = {}", A.format("f0100","blaster"), "starts on the player's tile"),
 ("B13", BL, "if target.active and target.tile.x == tile.x", "if target.tile.x == tile.x", A.format("f0100","blaster"), "an inactive target"),
 ("B14", BL, "\t\tfor i, target in targets do\n", "\t\tfor i = #targets, 1, -1 do\n\t\t\tlocal target = targets[i]\n", A.format("f0100","blaster"), "on one tile the lowest index"),
 ("B15", BL, "\tfor _, tile in Blaster.ray(m, from, h) do\n\t\tfor i, target in targets do\n\t\t\tif target.active and target.tile.x == tile.x and target.tile.y == tile.y then\n\t\t\t\treturn i",
   "\tlocal ray = Blaster.ray(m, from, h)\n\tfor r = #ray, 1, -1 do\n\t\tlocal tile = ray[r]\n\t\tfor i, target in targets do\n\t\t\tif target.active and target.tile.x == tile.x and target.tile.y == tile.y then\n\t\t\t\treturn i", A.format("f0100","blaster"), "the nearest active target"),
 # f0100 Session
 ("S1", SE, "if #member.queue + (if member.fire then 1 else 0) >= s.config.maxIntentsPerTick then", "if #member.queue >= s.config.maxIntentsPerTick then", A.format("f0100","shots"), "counts toward the per-tick limit"),
 ("S2", SE, "\t\tif member.fire then\n\t\t\treturn false, \"rate limited\" -- one shot a tick\n\t\tend\n", "", A.format("f0100","shots"), "only one is taken a tick"),
 ("S3", SE, "\t\tif fire then\n\t\t\tshoot(s, id, member, fire, out)\n\t\tend\n", "", A.format("f0100","shots"), "a shot eats the nearest active ghost"),
 ("S4", SE, "\t\tif member.ghosts then\n\t\t\tstepGhosts(s, id, member, playerPrev, ghostsPrev, before, out)\n\t\tend",
   "\t\tif member.ghosts then\n\t\t\tstepGhosts(s, id, member, playerPrev, ghostsPrev, before, out)\n\t\tend\n\t\tif fire then\n\t\t\tshoot(s, id, member, fire, out)\n\t\tend", A.format("f0100","shots"), "before anyone moves", ("\t\tif fire then\n\t\t\tshoot(s, id, member, fire, out)\n\t\tend\n\t\tlocal speed", "\t\tlocal speed")),
 ("S5", SE, "if set == nil or not Blaster.spend(member.blaster) then", "if set == nil or member.blaster.shots <= 0 then", A.format("f0100","shots"), "a miss spends the shot"),
 ("S6", SE, "active = set.ghosts[i].status == \"active\" }", "active = set.ghosts[i].status == \"active\" and set.ghosts[i].frightened }", A.format("f0100","shots"), "a shot eats the nearest active ghost"),
 ("S7", SE, "\tlocal points = Ghosts.eat(set, name)\n\ttable.insert(out, { kind = \"Shot\"", "\tGhosts.eat(set, name)\n\tlocal points = 200\n\ttable.insert(out, { kind = \"Shot\"", A.format("f0100","shots"), "shots in a row climb the chain"),
 ("S8", GH, "\t\t\tset.chain = 0 -- the power period is over", "\t\t\t-- the power period is over", A.format("f0100","shots"), "the chain restarts when the power runs out"),
 ("S9", SE, "\t\tif not moving then\n\t\t\tcontinue\n\t\tend\n\t\tif fire then\n\t\t\tshoot(s, id, member, fire, out)\n\t\tend", "\t\tif fire then\n\t\t\tshoot(s, id, member, fire, out)\n\t\tend\n\t\tif not moving then\n\t\t\tcontinue\n\t\tend", A.format("f0100","shots"), "a fire in a pause"),
 ("S10", SE, "\t\tlocal fire: Maze.Heading? = member.fire\n\t\tmember.fire = nil\n", "\t\tlocal fire: Maze.Heading? = member.fire\n\t\tif Game.canMove(member.play) then\n\t\t\tmember.fire = nil\n\t\tend\n", A.format("f0100","shots"), "not kept for when play starts"),
 ("S11", SE, "\tfor _, e in Game.addScore(member.play, points) do\n\t\ttable.insert(out, tagged(id, e))\n\tend\nend\n\nfunction Session.step", "end\n\nfunction Session.step", A.format("f0100","shots"), "for the chain's points, and costs one shot"),
 ("D1", SE, "\t\tif Blaster.drop(member.blaster) then\n\t\t\ttable.insert(out, { kind = \"ShotGained\", player = id, ghost = name })\n\t\tend\n", "", A.format("f0100","drops"), "rolls a drop gives a shot"),
 ("D2", SE, "\tlocal name: Ghosts.Name = set.ghosts[hit].name\n\tlocal points = Ghosts.eat(set, name)\n", "\tlocal name: Ghosts.Name = set.ghosts[hit].name\n\tlocal points = Ghosts.eat(set, name)\n\tif Blaster.drop(member.blaster) then\n\t\ttable.insert(out, { kind = \"ShotGained\", player = id, ghost = name })\n\tend\n", A.format("f0100","drops"), "a ghost that is shot rolls no drop"),
 ("D3", SE, "\tmember.queue = {}\n\tmember.fire = nil\n\tmember.jumpTick = jumpTick", "\tmember.queue = {}\n\tmember.fire = nil\n\tmember.blaster.shots = 0\n\tmember.jumpTick = jumpTick", A.format("f0100","drops"), "shots outlive a death"),
 ("D4", SE, "\t\tBlaster.reset(member.blaster)\n", "", A.format("f0100","drops"), "a new run starts with none"),
 ("D5", SE, "\t\tshots = s.members[id].blaster.shots,\n", "", A.format("f0100","drops"), "every frame carries the count"),
 ("D6", SE, "\t\tif Blaster.drop(member.blaster) then\n\t\t\ttable.insert(out, { kind = \"ShotGained\", player = id, ghost = name })\n\t\tend\n", "\t\tmember.blaster.shots = math.min(3, member.blaster.shots + 1)\n\t\ttable.insert(out, { kind = \"ShotGained\", player = id, ghost = name })\n", A.format("f0100","drops"), "one that rolls no drop gives nothing"),
 ("D7", SE, "blaster = Blaster.new(s.seed),", "blaster = Blaster.new(1),", A.format("f0100","drops"), "the session's drops are its seed's"),
 ("H1", HU, "\tlocal x = count(lives) * (l.iconSize + l.margin)\n", "\tlocal x = 0\n", A.format("f0100","hud"), "follows the lives"),
 ("H2", HU, "x = x + (i - 1) * (w + gap)", "x = x + (i - 1) * w", A.format("f0100","hud"), "half a margin apart"),
 ("H3", HU, "local w = round(l.iconSize / 2)", "local w = math.floor(l.iconSize / 2)", A.format("f0100","hud"), "round half up"),
 ("V1", VI, "if wrapped or not Maze.passable(m, nextTile, \"player\") then", "if not Maze.passable(m, nextTile, \"player\") then", A.format("f0100","hud"), "a wrapping row ends the beam"),
 ("V2", VI, "local ex = if dx ~= 0 then tile.x + dx * 0.5 else x", "local ex = if dx ~= 0 then tile.x else x", A.format("f0100","hud"), "a beam ends at the far edge"),
 # f0101
 ("J1", VI, "wallHeight = 9, eyeHeight = 4", "wallHeight = 8, eyeHeight = 4", A.format("f0101","sight"), "standing, almost no hidden ghost"),
 ("J2", VI, "View.JUMP = table.freeze({ rise = 14,", "View.JUMP = table.freeze({ rise = 8,", A.format("f0101","sight"), "at the top of a jump"),
 ("J3", VI, "View.GHOST = table.freeze({ width = 6, height = 10 })", "View.GHOST = table.freeze({ width = 6, height = 7 })", A.format("f0101","sight"), "at the top of a jump"),
 ("J4", VI, "return View.JUMP.rise * 4 * u * (1 - u)", "return View.JUMP.rise * (1 - math.abs(2 * u - 1))", A.format("f0101","jump"), "it is a parabola"),
 ("J5", VI, "return now >= last + View.JUMP.seconds + View.JUMP.cooldown", "return now >= last + View.JUMP.seconds", A.format("f0101","jump"), "before the cool-down"),
 ("J6", VI, "return now >= last + View.JUMP.seconds + View.JUMP.cooldown", "return true", A.format("f0101","jump"), "no new jump while one is up"),
 ("J7", VI, "\tif last == nil or not finite(last) or not finite(now) then\n\t\treturn 0\n\tend\n\tlocal u", "\tif last == nil then\n\t\treturn 0\n\tend\n\tlocal u", A.format("f0101","jump"), "at a time that is not finite: 0"),
 ("J8", "src/client/Camera.luau", "View.SCALE.eyeHeight + View.jumpRise(jumped, os.clock())", "View.SCALE.eyeHeight", A.format("f0101","place"), "the eye is the standing height plus"),
 ("J9", "src/client/GhostView.luau", "local BODY = Vector3.new(View.GHOST.width, View.GHOST.height, View.GHOST.width)", "local BODY = Vector3.new(6, 7, 6)", A.format("f0101","place"), "GhostView sizes"),
 ("J10", "src/client/Camera.luau", "\tif View.canJump(jumped, now) then\n\t\tjumped = now\n\tend", "\tjumped = now", A.format("f0101","place"), "asks View.canJump"),
 # f0102
 ("G1", AW, "\tif q + 0.5 == n and n % 2 ~= 0 then\n\t\tn -= 1\n\tend\n\treturn n % 8", "\treturn n % 8", A.format("f0102","sectors"), "exactly between two"),
 ("G2", AW, "\tlocal n = math.floor(q + 0.5)\n\tif q + 0.5 == n and n % 2 ~= 0 then\n\t\tn -= 1\n\tend\n\treturn n % 8", "\tlocal n = math.floor(q)\n\treturn n % 8", A.format("f0102","sectors"), "just either side of a boundary"),
 ("G3", AW, "local corner = math.atan(a)", "local corner = math.pi / 4", A.format("f0102","sectors"), "the four corners, on any screen"),
 ("G4", AW, "\t\t\tor ind.distance < held.distance\n", "\t\t\tor ind.distance > held.distance\n", A.format("f0102","glows"), "the nearest ghost in a sector lights it"),
 ("G5", AW, "(ind.distance == held.distance and ind.index < held.index)", "(ind.distance == held.distance and ind.index > held.index)", A.format("f0102","glows"), "a tie in distance goes to the earlier"),
 ("G6", AW, "if o.inView or not inView then", "if not inView then", A.format("f0102","glows"), "with inView, a ghost ahead in view is listed"),
 ("G7", AW, "if o.inView or not inView then", "if true then", A.format("f0102","glows"), "without the option nothing changes"),
 ("G8", AW, "\t\t\t\t\t\tinView = inView,\n", "\t\t\t\t\t\tinView = false,\n", A.format("f0102","glows"), "says so; one behind"),
 ("G9", AW, "\tlocal x = math.clamp((cu * 0.5 + 0.5) * w - s / 2, 0, w - s)\n\tlocal y = math.clamp((cv * 0.5 + 0.5) * h - s / 2, 0, h - s)", "\tlocal x = (cu * 0.5 + 0.5) * w - s / 2\n\tlocal y = (cv * 0.5 + 0.5) * h - s / 2", A.format("f0102","box"), "whole on the screen and clear of the middle"),
 ("G10", AW, "local s = Awareness.GLOW.side * math.min(w, h) * math.clamp(if size == size then size else 0, 0, 1)", "local s = Awareness.GLOW.side * math.min(w, h)", A.format("f0102","box"), "it grows with the glow's size"),
 ("G11", AW, "Awareness.GLOW = table.freeze({ side = 0.12 })", "Awareness.GLOW = table.freeze({ side = 0.3 })", A.format("f0102","box"), "a full-size glow is 12%"),
 ("G12", VI, "\t\telseif look == \"eyes\" then View.WHITE\n", "", A.format("f0102","colors"), "frightened is blue for everyone"),
 ("G13", VI, "elseif look == \"blinking\" then (if flash then View.WHITE else View.FRIGHTENED_COLOR)", "elseif look == \"blinking\" then View.FRIGHTENED_COLOR", A.format("f0102","colors"), "blinking flashes white"),
 ("G14", VI, "\treturn { r = c.r, g = c.g, b = c.b }\nend", "\treturn c :: any\nend", A.format("f0102","colors"), "fresh table"),
 ("G15", "src/client/DangerHud.luau", "\t\t\tinView = true,\n", "", A.format("f0102","place"), "lists every close ghost"),
 ("G16", "src/client/DangerHud.luau", "edge.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets", "edge.ScreenInsets = Enum.ScreenInsets.None", A.format("f0102","place"), "safe area"),
 # f0104
 ("K1", VI, "\tUp = \"LookUp\",", "\tUp = \"Forward\",", A.format("f0104","keys"), "maps exactly the ten keys"),
 ("K2", VI, "\tSpace = \"Jump\",", "\tSpace = \"Snap\",", A.format("f0104","keys"), "maps exactly the ten keys"),
 ("K3", VI, "\tE = \"Fire\",", "\tE = \"Fire\",\n\tF = \"Fire\",", A.format("f0104","keys"), "other keys do nothing"),
 ("L1", VI, "\t\tup = if key == \"up\" then down else a.up,", "\t\tup = if key then down else a.up,", A.format("f0104","look"), "sets and clears just that arrow"),
 ("L2", VI, "\treturn side * 1.5\nend", "\treturn -side * 1.5\nend", A.format("f0104","look"), "where the arrows look"),
 ("L3", VI, "\t\treturn if ahead < 0 then 2 else 0\n", "\t\treturn if ahead <= 0 then 2 else 0\n", A.format("f0104","look"), "where the arrows look"),
 ("A1", VI, "\tif q + 0.5 == n and n % 2 ~= 0 then\n\t\tn -= 1 -- exactly half way: the even quarter (ahead or behind)\n\tend\n", "", A.format("f0104","aim"), "two arrows together aim ahead or behind"),
 ("A2", VI, "local q = View.arrowQuarters(a) or (if finite(s.look.yaw) then wrap(s.look.yaw) / (PI / 2) else 0)", "local q = if finite(s.look.yaw) then wrap(s.look.yaw) / (PI / 2) else 0", A.format("f0104","aim"), "held arrows win over the look"),
 ("A3", VI, "\telseif n == 1 then\n\t\treturn Maze.left(heading)\n\telseif n == 3 then\n\t\treturn Maze.right(heading)", "\telseif n == 1 then\n\t\treturn Maze.right(heading)\n\telseif n == 3 then\n\t\treturn Maze.left(heading)", A.format("f0104","aim"), "aim ahead, left, right and behind"),
 ("A4", VI, "local q = View.arrowQuarters(a) or (if finite(s.look.yaw) then wrap(s.look.yaw) / (PI / 2) else 0)", "local q = View.arrowQuarters(a) or (s.look.yaw / (PI / 2))", A.format("f0104","aim"), "a look that is not a number"),
 ("C1", "src/client/Controls.luau", "if down or state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then", "if down then", A.format("f0104","place"), "hears a key going up"),
 ("C2", "src/client/Main.client.luau", "Controls.start(Camera.snap)", "Controls.start(function() end)", A.format("f0104","place"), "keeps what it builds on"),
 ("L4", VI, "return { look = toward(prev.look, { yaw = wrap(q * PI / 2), pitch = 0 }), spring = true }", "return { look = toward(look, { yaw = wrap(q * PI / 2), pitch = 0 }), spring = true }", A.format("f0104","look"), "any other look input is ignored"),
 ("L5", VI, "return { look = toward(prev.look, { yaw = wrap(q * PI / 2), pitch = 0 }), spring = true }", "return { look = toward(prev.look, { yaw = wrap(q * PI / 2), pitch = prev.look.pitch }), spring = true }", A.format("f0104","look"), "the pitch levels"),
 ("L6", VI, "return { look = toward(prev.look, { yaw = wrap(q * PI / 2), pitch = 0 }), spring = true }", "return { look = { yaw = wrap(q * PI / 2), pitch = 0 }, spring = true }", A.format("f0104","look"), "a quarter turn in TURN_SECONDS"),
 ("L7", VI, "return { look = back, spring = not (back.yaw == 0 and back.pitch == 0) }", "return { look = back, spring = true }", A.format("f0104","look"), "stops springing there"),
 ("L8", VI, "\tif look.yaw ~= prev.look.yaw or look.pitch ~= prev.look.pitch then\n\t\treturn { look = { yaw = look.yaw, pitch = look.pitch }, spring = false }\n\tend\n", "", A.format("f0104","look"), "any other look input takes over a spring"),
 ("L9", VI, "if look.yaw ~= prev.look.yaw or look.pitch ~= prev.look.pitch then", "if look.yaw ~= prev.look.yaw then", A.format("f0104","look"), "any other look input takes over a spring"),
 ("C3", "src/client/Camera.luau", "\t\tlook = View.look(look, delta.X, delta.Y)\n", "\t\tlook = View.look(look, 0, 0)\n", A.format("f0104","place"), "looks with View.steer"),
 ("C4", "src/client/Camera.luau", "\t\tsteer = View.steer(steer, look, arrows, dt)\n\t\tlook = steer.look\n", "", A.format("f0104","place"), "looks with View.steer"),
 ("K4", SE, "\tlocal fire: Maze.Heading? = Blaster.heading(raw)\n", "\tlocal fire: Maze.Heading? = nil\n", A.format("f0104","hunt"), "press E"),
 ("S12", SE, "\t\tif member.ghosts then\n\t\t\tstepGhosts(s, id, member, playerPrev, ghostsPrev, before, out)", "\t\tif fire then\n\t\t\tshoot(s, id, member, fire, out)\n\t\tend\n\t\tif member.ghosts then\n\t\t\tstepGhosts(s, id, member, playerPrev, ghostsPrev, before, out)", A.format("f0100","shots"), "a moving player shoots from the tile", ("\t\tif fire then\n\t\t\tshoot(s, id, member, fire, out)\n\t\tend\n\t\tlocal speed", "\t\tlocal speed")),
 ("S13", SE, "\tlocal from = Movement.occupied(s.maze, member.move)\n", "\tlocal px, py = Movement.position(member.move)\n\tlocal from = { x = math.floor(px), y = math.floor(py) }\n", A.format("f0100","shots"), "a moving player shoots from the tile"),
 ("S14", SE, "\tif set == nil or not Blaster.spend(member.blaster) then\n\t\treturn\n\tend\n\tmember.shot = { tick = s.tick, heading = heading }\n", "\tmember.shot = { tick = s.tick, heading = heading }\n\tif set == nil or not Blaster.spend(member.blaster) then\n\t\treturn\n\tend\n", A.format("f0100","shots"), "a fire the server drops leaves the frame's shot alone"),
 ("S15", SE, "\tmember.shot = { tick = s.tick, heading = heading }\n", "", A.format("f0100","shots"), "the frame names the latest shot"),
 ("V3", "src/client/BlastView.luau", "if shot and shot.tick == frame.tick and p then", "if shot and p then", A.format("f0100","place"), "draws the server's shot"),
 ("G17", AW, "\t\t\t\tname = ind.name,\n", "", A.format("f0102","glows"), "carries its nearest ghost's name"),
 ("G18", "src/client/DangerHud.luau", "local rgb = View.ghostColor(g.name or \"\", g.look, g.flash == true)", "local ghost = snap.ghosts[i]\n\t\t\tlocal rgb = View.ghostColor(ghost.name, g.look, ghost.flash)", A.format("f0102","place"), "not by position"),
 ("G19", "src/client/DangerHud.luau", "edge.DisplayOrder = -1", "edge.DisplayOrder = 0", A.format("f0102","place"), "under the radar"),
 ("G20", VI, "inky = table.freeze({ r = 0, g = 255, b = 255 }),", "inky = table.freeze({ r = 255, g = 0, b = 0 }),", A.format("f0102","colors"), "each ghost has its own colour"),
]

only = set(sys.argv[2:])
results = []
for row in M:
    mid, f, old, new, spec, case = row[:6]
    extra = row[6] if len(row) > 6 else None
    if only and mid not in only:
        continue
    path = f"{ROOT}/{f}"
    src = open(path).read()
    if src.count(old) != 1:
        results.append((mid, "NOAPPLY", f"old text found {src.count(old)}x"))
        continue
    mutated = src
    if extra:
        if mutated.count(extra[0]) != 1:
            results.append((mid, "NOAPPLY", "extra edit"))
            continue
        mutated = mutated.replace(extra[0], extra[1])
    if mutated.count(old) != 1:
        results.append((mid, "NOAPPLY", "old text after extra"))
        continue
    open(path, "w").write(mutated.replace(old, new))
    try:
        out = subprocess.run(["lune", "run", "tests/run", "--", spec], cwd=ROOT, capture_output=True, text=True, timeout=600).stdout
    finally:
        subprocess.run(["git", "checkout", "--", f], cwd=ROOT)
    lines = out.splitlines()
    verdict, why = "SURVIVED", ""
    for i, line in enumerate(lines):
        if line.startswith("FAIL ") and " :: " in line and case in line:
            msg = lines[i + 1] if i + 1 < len(lines) else ""
            if "expected" in msg:
                verdict, why = "KILLED", msg.strip()[-100:]
            else:
                verdict, why = "ERROR", msg.strip()[-140:]
            break
    if verdict == "SURVIVED":
        fails = [l for l in lines if l.startswith("FAIL ")]
        why = "; ".join(fails)[:300] or lines[-1] if lines else ""
    results.append((mid, verdict, why))
    print(mid, verdict, why, flush=True)

print("\nSUMMARY", {v: sum(1 for r in results if r[1] == v) for v in ("KILLED", "SURVIVED", "ERROR", "NOAPPLY")})
for r in results:
    if r[1] != "KILLED":
        print(" ", r)
