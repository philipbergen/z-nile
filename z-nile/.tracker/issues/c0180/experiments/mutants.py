# c0180's mutation runner for the trace, the runner's record, the record format, the wording and the narrowings: each
# mutant is applied alone to a prototype clone (experiments/proto.patch applied), its spec is run, and the mutant must
# fail a case on an assertion. Restores each file with git. Usage: C0180_PROTO=<clone> python3 mutants.py [ids...]
import subprocess, sys, os
P=os.environ['C0180_PROTO']  # a clone with experiments/proto.patch applied
AC='.tracker/issues/c0180/acceptance/'
E='z-nile/engine/main.luau'; RUN='z-nile/tests/run.luau'; CR='z-nile/tests/lib/commandrecord.luau'; RK='z-nile/lib/recordkey.luau'
M=[
('R6',E,'if trace and trace ~= "" then','if trace then','trace'),
('R7',E,'\t\tfor _, dir in dirs do\n\t\t\tlocal why: any = nil','\t\tfor _, dir in { dirs[1] } do\n\t\t\tlocal why: any = nil','trace'),
('R9',E,'\t\t\tif not wrote then\n\t\t\t\tstdio.ewrite(`zn: cannot record','\t\t\tif false then\n\t\t\t\tstdio.ewrite(`zn: cannot record','trace'),
('R11',E,'\t\t\tlocal why: any = nil\n\t\t\tlocal wrote = xpcall(sh.writeReplacing','\t\t\tprint(dir)\n\t\t\tlocal why: any = nil\n\t\t\tlocal wrote = xpcall(sh.writeReplacing','trace'),
('R12',RUN,'and allPassed(o) then','and allPassed(o) and #o.commands > 0 then','record'),
('R13',RUN,'and allPassed(o) then','then','record'),
('R14',RK,'for path in graph.closure(g, spec) do','for path in { [spec] = true } do','record'),
('R15',RUN,'print(`{passed} passed, {failed} failed, {#files} spec files`)\nprocess.exit(if failed == 0 then 0 else 1)\n-- a project','recordCommands({})\nprint(`{passed} passed, {failed} failed, {#files} spec files`)\nprocess.exit(if failed == 0 then 0 else 1)\n-- a project','record'),
('R16',RUN,'local trace = if INHERITED ~= "" then `{dir}:{INHERITED}` else dir','local trace = dir','record'),
('R17',RUN,'if #fs.readDir(dir) > 0 or not pcall(fs.removeDir, dir) then','if false then','record'),
('R18',RUN,'\tlocal keep: { [string]: boolean }? = nil\n\tif fullRun then','\tlocal keep: { [string]: boolean }? = nil\n\tif false then','record'),
('R19',CR,'\ttable.sort(sorted)\n\tlocal parts','\tlocal parts','commandrecord'),
('R20',CR,'names[i - 1] >= name','names[i - 1] == name','commandrecord'),
('R21',CR,'\tfor spec, e in new do\n\t\tlocal before = old[spec]','\tfor spec, e in new do\n\t\tif keep and not keep[spec] then\n\t\t\tcontinue\n\t\tend\n\t\tlocal before = old[spec]','commandrecord'),
('R33','z-nile/skills/zz-test/SKILL.md',"a change to the engine's Luau files (`z-nile/engine/**/*.luau`) selects instead, see **Command trace**.","a change to the engine's Luau files (`z-nile/engine/**/*.luau`) selects instead, see **Command trace**. (and any other change under `z-nile/` (the engine, the gate) z-nile's)",'docs'),
('R35','z-nile/tests/acceptance/c0081/publish-guard.spec.luau','\t\tscan("engine")\n\t\tt.expect(others > 0).toBe(true)','\t\tscan("engine")','narrowed'),
]
only=sys.argv[1:]
env=dict(os.environ); env['PATH']=os.path.expanduser('~/.rokit/bin')+':'+env['PATH']; env['ZN_SPEC_TRACE']=''
for mid,f,old,new,spec in M:
    if only and mid not in only: continue
    path=os.path.join(P,f); s=open(path).read()
    if s.count(old)!=1: print(mid,'ANCHOR',s.count(old)); continue
    open(path,'w').write(s.replace(old,new))
    r=subprocess.run(['lune','run','tests/run','--',AC+spec+'.spec.luau'],cwd=P+'/z-nile',capture_output=True,text=True,env=env)
    out=r.stdout+r.stderr
    fails=[l for l in out.split('\n') if l.startswith('FAIL')]
    print(mid, 'KILLED' if (r.returncode!=0 and fails and 'could not load' not in out) else 'SURVIVED', fails[:1])
    subprocess.run(['git','checkout','--',f],cwd=P)
