import subprocess, os
P=os.environ['C0180_SPLIT']  # a clone with experiments/split.patch applied
M=[
('R1','z-nile/engine/main.luau','return require("./cmd/find")','return require("./cmd/" .. "find")'),
('R2','z-nile/engine/gitroot.luau','local cli = require("./cli")','local cli = require("./cli")\nlocal _newCmd = require("./cmd/new")'),
('R3','z-nile/engine/main.luau','local USAGE = [[','local _gitroot = require("./gitroot")\nlocal USAGE = [['),
('R4','z-nile/engine/gitroot.luau','local cli = require("./cli")','local cli = require("./cli")\nlocal _guard = require("./guard")'),
('R5','z-nile/engine/main.luau','local USAGE = [[','local USAGE_TEXT = [['),
('R43','z-nile/engine/cmd/raft-plan.luau','local newCmd = require("./new")','local newCmd = require("./new")\nlocal _readyCmd = require("./ready")'),
('R47','z-nile/engine/main.luau','local args = table.clone(process.args)','for _, load in cmd :: any do\n\tload()\nend\nlocal args = table.clone(process.args)'),
# R44 is run by hand: write z-nile/engine/helpers.luau (`return {}`) and add `local _helpers = require("../helpers")`
# before `return function` in every z-nile/engine/cmd/*.luau; split.spec's "the split narrows" case must fail.
]
env=dict(os.environ); env['PATH']=os.path.expanduser('~/.rokit/bin')+':'+env['PATH']; env['ZN_SPEC_TRACE']=''
for mid,f,old,new in M:
    path=os.path.join(P,f); s=open(path).read(); assert s.count(old)==1,(mid,s.count(old))
    open(path,'w').write(s.replace(old,new,1))
    r=subprocess.run(['lune','run','tests/run','--','.tracker/issues/c0180/acceptance/split.spec.luau'],cwd=P+'/z-nile',capture_output=True,text=True,env=env)
    fails=[l for l in r.stdout.split('\n') if l.startswith('FAIL')]
    print(mid,'KILLED' if r.returncode and fails else 'SURVIVED', fails[:2])
    subprocess.run(['git','checkout','--',f],cwd=P)
