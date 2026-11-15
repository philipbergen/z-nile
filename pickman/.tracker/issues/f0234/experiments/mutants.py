#!/usr/bin/env python3
"""f0234's mutation check: apply each mutant to the prototype's source (a text substitution, restored after),
run its spec case's file, and report whether it failed on an assertion. It edits files only: no git command, no ref.
Usage (from the prep worktree): ./zn run --time 600 -- python3 -I <this> <prototype's pickman home>"""
import pathlib, subprocess, sys

HOME = pathlib.Path(sys.argv[1]).resolve()
assert (HOME / "default.project.json").is_file() and HOME.parent.name == "proto-f0234", HOME
A = ".tracker/issues/f0234/acceptance/"
HOP, VIEW = "src/shared/Logic/Hop/init.luau", "src/shared/Logic/View/init.luau"
CAM, MAIN, SES = "src/client/Camera.luau", "src/client/Main.client.luau", "src/shared/Logic/Session/init.luau"

MUTANTS = [
    ("H1", HOP, "if playAt - t >= Hop.TICKS / 2 then", "if playAt - t >= Hop.TICKS then", "held"),
    ("H2", HOP, "return Hop.rise(playAt - Hop.TICKS, t)\n", "return if t < playAt then Hop.RISE else 0\n", "held"),
    ("H3", HOP, "return Hop.rise(playAt - Hop.TICKS, t)\n",
     "return Hop.rise(playAt - Hop.LONG_TICKS, t, Hop.LONG_TICKS)\n", "held"),
    ("H4", HOP, "if playAt == nil or not finite(playAt) or not finite(t) then", "if playAt == nil then", "held"),
    ("H5", HOP, "if playAt - t >= Hop.TICKS / 2 then", "if playAt + 1 - t >= Hop.TICKS / 2 then", "held"),
    ("H5", HOP, "return Hop.rise(playAt - Hop.TICKS, t)\n", "return Hop.rise(playAt + 1 - Hop.TICKS, t)\n", None),
    ("R1", VIEW, "return tick + play.timer", "return tick + play.timer - 1", "ready"),
    ("R2", VIEW, "\treturn last\nend\n\n-- The arrows held", "\treturn nil\nend\n\n-- The arrows held", "ready"),
    ("R3", VIEW, 'if play.phase == "ready" and finite(tick) and finite(play.timer) then',
     'if play.phase == "ready" then', "ready"),
    ("R4", VIEW, 'if play.phase == "ready" and finite(tick)', 'if last == nil and play.phase == "ready" and finite(tick)',
     "ready"),
    ("C1", CAM, " + Hop.held(readyEnd, shown)", "", "camera"),
    ("C2", CAM, "Hop.held(readyEnd, shown)", "Hop.held(readyEnd, snap.tick)", "camera"),
    ("C3", CAM, "View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks) + Hop.held(readyEnd, shown)",
     "View.SCALE.eyeHeight + Hop.held(readyEnd, shown)", "camera"),
    ("C4", CAM, "\treadyEnd = View.readyEnd(readyEnd, play, tick)\n", "\treturn\n", "camera"),
    ("C5", CAM, "\t\tif not mouseHeld and not lookedThisFrame then",
     "\t\tif not mouseHeld and not lookedThisFrame and Hop.held(readyEnd, latest and latest.tick or 0) == 0 then",
     "camera"),
    ("C6", CAM, "\t\tif read then", "\t\tif read and Hop.held(readyEnd, latest and latest.tick or 0) == 0 then", "camera"),
    ("C7", CAM, "Hop.held(readyEnd, shown)", "Hop.held(readyEnd, shown + 1)", "camera"),
    ("M1", MAIN, "\tCamera.ready(frame.play, frame.tick)\n", "", "place"),
    ("M2", MAIN, "Camera.ready(frame.play, frame.tick)", "Camera.ready(frame.play, frame.tick + 1)", "place"),
    # a hop asked for in a pause starts one there (the pause's forgetting of a young hop dropped for it)
    ("S1", SES, "\t\t\tforgetYoungHop(member, id, s.tick - 1, out) -- already",
     "\t\t\tmember.hopped = if hop then s.tick else member.hopped -- already", "ready"),
    ("S2", SES, "\tmember.hop = false\n\tmember.hopped = nil\n", "\tmember.hop = false\n", "ready"),
]

def run(spec: str) -> tuple[bool, str]:
    p = subprocess.run(["lune", "run", "tests/run", "--", A + spec + ".spec.luau"], cwd=HOME,
                       capture_output=True, text=True, timeout=300)
    return p.returncode == 0, p.stdout + p.stderr

groups: dict[str, list] = {}
for m in MUTANTS:
    groups.setdefault(m[0], []).append(m)
bad = 0
for mid, edits in groups.items():
    saved = {}
    for _, path, old, new, _spec in edits:
        f = HOME / path
        saved.setdefault(path, f.read_text())
        s = f.read_text()
        assert s.count(old) == 1, (mid, path, old)
        f.write_text(s.replace(old, new))
    spec = next(e[4] for e in edits if e[4])
    try:
        ok, out = run(spec)
    finally:
        for path, text in saved.items():
            (HOME / path).write_text(text)
    load = "could not load spec" in out or "syntax error" in out
    asserted = "expected " in out  # the spec library's assertion message, not a runtime error
    verdict = "SURVIVED" if ok else ("LOAD ERROR" if load else ("killed" if asserted else "RUNTIME ERROR"))
    bad += verdict != "killed"
    print(f"{mid} ({spec}.spec): {verdict}")
for spec in ["held", "ready", "camera", "place"]:
    ok, _ = run(spec)
    print(f"unmutated {spec}.spec: {'pass' if ok else 'FAIL'}")
    bad += not ok
sys.exit(1 if bad else 0)
