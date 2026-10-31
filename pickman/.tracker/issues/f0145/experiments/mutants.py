#!/usr/bin/env python3
# f0145's mutation check (z-design step 4): applies each Rules and mutants row's mutant alone to a prototype's pickman/
# tree, runs the row's acceptance specs from that tree's .tracker/issues/f0145/acceptance, and restores the file.
# A row is killed when one of its specs fails on an assertion (loaderr counts load failures, which do not count).
# Usage (run it on a scratch prototype, never on a tree you care about; it rewrites src files and puts them back):
#   PATH="$HOME/.rokit/bin:$PATH" python3 -I mutants.py <prototype>/pickman [ROW ...]
import os, re, subprocess, sys
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
 'N3': (SUBMITS, [('\t\t\tsubmission.run,\n\t\t\tsubmission.lives\n', '\t\t\tsubmission.run\n')], ['runs']),
 'N4': (STORE, [('score = score, lives = lives }', 'score = score }')], ['runs']),
 'N5': (CON, [('\t\t\t\t\tif bought and s then', '\t\t\t\t\tif false and s then')], ['adapters']),
 'N6': (GAME, [('\t\t\tif g.waiting == 0 then', '\t\t\tif false then')], ['offer', 'adapters']),
 'N7': (PUR, [('\tif Purchases.mode() ~= "test" or pending[player] ~= product then', '\tif Purchases.mode() ~= "test" then')], ['adapters']),
 'N8': (PAY, [('\treturn if mode == "test" then Pay.TEST_STORE else Pay.STORE', '\treturn Pay.STORE')], ['pay', 'adapters']),
 'N9': (CON, [('\t\t\tlocal record, fresh = Purchases.testGrant(player, "continue", HttpService:GenerateGUID(false))',
               '\t\t\tlocal record, fresh = Purchases.grant(player.UserId, "continue", "test:" .. HttpService:GenerateGUID(false))')], ['adapters']),
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
 'P4': (CON, [('\t\tsentBack[player] = true\n\t\trefuse(player)\n\t\ttask.defer(refuse, player)', '\t\tsentBack[player] = true')], ['adapters']),
 'P5': (CON, [('\t\tif not ok then\n\t\t\tkick(player)\n\t\t\treturn\n\t\tend', '\t\tif not ok then\n\t\t\treturn\n\t\tend')], ['adapters']),
 'P6': (CON, [('\tgame:GetService("TeleportService").TeleportInitFailed:Connect(function(player: Player)\n\t\tkick(player)\n\tend)', '')], ['adapters']),
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
 'Q1': (CON, [('if known[player] == 0 or (last ~= nil', 'if false or (last ~= nil')], ['adapters']),
 'Q2': (CON, [('(last ~= nil and os.clock() - last < Continues.ASK_SECONDS)', 'false')], ['adapters']),
 'Q3': (CON, [('\t\t\tand not Session.holding(s, id) -- a screen is open (or a receipt awaited): the ask is already being answered\n', '')], ['adapters']),
 'Q4': (PAID, [('\tif seen and os.clock() - seen.at < Paid.PRESS_SECONDS then', '\tif false then')], ['adapters']),
 'Q5': (CON, [('\t\tif flight.held then\n\t\t\tSession.hold(s, id, true)', '\t\tif false then\n\t\t\tSession.hold(s, id, true)')], ['adapters']),
 'Q6': (CON, [('\t\tif flight.held and here then\n\t\t\tSession.hold(s, id, false)', '\t\tif here then\n\t\t\tSession.hold(s, id, false)')], ['adapters']),
 'Q7': (PAY, [('\tlocal nextR = copy(r)\n\tnextR.continues += 1\n\treturn nextR\nend', '\treturn (Pay.grant(r, "continue", "refund"))\nend')], ['pay', 'adapters']),
 'Q8': (PAY, [('\tlocal nextR = copy(r)\n\tnextR.continues += 1\n\treturn nextR\nend', '\tlocal nextR = copy(r)\n\tnextR.continues += 1\n\ttable.insert(nextR.receipts, "refund")\n\treturn nextR\nend')], ['pay']),
 'Q9': (CON, [('\t\tif player.Parent == nil then\n\t\t\treturn -- left during the write (design review 003 F5)\n\t\tend\n', '')], ['adapters']),
}
try:
    from mutants_early import EARLY  # the rows of the first prototype (Y, G, S, H, L, F, A, K), kept beside this file
    ROWS = {**EARLY, **ROWS}
except ImportError as e:
    print('mutants: no early rows:', e, file=sys.stderr)

def main():
    root = sys.argv[1]; only = sys.argv[2:]
    for mid, (f, edits, specs) in ROWS.items():
        if only and mid not in only:
            continue
        path = os.path.join(root, f); orig = open(path).read(); s = orig; missing = None
        for a, b in edits:
            if s.count(a) != 1:
                missing = a; break
            s = s.replace(a, b)
        if missing is not None:
            print(mid, 'NOT APPLIED', repr(missing[:60]), flush=True); continue
        open(path, 'w').write(s)
        try:
            out = []
            for spec in specs:
                r = subprocess.run(['lune', 'run', 'tests/run', '--', f'.tracker/issues/f0145/acceptance/{spec}.spec.luau'],
                                   cwd=root, capture_output=True, text=True)
                txt = r.stdout + r.stderr
                m = re.findall(r'(\d+ passed, \d+ failed, \d+ spec files)', txt)
                out.append(f"{spec}=({m[-1] if m else 'NO SUMMARY'}; loaderr {len(re.findall('could not load spec', txt))})")
            print(f'{mid}: ' + ' '.join(out), flush=True)
        finally:
            open(path, 'w').write(orig)

if __name__ == '__main__':
    main()
