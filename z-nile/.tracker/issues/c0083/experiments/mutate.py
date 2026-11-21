import subprocess, sys, os
P='/Users/philipbergen/code/pickman/.worktree/proto-suite-split'
Z=P+'/z-nile'
A='.tracker/issues/c0083/acceptance/'
M=[
 ("M1 unknown project is game","lib/suites.luau",'\treturn "harness"\nend','\treturn "game"\nend',"suites.spec.luau","AC1"),
 ("M2 projects ignores which","lib/suites.luau",'if which == "all" or suites.of(n) == which then','if true then',"suites.spec.luau","AC1"),
 ("M3 a path under no home touches nothing","lib/suites.luau",'hit[if best then suites.of((best :: select.Home).name) else "harness"] = true','if best then hit[suites.of((best :: select.Home).name)] = true end',"suites.spec.luau","AC1"),
 ("M4 mixed change uses first path only","lib/suites.luau",'for _, path in changed do\n\t\tlocal under','for _, path in { changed[1] } do\n\t\tlocal under',"suites.spec.luau","AC1"),
 ("M5 tracker document counts","lib/suites.luau",'if not under then','if true then',"suites.spec.luau","AC1"),
 ("M6 crossings always empty","lib/suites.luau",'\t\tif not kept[p] then','\t\tif false then',"suites.spec.luau","AC5"),
 ("M7 gate ignores crossings","lib/context.luau",'for _, p in suites.crossings(spec, paths) do','for _, p in {} :: { string } do',"gate.spec.luau","AC5"),
 ("M8 --suite changed prints all","affected.luau",'want = if #touched == 2 then "all" elseif #touched == 1 then touched[1] else "none"','want = "all"',"gate.spec.luau","AC3"),
 ("M9 bad --suite exits 0","affected.luau",'\t\tprocess.exit(2)\n\tend\n\tlocal names','\t\tprocess.exit(0)\n\tend\n\tlocal names',"gate.spec.luau","AC3"),
 ("M10 specs loop ignores the suite","check.sh",'if [[ -n $spec_narrow ]]; then','if false; then',"gate.spec.luau","AC4"),
 ("M11 --project allowed beside --suite","check.sh",'if [[ -n $suite && ${#wanted[@]} -gt 0 ]]; then','if false; then',"gate.spec.luau","AC4"),
 ("M12 bad value accepted","check.sh",'harness | game | changed) suite=$2 ;;','harness | game | changed | *) suite=$2 ;;',"gate.spec.luau","AC4"),
 ("M13 --suite all is changed","check.sh",'all) suite= ;;','all) suite=changed ;;',"gate.spec.luau","AC4"),
 ("M14 changed does not narrow a --full run","check.sh",'if [[ $suite != changed || $mode == full ]]; then spec_narrow=1; fi','if [[ $suite != changed ]]; then spec_narrow=1; fi',"gate.spec.luau","AC4"),
 ("M15 changed narrows an --affected run","check.sh",'if [[ $suite != changed || $mode == full ]]; then spec_narrow=1; fi','spec_narrow=1',"gate.spec.luau","AC4"),
 ("M16 a suite's projects get no static stage","check.sh",'[[ -n $found ]] || wanted+=("$s")','[[ -n $found ]] || true',"gate.spec.luau","AC4"),
 ("M17 --slow allowed beside --suite","check.sh",'if [[ -n $suite && $mode == slow ]]; then','if false; then',"gate.spec.luau","AC4"),
 ("M18 plan lists unnarrowed specs","check.sh",'    spec_picked "${names[$i]}" || continue\n    [[ -d','    [[ -d',"gate.spec.luau","AC4"),
 ("M19 --base dropped from the suite call","check.sh",'--suite "$suite" ${base_args[@]+"${base_args[@]}"}','--suite "$suite"',"gate.spec.luau","AC3"),
 ("M20 the real reader ignores the change set","affected.luau",'local touched = suites.changed(rules, files)','local touched = suites.changed(rules, explicit)',"gate.spec.luau","AC3"),
 ("M21 nothing changed still runs every project (static narrowing not applied to full+changed)","check.sh",'( $mode == full && $suite == changed )','( 0 -eq 1 )',"gate.spec.luau","AC4"),
 ("M22 suites section removed","skills/zz-test/SKILL.md",'## Suites\n','## Suite list\n',"docs.spec.luau","AC7"),
 ("M23 merging narrowed to --suite changed","skills/zz-rules/SKILL.md",'`z-nile/check.sh --full` there','`z-nile/check.sh --full --suite changed` there',"docs.spec.luau","AC10"),
 ("M24 promotion routes chores to the tooling home","/engine/projects.luau",'return if home == "." then `tests/acceptance/{id}` else `{home}/tests/acceptance/{id}`','return `z-nile/tests/acceptance/{id}`',"suites.spec.luau","AC9"),
 ("M25 z-nile listed as a game","lib/suites.luau",'suites.GAME = { "arcade",','suites.GAME = { "z-nile", "arcade",',"suites.spec.luau","AC1"),
 ("M26 watch.forSuite drops arcade from the game list","lib/watch.luau",'\tarcade = true,\n','',"suites.spec.luau","AC2"),
 ("M27 a tooling watch file names a game path","tests/tooling/affected.watch.txt",'z-nile/','pickman/src/shared/Logic/Game/init.luau\nz-nile/',"gate.spec.luau","AC5"),
 ("M28 a game watch file names a tooling path","tests/tooling/../../../pickman/tests/unit/Maze/maze.watch.txt",'pickman/','z-nile/check.sh\npickman/',"suites.spec.luau","AC1"),
]
only=sys.argv[1:] 
for name,f,old,new,spec,ac in M:
    if only and name.split()[0] not in only: continue
    path = Z+'/'+f if not f.startswith('/') else Z+f
    s=open(path).read()
    if old not in s:
        print("NOAPPLY",name); continue
    open(path,'w').write(s.replace(old,new,1))
    try:
        r=subprocess.run(['../zn','run','--time','600','--','lune','run','tests/run','--',A+spec],cwd=Z,capture_output=True,text=True)
        out=r.stdout+r.stderr
        fails=[l for l in out.splitlines() if l.startswith('FAIL')]
        hit=[l for l in fails if ac in l]
        assertion = any(('expected' in l2) for l2 in out.splitlines())
        print("KILLED" if hit and assertion else "SURVIVED", name, "|", (hit[0][-110:] if hit else (fails[0][-110:] if fails else out[-200:])))
    finally:
        open(path,'w').write(s)
