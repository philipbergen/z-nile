#!/usr/bin/env python3
# f0235 prep mutation check. Run from pickman/ with experiments/prototype.patch and experiments/records.patch applied:
#   ./zn run --time 900 -- sh -c 'cd pickman && python3 .tracker/issues/f0235/experiments/mutants.py'
# Applies each mutant to the prototype (one at a time, by an exact text that must occur once), runs its spec, and
# records whether the spec failed on an assertion (not a load or syntax error); restores the file after each.
import subprocess
A = ".tracker/issues/f0235/acceptance/"
VIEW = "src/shared/Logic/View/init.luau"
PV = "src/client/PelletView.luau"
CAM = "src/client/Camera.luau"
MAIN = "src/client/Main.client.luau"
GD = ".tracker/game-design.md"
AR = ".tracker/architecture.md"
M = [
 ("M1 beacon from the floor", VIEW, "local bottom, top = View.PELLET.height, View.BEACON.top", "local bottom, top = 0, View.BEACON.top", "beacon"),
 ("M2 beacon only to 12", VIEW, "width = 3, top = 20,", "width = 3, top = 12,", "beacon"),
 ("M3 beacon 1 wide", VIEW, "width = 3, top = 20,", "width = 1, top = 20,", "beacon"),
 ("M4 beacon nearly invisible", VIEW, "transparency = 0.3,", "transparency = 0.8,", "beacon"),
 ("M5 elevated at the wall tops", VIEW, "return eye > SCALE.wallHeight", "return eye >= SCALE.wallHeight", "rule"),
 ("M6 elevated only near the top", VIEW, "return eye > SCALE.wallHeight", "return eye > SCALE.eyeHeight + 7", "rule"),
 ("M7 no finite guard", VIEW, 'if type(eye) ~= "number" or eye ~= eye or math.abs(eye) == math.huge then', 'if type(eye) ~= "number" then', "rule"),
 ("M8 every slot keyed", VIEW, 'if slot.kind == "power" then\n\t\t\tlocal near', 'if true then\n\t\t\tlocal near', "rule"),
 ("M9 eaten ignored", VIEW, "out[i] = elevated and present[i] == true and not near", "out[i] = elevated and not near", "rule"),
 ("M10 elevation ignored", VIEW, "out[i] = elevated and present[i] == true and not near", "out[i] = present[i] == true and not near", "rule"),
 ("M11 missing entry shown", VIEW, "out[i] = elevated and present[i] == true and not near", "out[i] = elevated and present[i] ~= false and not near", "rule"),
 ("N1 clearance ignored", VIEW, "out[i] = elevated and present[i] == true and not near", "out[i] = elevated and present[i] == true", "rule"),
 ("N2 clearance inclusive", VIEW, "< clear * clear", "<= clear * clear", "rule"),
 ("N3 nil pose near everything", VIEW, "local near = pose ~= nil and", "local near = pose == nil or", "rule"),
 ("M12 beacon built shown", PV, "beacon.Transparency = 1\n", "beacon.Transparency = 0\n", "pellets"),
 ("M13 beacon collides", PV, "\t\t\tquiet(beacon)\n", "\t\t\tquiet(beacon)\n\t\t\tbeacon.CanCollide = true\n", "pellets"),
 ("M14 all beacons while up", PV, "View.beacons(h.slots, h.present,", "View.beacons(h.slots, table.create(#h.slots, true),", "pellets"),
 ("M15 adapter passes no pose", PV, "View.elevated(eye()), pose())", "View.elevated(eye()), nil)", "pellets"),
 ("M16 write every frame", PV, "if h.shown[i] ~= on then", "if true then", "pellets"),
 ("M17 beacon loop hides pellets", PV, "h.beacons[i].Transparency = if on", "h.parts[i].Transparency = if on", "pellets"),
 ("M18 first build kept", PV, "\tcurrent = h\n\treturn h", "\tcurrent = current or h\n\treturn h", "pellets"),
 ("S3 beacons pulse", PV, "\t\t\th.beacons[i] = beacon\n", "\t\t\th.beacons[i] = beacon\n\t\t\ttable.insert(h.power, beacon)\n", "pellets"),
 ("M19 Main passes no eye", MAIN, "PelletView.start(Camera.eye, Camera.pose)", "PelletView.start(function() return nil end, Camera.pose)", "place"),
 ("N4 Main passes no pose", MAIN, "PelletView.start(Camera.eye, Camera.pose)", "PelletView.start(Camera.eye, function() return nil end)", "place"),
 ("M21 PelletView reads the camera", PV, "View.elevated(eye())", "View.elevated(workspace.CurrentCamera.CFrame.Position.Y)", "place"),
 ("M20 eye is the standing height", CAM, "\t\teye = drawn\n", "\t\teye = View.SCALE.eyeHeight\n", "camera"),
 ("S1 eye shadowed by a local", CAM, "\t\teye = drawn\n", "\t\tlocal eye = drawn\n", "camera"),
 ("S2 the rise stored, not the eye", CAM, "\t\teye = drawn\n", "\t\teye = drawn - View.SCALE.eyeHeight\n", "camera"),
 ("S4 eye set before the hop", CAM, "local drawn = View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks)\n\t\teye = drawn", "eye = View.SCALE.eyeHeight\n\t\tlocal drawn = View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks)", "camera"),
 ("D1 bullet without (prep)", GD, "**(prep)**, the user may veto any: a beacon", "a beacon", "docs"),
 ("D2 bullet without the clearance", GD, "a beacon within 1.5 tiles of the eye is not shown", "a near beacon is not shown", "docs"),
 ("D3 View row without the beacons", AR, "; the power pellets' beacons, the raised-eye rule and the beacons' clearance (f0235)", "", "docs"),
]
out = []
for name, path, old, new, spec in M:
    src = open(path).read()
    if src.count(old) != 1:
        out.append(f"{name}: NOT APPLIED ({src.count(old)} matches)"); continue
    open(path, "w").write(src.replace(old, new))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", A + spec + ".spec.luau"], capture_output=True, text=True, timeout=300)
        text = r.stdout + r.stderr
        failed = [l for l in text.splitlines() if l.startswith("FAIL") and "::" in l]
        loadfail = "could not load" in text or "SyntaxError" in text
        verdict = "killed" if r.returncode != 0 and failed and not loadfail else ("LOAD ERROR" if loadfail else "SURVIVED")
        out.append(f"{name} [{spec}]: {verdict}" + (f" by {failed[0].split('::',1)[1].strip()}" if failed else ""))
    finally:
        open(path, "w").write(src)
print("\n".join(out))
