#!/usr/bin/env python3
# c0202's mutation check (prep only): applies each mutant to a throwaway clone of the prototype, runs its row's spec,
# and records whether the named case fails on an assertion (killed), passes (SURVIVED), or the spec does not load
# (NO RUN). It never writes the tree it is given: it refuses any root that is not a .worktree/proto-* checkout, and
# refuses to run when a base patch the prototype was built from has moved (design review 001 F5, F10).
# Run: ./zn run --time 1800 -- python3 -I <this file> <prototype root> [mutant ids...]
import hashlib
import os
import subprocess
import sys
import tempfile

PROTO = os.path.realpath(sys.argv[1])
if "/.worktree/proto-" not in PROTO + "/":
    sys.exit(f"refused: {PROTO} is not a .worktree/proto-* checkout")

# the patches the prototype's base was built from (E1), as committed in it; a moved one means a re-prep
BASES = {
    "pickman/.tracker/issues/done/f0145/experiments/deps.patch": "78e94ea9bee17366ce97afb1ccd7362edbe89a91c12011c1a5da8f885c664cff",
    "pickman/.tracker/issues/done/f0145/experiments/prototype.patch": "a46e2258db2c32496bc88149387cb129ceb7517ac74d00f71aff870f98dac90b",
    "pickman/.tracker/issues/done/f0186/experiments/prototype.patch": "f588be80b42dbb88043383be1819b4ca676461c4c3434c204295c25672a3f791",
    "arcade/.tracker/issues/f0201/experiments/prototype.patch": "f99bd914ff800cfc3403ab4000109951694ebebaa2b6d8381d7b8879d6afce7b",
    "z-nile/.tracker/issues/active/c0156/experiments/prototype.patch": "ed053dfdd1b177bd0cce96f90f4b61ac5b11392a1b36b63e65e6a854536e2f6c",
    "pickman/.tracker/issues/done/c0380/experiments/prototype.patch": "78cd528c26754809a3c224b032cb5fc3a08ebec60ad64496a8fbf1a392cb5c80",
    # f0395 has no prototype yet: these are the three library files after its emulation (experiments/f0395-emulation.patch)
    "arcade/src/shared/Logic/PaidPlay/init.luau": "fc9d6e00314e28f4a3e1533a6b351b2086b20f0d49a0e7cadd4ecf0056a16007",
    "arcade/src/shared/Prices.luau": "8da7dc8c0c3f9ea7c7f0c11443045da26338077f4d743f737c512979aac1e4d7",
    "arcade/src/shared/TestPurchase.luau": "51221e07a65ed1b9f05755bfd20047db4330927937c51a0ae53262ff0bb9c65e",
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
    ("M2", CONT, 'if (verdict :: string) == "play" then', "if true then", "arrival", "no pass the run is refused"),
    ("M3", CONT, 'if (verdict :: string) == "play" then', 'if (verdict :: string) == "play" and start ~= nil then', "arrival", "whose claim fails plays"),
    ("M4", CONT, "\t\tif player.Parent == nil then\n\t\t\treturn -- left during the claim", "\t\tif false then\n\t\t\treturn -- left during the claim", "arrival", "leaves during the claim"),
    ("M5", CONT, "\t\t\tif start ~= nil then\n\t\t\t\ttell(player)", "\t\t\tif true then\n\t\t\t\ttell(player)", "arrival", "whose claim fails plays"),
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
    ("M22", CONT, "\t\tif useOne(player) == \"unknown\" then", "\t\tif useOne(player) == \"never\" then", "offer", "used once the library's span allows it"),
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
    ("M49", "arcade/src/shared/Logic/PaidPlay/init.luau", "then `<s>{prices.struck}</s> {prices.price} {prices.sale}`", "then `{prices.struck} {prices.price} {prices.sale}`", "lobby", "a play's test screen strikes the list price"),
    ("M50", "arcade/src/shared/Logic/PaidPlay/init.luau", "else prices.revive or prices.price,", "else `<s>{prices.struck}</s> {prices.price} {prices.sale}`,", "offer", "a revive's test screen strikes nothing"),
    ("M51", "arcade/src/shared/Logic/PaidPlay/init.luau", "else prices.revive or prices.price,", "else `{prices.struck} {prices.price} {prices.sale}`,", "offer", "a revive's test screen strikes nothing"),
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
