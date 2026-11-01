import subprocess, os, sys
P=os.environ['C0180_PROTO']  # a clone with experiments/proto.patch applied
AC='.tracker/issues/c0180/acceptance/'
E='z-nile/engine/main.luau'; RUN='z-nile/tests/run.luau'; CR='z-nile/tests/lib/commandrecord.luau'; RK='z-nile/lib/recordkey.luau'
M=[
('R8',E,'if physical ~= dir or string.match(dir, "/%.cache/spec%-trace/[^/]+$") == nil then','if physical == nil then','trace'),
('R8b',E,'if physical ~= dir or string.match(dir, "/%.cache/spec%-trace/[^/]+$") == nil then','if physical == nil or not string.find(dir, "/.cache/", 1, true) then','trace'),
('R8c',E,'if physical ~= dir or string.match(dir, "/%.cache/spec%-trace/[^/]+$") == nil then','if physical == nil or string.match(dir, "/%.cache/spec%-trace/[^/]+$") == nil then','trace'),
('R37',E,'local recorded = if handler then name :: string else "usage"','if not handler then return end\n\t\tlocal recorded = name :: string','trace'),
('R39',CR,'if before and before.key == e.key then','if false then','record'),
('R40',RK,'recordkey.TOOLING = { "zn", "scripts", "z-nile/check.sh", "z-nile/lib", "z-nile/templates" }','recordkey.TOOLING = { "scripts", "z-nile/check.sh", "z-nile/lib", "z-nile/templates" }','record'),
('R41',RUN,'if string.match(n, "^[a-z][a-z%-]*$") then','if true then','record'),
('R9',E,'\t\t\tif not wrote then\n\t\t\t\tstdio.ewrite(`zn: cannot record','\t\t\tif false then\n\t\t\t\tstdio.ewrite(`zn: cannot record','trace'),
('R48',RK,'local extra = { "engine-base " .. recordkey.engineBase(root) }','local extra = {}','record'),
('R50',RK,'local extra = { "engine-base " .. recordkey.engineBase(root) }','local extra = { "engine-base " .. (process.exec("ls", { "z-nile/engine" }, { cwd = root }).stdout) }','record'),
('R51',RUN,'\tif not wrote then\n\t\tstdio.ewrite(`tests/run: could not write','\tif false then\n\t\tstdio.ewrite(`tests/run: could not write','record'),
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
    print(mid, 'KILLED' if (r.returncode!=0 and fails and 'could not load' not in out) else 'SURVIVED', fails[:2])
    subprocess.run(['git','checkout','--',f],cwd=P)
