# c0273 E4: apply each Rules-table mutant to the scratch prototype (.worktree/proto-c0273, never pushed), run the row's
# spec case there, and put the file back from the text read before the edit. Run bounded from the prep worktree:
#   ./zn run --time 1800 -- python3 z-nile/.tracker/issues/c0273/experiments/E4-mutants.py [M<n>...]
import subprocess, sys, os
P='/Users/philipbergen/code/pickman/.worktree/proto-c0273'
A=P+'/z-nile/.tracker/issues/c0273/acceptance'
M=[
 ('M1','z-nile/tests/lib/home.luau','if graph.isProjectFile(name) then\n\t\t\t\t\ttable.insert(files','if string.match(name, "%.project%.json$") then\n\t\t\t\t\ttable.insert(files','jsonc'),
 ('M2','z-nile/tests/lib/home.luau','if graph.isProjectFile(name) then\n\t\t\t\t\ttable.insert(files','if string.match(name, "%.project%.jsonc?") then\n\t\t\t\t\ttable.insert(files','jsonc'),
 ('M3','z-nile/tests/lib/home.luau','local found: { graph.GameRoot } = if ok','if not ok then\n\t\t\t\tcontinue\n\t\t\tend\n\t\t\tlocal found: { graph.GameRoot } = if ok','jsonc'),
 ('M4','z-nile/tests/lib/home.luau','if rojoRuns then\n\t\t\t\treads, why','if rojoRuns and not string.match(name, "c$") then\n\t\t\t\treads, why','jsonc'),
 ('M5','z-nile/tests/lib/home.luau','if not table.find(files, "default.project.json") then','if not table.find(files, "default.project.json") and not table.find(files, "default.project.jsonc") then','jsonc'),
 ('M6','z-nile/tests/lib/home.luau','if name == `{stem}.project.json` and table.find','if false and table.find','jsonc'),
 ('M7','z-nile/tests/lib/home.luau','if name == `{stem}.project.json` and table.find(files, `{stem}.project.jsonc`) then','if table.find(files, `{stem}.project.json`) and table.find(files, `{stem}.project.jsonc`) then','jsonc'),
 ('M8','z-nile/lib/graph.luau','graph.PROJECT_FILE = "%.project%.jsonc?$"','graph.PROJECT_FILE = "%.project%.json$"','jsonc'),
 ('M9','z-nile/lib/graph.luau','return string.match(name, "^(.*)%.project%.jsonc?$")','return string.match(name, "^(.*)%.project%.json")','jsonc'),
 ('M10','z-nile/lib/graph.luau','if graph.isProjectFile(name) and fs.isFile','if string.match(name, "%.project%.json$") and fs.isFile','jsonc'),
 ('M11','z-nile/lib/graph.luau','if not ok or type(project) ~= "table" or type((project :: any).tree) ~= "table" then','if not ok then\n\t\t\tcontinue\n\t\tend\n\t\tif type(project) ~= "table" or type((project :: any).tree) ~= "table" then','jsonc'),
 ('M12','z-nile/lib/graph.luau','for _, entry in projectsIn(".") do\n\t\ttable.insert(out, graph.gameRoots(entry.project))','for _, entry in projectsIn(".") do\n\t\tif string.match(entry.name, "c$") then\n\t\t\tcontinue\n\t\tend\n\t\ttable.insert(out, graph.gameRoots(entry.project))','jsonc'),
 ('M13','z-nile/lib/select.luau','"[^/]*" .. graph.PROJECT_FILE,','"[^/]*%.project%.json$",','jsonc'),
 ('M14','z-nile/check.sh','  for f in "${p}"*.project.jsonc; do [[ -f $f ]] && places+=("$h|$f"); done','  :','gate'),
 ('M15','z-nile/check.sh','  stem=$(basename "$f")\n  stem=${stem%.project.jsonc}\n  stem=${stem%.project.json}','  stem=$(basename "$f" .project.json)','gate'),
 ('M16','z-nile/check.sh','  for f in "${p}"*.project.json; do [[ -f $f ]] && places+=("$h|$f"); done\n  for f in "${p}"*.project.jsonc; do [[ -f $f ]] && places+=("$h|$f"); done # Rojo builds both names (c0273)','  for f in "${p}"*.project.jsonc; do [[ -f $f ]] && places+=("$h|$f"); done # Rojo builds both names (c0273)\n  for f in "${p}"*.project.json; do [[ -f $f ]] && places+=("$h|$f"); done','gate'),
 ('M18','z-nile/lib/graph.luau','for _, entry in projectsIn(".") do\n\t\ttable.insert(out, graph.gameRoots(entry.project))','local listed, found = pcall(projectsIn, ".")\n\tfor _, entry in (if listed then found else {}) do\n\t\ttable.insert(out, graph.gameRoots(entry.project))','jsonc'),
 ('M19','z-nile/tests/lib/home.luau','\t\t\tif not ok then\n\t\t\t\t-- the fail-closed line above stays','\t\t\tif false then\n\t\t\t\t-- the fail-closed line above stays','jsonc'),
 ('M20','z-nile/lib/graph.luau',"its mappings can't be told (a comment or a trailing comma, which Rojo builds, is not JSON to Lune's decoder)`","its mappings can't be told`",'jsonc'),

]
only=sys.argv[1:] 
for mid,f,old,new,spec in M:
    if only and mid not in only: continue
    path=P+'/'+f; s=open(path).read()
    if s.count(old)!=1: print(mid,'NOT APPLIED',s.count(old)); continue
    open(path,'w').write(s.replace(old,new))
    r=subprocess.run([P+'/zn','run','--time','200','--','lune','run','tests/run','--',A+'/'+spec+'.spec.luau'],cwd=P+'/z-nile',capture_output=True,text=True)
    open(path,'w').write(s)  # restore by content: no git command runs here
    out=r.stdout+r.stderr
    fails=[l for l in out.splitlines() if l.startswith('FAIL') and '::' in l]
    errs=[l.strip() for l in out.splitlines() if 'expected' in l or 'error' in l.lower()][:2]
    print(mid,'rc',r.returncode,'|',fails[:3],'|',errs)
