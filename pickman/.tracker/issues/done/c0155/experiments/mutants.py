# Mutation check for c0155: each mutant weakens a promoted case; c0155's narrowed.spec must fail on an assertion.
import subprocess, sys, shutil, os
clone, spec = os.path.realpath(sys.argv[1]), sys.argv[2]
# refuse anything but a separate clone under the temp folder: this edits promoted specs and a check.sh (review 001 F4)
import tempfile
tmp = os.path.realpath(tempfile.gettempdir())
def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""
here, there = common(os.path.dirname(os.path.abspath(__file__))), common(clone) if os.path.isdir(clone) else ""
if not clone.startswith(tmp + os.sep) or not there or there == here:
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}")
home = os.path.join(clone, "pickman")
B = os.path.join(home, "tests/acceptance/f0110/buttons.spec.luau")
P = os.path.join(home, "tests/acceptance/f0146/pad.spec.luau")
M = {
 "M1": (B, "\t\t\tt.expect(b.snap).toEqual(Touch.snapRect(box))\n\t\t\tt.expect(b.fire).toEqual(T.fireRect(box))\n\t\t\tt.expect(b.hop).toEqual(T.hopRect(box))\n",
        "\t\t\tt.expect(b).toEqual({ snap = Touch.snapRect(box), fire = T.fireRect(box), hop = T.hopRect(box) })\n"),
 "M2": (B, "\t\t\tt.expect(b.fire).toEqual(T.fireRect(box))\n", ""),
 "M3": (B, "\t\t\tt.expect(b.snap).toEqual(Touch.snapRect(box))\n", "\t\t\tt.expect(b.snap ~= nil).toBe(true)\n"),
 "M4": (P, "\t\tfor key, action in want do\n", "\t\tt.expect(Pad.BUTTONS).toEqual(want)\n\t\tfor key, action in want do\n"),
 "M5": (P, "\t\t\tDPadLeft = \"Left\",\n", ""),
 "M7": (B, '"Touch.buttons holds the snap, fire and hop rectangles (a later control may add a field)"', '"Touch.buttons holds the snap, fire and hop rectangles"'),
 "M8": (os.path.join(home, ".tracker/issues/done/f0146/check.sh"), '"$A/pad.spec.luau"', '"$A/flow.spec.luau"'),
 "M9": (B, "\t\t\tt.expect(b.hop).toEqual(T.hopRect(box))\n", "\t\t\tt.expect(b.hop).toEqual(T.hopRect(box))\n\t\t\tbreak\n"),
 "M10": (B, "\t\t\tt.expect(b.fire).toEqual(T.fireRect(box))\n", "\t\t\tt.expect(b.fire and b.fire.x).toBe(T.fireRect(box).x)\n"),
 "M11": (B, "\t\t\tt.expect(b.hop).toEqual(T.hopRect(box))\n", "\t\t\tlocal hr = T.hopRect(box)\n\t\t\tt.expect(b.hop and { b.hop.x, b.hop.y, b.hop.w }).toEqual({ hr.x, hr.y, hr.w })\n"),
 "M12": (os.path.join(home, ".tracker/issues/done/f0110/check.sh"), 'check "AC1:', '# check "AC1:'),
 "M13": (B, "\t\tfor _, s in SAMPLES do\n\t\t\tlocal box = boxOf(Hud.layout(s.width, s.height, s.inset))\n\t\t\tlocal b = T.buttons(box)\n\t\t\tt.expect(b.snap)",
         "\t\tfor _, s0 in SAMPLES do\n\t\t\tlocal s = SAMPLES[1]\n\t\t\tlocal box = boxOf(Hud.layout(s.width, s.height, s.inset))\n\t\t\tlocal b = T.buttons(box)\n\t\t\tt.expect(b.snap)"),
 "M14": (B, "\t\t\tt.expect(b.fire).toEqual(T.fireRect(box))\n", "\t\t\tlocal fr = T.fireRect(box)\n\t\t\tt.expect(b.fire ~= nil and b.fire.x <= fr.x and b.fire.y <= fr.y and b.fire.w <= fr.w and b.fire.h <= fr.h).toBe(true)\n"),
 "M15": (os.path.join(home, "src/shared/Logic/Pad/init.luau"), '\tDPadRight = "Right",\n', '\tDPadRight = "Right",\n\tButtonB = "Jump",\n'),
 "M16": (os.path.join(home, "src/shared/Logic/Pad/init.luau"), '\tDPadRight = "Right",\n}\n', '\tDPadRight = "Right",\n\tButtonY = "Pick",\n}\n'),
 "M6": (P, "\t\t\tt.expect(Pad.BUTTONS[key]).toBe(action)\n", "\t\t\tt.expect(Pad.BUTTONS[key] ~= nil).toBe(true)\n"),
}
only = sys.argv[3:] or list(M)
def run():
    r = subprocess.run(["lune", "run", "tests/run", "--", spec], cwd=home, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
code, out = run()
print("BASE", "pass" if code == 0 else "FAIL", out.strip().splitlines()[-1])
EXTRA = {"M16": (os.path.join(home, "src/shared/Logic/Pad/init.luau"), "\treturn BUTTONS[keyName]\n", '\treturn if keyName == "ButtonY" then "Jump" else BUTTONS[keyName]\n')}
for mid in only:
    path, old, new = M[mid]
    if mid in EXTRA:
        p2, o2, n2 = EXTRA[mid]
        old_text = open(p2).read()
        assert old_text.count(o2) == 1 and old_text.count(old) == 1
        open(p2, "w").write(old_text.replace(o2, n2).replace(old, new))
        try:
            code, out = run()
        finally:
            open(p2, "w").write(old_text)
        fails = [l.strip() for l in out.splitlines() if l.startswith("FAIL")]
        bad = "not an assertion failure" in out
        print(mid, "killed" if code != 0 and not bad else ("ERROR" if bad else "SURVIVED"), "|", "; ".join(f.split(":: ")[-1] for f in fails))
        continue
    text = open(path).read()
    assert text.count(old) >= 1, (mid, "anchor not found once")
    open(path, "w").write(text.replace(old, new))
    code, out = run()
    open(path, "w").write(text)
    fails = [l.strip() for l in out.splitlines() if l.startswith("FAIL")]
    bad = "not an assertion failure" in out
    print(mid, "killed" if code != 0 and not bad else ("ERROR" if bad else "SURVIVED"), "|", "; ".join(f.split(":: ")[-1] for f in fails))
