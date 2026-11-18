#!/usr/bin/env python3
# c0202's mutation check (prep only): applies each mutant to a throwaway clone of the prototype, runs its row's spec,
# and records whether the named case fails on an assertion (killed), passes (SURVIVED), or the spec does not load
# (NO RUN). It never writes the tree it is given: it refuses any root that is not a .worktree/proto-* checkout, and
# refuses to run when the library it was built on has moved or the prototype is not on the pinned main (design
# review 001 F5, F10; re-prep E6).
# Run: ./zn run --time 1800 -- python3 -I <this file> <prototype root> [mutant ids...]
import hashlib
import os
import subprocess
import sys
import tempfile

PROTO = os.path.realpath(sys.argv[1])
if "/.worktree/proto-" not in PROTO + "/":
    sys.exit(f"refused: {PROTO} is not a .worktree/proto-* checkout")

# Every dependency is on main now (re-prep, 2026-11-17): the prototype is cut from origin/main 1c840bc5b, and the
# library files this issue calls are pinned as they landed (f0201, R0110's review fixes, f0395); a moved one, or a
# prototype not on that base, means a re-prep (E6).
BASE = "1c840bc5b06ff65e22c5bbf3989e5f0a5c0556d2"
if subprocess.run(["git", "-C", PROTO, "merge-base", "--is-ancestor", BASE, "HEAD"]).returncode != 0:
    sys.exit(f"refused: {PROTO} is not cut from {BASE}")
BASES = {
    "arcade/src/server/Wallet.luau": "83b7234931061c97206975a2482eab249d6a6b68deb5ed682a7349f6077a1057",
    "arcade/src/server/Receipts.luau": "4c55adb157a51d19c2705d0436edfbd00115b342550bdedb08fc771393ba1e4c",
    "arcade/src/server/Catalog.luau": "d3dd1e9855f318153a7d4d090c02b814833d5cdaf60c381c2576b6550e578f81",
    "arcade/src/shared/Logic/PaidPlay/init.luau": "9fcad5063ea2120b9dbbe2b754bd2b0a53b3722b1af345f1c54b05bed6ae09e7",
    "arcade/src/shared/Prices.luau": "d9e822c9b4f400e2f9a6ffe8d6cee587aed651bdd22cfdb0f7c4fbff45ea1a98",
    "arcade/src/shared/TestPurchase.luau": "da3b7dc842895c7d54c9ba1724c448f8b63023da0338a08111db61939416d97b",
}
for rel, want in BASES.items():
    got = hashlib.sha256(open(os.path.join(PROTO, rel), "rb").read()).hexdigest()
    if got != want:
        sys.exit(f"refused: {rel} moved ({got}); rebuild the prototype (E1) and rerun")

ROOT = os.path.join(tempfile.mkdtemp(prefix="c0202-mut-"), "repo")
subprocess.run(["git", "clone", "-q", "--no-hardlinks", PROTO, ROOT], check=True)
HOME = os.path.join(ROOT, "pickman")
A = ".tracker/issues/c0202/acceptance/"
CONT = "pickman/src/server/Continues.luau"
PAID = "pickman/src/lobby/server/Paid.luau"
OFFER = "pickman/src/client/OfferView.luau"
PAY = "pickman/src/lobby/client/PayView.luau"
LOBBY = "pickman/src/shared/Logic/Lobby/init.luau"

# id, file, old text, new text, spec, a substring of the case that must fail
M = [
    ("M1", CONT, 'Continues.TITLE = "pickman"', 'Continues.TITLE = "snake"', "arrival", "took the free game on the portal"),
    ("M2", CONT, 'if (verdict :: string) == "play" or inStudio() then', "if true then", "arrival", "no pass the run is refused"),
    ("M3", CONT, 'if (verdict :: string) == "play" or inStudio() then', 'if ((verdict :: string) == "play" and start ~= nil) or inStudio() then', "arrival", "whose claim fails plays"),
    ("M4", CONT, "\t\tif player.Parent == nil then\n\t\t\treturn -- left during the claim", "\t\tif false then\n\t\t\treturn -- left during the claim", "arrival", "leaves during the claim"),
    ("M5", CONT, "\t\t\t\ttellMode(player) -- the claim failed", "\t\t\t\ttell(player) -- the claim failed", "arrival", "whose claim fails plays"),
    ("M52", CONT, "\t\t\t\ttellMode(player) -- the claim failed", "\t\t\t\t-- the claim failed", "arrival", "whose claim fails plays"),
    ("M6", CONT, "PaidPlay.status(record, os.time()))", "record)", "arrival", "tells the player what they hold"),
    ("M7", CONT, "\t\ttask.delay(Continues.BACK_SECONDS, kick, player)", "", "arrival", "no pass the run is refused"),
    ("M8", CONT, "\t\tif not ok then\n\t\t\tkick(player)", "\t\tif not ok then\n\t\t\t--", "arrival", "teleport errors"),
    ("M9", CONT, "if sentBack[player] and player.Parent ~= nil then", "if player.Parent ~= nil then", "arrival", "teleport errors"),
    ("M10", CONT, "\t\tif charged[player] then\n\t\t\treturn\n\t\tend", "", "arrival", "bought on the portal"),
    ("M11", CONT, "local used = Wallet.useRevive(player, Continues.TITLE)", 'local used = Wallet.useRevive(player, "snake")', "offer", "a revive held is used at once"),
    ("M12", CONT, "\t\t\tSession.continue(s, id)\n\t\t\ttell(player)", "\t\t\ttell(player)", "offer", "a revive held is used at once"),
    ("M13", CONT, 'Receipts.ask(player, Continues.TITLE, "revive")', 'Receipts.ask(player, Continues.TITLE, "play")', "offer", "prompts Pickman's revive product"),
    ("M14", CONT, 'if Session.offering(s, id) and Receipts.ask(player, Continues.TITLE, "revive") then', 'if Session.offering(s, id) then\n\t\t\tReceipts.ask(player, Continues.TITLE, "revive")', "offer", "closed server sells no revive"),
    ("M15", CONT, "\t\t\t\tif bought then\n\t\t\t\t\tSession.awaitReceipt", "\t\t\t\tif false then\n\t\t\t\t\tSession.awaitReceipt", "offer", "closed bought, it waits"),
    ("M16", CONT, "\t\t\t\telse\n\t\t\t\t\trelease(player)\n\t\t\t\tend", "\t\t\t\tend", "offer", "closed without buying lets the countdown run"),
    ("M17", CONT, 'if name ~= Continues.TITLE or kind ~= "revive" then', "if false then", "offer", "closed without buying lets the countdown run"),
    ("M18", CONT, 'if name == Continues.TITLE and kind == "revive" then\n\t\t\t\theard(player)', "if true then\n\t\t\t\theard(player)", "offer", "a play bought during the offer"),
    ("M19", CONT, '\t\t\tWallet.refund(player, Continues.TITLE, "revive")', "", "offer", "a decline during a revive's write"),
    ("M20", CONT, "\t\t\tif flight then\n\t\t\t\tflight.declined = true\n\t\t\telse", "\t\t\tif false then\n\t\t\telse", "offer", "a decline during a revive's write"),
    ("M21", CONT, "\t\tif flying[player] then\n\t\t\treturn \"busy\"\n\t\tend", "", "offer", "a second ask while a revive's write"),
    ("M22", CONT, '\t\telseif result == "unknown" then', '\t\telseif result == "never" then', "offer", "used once the library's span allows it"),
    ("M23", CONT, "local here = player.Parent ~= nil and session(player) == s", "local here = session(player) == s", "offer", "leaves during a revive's write"),
    ("M24", CONT, "and not Session.holding(s, id) -- a screen is open", "-- a screen is open", "offer", "prompts Pickman's revive product"),
    ("M25", PAID, "if now.free or now.plays > 0 then", "if now.free then", "lobby", "a play held goes"),
    ("M26", PAID, 'Receipts.ask(player, Paid.TITLE, "play")', 'Receipts.ask(player, Paid.TITLE, "revive")', "lobby", "a play held goes"),
    ("M27", PAID, "\t\t\t\tgo(player) -- a bought game starts at once", "", "lobby", "a play bought in the lobby starts at once"),
    ("M28", PAID, 'if name ~= Paid.TITLE or kind ~= "play" then', "if false then", "lobby", "a revive bought for later is kept"),
    ("M29", PAID, "\t\t\tWallet.pass(player, Paid.TITLE)", "", "lobby", "a read that answers down"),
    ("M30", PAID, "\t\t\tWallet.pass(player, Paid.TITLE) -- the play place lets this one game go free (decided 2026-10-26)\n\t\t\treturn true", "\t\t\treturn false", "lobby", "a read that answers down"),
    ("M31", PAID, "\t\treturn false -- a read under way: this press is dropped", "\t\treturn true", "lobby", "a press while the player's read is under way"),
    ("M32", PAID, "\t\tlocal record = Wallet.read(player, Paid.TITLE)\n\t\tif record then\n\t\t\ttell(player, record)\n\t\tend\n\tend)", "\tend)", "lobby", "a player joining is told"),
    ("M33", PAID, 'Paid.TITLE = "pickman"', 'Paid.TITLE = "snake"', "lobby", "a play held goes"),
    ("M34", OFFER, 'type(said.revives) == "number" then said.revives', 'type(said.continues) == "number" then said.continues', "clients", "reads the revives held"),
    ("M35", OFFER, "\tyes.Activated:Connect(function()\n\t\tif up and not TestPurchase.isOpen() then", "\tyes.Activated:Connect(function()\n\t\tif up then", "clients", "do nothing while the library's screen is open"),
    ("M36", OFFER, "\tTestPurchase.start()\n", "", "clients", "OfferView boots the library's test screen"),
    ("M37", PAY, "\tTestPurchase.start()\n", "", "clients", "PayView draws the line"),
    ("M38", PAY, "Lobby.payLine(status, mode, os.time(), Prices)", 'Lobby.payLine(status, mode, os.time(), { struck = "", price = "1 ROBUX", sale = "" })', "clients", "PayView draws the line"),
    ("M39", LOBBY, "return `<s>{prices.struck}</s> {prices.price} {prices.sale}`", 'return "<s>5 R$</s> 1 R$ SALE"', "clients", "the price of a play is the library's Prices"),
    ("M40", LOBBY, "local Lobby = {}\n", 'local Lobby = {}\nLobby.PRICE = table.freeze({ struck = "5 R$", price = "1 R$", sale = "SALE" })\n', "clients", "Lobby keeps no price table"),
    ("M41", "pickman/lobby.project.json", '    "ServerStorage": {\n      "Arcade": { "$path": "../arcade/src/server" }\n    },\n', "", "place", "both places map the library"),
    ("M42", CONT, "local Continues = {}\n", "local Continues = {}\ngame:GetService(\"MarketplaceService\").ProcessReceipt = nil\n", "place", "pickman keeps no copy"),
    ("M43", "pickman/.tracker/architecture.md", "Lobby -> Travel\n", "Lobby -> Pay\nLobby -> Travel\n", "place", "architecture.md no longer declares Pay"),
    ("M44", "arcade/src/shared/Logic/PaidPlay/init.luau", "continues = r.revives", "revives = r.revives", "records", "every record the new build writes"),
    ("M46", PAID, "\tif bought[player] then\n\t\tbought[player] = nil -- the play just granted goes, whatever a read under way would say\n\t\treturn true\n\tend\n", "", "lobby", "granted while the read on joining is under way"),
    ("M47", PAID, "\ttell(player, record)\n\tlocal now = PaidPlay.status", "\tlocal now = PaidPlay.status", "lobby", "a press after the library's READ_SECONDS"),
    ("M48", "pickman/.tracker/architecture.md", "Paid play is the arcade library's", "Paid play is pickman's", "place", "architecture.md no longer declares Pay"),
    ("M49", "arcade/src/shared/Logic/PaidPlay/init.luau", "then `<s>{plain(prices.struck)}</s> {plain(prices.price)} {plain(prices.sale)}`", "then `{plain(prices.struck)} {plain(prices.price)} {plain(prices.sale)}`", "lobby", "a play's test screen strikes the list price"),
    ("M50", "arcade/src/shared/Logic/PaidPlay/init.luau", "else plain(prices.revive)", "else `<s>{plain(prices.struck)}</s> {plain(prices.price)} {plain(prices.sale)}`", "offer", "a revive's test screen strikes nothing"),
    ("M51", "arcade/src/shared/Logic/PaidPlay/init.luau", "else plain(prices.revive)", "else `{plain(prices.struck)} {plain(prices.price)} {plain(prices.sale)}`", "offer", "a revive's test screen strikes nothing"),
    # re-prep (2026-11-17): main's landed behaviour kept through the switch (status.spec)
    ("M53", CONT, "\t\t\tstatus:FireClient(player, Wallet.mode(Continues.TITLE), nil)", '\t\t\tstatus:FireClient(player, "live", nil)', "status", "a closed arrival whose claim fails tells closed"),
    ("M54", CONT, "\t\ttell(player)\n\t\tlocal result = useOne(player)", "\t\tlocal result = useOne(player)", "status", "receipt heard outside the offer tells"),
    ("M55", CONT, '\t\tif result == "empty" then\n\t\t\ttell(player) -- none held, told after the screen opened', '\t\tif false then\n\t\t\ttell(player) -- none held, told after the screen opened', "status", "write that finds none held tells none held"),
    ("M56", CONT, "\t\t\ttell(player) -- the revive given back, told last\n", "", "status", "given back after its write tells"),
    ("M57", CONT, '\t\t\tif result == "none" or result == "empty" or result == "unknown" then\n\t\t\t\trelease(player)', "\t\t\tif false then\n\t\t\t\trelease(player)", "status", "granted confirm whose revive write fails"),
    ("M58", CONT, '\t\t\tif result == "none" or result == "empty" or result == "unknown" then\n\t\t\t\trelease(player)', '\t\t\tif result == "none" or result == "empty" then\n\t\t\t\trelease(player)', "status", "granted confirm whose revive write fails"),
    ("M64", CONT, "\t\tlocal verdict, start = Wallet.arrive(player, Continues.TITLE)", "\t\tif inStudio() then\n\t\t\tSession.allowOffer(s, tostring(player.UserId))\n\t\t\ttellMode(player)\n\t\t\treturn\n\t\tend\n\t\tlocal verdict, start = Wallet.arrive(player, Continues.TITLE)", "status", "in Studio an arrival still claims"),
    ("M65", CONT, "\t\tif flight.held and here then\n\t\t\tSession.hold(s, id, false)\n\t\tend\n\t\tif flight.declined then\n\t\t\tSession.decline(s, id)\n\t\tend\n\t\tif used == true then\n\t\t\ttell(player) -- the revive given back, told last\n", "\t\tif used == true then\n\t\t\ttell(player)\n\t\tend\n\t\tif flight.held and here then\n\t\t\tSession.hold(s, id, false)\n\t\tend\n\t\tif flight.declined then\n\t\t\tSession.decline(s, id)\n\t\tend\n\t\tif used == true then\n", "status", "whose give-back fails ends the run"),
    ("M59", CONT, 'if Wallet.mode(Continues.TITLE) == "test" then\n\t\t\tif result', "if true then\n\t\t\tif result", "offer", "used once the library's span allows it"),
    ("M60", CONT, 'if (verdict :: string) == "play" or inStudio() then', 'if (verdict :: string) == "play" then', "status", "in Studio an arrival with nothing to pay plays"),
    ("M61", CONT, "\treturn ok and studio == true", "\treturn ok", "status", "outside Studio an arrival"),
    ("M62", CONT, "\treturn ok and studio == true", "\treturn studio ~= false", "status", "or one that errors"),
    ("M63", CONT, "\t\t\t\telse\n\t\t\t\t\trelease(player)\n\t\t\t\tend", "\t\t\t\tend", "status", "confirm whose grant write fails releases"),
    ("M45", OFFER, "\t\tif up and not TestPurchase.isOpen() then\n\t\t\tsend(\"decline\")", "\t\tif up then\n\t\t\tsend(\"decline\")", "clients", "do nothing while the library's screen is open"),
]


def run(spec):
    p = subprocess.run(
        ["lune", "run", "tests/run", "--", A + spec + ".spec.luau"],
        cwd=HOME,
        capture_output=True,
        text=True,
        timeout=600,
    )
    return p.stdout + p.stderr


only = set(sys.argv[2:])
for mid, rel, old, new, spec, case in M:
    if only and mid not in only:
        continue
    path = os.path.join(ROOT, rel)
    text = open(path).read()
    if text.count(old) != 1:
        print(f"{mid} NOT APPLIED: {text.count(old)} matches in {rel}")
        continue
    open(path, "w").write(text.replace(old, new))
    try:
        out = run(spec)
    finally:
        open(path, "w").write(text)  # the clone is thrown away; this keeps each mutant alone
    if "could not load" in out:
        verdict = "NO RUN (load error)"
    elif any(l.startswith("FAIL ") and "::" in l and case in l for l in out.splitlines()):
        verdict = "killed"
    else:
        verdict = "SURVIVED"
    print(f"{mid} {spec} :: {case}: {verdict}", flush=True)
