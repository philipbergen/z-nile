"""Mutation check for c0283: python3 mutants.py ["<mutant id>" ...]  (MUT_WT names the prototype copy)

Each entry replaces one text in a copy of the prototype (proto-c0283), runs the row's spec through ./zn run, and restores the
file. A mutant is killed when the run fails; the output line says on what. An entry whose text is not found exits non-zero."""
import os
import subprocess
import sys

P = os.environ.get('MUT_WT', '/Users/philipbergen/code/pickman/.worktree/proto-c0283-mut')
Z = P + '/z-nile'
A = 'tests/acceptance/c0283/'
AP, AR, DC = A + 'approval.spec.luau', A + 'approve.spec.luau', A + 'docs.spec.luau'
PRV, MAIN = 'engine/provenance.luau', 'engine/main.luau'
M = [
    ('approved: the row holds the whole hash', PRV, 'design={string.sub(hash, 1, 12)}', 'design={hash}', AP),
    ('approved: the old rows are replaced', PRV, 'return provenance.record(text, id, "approved"', 'return provenance.record(nil, id, "approved"', AP),
    ('hint ignores CURSOR_AGENT', PRV, '"AI_AGENT", "CURSOR_AGENT", "GROK_SESSION_ID"', '"AI_AGENT", "GROK_SESSION_ID"', AP),
    ('hint ignores GROK_SESSION_ID', PRV, '"CURSOR_AGENT", "GROK_SESSION_ID", "ZN_DISPATCH" }', '"CURSOR_AGENT", "ZN_DISPATCH" }', AP),
    ('hint takes an empty marker', PRV, 'if v ~= nil and v ~= "" then', 'if v ~= nil then', AP),
    ('approve: an agent session with a terminal passes', MAIN, 'if provenance.hint(env).agent then', 'if false then', AR),
    ('approve: a human-claiming ZN_ACTOR passes an agent session', MAIN, 'if provenance.hint(env).agent then', 'if provenance.hint(env).agent and not string.find(process.env.ZN_ACTOR or "", "^human:") then', AR),
    ('approve: the agent markers are not read from the process', MAIN, 'env[name] = process.env[name]', 'env[name] = nil', AR),
    ('approve: no approved row is written', MAIN, '\tsh.writeReplacing(record, rtext :: string)\n', '\tsh.writeReplacing(record, if fs.isFile(record) then fs.readFile(record) else "")\n', AR),
    ('approve: the row rides another commit', MAIN, '`tracker: approve {id}`, "--", path, record })', '`tracker: approve {id}`, "--", path })', AR),
    ('approve: an uncommitted record is overwritten', MAIN, 'if sh.git({ "status", "--porcelain", "--", record }) ~= "" then', 'if false then', AR),
    ('approve: the approval is written before the record is decided', MAIN, 'if not rtext then\n\t\tfail(`{id}: {rerr}`)\n\tend\n\tlocal path = approval.file(item)\n\tsh.writeReplacing(path, text :: string)', 'local path = approval.file(item)\n\tsh.writeReplacing(path, text :: string)\n\tif not rtext then\n\t\tfail(`{id}: {rerr}`)\n\tend', AR),
    ('approve: the row carries another hash', MAIN, '\t\twho,\n\t\thash,\n\t\tos.date("!%Y-%m-%d %H:%M")', '\t\twho,\n\t\tstring.reverse(hash),\n\t\tos.date("!%Y-%m-%d %H:%M")', AR),
    ('docs: zz-rules loses the agent-session refusal', 'skills/zz-rules/SKILL.md', '**never in an agent session**', 'not in a dispatched step', DC),
    ('docs: zz-rules forgets the row', 'skills/zz-rules/SKILL.md', 'to the issue\'s `provenance.md` in the same `tracker: approve` commit', 'to a file', DC),
    ('docs: AGENTS.md lets an agent try', '../AGENTS.md', 'Tell the user to run it; never try to', 'Run it yourself', DC),
    ('approve: --check is refused in an agent session', MAIN, '\tlocal onlyCheck = opts["--check"] ~= nil\n\tif not onlyCheck then', '\tlocal onlyCheck = opts["--check"] ~= nil\n\tif true then', AR),
    ('fixture.exec does not clear the markers', 'tests/lib/fixture.luau', '\t\tscrubbed[name] = ""', '\t\tscrubbed[name] = nil :: any', AR),
]

def run(name, f, old, new, spec):
    path = f'{Z}/{f}'
    text = open(path).read()
    if text.count(old) != 1:
        return f'{name}: MUTANT DOES NOT APPLY ({text.count(old)} matches)', False
    open(path, 'w').write(text.replace(old, new, 1))
    try:
        r = subprocess.run(['./zn', 'run', '--time', '900', '--', 'bash', '-c', f'cd z-nile && lune run tests/run -- {spec}'],
                           cwd=P, capture_output=True, text=True)
    finally:
        open(path, 'w').write(text)
    out = r.stdout + r.stderr
    last = [l for l in out.splitlines() if 'passed' in l][-1:] or ['(no result line)']
    why = [l for l in out.splitlines() if l.startswith('     ')][:1]
    return f'{name}: {"KILLED" if r.returncode != 0 else "SURVIVED"} {last[0]} {why[0][-170:] if why else ""}', True

if __name__ == '__main__':
    if subprocess.run(['git', '-C', P, 'status', '--porcelain'], capture_output=True, text=True, timeout=60).stdout.strip():
        sys.exit(f'{P} is not clean: an interrupted run left a mutant in it (git -C {P} checkout -- .), then run again')
    only = sys.argv[1:]
    bad = 0
    for name, f, old, new, spec in M:
        if only and name not in only:
            continue
        line, applied = run(name, f, old, new, spec)
        print(line, flush=True)
        bad += (not applied) or 'SURVIVED' in line
    sys.exit(1 if bad else 0)
