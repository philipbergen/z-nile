#!/usr/bin/env python3
"""f0211 prep's mutation check: apply each row's mutant to a copy of a prototype's two modules and run the row's spec.

Usage (from the prep worktree's top):
  ./zn run --time 1800 -- python3 snake/.tracker/issues/f0211/experiments/mutants.py <prototype checkout> [ids...]

The prototype is only read. Its `snake/src/shared/Logic/{Maps,World}` and this item's acceptance specs are copied into
a fresh scratch home, `snake/.cache/f0211-mutants-<pid>/` of the checkout this script lives in, with its own
`.luaurc` (`@logic` is the copy, `@tests` the home's tests); each mutant is written into the copy only, and the
folder is removed at the end (design review 001 F7). A mutant is killed when the row's case fails (the spec loads).
A correct variant (C*) must keep every acceptance spec green.
"""
import os
import re
import shutil
import subprocess
import sys

MAPS = "src/shared/Logic/Maps/init.luau"
WORLD = "src/shared/Logic/World/init.luau"

# id, file, old text, new text, spec file, case substring
MUTANTS = [
    # Maps
    ("M1", MAPS, "areaPerPlayer = 250,", "areaPerPlayer = 200,", "maps", "the side for N players"),
    ("M2", MAPS, "return math.ceil(math.sqrt(T.baseArea", "return math.floor(math.sqrt(T.baseArea", "maps", "the side for N players"),
    ("M3", MAPS, "speedStep = 0.25,", "speedStep = 0.5,", "maps", "the speed is 4"),
    ("M4", MAPS, "return math.min(T.speedCap, T.speedStart + T.speedStep * (map - 1))", "return T.speedStart + T.speedStep * (map - 1)", "maps", "the speed is 4"),
    ("M5", MAPS, "goalBase = 10,", "goalBase = 12,", "maps", "the goal length"),
    ("M6", MAPS, "\treturn map - 1\n", "\treturn map\n", "maps", "map k has k - 1 walls"),
    ("M7", MAPS, "local length = T.wallMin - 1 + draw(Maps.wallMax(side) - T.wallMin + 1)", "local length = T.wallMin + 0 * draw(2)", "maps", "each wall is one straight segment"),
    ("M8", MAPS, "math.floor(side / 3))", "math.floor(side / 4))", "maps", "each wall is one straight segment"),
    ("M9", MAPS, 'local dir: Dir = if draw(2) == 1 then "H" else "V"', 'local dir: Dir = if draw(2) == 1 then "H" else "H"', "maps", "the direction is rolled"),
    ("M10", MAPS, "\tfor dy = -1, 1 do\n\t\tfor dx = -1, 1 do\n\t\t\tb.cells", "\tfor dy = 0, 0 do\n\t\tfor dx = 0, 0 do\n\t\t\tb.cells", "maps", "walls never connect"),
    ("M11", MAPS, "if t.x < 2 or t.y < 2 or t.x > side - 1 or t.y > side - 1 then", "if t.x < 1 or t.y < 1 or t.x > side or t.y > side then", "maps", "walls never connect"),
    ("M12", MAPS, "\tfor _, s in spawns do\n\t\tfor _, t in Maps.spawnTiles(s) do\n\t\t\tmark(b, t)", "\tfor _, s in {} :: { Spawn } do\n\t\tfor _, t in Maps.spawnTiles(s) do\n\t\t\tmark(b, t)", "maps", "spawn areas stay clear"),
    ("M13", MAPS, "middleReach = 2,", "middleReach = 6,", "maps", "map 2's single wall is near the middle"),
    ("M14", MAPS, 'local dir: Dir = if draw(2) == 1 then "H" else "V"', 'local dir: Dir = if math.random(2) == 1 then "H" else "V"', "maps", "the roll is seeded"),
    ("M15", MAPS, "grow = 2,", "grow = 4,", "maps", "the arena grows by 2"),
    ("M16", MAPS, "grow = 2,", "grow = 1,", "maps", "the arena grows by 2"),
    ("M17", MAPS, "\t\t\tchosen = scan(map, b)\n", "\t\t\tchosen = nil\n", "maps", "the roll always ends"),
    ("M18", MAPS, "\tif type(n) ~= \"number\" or n < 1 or n ~= math.floor(n) then", "\tif false then", "maps", "below 1 is an error"),
    ("M19", MAPS, "x = x0 + T.startLength, y = (y0 + y1) // 2", "x = x0 + 1, y = (y0 + y1) // 2", "maps", "one spawn per player"),
    # World: start and movement
    ("W1", WORLD, "lives = 3,", "lives = 5,", "moves", "a new world is map 1"),
    ("W2", WORLD, "readySeconds = 2,", "readySeconds = 1,", "moves", "a Ready snake stays put"),
    ("W3", WORLD, "w.untilStep += 1 / Maps.speed(w.map)", "w.untilStep += 0.5 / Maps.speed(w.map)", "moves", "an alive snake moves one tile per step"),
    ("W4", WORLD, "w.untilStep += 1 / Maps.speed(w.map)", "w.untilStep += 1 / Maps.speed(1)", "moves", "on map k it moves at the map's speed"),
    ("W5", WORLD, "heading = Maps.turn(heading, table.remove(s.turns, 1) :: Turn)", 'heading = Maps.turn(heading, if table.remove(s.turns, 1) == "Left" then "Right" else "Left")', "moves", "a turn is Left or Right of the heading"),
    ("W6", WORLD, "turnBuffer = 2,", "turnBuffer = 3,", "moves", "a third is dropped"),
    ("W7", WORLD, "\t\tif #s.turns > 0 then\n\t\t\theading = Maps.turn(heading, table.remove(s.turns, 1) :: Turn)\n\t\tend", "\t\twhile #s.turns > 0 do\n\t\t\theading = Maps.turn(heading, table.remove(s.turns, 1) :: Turn)\n\t\tend", "moves", "a quick Left, Left makes a U-turn"),
    ("W8", WORLD, '\tif turn ~= "Left" and turn ~= "Right" then\n\t\treturn false\n\tend\n', "", "moves", "there is no Back"),
    ("W9", WORLD, 'if s == nil or w.phase ~= "play" or (s.state ~= "ready" and s.state ~= "alive") then', 'if s == nil or w.phase ~= "play" or s.state ~= "alive" then', "moves", "a Ready snake may buffer"),
    ("W10", WORLD, "\t\t\t\tstep(w, draw, events)\n\t\t\t\tw.untilStep += 1 / Maps.speed(w.map)", "\t\t\t\tstep(w, draw, events)\n\t\t\t\tw.untilStep += 1 / Maps.speed(w.map)\n\t\t\t\tleft = 0", "moves", "however the time is cut"),
    ("W11", WORLD, "local EPS = 1e-9", "local EPS = 0", "moves", "real frame rates give the same game"),
    ("W12", WORLD, "\t\t\tw.untilStep -= slice\n\t\t\tfor _, s in w.snakes do\n\t\t\t\tif s.state == \"ready\" or s.state == \"dying\" then\n\t\t\t\t\ts.timer -= slice", "\t\t\tw.untilStep -= slice\n\t\t\tif w.untilStep <= EPS then\n\t\t\t\tstep(w, draw, events)\n\t\t\t\tw.untilStep += 1 / Maps.speed(w.map)\n\t\t\tend\n\t\t\tfor _, s in w.snakes do\n\t\t\t\tif s.state == \"ready\" or s.state == \"dying\" then\n\t\t\t\t\ts.timer -= slice", "moves", "a Ready snake moves on the step its Ready ends"),
    # World: food
    ("F1", WORLD, "\twhile #w.apples < #w.snakes + 1 do", "\twhile #w.apples < #w.snakes do", "food", "players + 1 apples"),
    ("F2", WORLD, "\tlocal occ = occupancy(w)\n\tlocal walls = wallSet(w)\n\tfor _, a in w.apples do", "\tlocal occ: { [number]: number } = {}\n\tlocal walls = wallSet(w)\n\tfor _, a in w.apples do", "food", "never land on a snake"),
    ("F3", WORLD, "appleGrow = 1,", "appleGrow = 0,", "food", "1 longer at once"),
    ("F4", WORLD, "s.score += T.applePoints * w.map", "s.score += T.applePoints", "food", "on map 3 an apple scores 30"),
    ("F5", WORLD, "\tif eaten > 0 then\n\t\ttopUp(w, draw)\n\tend", "", "food", "replaced at once"),
    ("F6", WORLD, "\tif free == 0 then\n\t\treturn\n\tend", "\tif free == 0 then\n\t\ttable.insert(w.apples, { x = 1, y = 1 })\n\t\treturn\n\tend", "food", "no free tile left"),
    ("F8", WORLD, "\tif free == 0 then\n\t\treturn\n\tend\n\tlocal pick = draw(free)", "\tlocal pick = draw(free)\n\tif free == 0 then\n\t\treturn\n\tend", "food", "no free tile left"),
    ("F9", WORLD, "\tif eaten > 0 then\n\t\ttopUp(w, draw)\n\tend", "\tfor _ = 1, eaten do\n\t\tplaceApple(w, draw)\n\tend", "food", "a short count is made up"),
    ("F7", WORLD, "local eats = appleAt(w, head.x, head.y) ~= nil", "local eats = appleAt(w, head.x, head.y) ~= nil or appleAt(w, s.body[1].x, s.body[1].y + 1) ~= nil", "food", "does not reach an apple"),
    # World: deaths
    ("D1", WORLD, "return x >= 1 and y >= 1 and x <= side and y <= side", "return x >= 0 and y >= 0 and x <= side + 1 and y <= side + 1", "deaths", "entering the border dies"),
    ("D2", WORLD, "if not inside(w, head.x, head.y) or walls[k] or (occ[k] or 0) > 1 then", "if not inside(w, head.x, head.y) or (occ[k] or 0) > 1 then", "deaths", "entering a wall dies"),
    ("D3", WORLD, "\tfor _, s in w.snakes do\n\t\tlocal body: { Tile }? = if moved[s]", "\tfor _, s in w.snakes do\n\t\tif moved[s] and #movers == 1 then\n\t\t\tcontinue\n\t\tend\n\t\tlocal body: { Tile }? = if moved[s]", "deaths", "its own body dies"),
    ("D4", WORLD, "\tlocal survivors = {}\n", "\tfor _, s in movers do\n\t\tlocal tl = s.body[#s.body]\n\t\tif #moved[s].body == #s.body then\n\t\t\tocc[key(w, tl.x, tl.y)] = (occ[key(w, tl.x, tl.y)] or 0) + 1\n\t\tend\n\tend\n\tlocal survivors = {}\n", "deaths", "its own tail leaves"),
    ("D5", WORLD, "local body: { Tile }? = if moved[s] then moved[s].body elseif", "local body: { Tile }? = if moved[s] and #movers == 1 then moved[s].body elseif", "deaths", "another snake's body dies"),
    ("D6", WORLD, "\t\tif body then\n\t\t\tfor _, t in body do", "\t\tif body then\n\t\t\tfor j, t in body do\n\t\t\t\tif j == 1 and moved[s] then\n\t\t\t\t\tcontinue\n\t\t\t\tend", "deaths", "two heads entering one tile"),
    ("D7", WORLD, "\t\tif body then\n\t\t\tfor _, t in body do", "\t\tif body then\n\t\t\tfor j, t in body do\n\t\t\t\tif j == 2 and moved[s] then\n\t\t\t\t\tcontinue\n\t\t\t\tend", "deaths", "two heads swapping tiles"),
    ("D8", WORLD, "\t\tif grow > 0 then\n\t\t\tgrow -= 1", "\t\tif s.grow > 0 then\n\t\t\tgrow -= 1", "deaths", "unless that snake grows"),
    ("D9", WORLD, 'elseif s.state == "ready" then s.body else nil', "else nil", "deaths", "a Ready snake is solid"),
    ("D10", WORLD, 'elseif s.state == "ready" then s.body else nil', 'elseif s.state == "ready" or s.state == "dying" then s.body else nil', "deaths", "another may pass where it died"),
    ("D11", WORLD, "deathSeconds = 1.5,", "deathSeconds = 1,", "deaths", "a death waits 1.5 s"),
    ("D12", WORLD, "\tfor i = 0, Maps.TUNING.startLength - 1 do\n\t\ttable.insert(s.body", "\tfor i = 0, Maps.TUNING.startLength - 2 do\n\t\ttable.insert(s.body", "deaths", "respawns with 4 segments"),
    ("D13", WORLD, "\tif s.lives <= 0 then\n\t\ts.state = \"over\"", "\tif s.lives <= 1 then\n\t\ts.state = \"over\"", "deaths", "3 lives"),
    ("D14", WORLD, '\t\t\t\tif allOver(w) then\n\t\t\t\t\tw.phase = "over"\n\t\t\t\tend\n', "", "deaths", "a solo game then stands still"),
    ("D15", WORLD, '\t\tif s.state ~= "over" then\n\t\t\treturn false\n\t\tend\n\tend\n\treturn true', '\t\tif s.state == "over" then\n\t\t\treturn true\n\t\tend\n\tend\n\treturn false', "deaths", "leaves the other playing"),
    ("D16", WORLD, "if a > bestA or (a == bestA and b > bestB) then", "if bestA < 0 or a < bestA or (a == bestA and b > bestB) then", "deaths", "farthest from every other snake's head"),
    ("D17", WORLD, "if a > bestA or (a == bestA and b > bestB) then", "if a > bestA then", "deaths", "farthest from the walls and the border"),
    ("D18", WORLD, "\t\t\t\t\t\ts.timer = w.untilStep -- try again at the next step", '\t\t\t\t\t\ts.state = "over"', "deaths", "no free placement"),
    ("D19", WORLD, 'if s == nil or w.phase ~= "play" or (s.state ~= "ready" and s.state ~= "alive") then', 'if s == nil or w.phase ~= "play" or s.state == "over" then', "deaths", "turns are refused while dying"),
    ("D20", WORLD, "\ts.lives -= 1\n\ts.turns = {}\n", "\ts.lives -= 1\n", "deaths", "a death forgets the buffered ones"),
    ("D21", WORLD, "\t\t\t\t\tif ok then\n\t\t\t\t\t\tfor i = 1, Maps.TUNING.clearAhead do", "\t\t\t\t\tif false then\n\t\t\t\t\t\tfor i = 1, Maps.TUNING.clearAhead do", "deaths", "farthest from every other snake's head"),
    ("D22", WORLD, 'elseif s.state == "ready" then s.body else nil', 'elseif s.state == "ready" or s.state == "over" then s.body else nil', "deaths", "an out snake's body"),
    ("D23", WORLD, "\t\t\tif not walls[k] and not occ[k] then\n\t\t\t\topen[k] = 2", "\t\t\tif not walls[k] then\n\t\t\t\topen[k] = 2", "deaths", "on a crowded board"),
    ("D24", WORLD, "\t\tif open[k] then\n\t\t\topen[k] = 1", "\t\tif false then\n\t\t\topen[k] = 1", "deaths", "on a crowded board"),
    ("D25", WORLD, "\ts.lives -= 1\n", "\ts.lives -= 1\n\ts.body = {}\n", "deaths", "keeps the body it died with"),
    # World: progress
    ("P1", WORLD, "if #s.body >= Maps.goal(w.map) then", "if #s.body > Maps.goal(w.map) then", "progress", "reaching the goal length ends the map"),
    ("P2", WORLD, "s.score += T.clearBonus * w.map", "s.score += T.clearBonus", "progress", "map k clears at 10 + 2k"),
    ("P3", WORLD, "if #s.body >= Maps.goal(w.map) then", "if #s.body >= Maps.goal(w.map) - 1 then", "progress", "one tile short"),
    ("P4", WORLD, "clearSeconds = 2,", "clearSeconds = 1,", "progress", "MAP CLEAR lasts 2 s"),
    ("P5", WORLD, "\t\tif w.phase == \"clear\" then\n\t\t\tslice = math.min(slice, w.timer)", "\t\tif w.phase == \"clear\" then\n\t\t\tslice = math.min(slice, w.timer)\n\t\t\tfor _, s in w.snakes do\n\t\t\t\tif s.state == \"alive\" then\n\t\t\t\t\ts.body[1] = { x = s.body[1].x, y = s.body[1].y }\n\t\t\t\t\ttable.insert(s.body, 1, { x = s.body[1].x + 1, y = s.body[1].y })\n\t\t\t\t\ttable.remove(s.body)\n\t\t\t\tend\n\t\t\tend", "progress", "nothing moves and turns are refused"),
    ("P6", WORLD, 'if s == nil or w.phase ~= "play" or (s.state', 'if s == nil or w.phase == "over" or (s.state', "progress", "nothing moves and turns are refused"),
    ("P7", WORLD, "\t\t\tlocal sp = layout.spawns[i]\n\t\t\tplace(s, { x = sp.x, y = sp.y }, sp.heading, events)", "\t\t\tlocal sp = layout.spawns[i]\n\t\t\tif #s.body == 0 or s.state == \"dying\" then\n\t\t\t\tplace(s, { x = sp.x, y = sp.y }, sp.heading, events)\n\t\t\tend", "progress", "the snake back to 4 segments"),
    ("P8", WORLD, "\tw.phase = \"play\"\n\tw.timer = 0\n", "\tw.phase = \"play\"\n\tw.timer = 0\n\tfor _, s in w.snakes do\n\t\ts.lives = T.lives\n\tend\n", "progress", "the snake back to 4 segments"),
    ("P9", WORLD, "\t\t\ttable.insert(cleared, s.id)\n", "\t\t\ttable.insert(cleared, s.id)\n\t\t\tbreak\n", "progress", "every snake reaching the goal"),
    ("P10", WORLD, '\t\tif s.state ~= "over" then\n\t\t\tlocal sp = layout.spawns[i]', '\t\tif s.state == "alive" or s.state == "ready" then\n\t\t\tlocal sp = layout.spawns[i]', "progress", "a dying one too"),
    ("P11", WORLD, '\t\tif s.state ~= "over" then\n\t\t\tlocal sp = layout.spawns[i]', "\t\tif true then\n\t\t\tlocal sp = layout.spawns[i]", "progress", "one with none stays out"),
    ("P12", WORLD, "start(w, Maps.roll(w.map + 1, #w.snakes, draw), draw, events)", "start(w, Maps.roll(w.map + 1, math.max(1, #w.snakes - 1), draw), draw, events)", "progress", "a dying one too"),
    ("P13", WORLD, "start(w, Maps.roll(w.map + 1, #w.snakes, draw), draw, events)", "start(w, Maps.roll(w.map + 2, #w.snakes, draw), draw, events)", "progress", "map k+1 has k walls"),
    ("P14", WORLD, "w.untilStep += 1 / Maps.speed(w.map)", "w.untilStep += 1 / Maps.speed(1)", "progress", "17 tiles in 4 s on map 2"),
    ("P15", WORLD, "\ts.heading = heading\n\ts.turns = {}\n", "\ts.heading = heading\n", "progress", "a map start forgets waiting turns"),
    ("P16", WORLD, "\ts.turns = {}\n\ts.grow = 0\n\ts.state = \"ready\"", "\ts.turns = {}\n\ts.state = \"ready\"", "progress", "a map start forgets waiting turns"),
    ("P17", WORLD, "\t\tif w.phase == \"clear\" then\n\t\t\tw.timer -= slice\n", "\t\tif w.phase == \"clear\" then\n\t\t\tw.timer -= slice\n\t\t\tfor _, s in w.snakes do\n\t\t\t\tif s.state == \"dying\" then\n\t\t\t\t\ts.timer -= slice\n\t\t\t\t\tif s.timer <= EPS then\n\t\t\t\t\t\tlocal spot = World.safest(w, s.id)\n\t\t\t\t\t\tif spot then\n\t\t\t\t\t\t\tplace(s, { x = spot.x, y = spot.y }, spot.heading, events)\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\tend\n", "progress", "during MAP CLEAR only its timer runs"),
]

# correct variants: a different but right implementation; every acceptance spec must stay green
VARIANTS = [
    # apples by rejection sampling, then the row-major list
    ("C1", WORLD, "\tlocal side = w.layout.side\n\tlocal free = 0\n", "\tlocal side = w.layout.side\n\tfor _ = 1, 20 do\n\t\tlocal x, y = draw(side), draw(side)\n\t\tlocal k = key(w, x, y)\n\t\tif not walls[k] and not occ[k] then\n\t\t\ttable.insert(w.apples, { x = x, y = y })\n\t\t\treturn\n\t\tend\n\tend\n\tlocal free = 0\n"),
    # the respawn's last tie-break the other way round (the highest y and x win)
    ("C2", WORLD, "if a > bestA or (a == bestA and b > bestB) then", "if a > bestA or (a == bestA and b >= bestB) then"),
    # a wall's position drawn before its direction and length
    ("C3", MAPS, 'local dir: Dir = if draw(2) == 1 then "H" else "V"\n\tlocal length = T.wallMin - 1 + draw(Maps.wallMax(side) - T.wallMin + 1)', 'local spare = draw(7)\n\tlocal dir: Dir = if (draw(2) + spare) % 2 == 0 then "H" else "V"\n\tlocal length = T.wallMin - 1 + draw(Maps.wallMax(side) - T.wallMin + 1)'),
    # spawns heading west from each cell's right edge
    ("C4", MAPS, 'table.insert(out, { x = x0 + T.startLength, y = (y0 + y1) // 2, heading = "E" :: Heading })', 'local x1 = math.floor((c + 1) * side / cols)\n\t\ttable.insert(out, { x = x1 - T.startLength, y = (y0 + y1) // 2, heading = "W" :: Heading })'),
]

SPECS = ["maps", "moves", "food", "deaths", "progress", "play"]

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))  # snake/ of the checkout holding this script


def run(scratch, specs, timeout):
    rel = os.path.relpath(scratch, HOME)
    args = ["lune", "run", "tests/run", "--"] + [f"{rel}/specs/{s}.spec.luau" for s in specs]
    try:
        p = subprocess.run(args, cwd=HOME, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return None, "timeout"


def main():
    proto = os.path.abspath(sys.argv[1])
    only = set(sys.argv[2:])
    source = os.path.join(proto, "snake", "src", "shared")
    scratch = os.path.join(HOME, ".cache", f"f0211-mutants-{os.getpid()}")
    if not scratch.startswith(os.path.join(HOME, ".cache") + os.sep):
        sys.exit("refusing: the scratch home must be under snake/.cache")
    os.makedirs(os.path.join(scratch, "specs"))
    try:
        open(os.path.join(scratch, ".luaurc"), "w").write(
            '{ "languageMode": "strict", "aliases": { "logic": "./Logic", "tests": "../../tests" } }\n'
        )
        for feature in ("Maps", "World"):
            os.makedirs(os.path.join(scratch, "Logic", feature))
            shutil.copy(os.path.join(source, "Logic", feature, "init.luau"), os.path.join(scratch, "Logic", feature, "init.luau"))
        for spec in SPECS:
            shutil.copy(os.path.join(HERE, "..", "acceptance", f"{spec}.spec.luau"), os.path.join(scratch, "specs", f"{spec}.spec.luau"))
        bad = check(scratch, only)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    print(f"done: {bad} problem(s)")
    sys.exit(1 if bad else 0)


def check(scratch, only):
    bad = 0
    for row in MUTANTS + VARIANTS:
        mid, rel = row[0], row[1]
        if only and mid not in only:
            continue
        path = os.path.join(scratch, rel.replace("src/shared/", ""))
        original = open(path).read()
        if original.count(row[2]) < 1:
            print(f"{mid}: NOT APPLIED (old text not found)")
            bad += 1
            continue
        try:
            open(path, "w").write(original.replace(row[2], row[3], 1))
            if mid.startswith("C"):
                code, out = run(scratch, SPECS, 180)
                ok = code == 0
                print(f"{mid}: {'green' if ok else 'RED'}")
                if not ok:
                    bad += 1
                    print("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or "expected" in l)[:2000])
            else:
                code, out = run(scratch, [row[4]], 60)
                if code is None:
                    print(f"{mid}: killed (timeout) {row[4]}")
                    continue
                loaded = "could not load spec" not in out
                fails = [l for l in out.splitlines() if l.startswith("FAIL") and "::" in l and row[5] in l]
                if loaded and fails:
                    lines = out.splitlines()
                    i = lines.index(fails[0])
                    msg = lines[i + 1].strip() if i + 1 < len(lines) else ""
                    msg = re.sub(r"^\S+/specs/", "", msg)
                    print(f"{mid}: killed {row[4]} :: {row[5]} ({msg[:120]})")
                else:
                    bad += 1
                    print(f"{mid}: SURVIVED {row[4]} :: {row[5]} (loaded={loaded})")
                    print("\n".join(l for l in out.splitlines() if l.startswith("FAIL"))[:1500])
        finally:
            open(path, "w").write(original)
    return bad


if __name__ == "__main__":
    main()
