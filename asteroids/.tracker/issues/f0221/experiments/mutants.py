# f0221 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, reads f0220's prototype and acceptance specs (read only) from this repository's refs or, while
# f0220's prep is in flight and unpushed, from its prep worktree, refuses unless they are the ones this check was
# cut from (their SHA-256 below), applies f0220's prototype and then this item's prototype.patch in the clone, runs
# f0220's specs and this item's specs on the unmutated base (all must pass), then applies each mutant (and each
# correct variant) in turn, runs the row's spec files from the clone's asteroids/, restores the file, and deletes
# the clone at the end.
# A mutant is killed when its spec run reports a FAIL whose message is an assertion ("expected ...") and no spec
# failed to load (a syntax or require error); another case of the same file may then fail on a runtime error. A correct variant (CV) must keep every spec green, f0220's included.
# Usage, from anywhere: ./zn run --time 1500 -- python3 -I <this file> [id prefixes...]
import hashlib, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
COMMON = subprocess.run(["git", "-C", HERE, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0221-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "asteroids")

# f0220's prototype and specs this base was cut from (its prepared prep branch, ac257be4, 2026-11-15)
F0220_PATCH_SHA = "d2bd00f257acbfbb47289f3e9079dc4b6dc552601ef475ad68f2103728025bd3"
F0220_SPECS_SHA = "775f2d095346ae0ced597cd64582a529d015ab4dcb51230382ae144016ad1d2f"
F0220_SPECS = ["field", "game", "hyperspace", "lives", "rocks", "saucers", "ship", "shots", "waves"]
F0220_REFS = ["HEAD", "origin/main", "origin/prep-asteroids-classic-rules", "prep-asteroids-classic-rules"]
F0220_WORKTREE = os.path.join(os.path.dirname(COMMON), ".worktree", "prep-asteroids-classic-rules")

A = ".tracker/issues/f0221/acceptance/"
FIELD = [A + "field.spec.luau"]
SCORES = [A + "scores.spec.luau"]
CONTACT = [A + "contact.spec.luau"]
SURV = [A + "survivor.spec.luau"]
MATCH = [A + "match.spec.luau"]
MINE = FIELD + SCORES + CONTACT + SURV + MATCH
B = ".tracker/issues/f0220/acceptance/"
THEIRS = [B + n + ".spec.luau" for n in F0220_SPECS]
ALL = MINE + THEIRS
L = "src/shared/Logic/"
TP = L + "TwoPlayer/init.luau"
CL = L + "Classic/init.luau"
PI = L + "Pilot/init.luau"

M = [
    # One field, opposite sides, 1.5 x the rocks (AC1)
    ("FI1 both ships start at the centre", TP, "\t\ttable.freeze({ x = W / 4, y = H / 2 }),\n\t\ttable.freeze({ x = 3 * W / 4, y = H / 2 }),", "\t\ttable.freeze({ x = W / 2, y = H / 2 }),\n\t\ttable.freeze({ x = W / 2, y = H / 2 }),", FIELD),
    ("FI2 player 2 starts pointing down", TP, "\t\tship = Ship.new(c.classic.ship, home.x, home.y),", "\t\tship = (function()\n\t\t\tlocal s = Ship.new(c.classic.ship, home.x, home.y)\n\t\t\tif slot == 2 then\n\t\t\t\ts.heading = 192\n\t\t\tend\n\t\t\treturn s\n\t\tend)(),", FIELD),
    ("FI3 16.5 rounded up", TP, "{ firstRocks = 6, rocksStep = 3, maxRocks = 16 }", "{ firstRocks = 6, rocksStep = 3, maxRocks = 17 }", FIELD),
    ("FI4 the solo count in wave 1", TP, "{ firstRocks = 6, rocksStep = 3, maxRocks = 16 }", "{ firstRocks = 4, rocksStep = 3, maxRocks = 16 }", FIELD),
    ("FI5 the solo step", TP, "{ firstRocks = 6, rocksStep = 3, maxRocks = 16 }", "{ firstRocks = 6, rocksStep = 2, maxRocks = 16 }", FIELD),
    ("FI6 another solo number changed", TP, "{ firstRocks = 6, rocksStep = 3, maxRocks = 16 }", "{ firstRocks = 6, rocksStep = 3, maxRocks = 16, shotLife = 50 }", FIELD),
    ("FI7 the match plays the solo config", TP, "\t\tconfig = c.classic,\n", "\t\tconfig = Classic.CONFIG,\n", FIELD),
    ("FI8 a saucer clock per player", TP, "\tClassic.saucerStep(m, target(m, order), events)\n", "\tClassic.saucerStep(m, target(m, order), events)\n\tif m.saucer == nil then\n\t\tm.saucerElapsed += 1\n\tend\n", FIELD),
    ("FI9 rocks clear of player 1's ship only", TP, "\tClassic.waveClock(m, ships(m), events)\n", "\tClassic.waveClock(m, { m.pilots[1].ship }, events)\n", FIELD),
    ("FI10 the rock always moves half the edge along", CL, "\t\t\tif nearest(f, mx, my, ships) >= near then\n", "\t\t\tif true then\n", FIELD),
    ("FI11 the rock moves only to a clear point", CL, "\t\t\tif nearest(f, mx, my, ships) >= near then\n", "\t\t\tif nearest(f, mx, my, ships) >= c.spawnClear then\n", FIELD),
    ("FI12 wave 1 clear of player 1 only", TP, "\tClassic.spawnWave(m, ships(m))\n\treturn m", "\tClassic.spawnWave(m, { m.pilots[1].ship })\n\treturn m", FIELD),
    # Each player's own ship, shots, score, lives (AC2)
    ("SC1 player 2 reads player 1's input", TP, "\treturn inputs[slot]\nend", "\treturn inputs[1]\nend", SCORES),
    ("SC2 two shots each", TP, "{ firstRocks = 6, rocksStep = 3, maxRocks = 16 }", "{ firstRocks = 6, rocksStep = 3, maxRocks = 16, shotLimit = 2 }", SCORES),
    ("SC3 a rock's points name no player", CL, "{ kind = \"RockHit\", id = r.id, size = r.size, points = points, by = by, player = p.slot }", "{ kind = \"RockHit\", id = r.id, size = r.size, points = points, by = by }", SCORES),
    ("SC4 a loss costs both players a life", TP, "\t\t\tClassic.collide(m, p, events)\n", "\t\t\tClassic.collide(m, p, events)\n\t\t\tif p.shipState == \"dead\" and p.timer == m.config.respawnTicks then\n\t\t\t\tfor _, q in m.pilots do\n\t\t\t\t\tif q ~= p then\n\t\t\t\t\t\tq.lives -= 1\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\tend\n", SCORES),
    ("SC5 player 2's first extra life at 20,000", TP, "\t\tnextExtra = c.classic.extraLifeEvery,\n", "\t\tnextExtra = c.classic.extraLifeEvery * slot,\n", SCORES),
    ("SC6 every ship respawns at the centre", PI, "\tlocal h = p.home\n\tif h then", "\tlocal h = nil :: Home?\n\tif h then", SCORES),
    ("SC7 the respawn waits for the centre", CL, "\t\treturn Classic.clearAt(g, hx, hy)\n", "\t\treturn Classic.clearAt(g, g.config.field.width / 2, g.config.field.height / 2)\n", SCORES),
    ("SC8 the saucer aims at player 1", TP, "\tlocal best, bestD = nil :: Pilot?, math.huge\n\tfor _, p in order do", "\tif playing(m.pilots[1]) and m.pilots[1].shipState == \"alive\" then\n\t\treturn m.pilots[1]\n\tend\n\tlocal best, bestD = nil :: Pilot?, math.huge\n\tfor _, p in order do", SCORES),
    ("SC9 the saucer aims from no score", CL, "Saucers.aim(s, sc, f, target.score, target.ship.x, target.ship.y, Classic.draw(g))", "Saucers.aim(s, sc, f, 0, target.ship.x, target.ship.y, Classic.draw(g))", SCORES),
    ("SC10 the saucer fires at a ship that is away", TP, "\t\tif playing(p) and p.shipState == \"alive\" then\n\t\t\tlocal d = Field.distance(m.config.field, s.x, s.y, p.ship.x, p.ship.y)", "\t\tif playing(p) then\n\t\t\tlocal d = Field.distance(m.config.field, s.x, s.y, p.ship.x, p.ship.y)", SCORES),
    ("SC11 a saucer shot takes the first listed ship", CL, "\t\t\t\tif t and (best == nil or t < best) then\n\t\t\t\t\tbest, hit = t, p", "\t\t\t\tif t and best == nil then\n\t\t\t\t\tbest, hit = t, p", SCORES),
    ("SC12 a saucer shot hits a protected ship", CL, "\t\t\tif Pilot.exposed(p) then\n\t\t\t\tlocal t = Field.sweep", "\t\t\tif p.shipState == \"alive\" then\n\t\t\t\tlocal t = Field.sweep", SCORES),
    ("SC13 player 1 always leads", TP, "\tm.lead = 3 - m.lead\n", "", SCORES),
    ("SC14 player 1's shots first whoever leads", TP, "\tfor i, p in order do\n\t\tif playing(p) then\n\t\t\tlocal foe = order[3 - i]", "\tfor i, p in m.pilots do\n\t\tif playing(p) then\n\t\t\tlocal foe = m.pilots[3 - i]", SCORES),
    ("SC15 the saucer's tie to player 1", TP, "\tlocal best, bestD = nil :: Pilot?, math.huge\n\tfor _, p in order do", "\tlocal best, bestD = nil :: Pilot?, math.huge\n\tfor _, p in m.pilots do", SCORES),
    ("SC16 a fire names no player", CL, "\t\t\tplayer = p.slot,\n\t\t\tshooter = shooter,", "\t\t\tplayer = if e.kind == \"Fire\" then nil else p.slot,\n\t\t\tshooter = shooter,", SCORES),
    ("SC17 the extra life names no player", CL, "\t\t\tplayer = p.slot,\n\t\t\tshooter = shooter,", "\t\t\tplayer = if e.kind == \"ExtraLife\" then nil else p.slot,\n\t\t\tshooter = shooter,", SCORES),
    ("SC18 a shot leaves from the other player's nose", PI, "\t\tlocal x, y = Ship.nose(p.ship, c.ship, f)\n", "\t\tlocal x, y = Ship.nose(p.ship, c.ship, f)\n\t\tif (p :: any).slot == 2 then\n\t\t\tx = (x + f.width / 2) % f.width\n\t\tend\n", SCORES),
    ("SC19 a saucer shot's exact tie to the later listed", CL, "\t\t\t\tif t and (best == nil or t < best) then\n\t\t\t\t\tbest, hit = t, p", "\t\t\t\tif t and (best == nil or t <= best) then\n\t\t\t\t\tbest, hit = t, p", CONTACT),
    ("SC20 the other ship holds a respawn", TP, "\t\t\tClassic.clock(m, p, events)\n", "\t\t\tlocal o = m.pilots[3 - (p.slot :: number)]\n\t\t\tlocal h = p.home :: Classic.Home\n\t\t\tif not (p.shipState == \"dead\" and o.shipState == \"alive\" and Field.distance(m.config.field, h.x, h.y, o.ship.x, o.ship.y) < 92) then\n\t\t\t\tClassic.clock(m, p, events)\n\t\t\tend\n", SCORES),
    ("SC21 the nearer by the raw difference", TP, "\t\t\tlocal d = Field.distance(m.config.field, s.x, s.y, p.ship.x, p.ship.y)", "\t\t\tlocal d = math.sqrt((s.x - p.ship.x) ^ 2 + (s.y - p.ship.y) ^ 2)", SCORES),
    ("SC22 aimed from the higher score", CL, "Saucers.aim(s, sc, f, target.score,", "Saucers.aim(s, sc, f, if (g :: any).pilots then math.max((g :: any).pilots[1].score, (g :: any).pilots[2].score) else target.score,", SCORES),
    ("SC23 the collisions in slot order", TP, "\t-- 8. each ship's collisions\n\tfor _, p in order do", "\t-- 8. each ship's collisions\n\tfor _, p in m.pilots do", SCORES),
    ("SC24 the controls in slot order", TP, "\t-- 2. each player's input\n\tfor _, p in order do", "\t-- 2. each player's input\n\tfor _, p in m.pilots do", SCORES),
    ("SC25 the clocks in slot order", TP, "\t-- 1. each ship's clocks\n\tfor _, p in order do", "\t-- 1. each ship's clocks\n\tfor _, p in m.pilots do", SCORES),
    # No friendly fire, ships bounce; two switches (AC3)
    ("CO1 friendly fire by default", TP, "\tfriendlyFire = false,\n", "\tfriendlyFire = true,\n", CONTACT),
    ("CO2 no bounce by default", TP, "\tshipsBounce = true,\n", "\tshipsBounce = false,\n", CONTACT),
    ("CO3 the friendly-fire switch ignored", TP, "Classic.moveShots(m, p, if m.pair.friendlyFire and playing(foe) then foe else nil, events)", "Classic.moveShots(m, p, nil, events)", CONTACT),
    ("CO4 a hit on the other ship scores", CL, "\t\t\tlose(g, foe :: Player, \"shot\", events, p.slot)\n", "\t\t\tlose(g, foe :: Player, \"shot\", events, p.slot)\n\t\t\tPilot.award(p, g.config, 200, emitter(events, p))\n", CONTACT),
    ("CO5 friendly fire hits a protected ship", CL, "\t\tif foe and Pilot.exposed(foe) then", "\t\tif foe and foe.shipState == \"alive\" then", CONTACT),
    ("CO6 friendly fire hits the shooter's own ship", TP, "\t\t\tlocal foe = order[3 - i]\n", "\t\t\tlocal foe = p\n", CONTACT),
    ("CO7 the shooter not named", CL, "\t\t\tlose(g, foe :: Player, \"shot\", events, p.slot)\n", "\t\t\tlose(g, foe :: Player, \"shot\", events)\n", CONTACT),
    ("CO8 the other ship before a rock on a tie", CL, "\t\tif ft and (best == nil or ft < best) and (st == nil or ft < st) then", "\t\tif ft and (best == nil or ft <= best) and (st == nil or ft <= st) then", CONTACT),
    ("CO9 the shot that hit flies on", CL, "\t\t\tlose(g, foe :: Player, \"shot\", events, p.slot)\n", "\t\t\tlose(g, foe :: Player, \"shot\", events, p.slot)\n\t\t\ttable.insert(kept, shot)\n", CONTACT),
    ("CO10 a bounce leaves them overlapping", TP, "\ta.ship.x, a.ship.y = Field.wrap(f, a.ship.x - nx * push, a.ship.y - ny * push)\n\tb.ship.x, b.ship.y = Field.wrap(f, b.ship.x + nx * push, b.ship.y + ny * push)\n", "", CONTACT),
    ("CO11 each moves the whole overlap", TP, "\tlocal push = (reach - d) / 2\n", "\tlocal push = reach - d\n", CONTACT),
    ("CO12 the whole velocities swapped", TP, "\tif closing < 0 then\n\t\ta.ship.vx += nx * closing\n\t\ta.ship.vy += ny * closing\n\t\tb.ship.vx -= nx * closing\n\t\tb.ship.vy -= ny * closing\n\tend", "\tif closing < 0 then\n\t\ta.ship.vx, b.ship.vx = b.ship.vx, a.ship.vx\n\t\ta.ship.vy, b.ship.vy = b.ship.vy, a.ship.vy\n\tend", CONTACT),
    ("CO13 the speeds swap when moving apart too", TP, "\tif closing < 0 then\n\t\ta.ship.vx += nx * closing", "\tif closing ~= 0 then\n\t\ta.ship.vx += nx * closing", CONTACT),
    ("CO14 a bounce past the top speed", TP, "\t\tif speed > c.ship.maxSpeed then\n\t\t\ts.vx = s.vx * c.ship.maxSpeed / speed", "\t\tif speed > 2 * c.ship.maxSpeed then\n\t\t\ts.vx = s.vx * c.ship.maxSpeed / speed", CONTACT),
    ("CO15 the bounce ignores the wrap", TP, "\tlocal dx, dy = Field.delta(f, a.ship.x, a.ship.y, b.ship.x, b.ship.y)\n", "\tlocal dx, dy = b.ship.x - a.ship.x, b.ship.y - a.ship.y\n", CONTACT),
    ("CO16 a ship that is away bounces", TP, "\t\tand a.shipState == \"alive\"\n\t\tand b.shipState == \"alive\"\n", "", CONTACT),
    ("CO17 protected ships don't bounce", TP, "\t\tand a.shipState == \"alive\"\n\t\tand b.shipState == \"alive\"\n", "\t\tand a.shipState == \"alive\"\n\t\tand b.shipState == \"alive\"\n\t\tand a.protect == 0\n\t\tand b.protect == 0\n", CONTACT),
    ("CO18 the bounce switch ignored", TP, "\t\tm.pair.shipsBounce\n\t\tand playing(a)", "\t\tplaying(a)", CONTACT),
    ("CO19 a bounce costs a life", TP, "\ttable.insert(events, { kind = \"Bounce\" })\n", "\ttable.insert(events, { kind = \"Bounce\" })\n\ta.lives -= 1\n\tb.lives -= 1\n", CONTACT),
    ("CO20 touching ships bounce", TP, "\tif d >= reach then\n\t\treturn\n\tend", "\tif d > reach then\n\t\treturn\n\tend", CONTACT),
    ("CO21 ships on one point part along y", TP, "\tlocal nx, ny = 1, 0\n", "\tlocal nx, ny = 0, 1\n", CONTACT),
    ("CO22 the same-point rule in the lead's order", TP, "\t\tbounce(m, m.pilots[1], m.pilots[2], events)", "\t\tbounce(m, a, b, events)", CONTACT),
    ("CO23 the foe only when nothing else is on the move", CL, "\t\tif ft and (best == nil or ft < best) and (st == nil or ft < st) then", "\t\tif ft and best == nil and st == nil then", CONTACT),
    # A lone survivor, the match's end, revive, leave (AC4)
    ("SU1 one out ends the match", TP, "\tif left == 0 then\n\t\tm.phase = \"gameover\"", "\tif left < 2 then\n\t\tm.phase = \"gameover\"", SURV),
    ("SU2 an out player's ship comes back", TP, "\tfor _, p in order do\n\t\tif playing(p) then\n\t\t\tClassic.clock(m, p, events)", "\tfor _, p in order do\n\t\tif true then\n\t\t\tClassic.clock(m, p, events)", SURV),
    ("SU3 an out player's shots fly on", TP, "\t\telse\n\t\t\tp.shots = {}\n\t\tend\n\tend\n\tif left == 0 then", "\t\tend\n\tend\n\tif left == 0 then", SURV),
    ("SU4 an out player's shots fly the tick they go out", TP, "\t-- 1. each ship's clocks\n\tfor _, p in order do\n\t\tif playing(p) then\n\t\t\tClassic.clock(m, p, events)\n\t\tend\n\tend\n\tif settle(m, events) then\n\t\treturn events\n\tend\n", "\t-- 1. each ship's clocks\n\tfor _, p in order do\n\t\tif playing(p) then\n\t\t\tClassic.clock(m, p, events)\n\t\tend\n\tend\n", SURV, [("\tfor i, p in order do\n\t\tif playing(p) then\n\t\t\tlocal foe = order[3 - i]", "\tfor i, p in order do\n\t\tif true then\n\t\t\tlocal foe = order[3 - i]")]),
    ("SU5 the survivor's waves at the solo count", TP, "\tif left == 0 then\n\t\tm.phase = \"gameover\"", "\tif left == 1 then\n\t\tm.config = Classic.CONFIG\n\tend\n\tif left == 0 then\n\t\tm.phase = \"gameover\"", SURV),
    ("SU6 the out player's home kept clear", TP, "\tfor _, p in m.pilots do\n\t\tif playing(p) then\n\t\t\ttable.insert(out, p.ship)", "\tfor _, p in m.pilots do\n\t\tif true then\n\t\t\ttable.insert(out, p.ship)", SURV),
    ("SU7 no MatchOver", TP, "\t\ttable.insert(events, { kind = \"MatchOver\" })\n", "", SURV),
    ("SU8 a finished match goes on", TP, "\tlocal events: { Classic.Event } = {}\n\tif over(m) then\n\t\treturn events\n\tend\n\tlocal order", "\tlocal events: { Classic.Event } = {}\n\tlocal order", SURV),
    ("SU9 a revive loses the score", TP, "\tp.revives += 1\n", "\tp.revives += 1\n\tp.score = 0\n", SURV),
    ("SU10 a revive restarts the extra-life count", TP, "\tp.revives += 1\n", "\tp.revives += 1\n\tp.nextExtra = p.score + m.config.extraLifeEvery\n", SURV),
    ("SU11 a revive not counted", TP, "\tp.revives += 1\n", "", SURV),
    ("SU12 a revived ship comes back at once", TP, "\tp.shipState = \"dead\"\n\tp.timer = 0\n\tp.protect = 0\n\tp.shots = {}\n\tm.phase = \"playing\"", "\tp.shipState = \"alive\"\n\tp.timer = 0\n\tp.protect = m.config.protectTicks\n\tp.shots = {}\n\tm.phase = \"playing\"", SURV),
    ("SU13 a revive leaves the match over", TP, "\tp.shots = {}\n\tm.phase = \"playing\"\n\treturn true", "\tp.shots = {}\n\treturn true", SURV),
    ("SU14 a revive while playing", TP, "\tif p == nil or p.left or p.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tp.phase = \"playing\"", "\tif p == nil or p.left then\n\t\treturn false\n\tend\n\tp.phase = \"playing\"", SURV),
    ("SU15 a revive after leaving", TP, "\tif p == nil or p.left or p.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tp.phase = \"playing\"", "\tif p == nil or p.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tp.phase = \"playing\"", SURV),
    ("SU16 a leaver's ship stays on the field", TP, "\tp.ship = Ship.new(m.config.ship, home.x, home.y)\n\tp.shipState = \"dead\"\n", "\tp.ship = Ship.new(m.config.ship, home.x, home.y)\n", SURV),
    ("SU17 a leaver's shots stay", TP, "\tp.protect = 0\n\tp.shots = {}\n\tlocal any = false", "\tp.protect = 0\n\tlocal any = false", SURV),
    ("SU18 a second leave counts", TP, "\tif p == nil or p.left then\n\t\treturn false\n\tend\n\tp.left = true", "\tif p == nil then\n\t\treturn false\n\tend\n\tp.left = true", SURV),
    ("SU19 the last to leave leaves the match playing", TP, "\tif not any then\n\t\tm.phase = \"gameover\"\n\tend\n\treturn true", "\treturn true", SURV),
    ("SU20 an out player's input still steers", TP, "\t\tif playing(p) then\n\t\t\tClassic.control(m, p, inputOf(inputs, p.slot :: number), events)", "\t\tif true then\n\t\t\tif p.shipState ~= \"alive\" then\n\t\t\t\tp.ship.heading = (p.ship.heading + 3) % 256\n\t\t\tend\n\t\t\tClassic.control(m, p, inputOf(inputs, p.slot :: number), events)", SURV),
    ("SU21 a revive restarts the wave", TP, "\tp.revives += 1\n", "\tp.revives += 1\n\tm.wave = 1\n", SURV),
    ("SU22 a revive resets the other player's lives", TP, "\tp.revives += 1\n", "\tp.revives += 1\n\tm.pilots[3 - slot].lives = m.config.lives\n", SURV),
    # The match (AC5)
    ("MA1 the seed ignored", TP, "\t\trng = Classic.seed(seed),\n", "\t\trng = Classic.seed(0),\n", MATCH),
    ("MA2 not deterministic", TP, "\t\trng = Classic.seed(seed),\n", "\t\trng = Classic.seed(seed + math.random(1, 1000)),\n", MATCH),
    ("MA3 the seed read raw", TP, "\t\trng = Classic.seed(seed),\n", "\t\trng = if seed == seed then seed else 0,\n", MATCH),
    ("MA4 a respawn names no player", CL, "\t\t\tplayer = p.slot,\n\t\t\tshooter = shooter,", "\t\t\tplayer = if e.kind == \"Respawn\" then nil else p.slot,\n\t\t\tshooter = shooter,", MATCH),
    ("MA5 the saucer's fire names its target", CL, "\t\ttable.insert(events, { kind = \"SaucerFire\", saucer = s.kind })", "\t\ttable.insert(events, { kind = \"SaucerFire\", saucer = s.kind, player = target.slot })", MATCH),
    ("MA6 every loss names a shooter", CL, "\tendIfOut(p, Pilot.lose(p, g.config, cause, emitter(events, p, shooter)), events)", "\tendIfOut(p, Pilot.lose(p, g.config, cause, emitter(events, p, shooter or p.slot)), events)", MATCH),
    ("MA7 the out players kept as a sparse list", TP, "\t\telse\n\t\t\tp.shots = {}\n\t\tend", "\t\telse\n\t\t\tp.shots = {}\n\t\t\tlocal mm = m :: any\n\t\t\tmm.out = mm.out or {}\n\t\t\tmm.out[(p.slot :: number) + 1] = true\n\t\tend", MATCH),
    ("MA8 a match that never ends", TP, "\tif left == 0 then\n\t\tm.phase = \"gameover\"\n\t\ttable.insert(events, { kind = \"MatchOver\" })\n\t\treturn true\n\tend", "\tif left == -1 then\n\t\treturn true\n\tend", MATCH),
    ("MA9 a tick rate of its own", TP, "{ firstRocks = 6, rocksStep = 3, maxRocks = 16 }", "{ firstRocks = 6, rocksStep = 3, maxRocks = 16, tickRate = 30 }", MATCH),
    ("MA10 a hyperspace names no player", CL, "\t\t\tplayer = p.slot,\n\t\t\tshooter = shooter,", "\t\t\tplayer = if e.kind == \"Hyperspace\" then nil else p.slot,\n\t\t\tshooter = shooter,", MATCH),
    # The solo rules unchanged by the split (AC6, f0220's specs)
    ("SO1 the solo saucer holds its fire", CL, "\tClassic.saucerStep(g, if g.shipState == \"alive\" then g else nil, events)", "\tClassic.saucerStep(g, nil, events)", THEIRS),
    ("SO2 the solo saucer's shots never hit", CL, "\tClassic.moveSaucerShots(g, { g }, events)", "\tClassic.moveSaucerShots(g, {}, events)", THEIRS),
    ("SO3 the solo wave ignores the ship", CL, "\tClassic.waveClock(g, { g.ship }, events)", "\tClassic.waveClock(g, {}, events)", THEIRS),
    ("SO4 the solo respawn off the centre", PI, "\treturn c.field.width / 2, c.field.height / 2\nend", "\treturn c.field.width / 4, c.field.height / 2\nend", THEIRS),
]

# Correct variants: right changes of the kind f0222 (the view, the place) and f0223 (boards, the revive offer) are
# expected to make. Each must keep every spec green, f0220's included.
CV = [
    ("CV1 a respawn says where", PI, "\t\t\temit({ kind = \"Respawn\", lives = p.lives })", "\t\t\temit({ kind = \"Respawn\", lives = p.lives, x = hx, y = hy })", ALL),
    ("CV2 a pilot learns who flies it", TP, "\t\trevives = 0,\n\t\tleft = false,\n", "\t\trevives = 0,\n\t\tleft = false,\n\t\tname = \"\",\n", ALL),
    ("CV3 the match counts its ticks", TP, "\t\tlead = 1,\n", "\t\tlead = 1,\n\t\tticks = 0,\n", ALL),
    ("CV4 a solo revive in Classic", CL, "-- read through a call, so the checks after each stage are not narrowed away\nlocal function over(g: Game)", "function Classic.revive(g: Game): boolean\n\tif g.phase ~= \"gameover\" then\n\t\treturn false\n\tend\n\tg.phase = \"playing\"\n\tg.lives = g.config.lives\n\tg.timer = 0\n\treturn true\nend\n\n-- read through a call, so the checks after each stage are not narrowed away\nlocal function over(g: Game)", ALL),
    ("CV5 a solo run counts its revives", CL, "\t\twaveTimer = 0,\n\t}\n\tClassic.spawnWave(g, { g.ship })", "\t\twaveTimer = 0,\n\t\trevives = 0,\n\t} :: any\n\tClassic.spawnWave(g, { g.ship })", ALL),
    ("CV6 a bounce says where", TP, "\ttable.insert(events, { kind = \"Bounce\" })\n", "\ttable.insert(events, { kind = \"Bounce\", x = a.ship.x, y = a.ship.y })\n", ALL),
]


def run(specs):
    return subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=900).stdout


def verdict(out, correct):
    lines = out.strip().splitlines()
    sums = [l for l in lines if " passed, " in l and " failed, " in l and "spec files" in l]
    last = sums[-1] if sums else (lines[-1] if lines else "NO OUTPUT")
    failed = "0 failed" not in last
    if correct:
        fails = [l.strip() for l in lines if l.startswith("FAIL ")]
        return ("ok (green)" if not failed else "RED: " + last + " " + "; ".join(fails)), not failed
    if not failed:
        return "SURVIVED", False
    msgs = [l for l in lines if l.startswith("     ")]
    # killed: a case fails on an assertion, and nothing failed to load (a syntax or require error)
    loads = [l for l in lines if "could not load" in l or "Unknown require" in l or "syntax" in l.lower()]
    if any("expected" in m for m in msgs) and not loads:
        return "killed", True
    return "ERROR (not an assertion): " + (msgs[0].strip() if msgs else last), False


def git_show(ref, path):
    r = subprocess.run(["git", "-C", REPO, "show", f"{ref}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def f0220_files():
    for ref in F0220_REFS:
        names = subprocess.run(["git", "-C", REPO, "ls-tree", "-r", "--name-only", ref], capture_output=True, text=True).stdout.splitlines()
        patch = [n for n in names if n.endswith("/f0220/experiments/prototype.patch")]
        if not patch:
            continue
        folder = patch[0][: -len("experiments/prototype.patch")]
        specs = {n: git_show(ref, folder + "acceptance/" + n + ".spec.luau") for n in F0220_SPECS}
        if all(specs.values()):
            return ref, git_show(ref, patch[0]), specs
    item = os.path.join(F0220_WORKTREE, "asteroids", ".tracker", "issues", "f0220")
    if os.path.isfile(os.path.join(item, "experiments", "prototype.patch")):
        read = lambda p: open(p, "rb").read()
        specs = {n: read(os.path.join(item, "acceptance", n + ".spec.luau")) for n in F0220_SPECS}
        return F0220_WORKTREE, read(os.path.join(item, "experiments", "prototype.patch")), specs
    sys.exit("refusing: f0220's prototype and specs are on none of " + ", ".join(F0220_REFS) + " nor in " + F0220_WORKTREE)


def main():
    ref, patch, specs = f0220_files()
    got_patch = hashlib.sha256(patch).hexdigest()
    got_specs = hashlib.sha256(b"".join(specs[n] for n in F0220_SPECS)).hexdigest()
    if got_patch != F0220_PATCH_SHA or got_specs != F0220_SPECS_SHA:
        sys.exit(f"refusing: f0220's prototype or specs in {ref} moved since this base was cut; re-cut prototype.patch")
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    if os.path.exists(os.path.join(HOME, "src/shared/Logic/Classic/init.luau")):
        sys.exit("refusing: Classic already exists in the clone (f0220 is implemented); re-cut prototype.patch on it")
    item = os.path.join(HOME, ".tracker", "issues", "f0221")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    theirs = os.path.join(HOME, ".tracker", "issues", "f0220", "acceptance")
    os.makedirs(theirs, exist_ok=True)
    for n in F0220_SPECS:
        open(os.path.join(theirs, n + ".spec.luau"), "wb").write(specs[n])
    base = os.path.join(TMP, "f0220.patch")
    open(base, "wb").write(patch)
    subprocess.run(["git", "-C", CLONE, "apply", base], check=True)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "prototype.patch")], check=True)
    only = sys.argv[1:]
    msg, good = verdict(run(ALL), True)
    print("intended (f0221's and f0220's specs)".ljust(56), msg, flush=True)
    if not good:
        return 1
    bad = 0
    for entry in M + CV:
        mid, rel, old, new, specs_for = entry[:5]
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        extra = entry[5] if len(entry) > 5 else []
        src = open(f).read()
        edited, anchors = src, True
        for o, n in [(old, new)] + extra:
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
            msg, good = verdict(run(specs_for), mid.startswith("CV"))
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
