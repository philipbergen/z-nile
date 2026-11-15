# f0220 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, copies this item's folder in, applies prototype.patch there (the five Logic features),
# runs the intended state, then applies each mutant (and each correct variant) to that clone, runs the row's spec
# files from the clone's asteroids/, restores the file, and deletes the clone at the end.
# A mutant is killed when its spec run reports a FAIL whose message is an assertion ("expected ..."), not a
# syntax, type or require error. A correct variant (CV) must stay green.
# Usage, from the repository root: ./zn run --time 1500 -- python3 -I asteroids/.tracker/issues/f0220/experiments/mutants.py [id prefixes...]
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0220-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "asteroids")
A = ".tracker/issues/f0220/acceptance/"
FIELD = [A + "field.spec.luau"]
SHIP = [A + "ship.spec.luau"]
SHOT = [A + "shots.spec.luau"]
ROCK = [A + "rocks.spec.luau"]
SAUC = [A + "saucers.spec.luau"]
HYP = [A + "hyperspace.spec.luau"]
LIV = [A + "lives.spec.luau"]
WAV = [A + "waves.spec.luau"]
GAME = [A + "game.spec.luau"]
ALL = FIELD + SHIP + SHOT + ROCK + SAUC + HYP + LIV + WAV + GAME
L = "src/shared/Logic/"
FI = L + "Field/init.luau"
SH = L + "Ship/init.luau"
RO = L + "Rocks/init.luau"
SA = L + "Saucers/init.luau"
CL = L + "Classic/init.luau"
RN = L + "Classic/Rng.luau"
PI = L + "Pilot/init.luau"

# the ship's loss and its respawn, as the prototype writes them
DESTROY_SHIP = "\tp.ship = Ship.new(c.ship, c.field.width / 2, c.field.height / 2)\n\tp.shipState = \"dead\""
RESPAWN_SHIP = "\t\t\tp.ship = Ship.new(c.ship, c.field.width / 2, c.field.height / 2)\n\t\t\tp.shipState = \"alive\""
CONTROL_GATE = "\tif p.shipState ~= \"alive\" then\n\t\treturn\n\tend\n\tlocal f = c.field"
SHOT_MOVE = "breakRock(g, bestRock, \"shot\", events)\n\t\telse\n\t\t\tshot.x, shot.y = Field.wrap(f, shot.x + shot.vx, shot.y + shot.vy)"

M = [
    # Field
    ("FI1 a field 1,000 wide", FI, "width = 1024", "width = 1000", FIELD),
    ("FI2 no wrap up and down", FI, "return x % f.width, y % f.height", "return x % f.width, y", FIELD),
    ("FI3 distances the long way", FI, "\tif d >= size / 2 then\n\t\td -= size", "\tif false then\n\t\td -= size", FIELD),
    ("FI4 half the field counts positive", FI, "\tif d >= size / 2 then", "\tif d > size / 2 then", FIELD),
    ("FI5 headings clockwise", FI, "return math.cos(a), math.sin(a)", "return math.cos(a), -math.sin(a)", FIELD),
    ("FI6 the heading below, not the nearest", FI, "(2 * math.pi) + 0.5) % Field.HEADINGS", "(2 * math.pi)) % Field.HEADINGS", FIELD),
    ("FI7 a move checked only where it lands", FI, "local along = math.clamp(b / a, 0, 1)", "local along = 1", FIELD + SHOT),
    ("FI8 the sweep ignores the wrap", FI, "\tlocal dx, dy = Field.delta(f, x, y, cx, cy)\n\tlocal c =", "\tlocal dx, dy = cx - x, cy - y\n\tlocal c =", FIELD),
    ("FI9 the sweep gives the closest point, not the entry", FI, "\treturn math.clamp((b - math.sqrt(math.max(b * b - a * c, 0))) / a, 0, 1)", "\treturn along", FIELD),
    ("FI10 touching counts as reaching", FI, "if ex * ex + ey * ey >= r * r then", "if ex * ex + ey * ey > r * r then", FIELD),
    # Ship
    ("SH1 turns 4 a tick", SH, "turnRate = 3,", "turnRate = 4,", SHIP),
    ("SH2 turns the other way", SH, "s.heading = (s.heading + turn * c.turnRate)", "s.heading = (s.heading - turn * c.turnRate)", SHIP),
    ("SH3 the heading not wrapped", SH, "s.heading = (s.heading + turn * c.turnRate) % Field.HEADINGS", "s.heading = s.heading + turn * c.turnRate", SHIP),
    ("SH4 thrust before the turn", SH, [
        ("\ts.heading = (s.heading + turn * c.turnRate) % Field.HEADINGS\n\tif thrust then", "\tif thrust then"),
        ("\ts.vx *= 1 - c.drag\n", "\ts.heading = (s.heading + turn * c.turnRate) % Field.HEADINGS\n\ts.vx *= 1 - c.drag\n"),
    ], None, SHIP),
    ("SH5 thrust 0.2", SH, "thrust = 0.1,", "thrust = 0.2,", SHIP),
    ("SH6 no drag while thrusting", SH, "\ts.vx *= 1 - c.drag\n\ts.vy *= 1 - c.drag\n", "\tif not thrust then\n\t\ts.vx *= 1 - c.drag\n\t\ts.vy *= 1 - c.drag\n\tend\n", SHIP),
    ("SH7 drag after the move", SH, [
        ("\ts.vx *= 1 - c.drag\n\ts.vy *= 1 - c.drag\n", ""),
        ("\ts.x, s.y = Field.wrap(f, s.x + s.vx, s.y + s.vy)\n", "\ts.x, s.y = Field.wrap(f, s.x + s.vx, s.y + s.vy)\n\ts.vx *= 1 - c.drag\n\ts.vy *= 1 - c.drag\n"),
    ], None, SHIP),
    ("SH8 no top speed", SH, "if speed > c.maxSpeed then", "if false then", SHIP),
    ("SH9 the top speed on each axis", SH, "\tlocal speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)\n\tif speed > c.maxSpeed then",
     "\ts.vx = math.clamp(s.vx, -c.maxSpeed, c.maxSpeed)\n\ts.vy = math.clamp(s.vy, -c.maxSpeed, c.maxSpeed)\n\tlocal speed = 0\n\tif speed > c.maxSpeed then", SHIP),
    ("SH10 the top speed before the drag", SH, [
        ("\ts.vx *= 1 - c.drag\n\ts.vy *= 1 - c.drag\n", ""),
        ("\ts.x, s.y = Field.wrap(f, s.x + s.vx, s.y + s.vy)\n", "\ts.vx *= 1 - c.drag\n\ts.vy *= 1 - c.drag\n\ts.x, s.y = Field.wrap(f, s.x + s.vx, s.y + s.vy)\n"),
    ], None, SHIP),
    ("SH11 drag 2%", SH, "drag = 0.01,", "drag = 0.02,", SHIP),
    ("SH12 starts pointing along +x", SH, "startHeading = 64,", "startHeading = 0,", SHIP),
    ("SH13 any turn number", PI, "local turn = if input.turn == 1 then 1 elseif input.turn == -1 then -1 else 0", "local turn = if type(input.turn) == \"number\" then input.turn else 0", SHIP),
    ("SH14 any truthy thrust", PI, "thrust = input.thrust == true,", "thrust = input.thrust ~= nil and input.thrust ~= false,", SHIP),
    ("SH15 top speed 7", SH, "maxSpeed = 6,", "maxSpeed = 7,", SHIP),
    # Shots
    ("SO1 five shots", CL, "shotLimit = 4,", "shotLimit = 5,", SHOT),
    ("SO2 a fire beyond the limit remembered", PI, "\tif controls.fire and #p.shots < c.shotLimit then\n",
     "\tif controls.fire then\n\t\t(p :: any).queued = true\n\tend\n\tif (p :: any).queued and #p.shots < c.shotLimit then\n\t\t(p :: any).queued = nil\n", SHOT),
    ("SO3 the ship's velocity not added", PI, "vx = ux * c.shotSpeed + p.ship.vx,", "vx = ux * c.shotSpeed,", SHOT),
    ("SO4 a shot lives 61 ticks", CL, "shotLife = 60,", "shotLife = 61,", SHOT),
    ("SO5 the shot starts at the ship's centre", PI, "\t\tlocal x, y = Ship.nose(p.ship, c.ship, f)\n", "\t\tlocal x, y = p.ship.x, p.ship.y\n", SHOT),
    ("SO6 shot speed 9", CL, "shotSpeed = 8,", "shotSpeed = 9,", SHOT),
    ("SO7 any truthy fire", PI, "fire = input.fire == true,", "fire = input.fire ~= nil and input.fire ~= false,", SHOT),
    ("SO8 shots do not wrap", CL, SHOT_MOVE, "breakRock(g, bestRock, \"shot\", events)\n\t\telse\n\t\t\tshot.x, shot.y = shot.x + shot.vx, shot.y + shot.vy", SHOT + FIELD),
    ("SO9 a hit does not end the shot", CL, "\t\t\tbreakRock(g, bestRock, \"shot\", events)\n", "\t\t\tbreakRock(g, bestRock, \"shot\", events)\n\t\t\ttable.insert(kept, shot)\n", SHOT),
    ("SO10 the first rock listed, not the nearest", CL, "\t\t\tif t and (best == nil or t < best) then", "\t\t\tif t and best == nil then", SHOT),
    ("SO11 the saucer before any rock", CL, "if st and (best == nil or st < best) then", "if st then", SHOT),
    ("SO12 a tie goes to the saucer", CL, "if st and (best == nil or st < best) then", "if st and (best == nil or st <= best) then", SHOT),
    ("SO14 a tie between rocks goes to the later", CL, "\t\t\tif t and (best == nil or t < best) then", "\t\t\tif t and (best == nil or t <= best) then", SHOT),
    ("SO13 pieces out of reach until the next tick", CL, [
        ("\tlocal kept = {}\n\tfor _, shot in g.shots do", "\tlocal kept = {}\n\tlocal known = {}\n\tfor _, r in g.rocks do\n\t\tknown[r.id] = true\n\tend\n\tfor _, shot in g.shots do"),
        ("\t\t\tlocal t = Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, r.x, r.y, Rocks.SIZES[r.size].radius)",
         "\t\t\tlocal t = if known[r.id] then Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, r.x, r.y, Rocks.SIZES[r.size].radius) else nil"),
    ], None, SHOT),
    # Rocks
    ("RO1 a large radius of 30", RO, "{ radius = 40, points = 20,", "{ radius = 30, points = 20,", ROCK),
    ("RO2 a large rock worth 10", RO, "radius = 40, points = 20,", "radius = 40, points = 10,", ROCK),
    ("RO3 a medium rock worth 100", RO, "radius = 20, points = 50,", "radius = 20, points = 100,", ROCK),
    ("RO4 a small rock worth 50", RO, "radius = 10, points = 100,", "radius = 10, points = 50,", ROCK),
    ("RO5 large splits into small", RO, "splitsInto = \"medium\",", "splitsInto = \"small\",", ROCK),
    ("RO6 large splits in three", RO, "splitsInto = \"medium\", pieces = 2", "splitsInto = \"medium\", pieces = 3", ROCK),
    ("RO7 small splits too", RO, "splitsInto = nil, pieces = 0", "splitsInto = \"small\" :: SizeName?, pieces = 2", ROCK),
    ("RO8 pieces keep the parent's id", RO, "Rocks.launch(firstId + i - 1, into, r.x, r.y, draw)", "Rocks.launch(r.id, into, r.x, r.y, draw)", ROCK),
    ("RO9 every rock heads one way", RO, "\tlocal heading = draw(Field.HEADINGS) - 1", "\tlocal heading = (draw(Field.HEADINGS) - 1) * 0", ROCK),
    ("RO10 the speed not drawn", RO, "local speed = Rocks.speed(size, draw(Rocks.SPEED_STEPS))", "local speed = Rocks.speed(size, 1 + draw(Rocks.SPEED_STEPS) * 0)", ROCK),
    ("RO11 a medium rock no faster than a large", RO, "speedMax = 2.25,", "speedMax = 1.5,", ROCK),
    ("RO12 rocks slow down", RO, "\tr.x, r.y = Field.wrap(f, r.x + r.vx, r.y + r.vy)", "\tr.x, r.y = Field.wrap(f, r.x + r.vx, r.y + r.vy)\n\tr.vx *= 0.999\n\tr.vy *= 0.999", ROCK),
    ("RO13 a rammed rock does not split", CL, "\t\t\tbreakRock(g, i, \"ship\", events)\n\t\t\tendIfOut(g, Pilot.lose(g, c, \"rock\", emitter(events)), events)", "\t\t\ttable.remove(g.rocks, i)\n\t\t\tendIfOut(g, Pilot.lose(g, c, \"rock\", emitter(events)), events)", ROCK),
    ("RO14 a rammed rock does not score", CL, "\t\t\tbreakRock(g, i, \"ship\", events)\n", "\t\t\tg.score -= Rocks.SIZES[r.size].points\n\t\t\tbreakRock(g, i, \"ship\", events)\n", ROCK),
    ("RO15 the last rock overlapped, not the first", CL, "\tfor i, r in g.rocks do\n\t\tif Field.distance(f, sx, sy, r.x, r.y)", "\tfor i = #g.rocks, 1, -1 do\n\t\tlocal r = g.rocks[i]\n\t\tif Field.distance(f, sx, sy, r.x, r.y)", ROCK),
    ("RO16 a rock reaches 0.2 further", CL, "< Rocks.SIZES[r.size].radius + c.ship.radius then", "< Rocks.SIZES[r.size].radius + c.ship.radius + 0.2 then", ROCK),
    ("RO17 a ship radius of 10", SH, "radius = 12,", "radius = 10,", ROCK),
    ("RO18 the hit names no cause", CL, "{ kind = \"RockHit\", id = r.id, size = r.size, points = points, by = by }", "{ kind = \"RockHit\", id = r.id, size = r.size, points = points }", ROCK),
    # Saucers
    ("SA1 the first wait 901", SA, "firstWait = 900,", "firstWait = 901,", SAUC),
    ("SA2 the wait 100 shorter a wave", SA, "waitStep = 120,", "waitStep = 100,", SAUC),
    ("SA3 the wait never under 300", SA, "minWait = 360,", "minWait = 300,", SAUC),
    ("SA4 the wait of wave 1 always", CL, "Saucers.wait(sc, g.wave)", "Saucers.wait(sc, 1)", SAUC),
    ("SA5 the wait paused while the ship is lost", CL, "\tif s == nil then\n\t\tg.saucerElapsed += 1\n", "\tif s == nil then\n\t\tif g.shipState == \"alive\" then\n\t\t\tg.saucerElapsed += 1\n\t\tend\n", SAUC),
    ("SA6 small only below the share", SA, "if draw(8) <= Saucers.smallShare(c, wave)", "if draw(8) < Saucers.smallShare(c, wave)", SAUC),
    ("SA7 the share does not grow", SA, "smallEighths = table.freeze({ 1, 2, 3, 4, 5, 6, 7 })", "smallEighths = table.freeze({ 1, 1, 1, 1, 1, 1, 1 })", SAUC),
    ("SA8 the share stops at 6", SA, "smallEighths = table.freeze({ 1, 2, 3, 4, 5, 6, 7 })", "smallEighths = table.freeze({ 1, 2, 3, 4, 5, 6, 6 })", SAUC),
    ("SA9 the side drawn before the kind", SA, [
        ("\tlocal kind: Kind = if draw(8) <= Saucers.smallShare(c, wave) then \"small\" else \"large\"\n\tlocal dir = if draw(2) == 1 then 1 else -1\n",
         "\tlocal dir = if draw(2) == 1 then 1 else -1\n\tlocal kind: Kind = if draw(8) <= Saucers.smallShare(c, wave) then \"small\" else \"large\"\n"),
    ], None, SAUC),
    ("SA10 the sides swapped", SA, "local dir = if draw(2) == 1 then 1 else -1", "local dir = if draw(2) == 2 then 1 else -1", SAUC),
    ("SA11 the height one off", SA, "local y = draw(f.height) - 1", "local y = draw(f.height)", SAUC),
    ("SA12 the large saucer at 2.5", SA, "speed = 2,", "speed = 2.5,", SAUC),
    ("SA13 a saucer never leaves", SA, "return s.travelled >= f.width", "return false", SAUC),
    ("SA14 a saucer leaves only past the width", SA, "return s.travelled >= f.width", "return s.travelled > f.width", SAUC),
    ("SA15 a course change every 30 ticks", SA, "turnTicks = 60,", "turnTicks = 30,", SAUC),
    ("SA16 courses twice as steep", SA, "s.vy = (draw(3) - 2) * speed", "s.vy = (draw(3) - 2) * speed * 2", SAUC),
    ("SA17 never level again", SA, "s.vy = (draw(3) - 2) * speed", "s.vy = (if draw(2) == 1 then -1 else 1) * speed", SAUC),
    ("SA18 the large fires every 59", SA, "fireTicks = 60,", "fireTicks = 59,", SAUC),
    ("SA19 the small fires every 45", SA, "fireTicks = 40,", "fireTicks = 45,", SAUC),
    ("SA20 the large saucer aims", SA, "\tif not c[s.kind].aimed then", "\tif false then", SAUC),
    ("SA21 the aim ignores the wrap", SA, "\tlocal dx, dy = Field.delta(f, s.x, s.y, tx, ty)", "\tlocal dx, dy = tx - s.x, ty - s.y", SAUC),
    ("SA22 the spread never shrinks", SA, "\t\tif score >= row.score then", "\t\tif row.score == 0 then", SAUC),
    ("SA23 the spread steps after the threshold", SA, "\t\tif score >= row.score then", "\t\tif score > row.score then", SAUC),
    ("SA24 the aim from a fixed score", CL, "Saucers.aim(s, sc, f, g.score, g.ship.x, g.ship.y, drawer(g))", "Saucers.aim(s, sc, f, 50000, g.ship.x, g.ship.y, drawer(g))", SAUC),
    ("SA25 the aim error one off", SA, "local err = draw(2 * spread + 1) - 1 - spread", "local err = draw(2 * spread + 1) - spread", SAUC),
    ("SA26 fires while the ship is away", CL, " and g.shipState == \"alive\" then\n\t\ts.fireElapsed = 0", " then\n\t\ts.fireElapsed = 0", SAUC),
    ("SA27 a shot due while the ship is away is dropped", CL, "\tif s.fireElapsed >= sc[s.kind].fireTicks and g.shipState == \"alive\" then\n\t\ts.fireElapsed = 0\n",
     "\tif s.fireElapsed >= sc[s.kind].fireTicks then\n\t\ts.fireElapsed = 0\n\tend\n\tif s.fireElapsed == 0 and g.shipState == \"alive\" then\n", SAUC),
    ("SA28 saucer shots at 7", SA, "shotSpeed = 6,", "shotSpeed = 7,", SAUC),
    ("SA29 saucer shots live 61", SA, "shotLife = 60,", "shotLife = 61,", SAUC),
    ("SA30 the protected ship is hit", PI, "return p.shipState == \"alive\" and p.protect == 0", "return p.shipState == \"alive\"", SAUC),
    ("SA31 the large saucer worth 100", SA, "points = 200,", "points = 100,", SAUC),
    ("SA32 the small saucer worth 500", SA, "points = 1000,", "points = 500,", SAUC),
    ("SA33 a hit does not start the wait again", CL, "\tg.saucer = nil\n\tg.saucerElapsed = 0\n\ttable.insert(events, { kind = \"SaucerHit\"", "\tg.saucer = nil\n\ttable.insert(events, { kind = \"SaucerHit\"", SAUC),
    ("SA34 a rammed saucer does not score", CL, "\t\tbreakSaucer(g, \"ship\", events)\n", "\t\tg.saucer = nil\n", SAUC),
    ("SA35 saucer shots break rocks", CL, "\t\tif hit then\n\t\t\tendIfOut(g, Pilot.lose(g, c, \"saucershot\", emitter(events)), events)",
     "\t\tfor i, r in g.rocks do\n\t\t\tif Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, r.x, r.y, Rocks.SIZES[r.size].radius) then\n\t\t\t\ttable.remove(g.rocks, i)\n\t\t\t\tbreak\n\t\t\tend\n\t\tend\n\t\tif hit then\n\t\t\tendIfOut(g, Pilot.lose(g, c, \"saucershot\", emitter(events)), events)", SAUC),
    ("SA36 the small saucer radius 12", SA, "radius = 10, points = 1000", "radius = 12, points = 1000", SAUC),
    ("SA37 the large saucer radius 15", SA, "radius = 20, points = 200", "radius = 15, points = 200", SAUC),
    # Hyperspace
    ("HY1 31 ticks away", CL, "hyperspaceTicks = 30,", "hyperspaceTicks = 31,", HYP),
    ("HY2 the velocity kept", PI, "p.ship.x, p.ship.y, p.ship.vx, p.ship.vy = x, y, 0, 0", "p.ship.x, p.ship.y = x, y", HYP),
    ("HY3 a fire on the jump's tick", PI, "\tif controls.hyperspace then\n\t\tlocal x = draw(f.width) - 1",
     "\tif controls.hyperspace and controls.fire and #p.shots < c.shotLimit then\n\t\ttable.insert(p.shots, { x = p.ship.x, y = p.ship.y, vx = 0, vy = 8, life = c.shotLife })\n\t\temit({ kind = \"Fire\" })\n\tend\n\tif controls.hyperspace then\n\t\tlocal x = draw(f.width) - 1", HYP),
    ("HY4 any truthy hyperspace", PI, "hyperspace = input.hyperspace == true,", "hyperspace = input.hyperspace ~= nil and input.hyperspace ~= false,", HYP),
    ("HY5 the ship can be hit in hyperspace", PI, "return p.shipState == \"alive\" and p.protect == 0", "return p.shipState ~= \"dead\" and p.protect == 0", HYP),
    ("HY6 the ship flies in hyperspace", PI, CONTROL_GATE, CONTROL_GATE.replace("~= \"alive\"", "== \"dead\""), HYP),
    ("HY7 explodes unless the draw is 1", PI, "if draw(c.hyperspaceOdds) == 1 then", "if draw(c.hyperspaceOdds) ~= 1 then", HYP),
    ("HY8 the odds of the classic table", PI, "if draw(c.hyperspaceOdds) == 1 then", "if draw(6) == 1 then", HYP),
    ("HY9 explodes 1 in 3", PI, "if draw(c.hyperspaceOdds) == 1 then", "if draw(c.hyperspaceOdds) <= 2 then", HYP),
    ("HY10 the spot not drawn", PI, "\t\tlocal x = draw(f.width) - 1\n\t\tlocal y = draw(f.height) - 1", "\t\tlocal x = f.width / 2\n\t\tlocal y = f.height / 2", HYP),
    ("HY11 back a tick late", PI, "\t\tp.timer -= 1\n\t\tif p.timer <= 0 then", "\t\tp.timer -= 1\n\t\tif p.timer < 0 then", HYP),
    ("HY12 a lost ship takes input", PI, CONTROL_GATE, CONTROL_GATE.replace("~= \"alive\"", "== \"hyperspace\""), HYP + LIV),
    ("HY13 the explosion costs no life", PI, "\t\t\t\treturn Pilot.lose(p, c, \"hyperspace\", emit)", "\t\t\t\tp.shipState = \"dead\"\n\t\t\t\tp.timer = c.respawnTicks\n\t\t\t\treturn false", HYP),
    # Lives
    ("LI1 four lives", CL, "\tlives = 3,", "\tlives = 4,", LIV),
    ("LI2 the wait 119 ticks", CL, "respawnTicks = 120,", "respawnTicks = 119,", LIV),
    ("LI3 back where it was lost", PI, [
        (DESTROY_SHIP, "\tp.ship.vx, p.ship.vy = 0, 0\n\tp.shipState = \"dead\""),
        (RESPAWN_SHIP, "\t\t\tp.ship = Ship.new(c.ship, p.ship.x, p.ship.y)\n\t\t\tp.shipState = \"alive\""),
    ], None, LIV),
    ("LI4 the centre not checked", PI, "if p.timer == 0 and clear() then", "if p.timer == 0 then", LIV),
    ("LI5 the rock's size not counted", CL, "< Rocks.SIZES[r.size].radius + c.clearRadius then", "< c.clearRadius then", LIV),
    ("LI6 a clear radius of 70", CL, "clearRadius = 80,", "clearRadius = 70,", LIV),
    ("LI7 the saucer not checked", CL, "if s and Field.distance(f, cx, cy, s.x, s.y) < c.saucers[s.kind].radius + c.clearRadius then", "if false then", LIV),
    ("LI8 protected 119 ticks", CL, "protectTicks = 120,", "protectTicks = 119,", LIV),
    ("LI9 no protection", PI, "\t\t\tp.protect = c.protectTicks", "\t\t\tp.protect = 0", LIV),
    ("LI10 the protected ship cannot fire", PI, CONTROL_GATE, CONTROL_GATE.replace("~= \"alive\" then", "~= \"alive\" or p.protect > 0 then"), LIV),
    ("LI11 a loss clears the shots", PI, "\tp.protect = 0\n\treturn p.lives <= 0", "\tp.protect = 0\n\tp.shots = {}\n\treturn p.lives <= 0", LIV),
    ("LI12 one extra life only", PI, "while c.extraLifeEvery > 0 and p.score >= p.nextExtra do", "while p.nextExtra == c.extraLifeEvery and p.score >= p.nextExtra do", LIV),
    ("LI13 the extra life past 10,000", PI, "and p.score >= p.nextExtra do", "and p.score > p.nextExtra do", LIV),
    ("LI14 the next extra from the score", PI, "p.nextExtra += c.extraLifeEvery", "p.nextExtra = p.score + c.extraLifeEvery", LIV),
    ("LI15 the ram's loss before its points", CL, "\t\t\tbreakRock(g, i, \"ship\", events)\n\t\t\tendIfOut(g, Pilot.lose(g, c, \"rock\", emitter(events)), events)", "\t\t\tlocal out = Pilot.lose(g, c, \"rock\", emitter(events))\n\t\t\tbreakRock(g, i, \"ship\", events)\n\t\t\tendIfOut(g, out, events)", LIV),
    ("LI16 a lost ship still collides", CL, "\tif not Pilot.exposed(g) then\n\t\treturn\n\tend", "\tif g.protect > 0 then\n\t\treturn\n\tend", LIV),
    ("LI17 the run goes on at game over", CL, "\tlocal events: { Event } = {}\n\tif over(g) then\n\t\treturn events\n\tend\n", "\tlocal events: { Event } = {}\n", LIV),
    ("LI18 the last ship plays on", PI, "\treturn p.lives <= 0", "\treturn p.lives < 0", LIV),
    ("LI19 the respawn says no lives", PI, "emit({ kind = \"Respawn\", lives = p.lives })", "emit({ kind = \"Respawn\" })", LIV),
    ("LI20 the heading kept through a loss", PI, [
        (DESTROY_SHIP, "\tp.ship = { x = c.field.width / 2, y = c.field.height / 2, vx = 0, vy = 0, heading = p.ship.heading }\n\tp.shipState = \"dead\""),
        (RESPAWN_SHIP, "\t\t\tp.ship.vx, p.ship.vy = 0, 0\n\t\t\tp.shipState = \"alive\""),
    ], None, LIV),
    ("LI21 a lost ship's shots vanish", CL, "\tlocal kept = {}\n\tfor _, shot in g.shots do", "\tlocal kept = {}\n\tfor _, shot in (if g.shipState == \"dead\" then {} else g.shots) do", LIV),
    # Waves
    ("WA1 five rocks first", CL, "firstRocks = 4,", "firstRocks = 5,", WAV),
    ("WA2 three more a wave", CL, "rocksStep = 2,", "rocksStep = 3,", WAV),
    ("WA3 up to 12", CL, "maxRocks = 11,", "maxRocks = 12,", WAV),
    ("WA4 the next wave after 119 ticks", CL, "waveTicks = 120,", "waveTicks = 119,", WAV),
    ("WA5 rocks start off the edge", CL, "\t\tlocal x, y = at, 0\n", "\t\tlocal x, y = at, 1\n", WAV),
    ("WA6 no move away from the ship", CL, "if Field.distance(f, x, y, g.ship.x, g.ship.y) < c.spawnClear then", "if false then", WAV),
    ("WA7 moved an eighth along, not half", CL, "x = (x + f.width / 2) % f.width", "x = (x + f.width / 8) % f.width", WAV),
    ("WA8 a clearance of 100", CL, "spawnClear = 160,", "spawnClear = 100,", WAV),
    ("WA9 the wave clock paused while the ship is lost", CL, "\tif g.waveTimer > 0 then\n\t\tg.waveTimer -= 1\n", "\tif g.waveTimer > 0 then\n\t\tg.waveTimer -= if g.shipState == \"dead\" then 0 else 1\n", WAV),
    ("WA10 a new wave clears the shots", CL, "\t\t\tg.wave += 1\n\t\t\tspawnWave(g)\n", "\t\t\tg.wave += 1\n\t\t\tg.shots = {}\n\t\t\tspawnWave(g)\n", WAV),
    ("WA11 a new wave clears the saucer", CL, "\t\t\tg.wave += 1\n\t\t\tspawnWave(g)\n", "\t\t\tg.wave += 1\n\t\t\tg.saucer = nil\n\t\t\tspawnWave(g)\n", WAV),
    ("WA12 a new wave restarts the saucer clock", CL, "\t\t\tg.wave += 1\n\t\t\tspawnWave(g)\n", "\t\t\tg.wave += 1\n\t\t\tg.saucerElapsed = 0\n\t\t\tspawnWave(g)\n", WAV),
    ("WA13 the wave number kept", CL, "\t\t\tg.wave += 1\n\t\t\tspawnWave(g)\n", "\t\t\tspawnWave(g)\n", WAV),
    ("WA14 a clear on the tick the run ends", CL, "\tcollide(g, events)\n\tif over(g) then\n\t\treturn events\n\tend\n", "\tcollide(g, events)\n", WAV),
    ("WA15 only the bottom edge", CL, "local at = draw(f.width + f.height) - 1", "local at = draw(f.width) - 1", WAV),
    ("WA16 a new wave keeps the score only partly", CL, "\t\t\tg.wave += 1\n\t\t\tspawnWave(g)\n", "\t\t\tg.wave += 1\n\t\t\tg.score -= g.score % 1000\n\t\t\tspawnWave(g)\n", WAV),
    # The run
    ("GA1 30 ticks a second", CL, "\ttickRate = 60,", "\ttickRate = 30,", GAME),
    ("GA2 the seed scaled, not floored", RN, "math.floor(seed)", "math.floor(seed * 2)", GAME),
    ("GA3 a NaN seed kept", RN, "\tif s ~= s or math.abs(s) == math.huge then", "\tif math.abs(s) == math.huge then", GAME),
    ("GA4 the seed ignored", RN, "\treturn s % (MODULUS - 1) + 1", "\treturn 12345", GAME),
    ("GA5 the draw kept in the run", CL, "\tlocal draw = drawer(g)\n\tfor _ = 1, Classic.rockCount(c, g.wave) do", "\tlocal draw = drawer(g)\n\tlocal kept: any = g\n\tkept.draw = draw\n\tfor _ = 1, Classic.rockCount(c, g.wave) do", GAME),
    ("GA6 the appearing saucer unnamed", CL, "{ kind = \"SaucerAppear\", saucer = new.kind }", "{ kind = \"SaucerAppear\" }", GAME),
    ("RO19 the generator never advances", CL, "\t\tg.rng, v = Rng.next(g.rng, n)", "\t\tlocal _\n\t\t_, v = Rng.next(g.rng, n)", ROCK),
    # design review 001
    ("FI11 a ram measured without the wrap", CL, "\t\tif Field.distance(f, sx, sy, r.x, r.y) < Rocks.SIZES[r.size].radius + c.ship.radius then", "\t\tif math.sqrt((sx - r.x) ^ 2 + (sy - r.y) ^ 2) < Rocks.SIZES[r.size].radius + c.ship.radius then", FIELD),
    ("FI12 a saucer's ram measured without the wrap", CL, "if s and Field.distance(f, sx, sy, s.x, s.y) < c.saucers[s.kind].radius + c.ship.radius then", "if s and math.sqrt((sx - s.x) ^ 2 + (sy - s.y) ^ 2) < c.saucers[s.kind].radius + c.ship.radius then", FIELD),
    ("FI13 a saucer's shot swept without the wrap", CL, "Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, g.ship.x, g.ship.y, c.ship.radius)", "Field.sweep({ width = 1e9, height = 1e9 }, shot.x, shot.y, shot.vx, shot.vy, g.ship.x, g.ship.y, c.ship.radius)", FIELD),
    ("FI14 the ship's shot swept without the wrap", CL, "local t = Field.sweep(f, shot.x, shot.y, shot.vx, shot.vy, r.x, r.y, Rocks.SIZES[r.size].radius)", "local t = Field.sweep({ width = 1e9, height = 1e9 }, shot.x, shot.y, shot.vx, shot.vy, r.x, r.y, Rocks.SIZES[r.size].radius)", FIELD),
    ("FI15 the saucer's shots do not wrap", CL, "\t\telse\n\t\t\tshot.x, shot.y = Field.wrap(f, shot.x + shot.vx, shot.y + shot.vy)\n\t\t\tshot.life -= 1\n\t\t\tif shot.life > 0 then\n\t\t\t\ttable.insert(kept, shot)\n\t\t\tend\n\t\tend\n\tend\n\tg.saucerShots = kept",
     "\t\telse\n\t\t\tshot.x, shot.y = shot.x + shot.vx, shot.y + shot.vy\n\t\t\tshot.life -= 1\n\t\t\tif shot.life > 0 then\n\t\t\t\ttable.insert(kept, shot)\n\t\t\tend\n\t\tend\n\tend\n\tg.saucerShots = kept", FIELD),
    ("OR1 the collisions before the ship's shots", CL, [
        ("\tmoveShots(g, events)\n\tmoveSaucerShots(g, events)\n\tif over(g) then\n\t\treturn events\n\tend\n\tcollide(g, events)\n",
         "\tmoveSaucerShots(g, events)\n\tif over(g) then\n\t\treturn events\n\tend\n\tcollide(g, events)\n\tif over(g) then\n\t\treturn events\n\tend\n\tmoveShots(g, events)\n"),
    ], None, LIV),
    ("OR2 the saucer's shots before the ship's", CL, "\tmoveShots(g, events)\n\tmoveSaucerShots(g, events)\n", "\tmoveSaucerShots(g, events)\n\tmoveShots(g, events)\n", LIV),
    ("OR3 a respawned ship acts from the next tick", PI, [
        ("\t\t\tp.protect = c.protectTicks\n", "\t\t\tp.protect = c.protectTicks\n\t\t\tp.timer = -1\n"),
        (CONTROL_GATE, "\tif p.shipState ~= \"alive\" or p.timer < 0 then\n\t\tp.timer = 0\n\t\treturn\n\tend\n\tlocal f = c.field"),
    ], None, LIV),
    ("OR4 a new saucer moves on its first tick", CL, "\t\t\ttable.insert(events, { kind = \"SaucerAppear\", saucer = new.kind })\n\t\tend\n\t\treturn\n",
     "\t\t\ttable.insert(events, { kind = \"SaucerAppear\", saucer = new.kind })\n\t\t\tSaucers.move(new, sc, f, drawer(g))\n\t\tend\n\t\treturn\n", SAUC),
    ("OR5 the saucer holds fire at a protected ship", CL, "and g.shipState == \"alive\" then\n\t\ts.fireElapsed = 0", "and Pilot.exposed(g) then\n\t\ts.fireElapsed = 0", SAUC),
    ("PR1 the protection stops while away", PI, "\tif p.shipState ~= \"dead\" and p.protect > 0 then", "\tif p.shipState == \"alive\" and p.protect > 0 then", HYP),
    ("PR2 a jump ends the protection", PI, "\t\tp.timer = c.hyperspaceTicks\n", "\t\tp.timer = c.hyperspaceTicks\n\t\tp.protect = 0\n", HYP),
    ("PR3 the protection saves the ship from the explosion", PI, "if draw(c.hyperspaceOdds) == 1 then", "if draw(c.hyperspaceOdds) == 1 and p.protect == 0 then", HYP),
    ("RO20 pieces carry their parent's velocity", RO, "\t\t\ttable.insert(out, Rocks.launch(firstId + i - 1, into, r.x, r.y, draw))",
     "\t\t\tlocal piece = Rocks.launch(firstId + i - 1, into, r.x, r.y, draw)\n\t\t\tpiece.vx += r.vx\n\t\t\tpiece.vy += r.vy\n\t\t\ttable.insert(out, piece)", ROCK),
    ("RO21 a ram at exactly the two radii", CL, "\t\tif Field.distance(f, sx, sy, r.x, r.y) < Rocks.SIZES[r.size].radius + c.ship.radius then", "\t\tif Field.distance(f, sx, sy, r.x, r.y) <= Rocks.SIZES[r.size].radius + c.ship.radius then", ROCK),
    ("LI22 the centre blocked at exactly 80 beyond", CL, "< Rocks.SIZES[r.size].radius + c.clearRadius then", "<= Rocks.SIZES[r.size].radius + c.clearRadius then", LIV),
    ("LI23 the loss reports the centre", PI, "lives = p.lives, x = p.ship.x, y = p.ship.y })", "lives = p.lives, x = c.field.width / 2, y = c.field.height / 2 })", LIV + HYP),
    ("LI24 the loss names no place", PI, "lives = p.lives, x = p.ship.x, y = p.ship.y })", "lives = p.lives })", GAME),
]

CV = [
    ("CV1 a hit says where", CL, "{ kind = \"RockHit\", id = r.id, size = r.size, points = points, by = by }", "{ kind = \"RockHit\", id = r.id, size = r.size, points = points, by = by, x = r.x, y = r.y }", ALL),
    ("CV2 the state learns its player count", CL, "\t\twaveTimer = 0,\n\t}", "\t\twaveTimer = 0,\n\t\tplayers = 1,\n\t}", ALL),
    ("CV3 the ship learns an owner", SH, "return { x = x, y = y, vx = 0, vy = 0, heading = c.startHeading }", "return { x = x, y = y, vx = 0, vy = 0, heading = c.startHeading, owner = 1 } :: any", ALL),
    ("CV5 a second pilot stepped by the same functions", CL, "\tPilot.control(g, g.config, Pilot.controls(input), drawer(g), emitter(events))\n",
     "\tPilot.control(g, g.config, Pilot.controls(input), drawer(g), emitter(events))\n\tlocal holder: any = g\n\tholder.wing = holder.wing or Pilot.new(g.config, 0, 0)\n\tPilot.clock(holder.wing, g.config, drawer(g), function()\n\t\treturn true\n\tend, function() end)\n\tPilot.control(holder.wing, g.config, Pilot.controls({ turn = 1 }), drawer(g), function() end)\n", ALL),
    ("CV4 the rocks spawn from a config the caller gives", CL, "\tfor _ = 1, Classic.rockCount(c, g.wave) do", "\tlocal n = Classic.rockCount(c, g.wave)\n\tfor _ = 1, n do", ALL),
]


def run(specs):
    return subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=600).stdout


def verdict(out, correct):
    lines = out.strip().splitlines()
    sums = [l for l in lines if " passed, " in l and " failed, " in l and "spec files" in l]
    last = sums[-1] if sums else (lines[-1] if lines else "NO OUTPUT")
    failed = "0 failed" not in last
    if correct:
        return ("ok (green)" if not failed else "RED: " + last), not failed
    if not failed:
        return "SURVIVED", False
    msgs = [l for l in lines if l.startswith("     ")]
    if any("expected" in m for m in msgs) and not any(("attempt to" in m or "Unknown require" in m or "syntax" in m.lower()) for m in msgs):
        return "killed", True
    return "ERROR (not an assertion): " + (msgs[0].strip() if msgs else last), False


def main():
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    item = os.path.join(HOME, ".tracker", "issues", "f0220")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    for f in ("Field", "Ship", "Rocks", "Saucers", "Pilot", "Classic"):
        shutil.rmtree(os.path.join(HOME, L, f), ignore_errors=True)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "prototype.patch")], check=True)
    only = sys.argv[1:]
    out = run(ALL)
    print("intended".ljust(56), verdict(out, True)[0], flush=True)
    bad = 0
    for mid, rel, old, new, specs in M + CV:
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        pairs = old if isinstance(old, list) else [(old, new)]
        edited, anchors = src, True
        for o, n in pairs:
            if edited.count(o) != 1:
                print(mid.ljust(56), "ANCHOR", edited.count(o), repr(o[:50]), flush=True)
                anchors = False
                break
            edited = edited.replace(o, n)
        if not anchors:
            bad += 1
            continue
        open(f, "w").write(edited)
        try:
            msg, good = verdict(run(specs), mid.startswith("CV"))
        finally:
            open(f, "w").write(src)
        if not good:
            bad += 1
        print(mid.ljust(56), msg, flush=True)
    print(f"{len(M)} mutants, {len(CV)} correct variants, {bad} not as intended")
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        code = main()
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    sys.exit(code)
