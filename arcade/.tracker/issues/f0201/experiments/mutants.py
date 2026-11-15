"""f0201 prep mutation check: applies each Rules-and-mutants row's mutant to the prototype (one at a time) and runs
that row's spec. A mutant is killed when a case fails on an assertion ("expected ..."); a failure that is not an
assertion (a load or runtime error) is reported as an error, and a mutant that passes survives.
Usage (from anywhere): python3 -I mutants.py <prototype worktree> <prep worktree>"""
import os, re, subprocess, sys

PROTO, PREP = sys.argv[1], sys.argv[2]
HOME = os.path.join(PROTO, "arcade")
ACC = os.path.join(PREP, "arcade/.tracker/issues/f0201/acceptance")
L = "src/shared/Logic/PaidPlay/init.luau"
W = "src/server/Wallet.luau"
R = "src/server/Receipts.luau"
C = "src/shared/TestPurchase.luau"

# (id, spec, file, [(old, new)])
M = [
 ("Y1", "paidplay", L, [("now - r.free >= PaidPlay.FREE_SECONDS", "now - r.free > PaidPlay.FREE_SECONDS")]),
 ("Y2", "paidplay", L, [("n.free = now", "n.free = r.free")]),
 ("Y3", "paidplay", L, [("\tif PaidPlay.freeDue(r, now) then\n\t\tlocal n = copy(r)\n\t\tn.free = now\n\t\treturn \"free\", n\n\tend\n\tif r.plays >= 1 then\n\t\tlocal n = copy(r)\n\t\tn.plays -= 1\n\t\treturn \"credit\", n\n\tend",
                         "\tif r.plays >= 1 then\n\t\tlocal n = copy(r)\n\t\tn.plays -= 1\n\t\treturn \"credit\", n\n\tend\n\tif PaidPlay.freeDue(r, now) then\n\t\tlocal n = copy(r)\n\t\tn.free = now\n\t\treturn \"free\", n\n\tend")]),
 ("Y4", "paidplay", L, [(" or table.find(r.receipts, receiptId) then", " then")]),
 ("Y5", "paidplay", L, [("while #n.receipts > PaidPlay.RECEIPTS_KEPT do", "while false do")]),
 ("Y6", "paidplay", L, [("table.remove(n.receipts, 1)", "table.remove(n.receipts)")]),
 ("Y7", "paidplay", L, [("if r.revives < 1 then", "if r.revives < 0 then")]),
 ("Y8", "config", L, [("if raw ~= PaidPlay.LIVE then", "if string.lower(tostring(raw)) ~= PaidPlay.LIVE then")]),
 ("Y9", "paidplay", L, [("x == x and x >= 0 and", "x == x and")]),
 ("Y10", "config", L, [("id(read(entry.play)), id(read(entry.revive))", "id(tonumber(read(entry.play))), id(tonumber(read(entry.revive)))")]),
 ("Y11", "config", L, [("uses[f.ids.play] == 1", "uses[f.ids.play] >= 1"), ("uses[f.ids.revive] == 1", "uses[f.ids.revive] >= 1")]),
 ("Y12", "config", L, [("\treturn \"closed\"\nend", "\treturn \"test\"\nend")]),
 ("Y13", "config", L, [("\tif mode == \"test\" then\n\t\treturn entry.testStore", "\tif mode ~= \"live\" then\n\t\treturn entry.testStore")]),
 ("Y14", "paidplay", L, [("whole(raw.revives) or whole(raw.continues) or 0", "whole(raw.revives) or 0")]),
 ("Y15", "paidplay", L, [("\treturn add(r, kind)\nend\n\n-- One held", "\treturn (PaidPlay.grant(r, kind, \"refund\"))\nend\n\n-- One held")]),
 ("Y16", "paidplay", L, [("if start == \"buy\" and not passed then", "if start ~= \"free\" and start ~= \"credit\" and not passed then")]),
 ("Y17", "paidplay", L, [("if start == \"buy\" and not passed then", "if start == \"buy\" then")]),
 ("Y18", "paidplay", L, [("\tif whole(now) == nil then\n\t\treturn false\n\tend\n", "")]),
 ("Y19", "config", L, [("confirm = table.freeze({ \"Return\", \"KeypadEnter\", \"ButtonA\" })", "confirm = table.freeze({ \"Return\", \"KeypadEnter\", \"ButtonA\", \"Space\" })")]),
 ("Y20", "config", L, [("\t\t`{prices.struck} {prices.price} {prices.sale}`,\n\t\tPaidPlay.TEST_NOTE,\n", "\t\t`{prices.struck} {prices.price} {prices.sale}`,\n")]),
 ("Y21", "paidplay", L, [("\tif r.plays >= 1 then\n\t\tlocal n = copy(r)", "\tif r.plays >= 1 then\n\t\tlocal n = r")]),
 ("W1", "wallet", W, [("\tif done ~= nil then\n\t\treturn done.verdict, done.start\n\tend\n", "")]),
 ("W2", "wallet", W, [("\tif waiting ~= nil then\n\t\ttable.insert(waiting, coroutine.running())\n\t\treturn coroutine.yield()\n\tend\n", "")]),
 ("W3", "wallet", W, [("PaidPlay.arrive(start, passed) ::", "PaidPlay.arrive(start or \"buy\", passed) ::")]),
 ("W4", "wallet", W, [("local back, final, start = within(Wallet.WAIT_SECONDS, function(): (PaidPlay.Record?, any)", "local back, final, start = (function(f: any): any return true, f() end)(function(): (PaidPlay.Record?, any)")]),
 ("W5", "wallet", W, [("\tlocal passed = takePass(player, name)", "\tlocal passed = start == \"buy\" and takePass(player, name)")]),
 ("W6", "wallet", W, [("\t\tpassMap:RemoveAsync(key)\n", "")]),
 ("W7", "wallet", W, [("\tif not ok then\n\t\treturn true\n\tend\n\tif value == nil then", "\tif not ok then\n\t\treturn false\n\tend\n\tif value == nil then")]),
 ("W8", "wallet", W, [("\treturn `{name}/{userId}`", "\treturn tostring(userId)")]),
 ("W9", "wallet", W, [("\t\t\tfinal, decision = n or r, d", "\t\t\tif final == nil then\n\t\t\t\tfinal, decision = n or r, d\n\t\t\tend")]),
 ("W10", "wallet", W, [("\t\ttallies[key] = (tallies[key] or 0) + 1\n", "")]),
 ("W11", "wallet", W, [("\ttallies[keyOf(name, userId)] = 0\n", "")]),
 ("W12", "wallet", W, [("\tslots[player] = nil\nend)", "\tslots[player] = nil\n\ttable.clear(tallies)\nend)")]),
 ("W13", "wallet", W, [("\tif slot.using then\n\t\treturn nil\n\tend\n", "")]),
 ("W14", "wallet", W, [("\tif seen ~= nil and seen.revives < 1 then\n\t\treturn false\n\tend\n", "")]),
 ("W15", "wallet", W, [("\tif slot.usedAt ~= nil and os.clock() - slot.usedAt < Wallet.USE_SECONDS then\n\t\treturn nil\n\tend\n", "")]),
 ("W16", "wallet", W, [("\tif slot.reading then\n\t\treturn nil, \"busy\"\n\tend\n", "")]),
 ("W17", "wallet", W, [("\tif slot.seen ~= nil and slot.seenAt ~= nil and os.clock() - slot.seenAt < Wallet.READ_SECONDS then\n\t\treturn slot.seen\n\tend\n", "")]),
  ("W19", "wallet", W, [("local ok, opened = pcall(function(): any\n\t\t\treturn DataStoreService:GetDataStore(name)\n\t\tend)", "local ok, opened = true, DataStoreService:GetDataStore(name)")]),
 ("W20", "wallet", W, [("\tif not back or not ok then\n\t\treturn nil, \"down\"", "\tif not back or not ok then\n\t\tslot.reading = false\n\t\treturn nil, \"down\"")]),
 ("W21", "wallet", W, [("\tslot.arriving = {}\n", "\tslot.arriving = {}\n\tlocal jd = player:GetJoinData()\n\tif jd and type(jd.TeleportData) == \"table\" and jd.TeleportData.paid then\n\t\tslot.arriving = nil\n\t\treturn \"play\", \"credit\"\n\tend\n")]),
 ("W22", "wallet", W, [("\t\treturn update(\n\t\t\tPaidPlay.store(t.entry, t.mode),\n\t\t\tuserId,", "\t\treturn update(\n\t\t\tt.entry.store,\n\t\t\tuserId,")]),
  ("R1", "receipts", R, [("\tif not written then\n\t\treturn Enum.ProductPurchaseDecision.NotProcessedYet\n\tend", "")]),
 ("R2", "receipts", R, [("\tif fresh and Wallet.mode(product.name) ~= \"test\" then", "\tif Wallet.mode(product.name) ~= \"test\" then")]),
 ("R3", "receipts", R, [("\tif\n\t\tproduct == nil\n\t\tor type(purchaseId)", "\tif product == nil then\n\t\treturn Enum.ProductPurchaseDecision.PurchaseGranted\n\tend\n\tif\n\t\tfalse\n\t\tor type(purchaseId)")]),
 ("R4", "receipts", W, [("grantInto(t.entry.store, userId, kind, receiptId)", "grantInto(PaidPlay.store(t.entry, t.mode), userId, kind, receiptId)")]),
 ("R5", "receipts", R, [("\tif fresh and Wallet.mode(product.name) ~= \"test\" then", "\tif fresh then")]),
 ("R6", "receipts", R, [("\tlocal written, fresh = Wallet.grant(", "\tif present(info.PlayerId) == nil then\n\t\treturn Enum.ProductPurchaseDecision.NotProcessedYet\n\tend\n\tlocal written, fresh = Wallet.grant(")]),
 ("R7", "receipts", R, [("\tpending[player] = nil\n\tif what == \"cancel\" then", "\tif what == \"cancel\" then")]),
 ("R8", "receipts", R, [("\tif t.mode == \"live\" then\n\t\tMarketplaceService", "\tpending[player] = pending[player] or { name = name, kind = kind }\n\tif t.mode == \"live\" then\n\t\tMarketplaceService")]),
 ("R9", "receipts", R, [("\tif t.mode == \"test\" and pending[player] == nil then", "\tif t.mode ~= \"live\" and pending[player] == nil then")]),
 ("R10", "receipts", R, [("\tif t.mode == \"test\" and pending[player] == nil then", "\tif t.mode == \"test\" then")]),
 ("R11", "receipts", R, [("\tlocal p = pending[player]\n", "\tlocal p = pending[player]\n\tif p == nil then\n\t\tfor _, other in pending do\n\t\t\tp = other\n\t\tend\n\tend\n")]),
 ("R12", "receipts", R, [("pending[player]", "pending[player.UserId]", "all"), ("\tPlayers.PlayerRemoving:Connect(function(player: any)\n\t\tpending[player.UserId] = nil\n\tend)\n", "")]),
 ("R13", "receipts", R, [("\tclosed(player, p.name, p.kind, written)\n\tif written then\n\t\tgranted(player, p.name, p.kind)\n\tend", "\tif written then\n\t\tgranted(player, p.name, p.kind)\n\tend\n\tclosed(player, p.name, p.kind, written)")]),
 ("R14", "receipts", R, [("\t\t\tclosed(player, product.name, product.kind, bought == true)\n", "")]),
 ("R16", "receipts", R, [("\tif started then\n\t\treturn false\n\tend\n", "")]),
 ("R17", "receipts", R, [("\tlocal fn = on.granted\n\tif fn ~= nil and player.Parent ~= nil then", "\tlocal fn = on.granted\n\tif fn ~= nil then")]),
 ("R18", "receipts", W, [("grantInto(t.entry.testStore, player.UserId, kind, receiptId)", "grantInto(t.entry.store, player.UserId, kind, receiptId)")]),
 ("R19", "receipts", W, [("\"test:\" .. HttpService:GenerateGUID(false)", "\"test:1\"")]),
 ("R20", "receipts", R, [("\t\tor purchaseId == \"\"\n", "")]),
 ("R21", "receipts", R, [("\t\tor type(info.PlayerId) ~= \"number\"\n", "")]),
 ("R22", "receipts", R, [("\tclosed(player, p.name, p.kind, written)", "\tclosed(player, p.name, p.kind, true)")]),
 ("C1", "client", C, [("if state == Enum.UserInputState.Begin then", "if state == Enum.UserInputState.End then")]),
 ("C2", "client", C, [("\t\t\tContextActionService:UnbindAction(TestPurchase.ACTION)\n", "")]),
 ("C3", "client", C, [("TestPurchase.PRIORITY = 3000", "TestPurchase.PRIORITY = 2000")]),
 ("C5", "client", C, [("button(frame, TestPurchase.BUY, 0.05, \"confirm\")", "button(frame, TestPurchase.BUY, 0.05, \"cancel\")")]),
 ("C6", "client", C, [("\t\tclose()\n\t\tremote:FireServer(what)", "\t\tremote:FireServer(what)")]),
 ("C7", "client", C, [("\t\t\tif type(line) == \"string\" then\n\t\t\t\ttable.insert(text, line)\n\t\t\tend", "\t\t\ttable.insert(text, tostring(line))")]),
 ("C8", "client", C, [("\t\tscreen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets\n", "")]),
 ("C9", "client", C, [("\tif started then\n\t\treturn\n\tend\n", "")]),
]

def run(spec):
    out = subprocess.run([os.path.join(PREP, "zn"), "run", "--time", "120", "--", "lune", "run", "tests/run", "--",
                          f".cache/acc/{spec}.spec.luau"], cwd=HOME, capture_output=True, text=True).stdout
    return out

os.makedirs(os.path.join(HOME, ".cache/acc"), exist_ok=True)
for f in os.listdir(ACC):
    if f.endswith(".spec.luau"):
        with open(os.path.join(ACC, f)) as src, open(os.path.join(HOME, ".cache/acc", f), "w") as dst:
            dst.write(src.read())

only = set(sys.argv[3:])
results = []
for mid, spec, path, edits in M:
    if only and mid not in only:
        continue
    full = os.path.join(HOME, path)
    original = open(full).read()
    text = original
    ok = True
    for e in edits:
        old, new = e[0], e[1]
        n = text.count(old)
        if n == 0 or (n > 1 and len(e) < 3):
            ok = False
            results.append((mid, spec, f"bad mutant: {n} matches of {old[:50]!r}"))
            break
        text = text.replace(old, new) if len(e) >= 3 else text.replace(old, new, 1)
    if not ok:
        continue
    try:
        open(full, "w").write(text)
        out = run(spec)
    finally:
        open(full, "w").write(original)
    fails = re.findall(r"^FAIL [^\n]* :: ([^\n]*)\n\s+([^\n]*)", out, re.M)
    if not fails and re.search(r"\d+ passed, 0 failed", out):
        verdict = "SURVIVED"
    elif not fails:
        verdict = "NO RUN: " + " ".join(out.strip().splitlines()[-2:])[:160]
    elif any("expected" in msg for _, msg in fails):
        case = next(c for c, msg in fails if "expected" in msg)
        verdict = f"killed: {case}"
    else:
        verdict = f"ERROR: {fails[0][1][:120]}"
    results.append((mid, spec, verdict))
for r in results:
    print(" | ".join(r))
