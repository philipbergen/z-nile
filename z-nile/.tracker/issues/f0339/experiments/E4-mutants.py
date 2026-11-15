# f0339 prep E4: apply each Rules-and-mutants row's mutant to the prototype (.worktree/proto-f0339), run the row's
# spec(s), restore. Run through ./zn run (it is bounded). A row passes when its case fails on an assertion.
# Specs run inside the dispatched session as they are (no marker stripped): approve-page clears them itself.
import subprocess, sys, os
P = '/Users/philipbergen/code/pickman/.worktree/proto-f0339'
ZN = '/Users/philipbergen/code/pickman/.worktree/prep-ticket-explainer-page/zn'
A = P + '/z-nile/.tracker/issues/f0339/acceptance/'
X = 'z-nile/engine/explainer.luau'
M = 'z-nile/engine/main.luau'
S = 'z-nile/.tracker/issues/f0339/acceptance/approve-page.spec.luau'
E, AP, D = ['explainer'], ['approve-page'], ['docs']
mutants = [
 ('M1 any contract hash passes', X, [('elseif named[1] ~= string.lower(hash) then', 'elseif false then')], E + AP),
 ('M2 a repeated meta tag passes', X, [('elseif #named > 1 then', 'elseif false then')], E),
 ('M3 a repeated section passes', X, [('elseif #found > 1 then', 'elseif false then')], E),
 ('M4 order not checked', X, [('\tif not ordered then', '\tif false then')], E),
 ('M5 no diagram needed', X, [('local svg = picture(body)\n', 'local svg = picture(body) or "<svg>"\n')], E),
 ('M6 touched searched in the whole page', X, [('if not string.find(changes, string.lower(p), 1, true) then', 'if not string.find(low, string.lower(p), 1, true) then')], E),
 ('M7 only the first choice is judged', X, [('\t\tfor i, s in marks do', '\t\tfor i, s in { marks[1] } do')], E),
 ('M8 choice substring matches choices', X, [('if hasClass(classes :: string, "choice") then', 'if string.find(classes :: string, "choice", 1, true) then')], E),
 ('M9 css url not checked', X, [('for value in string.gmatch(low, "url%(%s*([^%)]*)%)") do', 'for value in string.gmatch("", "x") do')], E),
 ('M10 only src is checked', X, [('\t\tfor _, name in explainer.ATTRS do', '\t\tfor _, name in { "src" } do')], E + AP),
 ('M11 a y prefix approves', X, [('return a == "y" or a == "yes"', 'return string.sub(a, 1, 1) == "y"')], E),
 ('M12 empty answer approves (default yes)', X, [('return a == "y" or a == "yes"', 'return a == "" or a == "y" or a == "yes"')], E),
 ('M13 approve skips the page check', M, [('local problems = pageIO.problems(item, hash)\n\tif #problems > 0 then\n\t\tfail(`{id}: the explainer page', 'local problems = pageIO.problems(item, hash)\n\tif false then\n\t\tfail(`{id}: the explainer page')], AP),
 ('M14 page not in the dirty check', M, [('\ttable.insert(paths, page)\n', '')], AP),
 ('M15 approve never opens the page', M, [('local opened, opener = pageIO.open(full)', 'local opened, opener = true, "open"')], AP),
 ('M15b asks first, then opens', M, [('local opened, opener = pageIO.open(full)', 'local opened, opener = true, "open"'), ('\tlocal answer = pageIO.readLine()\n', '\tlocal answer = pageIO.readLine()\n\tpageIO.open(full)\n')], AP),
 ('M16 no recheck after the answer', M, [('\tif changedNow or contract.hash(after :: contract.Parts) ~= hash then', '\tif false then')], AP),
 ('M17 a failed opener refuses', M, [("\t\tstdio.ewrite(`warning: could not open {full} with {opener}; open it yourself and read it before you answer\\n`)", "\t\tfail(`could not open {full}`)")], AP),
 ('M18 explain exits 0 on problems', M, [('\t\tprocess.exit(1)\n\tend\n\tprint("ok")', '\tend\n\tprint("ok")')], AP),
 ('M19 a missing page passes', M, [('\tif not fs.isFile(path) then\n\t\treturn {\n', '\tif false then\n\t\treturn {\n')], AP),
 ('M20 approve passes no Touched modules', M, [('hash, touchedModules(item) or {})', 'hash, {})')], AP),
 ('M21 TERMINAL omits ZN_DISPATCH', S, [('\tZN_DISPATCH = "",\n', '')], AP),
 ('M22 scripts allowed', X, [('if string.find(low, "<script", 1, true) then', 'if false then')], E),
 ('M23 event handlers allowed', X, [('\t\tif handler then', '\t\tif false then')], E),
 ('M24 refresh allowed', X, [('if string.find(tag, "^<meta[%s/]") and', 'if false and')], E),
 ('M25 image-set unchecked', X, [('for body in string.gmatch(low, "image%-set%(([^%)]*)%)") do', 'for body in string.gmatch("", "x") do')], E),
 ('M26 no :// backstop', X, [('\tif #out == 0 then\n\t\t-- the backstop', '\tif false then\n\t\t-- the backstop')], E),
 ('M27 xmlns not exempt', X, [('local bare = string.gsub(low, "xmlns[%w:]*%s*=%s*[\\"\'][^\\"\']*[\\"\']", "")', 'local bare = low')], E),
 ('M28 placeholders allowed', X, [('if hasClass(classes, explainer.FILL) then', 'if false then')], E + D),
 ('M29 one picture twice allowed', X, [('if pictures.before and pictures.before == pictures.after then', 'if false then')], E),
 ('M30 whitespace between tags counts', X, [('local tight = string.gsub(svg, ">%s+<", "><")', 'local tight = svg')], E),
 ('M31 the id must come first', X, [('local id = string.match(attrs :: string, "[%s/\\"\']id%s*=', 'local id = string.match(attrs :: string, "^%s+id%s*=')], E),
 ('M32 --publish never warns about the page', M, [('if onMainPage ~= fs.readFile(pageRel) then', 'if false then')], AP),
 ('M33 --publish always warns', M, [('if onMainPage ~= fs.readFile(pageRel) then', 'if true then')], AP),
 ('M34 the prompt omits the hash', M, [('stdio.write(`Approve {id}, contract {string.sub(hash, 1, 12)}? [y/N] `)', 'stdio.write(`Approve {id}? [y/N] `)')], AP),
 ('M35 no answer is not named', M, [('local said = if answer then sh.trim(answer) else "no answer"', 'local said = if answer then sh.trim(answer) else ""')], AP),
 ('M36 explain takes a raft', M, [('\t\tfail(`explain takes an issue ({item.id} is a {item.kind})`)', '\t\tlocal _ = 0')], AP),
 ('M37 explain ignores an unknown option', M, [('\t\tfail(`usage: explain <issue-id> (unknown option {k})`)', '\t\tlocal _ = k')], AP),
 ('M38 case-sensitive matching', X, [('\tlocal low = string.lower(html)\n', '\tlocal low = html\n')], E),
]
only = sys.argv[1:]
for name, f, edits, specs in mutants:
    if only and name.split()[0] not in only:
        continue
    path = P + '/' + f
    orig = open(path).read()
    text = orig
    bad = [o for o, _ in edits if text.count(o) != 1]
    if bad:
        print(name, 'NOT APPLIED', [b[:50] for b in bad])
        continue
    for o, n in edits:
        text = text.replace(o, n)
    open(path, 'w').write(text)
    try:
        res = []
        for s in specs:
            r = subprocess.run([ZN, 'run', '--time', '400', '--', 'lune', 'run', 'tests/run', '--', A + s + '.spec.luau'],
                               cwd=P + '/z-nile', capture_output=True, text=True)
            out = r.stdout + r.stderr
            fails = [l.split('::', 1)[1].strip()[:70] for l in out.split('\n') if l.startswith('FAIL') and '::' in l]
            load = 'could not load' in out
            res.append(f"{s}: {'LOAD-ERROR' if load else str(len(fails)) + ' red'} {fails[:1]}")
        print(name, '|', ' ; '.join(res), flush=True)
    finally:
        open(path, 'w').write(orig)
