import subprocess, sys, shutil, os
P='/Users/philipbergen/code/pickman/.worktree/proto-f0339'
ZN='/Users/philipbergen/code/pickman/.worktree/prep-ticket-explainer-page/zn'
A=P+'/z-nile/.tracker/issues/f0339/acceptance/'
X='z-nile/engine/explainer.luau'; M='z-nile/engine/main.luau'
mutants=[
 ('M1 any contract hash passes', X, 'elseif named[1] ~= string.lower(hash) then', 'elseif false then', ['explainer','approve-page']),
 ('M2 a repeated meta tag passes', X, 'elseif #named > 1 then', 'elseif false then', ['explainer']),
 ('M3 a repeated section passes', X, '\t\telseif opens > 1 then\n', '\t\telseif false then\n', ['explainer']),
 ('M4 order not checked', X, '\tif not ordered then', '\tif false then', ['explainer']),
 ('M5 no diagram needed', X, 'if body and not string.find(body, "<svg", 1, true) then', 'if false then', ['explainer']),
 ('M6 touched searched in the whole page', X, 'if not string.find(changes, string.lower(p), 1, true) then', 'if not string.find(low, string.lower(p), 1, true) then', ['explainer']),
 ('M7 only the first choice is judged', X, '\t\tfor i, block in blocks do', '\t\tfor i, block in { blocks[1] } do', ['explainer']),
 ('M8 choice substring matches choices', X, 'if string.match(whole, "[\\"\'%s]choice[\\"\'%s]") then', 'if true then', ['explainer']),
 ('M9 css url not checked', X, 'for value in string.gmatch(low, "url%(%s*([^%)]*)%)") do', 'for value in string.gmatch("", "x") do', ['explainer']),
 ('M10 links to the web allowed', X, 'local names = table.clone(explainer.ATTRS)', 'local names = { "src" }', ['explainer','approve-page']),
 ('M11 a y prefix approves', X, 'return a == "y" or a == "yes"', 'return string.sub(a, 1, 1) == "y"', ['explainer']),
 ('M12 empty answer approves (default yes)', X, 'return a == "y" or a == "yes"', 'return a == "" or a == "y" or a == "yes"', ['explainer']),
 ('M13 approve skips the page check', M, '\tif #problems > 0 then\n\t\tfail(`{id}: the explainer page does not hold', '\tif false then\n\t\tfail(`{id}: the explainer page does not hold', ['approve-page']),
 ('M14 page not in the dirty check', M, '\ttable.insert(paths, page)\n', '', ['approve-page']),
 ('M15 opens only after y', M, '\tlocal opened, opener = openInDefaultApp(full)\n\tif opened then', '\tlocal opened, opener = true, "open"\n\tif opened then', ['approve-page']),
 ('M16 no recheck after the answer', M, '\tif changedNow or contract.hash(after :: contract.Parts) ~= hash then', '\tif false then', ['approve-page']),
 ('M17 a failed opener refuses', M, "\t\tstdio.ewrite(`warning: could not open {full} with {opener}; open it yourself and read it before you answer\\n`)", "\t\tfail(`could not open {full}`)", ['approve-page']),
 ('M18 explain exits 0 on problems', M, '\t\tprocess.exit(1)\n\tend\n\tprint("ok")', '\tend\n\tprint("ok")', ['approve-page']),
 ('M19 a missing page passes approve', M, '\tif not fs.isFile(path) then\n\t\treturn {\n', '\tif false then\n\t\treturn {\n', ['approve-page']),
 ('M20 approve passes no Touched modules', M, 'return explainer.check(path, fs.readFile(path), hash, touchedModules(item) or {})', 'return explainer.check(path, fs.readFile(path), hash, {})', ['approve-page']),
]
only=sys.argv[1:]
for name,f,old,new,specs in mutants:
    if only and name.split()[0] not in only: continue
    path=P+'/'+f; orig=open(path).read()
    if orig.count(old)!=1:
        print(name,'NOT APPLIED (count',orig.count(old),')'); continue
    open(path,'w').write(orig.replace(old,new))
    try:
        res=[]
        for s in specs:
            r=subprocess.run([ZN,'run','--time','300','--','lune','run','tests/run','--',A+s+'.spec.luau'],cwd=P+'/z-nile',capture_output=True,text=True,env={k:v for k,v in os.environ.items() if k!='ZN_DISPATCH'})
            out=r.stdout+r.stderr
            fails=[l.strip() for l in out.split('\n') if l.startswith('FAIL') and '::' in l]
            loaderr='could not load' in out or 'error requiring' in out
            res.append(f"{s}: {'LOAD-ERROR' if loaderr else (str(len(fails))+' failing')} {fails[:2]}")
        print(name,'|',' ; '.join(res))
    finally:
        open(path,'w').write(orig)
