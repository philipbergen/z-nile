# Mutation check for c0164. Usage: python3 -I mutants.py <clone> [ids...]
# <clone>: a separate clone under the temp folder at R0056's tip (867d838b) with f0126's experiments/prototype.patch
# applied (`git apply -3 --exclude='pickman/.tracker/*'`), f0126's acceptance specs copied to
# pickman/tests/acceptance/f0126/ and this issue's experiments/views.patch applied there. Each mutant edits Main;
# the new views.spec case must fail on an assertion. Correct variants (C*) must leave every views.spec case green.
import os, subprocess, sys, tempfile
clone = os.path.realpath(sys.argv[1])
tmp = os.path.realpath(tempfile.gettempdir())
def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""
here, there = common(os.path.dirname(os.path.abspath(__file__))), common(clone) if os.path.isdir(clone) else ""
if not clone.startswith(tmp + os.sep) or not there or there == here:
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}")
home = os.path.join(clone, "pickman")
# the base is f0126's prototype, still in flight: refuse if its patch or specs moved since this prep ran (lesson
# z-design/in-flight-bases-pin-their-source; design review 003 F3)
import hashlib, glob
F0126 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../f0126")
def sha(paths):
    h = hashlib.sha256()
    for p in paths:
        h.update(open(p, "rb").read())
    return h.hexdigest()
PATCH_SHA = "a68aeef997f5bb44d208c1fb02e30598ad4af5306bff524270bbcae76bd3511f"
SPECS_SHA = "1b351c87116d94e7d7bdfc2e14820d3a6cbdba56620c97a40561fab56f68a2b6"
if sha([os.path.join(F0126, "experiments/prototype.patch")]) != PATCH_SHA or sha(sorted(glob.glob(os.path.join(F0126, "acceptance/*.luau")))) != SPECS_SHA:
    sys.exit("refused: f0126's prototype.patch or acceptance specs changed since c0164's prep; rebuild the base and rerun")
MAIN = os.path.join(home, "src/client/Main.client.luau")
SPEC = "tests/acceptance/f0126/views.spec.luau"
WALLS = "tests/place/main-walls.spec.luau" # R0056's, narrowed by c0164 to where the two calls sit
CASE = "Main turns the walls and the radar green while the ghosts are edible, and blue again after, every frame"
BLOCK = "\tif model then\n\t\tMazeView.edible(model, View.edible(frame.play))\n\tend\n"
RADAR = "\tDangerHud.wallState(overlay.flash, View.edible(frame.play))\n"
FLASH = "\t\tMazeView.flash(model, overlay.flash)\n"
HEAD = "snapshots.OnClientEvent:Connect(function(frame: Session.Frame)\n"
M = {
 # c0164's captured mutants
 "N1": [(BLOCK, ""), (FLASH, FLASH + "\t\tlocal e = MazeView.edible\n\t\te(model, View.edible(frame.play))\n")],
 "N2": [(BLOCK, ""), (FLASH, FLASH + '\t\tMazeView["edible"](model, View.edible(frame.play))\n')],
 "N3": [(BLOCK, "\tif model then\n\t\tmodel:SetAttribute(\"Edible\", View.edible(frame.play))\n\tend\n")],
 "N4": [(HEAD, "local first: Session.Frame? = nil\n" + HEAD + "\tfirst = first or frame\n"),
        (BLOCK, "\tif model then\n\t\tlocal frame = first :: Session.Frame\n\t\tMazeView.edible(model, View.edible(frame.play))\n\tend\n")],
 "N6": [(HEAD, "local wasEdible = false\n" + HEAD),
        (BLOCK, "\twasEdible = wasEdible or View.edible(frame.play)\n\tif model then\n\t\tMazeView.edible(model, wasEdible)\n\tend\n")],
 # what R0056's text pin killed
 "P1": [(BLOCK, BLOCK.replace("if model then", "if model and false then"))],
 "P2": [(BLOCK, "\t--[[\n" + BLOCK + "\t]]\n")],
 "P3": [(RADAR, "\tlocal _ = [[\n" + RADAR + "\t]]\n")],
 "P5": [(BLOCK, BLOCK + "\tMazeView.edible(model, false)\n")],
 "P6": [(RADAR, "\tif overlay.flash then\n\t" + RADAR + "\tend\n")],
 "P7": [(RADAR, RADAR + RADAR)],
 # design review 001 F1: the state updated only during play (stuck through a level clear or a death)
 "S2": [(HEAD, "local lastEdible = false\n" + HEAD),
        (BLOCK, "\tif frame.play.phase == \"playing\" then\n\t\tlastEdible = View.edible(frame.play)\n\tend\n\tif model then\n\t\tMazeView.edible(model, lastEdible)\n\tend\n")],
 "S2r": [(HEAD, "local lastRadar = false\n" + HEAD),
        (RADAR, "\tif frame.play.phase == \"playing\" then\n\t\tlastRadar = View.edible(frame.play)\n\tend\n\tDangerHud.wallState(overlay.flash, lastRadar)\n")],
 # design review 002 F1: guards on fields the case once held constant, and cutoffs above 0
 "G1": [(BLOCK, BLOCK.replace("if model then", "if model and frame.play.lives > 0 then"))],
 "G2": [(BLOCK, BLOCK.replace("if model then", "if model and frame.play.phase ~= \"gameover\" then"))],
 "L1": [(BLOCK, BLOCK.replace("if model then", "if model and frame.play.level == 1 then"))],
 "T1": [(BLOCK, BLOCK.replace("View.edible(frame.play)", "frame.play.frightened > 1"))],
 "T1r": [(RADAR, RADAR.replace("View.edible(frame.play)", "frame.play.frightened >= 6"))],
 "T2": [(BLOCK, BLOCK.replace("View.edible(frame.play)", "frame.play.frightened > 5"))],
 # design review 003 F1: guards on fields outside play
 "B1": [(BLOCK, BLOCK.replace("if model then", "if model and frame.boon == nil then"))],
 "W1": [(BLOCK, BLOCK.replace("if model then", "if model and (frame.walls == nil or #frame.walls.opened == 0) then"))],
 "H1": [(BLOCK, BLOCK.replace("if model then", "if model and frame.hopped == nil then"))],
 "GH": [(BLOCK, BLOCK.replace("if model then", "if model and frame.ghosts == nil then"))],
 "K1": [(HEAD, "local keptEdible = false\n" + HEAD),
        (BLOCK, "\tif frame.pick == nil then\n\t\tkeptEdible = View.edible(frame.play)\n\tend\n\tif model then\n\t\tMazeView.edible(model, keptEdible)\n\tend\n")],
 "K1r": [(HEAD, "local keptRadar = false\n" + HEAD),
        (RADAR, "\tif frame.pick == nil then\n\t\tkeptRadar = View.edible(frame.play)\n\tend\n\tDangerHud.wallState(overlay.flash, keptRadar)\n")],
 "R1": [(BLOCK, BLOCK.replace("if model then", "if model and frame.play.phase ~= \"ready\" then"))],
 "TK": [(BLOCK, BLOCK.replace("if model then", "if model and frame.tick % 2 == 0 then"))],
 # design review 004 F1: guards on frame fields no hand-built context varies; R0056's narrowed main-walls.spec (where
 # the calls sit) kills them (decided with the user, 2026-11-01: "Keep both")
 "PL0": [(BLOCK, BLOCK.replace("if model then", "if model and string.find(frame.pellets, \"[^A]\") ~= nil then"))],
 "PL0r": [(RADAR, "\tif string.find(frame.pellets, \"[^A]\") ~= nil then\n\t" + RADAR + "\tend\n")],
 # design review 004: guards on fields the case still holds constant
 "PM": [(BLOCK, BLOCK.replace("if model then", "if model and not frame.player.moving then"))],
 "PJ": [(BLOCK, BLOCK.replace("if model then", "if model and frame.player.jumpTick < 0 then"))],
 "PH": [(BLOCK, BLOCK.replace("if model then", "if model and frame.player.heading == HEADING0 then")), (HEAD, "local HEADING0: string? = nil\n" + HEAD + "\tHEADING0 = HEADING0 or frame.player.heading\n")],
 "PE": [(HEAD, "local firstPellets: string? = nil\n" + HEAD + "\tfirstPellets = firstPellets or frame.pellets\n"), (BLOCK, BLOCK.replace("if model then", "if model and frame.pellets == firstPellets then"))],
 "PEr": [(HEAD, "local firstPellets: string? = nil\n" + HEAD + "\tfirstPellets = firstPellets or frame.pellets\n"), (RADAR, "\tif frame.pellets == firstPellets then\n\t" + RADAR + "\telse\n\t\tDangerHud.wallState(overlay.flash, false)\n\tend\n")],
 "W2": [(BLOCK, BLOCK.replace("if model then", "if model and (frame.walls == nil or #frame.walls.opened < 2) then"))],
 "WM": [(BLOCK, BLOCK.replace("if model then", "if model and (frame.walls == nil or #frame.walls.marked < 3) then"))],
 "SH": [(BLOCK, BLOCK.replace("if model then", "if model and (frame.shots or 0) < 3 then"))],
 "GE": [(BLOCK, BLOCK.replace("if model then", "if model and not (frame.ghosts and frame.ghosts[1] and frame.ghosts[1].look == \"eyes\") then"))],
 "GB": [(BLOCK, BLOCK.replace("if model then", "if model and not (frame.ghosts and frame.ghosts[1] and frame.ghosts[1].look == \"blinking\") then"))],
 "BK": [(BLOCK, BLOCK.replace("if model then", "if model and not (frame.boon and frame.boon.kind == \"shot\") then"))],
 "KF": [(BLOCK, BLOCK.replace("if model then", "if model and not (frame.pick and frame.pick.wall.x ~= 7) then"))],
 "OP": [(HEAD, "local firstOpened: number? = nil\n" + HEAD + "\tfirstOpened = firstOpened or (if frame.walls then #frame.walls.opened else 0)\n"), (BLOCK, BLOCK.replace("if model then", "if model and (if frame.walls then #frame.walls.opened else 0) == firstOpened then"))],
 "OPr": [(HEAD, "local wk0: string? = nil\n" + HEAD), (BLOCK, BLOCK.replace("if model then", "if model and (wk0 == nil or wk0 == wallsKey) then") + "\twk0 = wk0 or wallsKey\n")],
 # design review 005 F1: the frame rebound around the unchanged calls (killed by the case once the frames carry the
 # game's values: pellets all eaten at a level clear, the player jumping)
 "X1": [(HEAD, "local kept: Session.Frame? = nil\n" + HEAD),
        (BLOCK + RADAR, "\tlocal now = frame\n\tif string.find(frame.pellets, \"[^A]\") ~= nil or kept == nil then\n\t\tkept = frame\n\tend\n\tframe = kept :: Session.Frame\n" + BLOCK + RADAR + "\tframe = now\n")],
 "X2": [(HEAD, "local kept: Session.Frame? = nil\n" + HEAD),
        (BLOCK + RADAR, "\tlocal now = frame\n\tif frame.player.jumpTick < 0 or kept == nil then\n\t\tkept = frame\n\tend\n\tframe = kept :: Session.Frame\n" + BLOCK + RADAR + "\tframe = now\n")],
 "X3": [(HEAD, "local kept: Session.Frame? = nil\n" + HEAD),
        (BLOCK + RADAR, "\tlocal now = frame\n\tif frame.play.phase ~= \"levelclear\" or kept == nil then\n\t\tkept = frame\n\tend\n\tframe = kept :: Session.Frame\n" + BLOCK + RADAR + "\tframe = now\n")],
 # wrong arguments
 "A1": [(RADAR, "\tDangerHud.wallState(false, View.edible(frame.play))\n")],
 "A2": [(BLOCK, BLOCK.replace("View.edible(frame.play)", "true"))],
 "A3": [(RADAR, RADAR.replace("View.edible(frame.play)", "frame.play.frightened > 6"))],
}
CORRECT = {
 # the text pin's P4 (a return before the calls when there is no model): never taken, since the first frame builds it
 "P4": [(BLOCK, "\tif not model then\n\t\treturn\n\tend\n" + BLOCK)],
 "C1": [(BLOCK + RADAR, "\tlocal edible = View.edible(frame.play)\n\tif model then\n\t\tMazeView.edible(model, edible)\n\tend\n\tDangerHud.wallState(overlay.flash, edible)\n")],
 "C2": [(HEAD, "local function paintWalls(model: any, frame: Session.Frame, flash: boolean)\n\tif model then\n\t\tMazeView.edible(model, View.edible(frame.play))\n\tend\n\tDangerHud.wallState(flash, View.edible(frame.play))\nend\n" + HEAD),
        (BLOCK + RADAR, "\tpaintWalls(model, frame, overlay.flash)\n")],
}
# f0109's place.spec reads Main's text (its two calls' spelling): a correct variant passes views.spec but may fail it
F0109 = next((os.path.join(d, "place.spec.luau") for d in [os.path.join(home, ".tracker/issues/active/f0109/acceptance"), os.path.join(home, ".tracker/issues/done/f0109/acceptance"), os.path.join(home, "tests/acceptance/f0109")] if os.path.isfile(os.path.join(d, "place.spec.luau"))), None)
def run(spec=None):
    specs = [spec] if spec else [SPEC, WALLS]
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=home, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
def apply(edits):
    text = open(MAIN).read()
    out = text
    for old, new in edits:
        assert out.count(old) == 1, ("anchor not found once", old[:40])
        out = out.replace(old, new)
    open(MAIN, "w").write(out)
    return text
code, out = run()
print("BASE", "pass" if code == 0 else "FAIL", out.strip().splitlines()[-1])
ids = sys.argv[2:] or (list(M) + list(CORRECT))
for mid in ids:
    edits = M.get(mid) or CORRECT[mid]
    text = apply(edits)
    try:
        code, out = run()
    finally:
        open(MAIN, "w").write(text)
    fails = [l.split(":: ")[-1].strip() for l in out.splitlines() if l.startswith("FAIL")]
    if mid in CORRECT:
        extra = ""
        if F0109:
            text2 = apply(edits)
            try:
                c2, _ = run(os.path.relpath(F0109, home))
            finally:
                open(MAIN, "w").write(text2)
            extra = " (f0109 place.spec " + ("green" if c2 == 0 else "RED") + ")"
        print(mid, ("green" if code == 0 else "RED") + extra, "|", "; ".join(fails))
    else:
        # killed: the new case, or the narrowed main-walls placement rule, fails (and nothing else breaks for another reason)
        ok = code != 0 and all(f == CASE or "MazeView.edible" in f or "DangerHud.wallState" in f or "the rule names" in f for f in fails)
        print(mid, "killed" if ok else ("SURVIVED" if code == 0 else "OTHER"), "|", "; ".join(fails))
