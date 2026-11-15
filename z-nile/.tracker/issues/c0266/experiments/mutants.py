import pathlib, subprocess, sys, shutil
C="z-nile/tests/acceptance/c0114/classified.spec.luau"
ACC="../z-nile/.tracker/issues/c0266/acceptance"  # from z-nile/
base=subprocess.run(["git","show","HEAD:"+C],capture_output=True,text=True).stdout
M=[
 ("M1 chores-only case left", C, None, base),
 ("M2 c and d only", C, "\t\t\t\tif typed ~= store.typeOf(item) then", "\t\t\t\tif typed ~= store.typeOf(item) or typed == \"feature\" then"),
 ("M3 type comparison dropped", C, "\t\t\t\tif typed ~= store.typeOf(item) then", "\t\t\t\tif false then"),
 ("M4 defect pin dropped", C, "\t\tt.expect(defect).toBe(true)\n", ""),
 ("M5 filed chore branch deleted", C, "\t\t\telseif root == \"z-nile/.tracker\" and store.typeOf(item) ~= \"chore\" then\n\t\t\t\ttable.insert(wrong, `{kind} {slug} ({item.id}): a {store.typeOf(item)} in z-nile's root`)\n", ""),
 ("M9 the elseif joined onto the comment above", C, "\t\t\t-- record of them, not a rule for the root\n\t\t\telseif", "\t\t\t-- record of them, not a rule for the root elseif"),
 ("M6 tracker CLI bugs kept", "z-nile/skills/z-ticket/SKILL.md", "     - a game's own spec or test helper that is broken.\n", "     - a game's own spec or test helper that is broken;\n     - tracker CLI bugs.\n"),
 ("M7 every-root bullet omitted", "z-nile/skills/z-ticket/SKILL.md", "   - **Every root holds all three types** (c0266)", "   - Roots"),
 ("M8 zz-stats z-nile sentence omitted", "z-nile/skills/zz-stats/SKILL.md", " Every root's features and defects count, z-nile's included (c0266).", ""),
]
for name, path, old, new in M:
    p=pathlib.Path(path); keep=p.read_text()
    if old is None: s=new
    else:
        assert keep.count(old)==1, (name, "anchor")
        s=keep.replace(old,new)
    p.write_text(s)
    try:
        spec = "pinned" if path==C else "docs"
        r=subprocess.run(["lune","run","tests/run","--",f"{ACC}/{spec}.spec.luau"],cwd="z-nile",capture_output=True,text=True)
        out=r.stdout+r.stderr
        fails=[l for l in out.splitlines() if l.startswith("FAIL") or "expected" in l or "still" in l or "missing" in l]
        print(f"{name}: {spec} -> {'KILLED' if ' 0 failed' not in out else 'SURVIVED'} :: {' | '.join(fails)[:300]}")
    finally:
        p.write_text(keep)
