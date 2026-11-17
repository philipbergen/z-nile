#!/usr/bin/env python3
# f0145's mutation check (z-design step 4): applies each Rules and mutants row's mutant alone to a prototype's pickman/
# tree, runs the row's acceptance specs from that tree's f0145 acceptance folder (wherever the item's lifecycle put it:
# .tracker/issues/f0145, .tracker/issues/active/f0145, or tests/acceptance/f0145 once promoted), and restores the file.
# A row's verdict is computed, never read off by hand: KILLED when one of its specs fails on an assertion and none
# fails to load; LOADFAIL when a spec failed to load (that does not count as killed); SURVIVED when every spec
# passed; NOSUMMARY when the runner printed no summary. Before any row, every spec named by a row is run unmutated
# and must pass (BASELINE), so a stale path or a red tree cannot read as a kill.
# The bug this replaces (found in R0118's execution, 2026-11-16): the folder was hard-coded to
# .tracker/issues/f0145/acceptance, so on a tree where the item had moved every spec failed to load ("0 passed,
# 1 failed") and the printed line looked like a kill; nothing checked a baseline, and the verdict was left to the reader.
# A spec entry is a name under the acceptance folder ('adapters'), or a path from pickman/ ending .spec.luau.
# Usage (run it on a scratch prototype, never on a tree you care about; it rewrites src files and puts them back):
#   PATH="$HOME/.rokit/bin:$PATH" python3 -I mutants.py <prototype>/pickman [ROW ...]
import os, re, signal, subprocess, sys
sys.dont_write_bytecode = True  # no __pycache__ beside the experiments
# ./zn run stops a run with TERM: raise instead, so the finally below puts the mutated file back
signal.signal(signal.SIGTERM, lambda *_: sys.exit('mutants: stopped (TERM); the mutated file was restored'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # mutants_early.py beside this file, also under -I

PAY = 'src/shared/Logic/Pay/init.luau'; GAME = 'src/shared/Logic/Game/init.luau'; SES = 'src/shared/Logic/Session/init.luau'
HIS = 'src/shared/Logic/Hiscores/init.luau'; LOB = 'src/shared/Logic/Lobby/init.luau'; FLOW = 'src/shared/Logic/Flow/init.luau'
PUR = 'src/shared/Purchases.luau'; CON = 'src/server/Continues.luau'; PAID = 'src/lobby/server/Paid.luau'
STARTS = 'src/lobby/server/Starts.luau'; OV = 'src/client/OfferView.luau'; TP = 'src/shared/TestPurchase.luau'
SESSIONS = 'src/server/Sessions.luau'; SUBMITS = 'src/server/Submits.luau'; STORE = 'src/server/HiscoreStore.luau'

ROWS = {
 # review 001
 'N1': (SES, [('\t\tGame.allowOffer(member.play, 0)\n', '')], ['offer', 'runs']),
 'N2': (SESSIONS, [('\t\t\tSession.depart(s, tostring(player.UserId))\n', '')], ['runs']),
 'N3': (SUBMITS, [('\t\t\tsubmission.run,\n\t\t\tsubmission.lives -- f0145: the lives the run spent\n', '\t\t\tsubmission.run\n')], ['runs']),
 'N4': (STORE, [('\t\t\t\tlives = lives,\n', '')], ['runs']),
 'N5': (CON, [('\t\t\t\t\tif bought then', '\t\t\t\t\tif false then')], ['adapters']),
 'N6': (GAME, [('\t\t\tif g.waiting == 0 then', '\t\t\tif false then')], ['offer', 'adapters']),
 'N7': (PUR, [('\tif Purchases.mode() ~= "test" or pending[player] ~= product then', '\tif Purchases.mode() ~= "test" then')], ['adapters']),
 'N8': (PAY, [('\treturn if mode == "test" then Pay.TEST_STORE else Pay.STORE', '\treturn Pay.STORE')], ['pay', 'adapters']),
 'N9': (CON, [('local record, fresh = Purchases.testGrant(player, "continue", Purchases.guid())',
               'local record, fresh = Purchases.grant(player.UserId, "continue", "test:" .. Purchases.guid())')], ['adapters']),
 'N10': (PUR, [('\t\tstore():UpdateAsync(tostring(userId), function(old: any): any\n\t\t\tlocal nextR, a = change(Pay.record(old))\n\t\t\tanswer, written = a, nextR\n\t\t\treturn nextR\n\t\tend)',
                '\t\tlocal nextR, a = change(Pay.record(store():GetAsync(tostring(userId))))\n\t\tanswer, written = a, nextR\n\t\tstore():UpdateAsync(tostring(userId), function(): any\n\t\t\treturn nextR\n\t\tend)')], ['adapters']),
 'N11': (PUR, [('\t\t\tanswer, written = a, nextR\n', '\t\t\tif answer == nil then\n\t\t\t\tanswer, written = a, nextR\n\t\t\tend\n')], ['adapters']),
 'N12': (PAY, [('\tif how == nil or how == "free" or how == "credit" or passed then', '\tif true then')], ['pay', 'adapters']),
 'N13': (PAY, [('\treturn if id(p.play) and id(p.continue) then "live" else "closed"', '\treturn "live"')], ['pay', 'adapters']),
 'N14': (PUR, [('\t\t\tmap:RemoveAsync(tostring(userId))\n', '')], ['adapters']),
 'N15': (PAID, [('\t\tPurchases.pass(player.UserId) -- the play place lets this one game go free (decided 2026-10-26)\n', '')], ['adapters']),
 # review 002
 'P1': (SES, [('function Session.depart(s: Session, id: PlayerId)\n\tlocal member = s.members[id]\n', 'function Session.depart(s: Session, id: PlayerId)\n\tlocal member = memberOf(s, id)\n')], ['offer']),
 'P2': (SES, [('\tif member then\n\t\tGame.refuse(member.play)\n\tend', '\tif member then\n\t\tGame.decline(member.play)\n\tend')], ['offer', 'adapters']),
 'P3': (GAME, [('\tg.phase, g.offer, g.held, g.waiting = "gameover", 0, false, 0\n', '\tg.offer, g.held, g.waiting = 0, false, 0\n')], ['offer', 'adapters']),
 'P4': (CON, [('\t\tsentBack[player] = true\n\t\tSession.refuse(s, tostring(player.UserId))\n', '\t\tsentBack[player] = true\n')], ['adapters']),
 'P5': (CON, [('\t\tif not ok then\n\t\t\tkick(player)\n\t\t\treturn\n\t\tend', '\t\tif not ok then\n\t\t\treturn\n\t\tend')], ['adapters']),
 'P6': (CON, [('\tTeleportService.TeleportInitFailed:Connect(function(player: Player)\n\t\tkick(player)\n\tend)', '')], ['adapters']),
 'P7': (CON, [('\t\ttask.delay(Continues.BACK_SECONDS, kick, player)\n', '')], ['adapters']),
 'P8': (CON, [('\t\tif sentBack[player] and player.Parent ~= nil then', '\t\tif player.Parent ~= nil then')], ['adapters']),
 'P9': (CON, [('\t\tlocal passed = Purchases.takePass(player.UserId)\n', '\t\tlocal passed = how == "buy" and Purchases.takePass(player.UserId)\n')], ['adapters']),
 'P10': (PUR, [('\treturn not ok or had == true', '\treturn ok and had == true')], ['adapters']),
 'P11': (PAY, [('\treturn if id(p.play) and id(p.continue) then "live" else "closed"', '\treturn if id(p.play) and id(p.continue) then "live" else "test"')], ['pay', 'adapters']),
 'P12': (PUR, [('\tif mode == "closed" then\n\t\treturn\n\telseif mode == "live" then', '\tif mode == "live" then')], ['adapters']),
 'P14': (PAY, [('\treturn if mode == "test" then Pay.TEST_STORE else Pay.STORE', '\treturn if mode == "live" then Pay.STORE else Pay.TEST_STORE')], ['pay', 'adapters']),
 'P15': (CON, [('\t\tif flying[player] then\n\t\t\treturn "busy"\n\t\tend\n', '')], ['adapters']),
 'P16': (CON, [('\t\tif used and here and not flight.declined then', '\t\tif used then')], ['adapters']),
 'P17': (CON, [('\t\tif used then\n\t\t\t-- given back', '\t\tif false then\n\t\t\t-- given back')], ['adapters']),
 'P18': (CON, [('\t\t\tif flight then\n\t\t\t\tflight.declined = true\n\t\t\telse', '\t\t\tif false then\n\t\t\t\tflight.declined = true\n\t\t\telse')], ['adapters']),
 'P19': (CON, [('\n\t\t\tand Purchases.canBuy()', '')], ['adapters']),
 'P20': (LOB, [('\t\tline = if mode == "closed" then "STORE UNAVAILABLE" else "1 ROBUX A GAME"', '\t\tline = "1 ROBUX A GAME"')], ['views']),
 'P21': (FLOW, [('\tif o.mode == "closed" then\n', '\tif false then\n')], ['views']),
 # review 003
 'Q1': (CON, [('local quiet = known[player] == 0 or (last ~= nil', 'local quiet = false or (last ~= nil')], ['adapters']),
 'Q2': (CON, [('(last ~= nil and os.clock() - last < Continues.ASK_SECONDS)', 'false')], ['adapters']),
 'Q3': (CON, [('\t\t\tand not Session.holding(s, id) -- a screen is open (or a receipt awaited): the ask is already being answered\n', '')], ['adapters']),
 'Q4': (PAID, [('\tif seen and os.clock() - seen.at < Paid.PRESS_SECONDS then', '\tif false then')], ['adapters']),
 'Q5': (CON, [('\t\tif flight.held then\n\t\t\tSession.hold(s, id, true)', '\t\tif false then\n\t\t\tSession.hold(s, id, true)')], ['adapters']),
 'Q6': (CON, [('\t\tif flight.held and here then\n\t\t\tSession.hold(s, id, false)', '\t\tif here then\n\t\t\tSession.hold(s, id, false)')], ['adapters']),
 'Q7': (PAY, [('\tlocal nextR = copy(r)\n\tnextR.continues += 1\n\treturn nextR\nend', '\treturn (Pay.grant(r, "continue", "refund"))\nend')], ['pay', 'adapters']),
 'Q8': (PAY, [('\tlocal nextR = copy(r)\n\tnextR.continues += 1\n\treturn nextR\nend', '\tlocal nextR = copy(r)\n\tnextR.continues += 1\n\ttable.insert(nextR.receipts, "refund")\n\treturn nextR\nend')], ['pay']),
 # the resume of 2026-11-15 (f0126 on main, f0148's Sessions.made)
 'Q10': (PAID, [('\t\tif ok then\n\t\t\ttell(player, record)\n\t\tend', '\t\tif ok then\n\t\t\tkept[player] = { at = os.clock(), record = record }\n\t\t\ttell(player, record)\n\t\tend')], ['adapters']),
 'S3': (SES, [('\t\tteleport(s, member, s.tick + 1)\n\t\tresetGhosts(member, "respawn", s.tick + 1)\n',
               '\t\tteleport(s, member, s.tick + 1)\n\t\tPellets.reset(member.pellets)\n\t\tfreshMaze(s, member)\n\t\tresetGhosts(member, "continue", s.tick + 1)\n')], ['offer', 'tests/unit/Session/session.spec.luau']),
 # R0118's execution: the ghosts' "respawn" reset alone, which only the unit case observes (Implementation steps, 2)
 'S4': (SES, [('\t\tresetGhosts(member, "respawn", s.tick + 1)\n', '\t\tresetGhosts(member, "continue", s.tick + 1)\n')], ['tests/unit/Session/session.spec.luau']),
 'M1': ('src/server/Main.server.luau', [('Sessions.made(require("./Continues").start(Sessions.session))', 'require("./Continues").start(Sessions.session)')], ['place']),
 'M2': ('src/server/Main.server.luau', [('Sessions.made(require("./Continues").start(Sessions.session)) -- f0145: paid play on arrival, the continue offer\nSessions.start(require("./Submits"))\n',
               'Sessions.start(require("./Submits"))\nSessions.made(require("./Continues").start(Sessions.session))\n')], ['place']),
 # R0118's execution: the last table row (d0124's list carries the lives), which had no runner id
 'T1': (HIS, [('\t\t\t\tlives = Hiscores.lives(e.lives), -- f0145: the list\'s copy keeps the lives spent\n', '')], ['top']),
 'Q9': (CON, [('\t\tif player.Parent == nil then\n\t\t\treturn -- left during the write (design review 003 F5)\n\t\tend\n', '')], ['adapters']),
}
try:
    from mutants_early import EARLY  # the rows of the first prototype (Y, G, S, H, L, F, A, K), kept beside this file
    ROWS = {**EARLY, **ROWS}
except ImportError as e:
    print('mutants: no early rows:', e, file=sys.stderr)

def acceptance(root):
    for rel in ('.tracker/issues/f0145/acceptance', '.tracker/issues/active/f0145/acceptance',
                '.tracker/issues/done/f0145/acceptance', 'tests/acceptance/f0145'):
        if os.path.isdir(os.path.join(root, rel)):
            return rel
    sys.exit('mutants: no f0145 acceptance folder under ' + root)

def spec_path(acc, spec):
    return spec if spec.endswith('.spec.luau') else f'{acc}/{spec}.spec.luau'

def run(root, path):
    r = subprocess.run(['lune', 'run', 'tests/run', '--', path], cwd=root, capture_output=True, text=True, timeout=600)
    txt = r.stdout + r.stderr
    m = re.findall(r'(\d+) passed, (\d+) failed, \d+ spec files', txt)
    loaderr = len(re.findall('could not load spec', txt))
    if not m:
        return 'NOSUMMARY', 'no summary', loaderr
    passed, failed = int(m[-1][0]), int(m[-1][1])
    verdict = 'LOADFAIL' if loaderr else ('KILLED' if failed > 0 else 'SURVIVED')
    return verdict, f'{passed} passed, {failed} failed', loaderr

def main():
    root = sys.argv[1]; only = sys.argv[2:]
    acc = acceptance(root)
    rows = {mid: row for mid, row in ROWS.items() if not only or mid in only}
    specs_used = sorted({spec_path(acc, s) for (_, _, specs) in rows.values() for s in specs})
    red = False
    for path in specs_used:
        verdict, summary, loaderr = run(root, path)
        ok = verdict == 'SURVIVED'  # unmutated, every case must pass
        red = red or not ok
        print(f'BASELINE {"ok" if ok else "RED"} {path}: {summary}; loaderr {loaderr}', flush=True)
    if red:
        sys.exit('mutants: the unmutated tree is not green; no row is judged')
    tally = {}
    for mid, (f, edits, specs) in rows.items():
        path = os.path.join(root, f); orig = open(path).read(); s = orig; missing = None
        for a, b in edits:
            if s.count(a) != 1:
                missing = a; break
            s = s.replace(a, b)
        if missing is not None:
            print(f'{mid}: NOTAPPLIED {missing[:60]!r}', flush=True); tally['NOTAPPLIED'] = tally.get('NOTAPPLIED', 0) + 1
            continue
        open(path, 'w').write(s)
        try:
            out = []; verdicts = []
            for spec in specs:
                verdict, summary, loaderr = run(root, spec_path(acc, spec))
                verdicts.append(verdict)
                out.append(f'{spec}=({summary}; loaderr {loaderr}; {verdict})')
            if 'LOADFAIL' in verdicts or 'NOSUMMARY' in verdicts:
                row = 'LOADFAIL'
            elif 'KILLED' in verdicts:
                row = 'KILLED'
            else:
                row = 'SURVIVED'
            tally[row] = tally.get(row, 0) + 1
            print(f'{mid}: {row} ' + ' '.join(out), flush=True)
        finally:
            open(path, 'w').write(orig)
    print('TALLY ' + ' '.join(f'{k}={v}' for k, v in sorted(tally.items())), flush=True)

if __name__ == '__main__':
    main()
