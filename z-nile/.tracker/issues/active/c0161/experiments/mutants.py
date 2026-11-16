import subprocess,sys,os,re,shutil
# usage: python3 -I mutants.py <prototype clone root> [mutant ids]  (BOUNDED=<path of the time-bounded runner>)
# The clone has proto-engine.patch and proto-fixtures.patch applied and this issue's acceptance/ copied under
# z-nile/.tracker/issues/c0161/. Each mutant is applied to one engine file, the named spec run from z-nile/, then undone.
P=sys.argv.pop(1)
BOUNDED=os.environ['BOUNDED']
Z=P+'/z-nile'
ST=Z+'/engine/status.luau'; MN=Z+'/engine/main.luau'
RULE='.tracker/issues/c0161/acceptance/review-rule.spec.luau'
GATE='.tracker/issues/c0161/acceptance/review-gate.spec.luau'
RAFT='.tracker/issues/c0161/acceptance/review-raft.spec.luau'
REC='.tracker/issues/c0161/acceptance/design-record.spec.luau'
READ='.tracker/issues/c0161/acceptance/review-read.spec.luau'
RP=Z+'/engine/raftplan.luau'
def move_rerecord_after_kept(src):
    # K7: the re-record of Design record lines runs after the grouped: re-record instead of before it
    i=src.index('\tfor _, q in quoting do')
    j=src.index('\tfor _, k in kept do')
    block=src[i:j]
    rest=src[:i]+src[j:]
    k=rest.index('\tfor _, k in kept do')
    end=rest.index('\nend\n',k)
    return rest[:end+1]+block+rest[end+1:]
def check_in_fold_only(src):
    # N5x: the stale check sits in cmd.fold after its refuseUnraftable call, not inside refuseUnraftable (recombine unchecked)
    blk='\tlocal stale = preparedRead(issue.id, originFolderFiles(issue.dir))\n\tif stale then\n\t\tfail(stale)\n\tend\n'
    s2=src.replace(blk,'')
    call='refuseUnraftable(issue, raft)\n'
    i=s2.index(call)
    ls=s2.rfind('\n',0,i)+1
    indent=s2[ls:i]
    body=''.join(indent+l[1:]+'\n' if l.strip() else '\n' for l in blk.split('\n') if l)
    return s2[:i+len(call)]+body+s2[i+len(call):]
M=[
 ('N1',ST,'string.match(rel, "^design%-review%-(%d%d%d)%.md$")','string.match(rel, "design%-review%-(%d%d%d)%.md")',RULE),
 ('N2',ST,'(tonumber(n) :: number) > newest','(tonumber(n) :: number) < newest or newest == 0',RULE),
 ('V1',ST,'if verdict ~= "approve" then','if false then',RULE),
 ('V2',ST,'if string.sub(line, 1, #"Verdict: ") == "Verdict: " then','if string.find(line, "Verdict: ", 1, true) ~= nil then',RULE),
 ('V4',ST,'if verdict ~= "approve" then','if not string.match(verdict or "", "^approve") then',RULE),
 ('C1',ST,'if verdict == "changes" then','if verdict == "changes" then verdict = "approve" end\n\tif false then',RULE),
 ('Q1',ST,'if quoted ~= record then','if false then',RULE),
 ('Q2',ST,'if quoted == nil then','if false then',RULE),
 ('Q4',ST,'elseif string.sub(line, 1, #"Design record:") == "Design record:" then','elseif string.find(line, "Design record:", 1, true) ~= nil then',RULE),
 ('R1',ST,'elseif record ~= nil then','elseif false then',RULE),
 ('R2',ST,'if verdict ~= nil then','if false then',RULE),
 ('R3',ST,'if hash == nil then','if false then',RULE),
 ('R4',ST,'if not quotes then','if false then',RULE),
 ('R5',ST,'local problem = status.designReviewProblem(files, record)\n\tif problem then\n\t\treturn `is prepared','local problem = nil\n\tif problem then\n\t\treturn `is prepared',RULE),
 ('R6',ST,'if string.match(line, "^Design record: (%x+)[ \\r]*$") == from then','if string.find(line, from, 1, true) then',RULE),
 ('N1x',MN,'\t\t\t\t\tif st == "prepared" then\n\t\t\t\t\t\tlocal stale = preparedRead(','\t\t\t\t\tif false then\n\t\t\t\t\t\tlocal stale = preparedRead(',READ),
 ('N2x',MN,'\tlocal stale = preparedRead(issue.id, originFolderFiles(issue.dir))','\tlocal stale = nil',READ),
 ('N3x',MN,'\t\t\t\t\t\tlocal stale = preparedRead(m.id, mfiles)','\t\t\t\t\t\tlocal stale = nil',READ),
 ('N4x',MN,'\t\t\t\t\t\tlocal stale = preparedRead(m.id, mfiles)','\t\t\t\t\t\tlocal stale = statusLib.preparedReadProblem(mfiles, "000000000000")\n\t\t\t\t\t\tstale = if stale then `{m.id} {stale}` else nil',READ),
 ('N5x',MN,'\tlocal stale = preparedRead(issue.id, originFolderFiles(issue.dir))\n\tif stale then\n\t\tfail(stale)\n\tend\n',check_in_fold_only,READ),
 ('N6x',MN,'\t\t\tplanned.stale = statusLib.preparedReadProblem(files, raftplan.designRecord(it.id, files))','\t\t\tplanned.stale = nil',READ),
 ('N7x',MN,'\tlocal stale = preparedRead(issue.id, originFolderFiles(issue.dir))','\tlocal stale = preparedRead(issue.id, gitFolderFiles(issue.dir))',READ),
 ('N2y',ST,'(tonumber(n) :: number) > newest','(tonumber(n) :: number) < newest or newest == 0',READ),
 ('N8x',MN,'planned.stale = statusLib.preparedReadProblem(files, raftplan.designRecord(it.id, files))','planned.stale = statusLib.preparedReadProblem(files, "000000000000")',READ),
 ('N9x',MN,'\t\t\tlocal files = originFolderFiles(it.dir)\n\t\t\tplanned.stale','\t\t\tlocal files = gitFolderFiles(it.dir)\n\t\t\tplanned.stale',READ),
 ('F4x',MN,'\trefuseInMainCheckout("design-record")\n','',REC),
 ('K9',MN,'\t\t\t\tlocal files = gitFolderFiles(dir)\n\t\t\t\tlocal current','\t\t\t\tlocal files = gitFolderFiles(dir, true)\n\t\t\t\tlocal current',REC),
 ('K10',MN,'\t\t\tif rounds then\n\t\t\t\tlocal files = gitFolderFiles(dir)','\t\t\tif rounds and idMap[iid] ~= nil then\n\t\t\t\tlocal files = gitFolderFiles(dir)',REC),
 ('K11',RP,'\t\t\tinFront = seen == 1\n\t\t\ttable.insert(kept, line)\n','\t\t\tinFront = seen == 1\n',REC),
 ('G1',MN,'\t\t\t\tif not store.isRaftId(t) then\n\t\t\t\t\t-- c0161','\t\t\t\tif false then\n\t\t\t\t\t-- c0161',GATE),
 ('F1',MN,'local own = gitFolderFiles(localItem.dir)','local own = gitFolderFiles(localItem.dir, true)',GATE),
 ('P2',MN,'\t\t\t\tif not store.isRaftId(t) then\n\t\t\t\t\t-- c0161','\t\t\t\tif t == id and not store.isRaftId(t) then\n\t\t\t\t\t-- c0161',RAFT),
 ('P3',MN,'\t\t\t\tif not store.isRaftId(t) then\n\t\t\t\t\t-- c0161','\t\t\t\tdo\n\t\t\t\t\t-- c0161',RAFT),
 ('P1',MN,'\t\t\t\t\t\trafted = true\n','\t\t\t\t\t\trafted = true\n\t\t\t\t\t\tdo local pr = statusLib.designReviewProblem(gitFolderFiles(store.get(t).dir), "x"); if pr then return `{t} {pr}` end end\n',RAFT),
 ('L5',MN,'local problem = statusLib.designReviewProblem(own, raftplan.designRecord(t, own))\n','local problem = statusLib.designReviewProblem(own, raftplan.designRecord(t, own))\n\t\t\t\t\tif problem and t ~= id and gitFolderFiles(store.get(id).dir)["design-review-001.md"] ~= nil then problem = nil end\n',RAFT),
 ('K1',MN,'print(raftplan.designRecord(id, gitFolderFiles(item.dir)))','print(raftplan.designRecord(id, gitFolderFiles(item.dir, true)))',REC),
 ('K2',RP,'if spec or (not specsOnly','if spec or string.sub(rel, 1, 14) == "design-review-" or (not specsOnly',REC),
 ('K3',RP,'{ "status", "raft", "design" }','{ "status", "raft" }',REC),
 ('K4',RP,'local spec = rel == "check.sh" or string.sub(rel, 1, #"acceptance/") == "acceptance/"','local spec = string.sub(rel, 1, #"acceptance/") == "acceptance/"',REC),
 ('K8',RP,' or string.sub(rel, 1, #"experiments/") == "experiments/"','',REC),
 ('K5',MN,'\t\t\t\tif out ~= text then\n\t\t\t\t\tfs.writeFile(p, out)\n\t\t\t\tend','\t\t\t\tif false then\n\t\t\t\t\tfs.writeFile(p, out)\n\t\t\t\tend',REC),
 ('K6',MN,'if hash ~= nil and hash == current then','if hash ~= nil then',REC),
 ('K7',MN,'\tfor _, q in quoting do',move_rerecord_after_kept,REC),
]
only=sys.argv[1:]
for mid,f,old,new,spec in M:
    if only and mid not in only: continue
    s=open(f).read()
    if s.count(old)!=1: print(mid,'APPLY-FAIL count',s.count(old)); continue
    open(f+'.orig','w').write(s); open(f,'w').write(new(s) if callable(new) else s.replace(old,new))
    try:
        r=subprocess.run(['perl',BOUNDED,'240','lune','run','tests/run','--',spec],cwd=Z,capture_output=True,text=True)
        out=r.stdout+r.stderr
        m=re.search(r'(\d+) passed, (\d+) failed',out)
        fails=[l[:150] for l in out.split('\n') if l.startswith('FAIL')]
        err=[l[:200] for l in out.split('\n') if 'attempt' in l or 'Syntax' in l or 'SyntaxError' in l][:1]
        print(mid,m.group(0) if m else 'NO-SUMMARY '+out[-200:],'|',fails[:3],err)
    finally:
        shutil.move(f+'.orig',f)
    sys.stdout.flush()
