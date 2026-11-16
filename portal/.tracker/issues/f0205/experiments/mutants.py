# f0205 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, copies this item's folder in, applies f0201's prototype (arcade's PaidPlay, Prices, Wallet,
# Catalog: arcade/.tracker/issues/f0201/experiments/prototype.patch), f0199-standin.patch (arcade's Travel and Places
# as f0199's Design states them) and prototype.patch (this issue's portal code), runs the intended state, then applies
# each mutant (and each correct variant) to that clone, runs the row's spec files from the clone's portal/, restores
# the file, and deletes the clone at the end.
# A mutant is killed when its spec run reports a FAIL whose message is an assertion ("expected ..."), not a syntax,
# type or require error. A correct variant (CV) must stay green.
# Usage, from the repository root: ./zn run --time 1800 -- python3 -I portal/.tracker/issues/f0205/experiments/mutants.py [id prefixes...]
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0205-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "portal")
A = ".tracker/issues/f0205/acceptance/"
CAR = [A + "carousel.spec.luau"]
CARD = [A + "card.spec.luau"]
GAMES = [A + "games.spec.luau"]
SRV = [A + "server.spec.luau"]
CLI = [A + "client.spec.luau"]
PLC = [A + "place.spec.luau"]
META = ["tests/meta/architecture.spec.luau"]
ALL = CAR + CARD + GAMES + SRV + CLI + PLC + META
CA = "src/shared/Logic/Carousel/init.luau"
CD = "src/shared/Logic/Card/init.luau"
GA = "src/shared/Games.luau"
SV = "src/server/Cards.luau"
CV_ = "src/client/CarouselView.luau"
SMAIN = "src/server/Main.server.luau"
CMAIN = "src/client/Main.client.luau"
PJ = "default.project.json"
AM = ".tracker/architecture.md"

M = [
    # Carousel
    ("C1 no wrap", CA, "index = (c.index - 1 + by) % c.count + 1", "index = math.clamp(c.index + by, 1, c.count)", CAR),
    ("C2 a new row starts at the last card", CA, "return { count = count, index = 1, wheelAt = nil }", "return { count = count, index = count, wheelAt = nil }", CAR),
    ("C3 a fractional step moves", CA, "\tif whole(by) then\n\t\tindex", "\tif finite(by) then\n\t\tindex", CAR),
    ("C4 a step changes the row it is given", CA, "\treturn { count = c.count, index = index, wheelAt = c.wheelAt }", "\tc.index = index\n\treturn c", CAR),
    ("C5 the left shoulder goes forward", CA, "\tButtonL1 = \"prev\",", "\tButtonL1 = \"next\",", CAR),
    ("C6 Space plays too", CA, "\tButtonA = \"play\",", "\tButtonA = \"play\",\n\tSpace = \"play\",", CAR),
    ("C7 bound at the test screen's priority", CA, "Carousel.PRIORITY = 2000", "Carousel.PRIORITY = 3000", CAR),
    ("C8 the wheel the wrong way", CA, "return after, if delta > 0 then \"prev\" else \"next\"", "return after, if delta > 0 then \"next\" else \"prev\"", CAR),
    ("C9 the rest counted from the last step", CA, "local after: Carousel = { count = c.count, index = c.index, wheelAt = now }",
     "local after: Carousel = {\n\t\tcount = c.count,\n\t\tindex = c.index,\n\t\twheelAt = if rested and finite(delta) and delta ~= 0 then now else c.wheelAt,\n\t}", CAR),
    ("C10 a rest of exactly WHEEL_GAP is not enough", CA, "now - c.wheelAt >= Carousel.WHEEL_GAP", "now - c.wheelAt > Carousel.WHEEL_GAP", CAR),
    ("C11 no rest needed", CA, "\tif not rested then\n\t\treturn after, nil\n\tend", "\tif false then\n\t\treturn after, nil\n\tend", CAR),
    ("C12 a still wheel event is no event", CA, "\tif not finite(delta) or delta == 0 then\n\t\treturn after, nil", "\tif not finite(delta) or delta == 0 then\n\t\treturn c, nil", CAR),
    ("C13 a time that is not a number counts", CA, "\tif not finite(now) then\n\t\treturn c, nil\n\tend", "\tif false then\n\t\treturn c, nil\n\tend", CAR),
    ("C14 a clock that went back waits", CA, " or now < c.wheelAt", "", CAR),
    ("C15 swipes the other way", CA, "\tif direction == \"Left\" then\n\t\treturn \"next\"\n\telseif direction == \"Right\" then\n\t\treturn \"prev\"",
     "\tif direction == \"Left\" then\n\t\treturn \"prev\"\n\telseif direction == \"Right\" then\n\t\treturn \"next\"", CAR),
    ("C16 offsets the long way", CA, "\tif d > c.count / 2 then\n\t\td -= c.count\n\tend", "", CAR),
    ("C17 the opposite card counts to the left", CA, "\tif d > c.count / 2 then", "\tif d >= c.count / 2 then", CAR),
    ("C18 the front card as tall as the screen", CA, "local h = height * Carousel.HEIGHT", "local h = height", CAR),
    ("C19 no width cap", CA, "local w = math.min(h * Carousel.ASPECT, width * Carousel.MAX_WIDTH)", "local w = h * Carousel.ASPECT", CAR),
    ("C20 neighbours overlap the front card", CA, "(w / 2 + width * Carousel.GAP + sw / 2)", "(w / 2 + sw / 2 - width * Carousel.GAP)", CAR),
    ("C21 neighbours not dimmed", CA, "shown = shown, dim = Carousel.SIDE_DIM", "shown = shown, dim = 0", CAR),
    ("C22 far cards shown", CA, "local shown = (offset == 1 or offset == -1) and x < width", "local shown = x < width", CAR),
    ("C23 neighbours full size", CA, "local sw, sh = w * Carousel.SIDE_SCALE, h * Carousel.SIDE_SCALE", "local sw, sh = w, h", CAR),
    # Card
    ("K1 the sale's words written in", CD, "text = `{prices.price} {prices.sale}`", "text = \"1 R$ SALE\"", CARD),
    ("K2 the price not struck", CD, "struck = Card.strike(prices.struck)", "struck = prices.struck", CARD),
    ("K3 markup not escaped", CD, "\treturn (string.gsub(string.gsub(string.gsub(text, \"&\", \"&amp;\"), \"<\", \"&lt;\"), \">\", \"&gt;\"))", "\treturn text", CARD),
    ("K4 a free start shown on an unpublished card", CD, "\telseif not state.published then", "\telseif not state.published and state.free ~= true then", CARD),
    ("K5 an unread free state shows the sale", CD, "\telseif state.free == false then", "\telseif state.free ~= true then", CARD),
    ("K6 an unknown state shows coming soon", CD, "\tif state == nil then\n\t\treturn { kind = \"none\", struck = \"\", text = \"\" }", "\tif state == nil then\n\t\treturn { kind = \"soon\", struck = \"\", text = Card.SOON }", CARD),
    ("K7 published by the entry's name", CD, "return ids[entry.place] ~= nil", "return ids[entry.name] ~= nil", CARD),
    ("K8 a free state sent for an unpublished place", CD, "free = if p then known[e.name] else nil", "free = known[e.name]", CARD),
    ("K9 only published titles sent", CD, "\t\tout[e.name] = { published = p, free = if p then known[e.name] else nil }",
     "\t\tif p then\n\t\t\tout[e.name] = { published = p, free = known[e.name] }\n\t\tend", CARD),
    ("K10 any published value read", CD, "\t\t\tand type(s.published) == \"boolean\"\n", "", CARD),
    ("K11 any free value read", CD, "\t\t\tand (s.free == nil or type(s.free) == \"boolean\")\n", "", CARD),
    ("K12 a free state kept for an unpublished place", CD, "out[e.name] = { published = s.published, free = if s.published then s.free else nil }", "out[e.name] = { published = s.published, free = s.free }", CARD),
    ("K13 a message that is not a table read as one", CD, "\tif type(raw) ~= \"table\" then\n\t\treturn out\n\tend", "\tif raw == nil then\n\t\treturn out\n\tend", CARD),
    ("K14 the angle never wraps", CD, "return (seconds * Card.SPIN) % (2 * math.pi)", "return seconds * Card.SPIN", CARD),
    ("K15 a time that is not a number turns the preview", CD, "\tif seconds ~= seconds or seconds == math.huge or seconds == -math.huge then\n\t\treturn 0\n\tend", "", CARD),
    ("K16 the buttons overlap the badge", CD, "Buttons = table.freeze({ top = 0.56,", "Buttons = table.freeze({ top = 0.5,", CARD),
    ("K17 the camera too close", CD, "distance = 22", "distance = 12", CARD),
    ("K18 no room kept for the buttons", CD, "Card.ORDER = table.freeze({ \"Title\", \"Tagline\", \"Preview\", \"Badge\", \"Buttons\", \"Boards\" })",
     "Card.ORDER = table.freeze({ \"Title\", \"Tagline\", \"Preview\", \"Badge\", \"Boards\" })", CARD),
    # Games
    ("G1 a name the Catalog does not know", GA, "\t\tname = \"pickman\",", "\t\tname = \"pacman\",", GAMES),
    ("G2 a place Places does not know", GA, "\t\tplace = \"Invaders\",", "\t\tplace = \"Invader\",", GAMES),
    ("G3 a title not the Catalog's", GA, "\t\ttitle = \"SNAKE\",", "\t\ttitle = \"Snake\",", GAMES),
    ("G4 a part out of frame", GA, "part(\"Ball\", { 1.2, 1.2, 1.2 }, { 3, 0, 0 }, WHITE)", "part(\"Ball\", { 1.2, 1.2, 1.2 }, { 3.8, 0, 0 }, WHITE)", GAMES),
    ("G5 entries not frozen", GA, "\ttable.freeze(e)\n", "", GAMES),
    ("G6 two games, one tagline", GA, "tagline = \"Split the rocks. Dodge the saucers. Stay alive.\"", "tagline = \"Eat, grow and outlast the walls.\"", GAMES),
    ("G7 a colour past 255", GA, "local YELLOW, WHITE, RED, PINK = { 255, 221, 0 }", "local YELLOW, WHITE, RED, PINK = { 256, 221, 0 }", GAMES),
    ("G8 the games in another order", GA, [
        ("\t\tname = \"snake\",\n\t\tplace = \"Snake\",\n\t\ttitle = \"SNAKE\",", "\t\tname = \"@@\",\n\t\tplace = \"@P\",\n\t\ttitle = \"@T\","),
        ("\t\tname = \"invaders\",\n\t\tplace = \"Invaders\",\n\t\ttitle = \"INVADERS\",", "\t\tname = \"snake\",\n\t\tplace = \"Snake\",\n\t\ttitle = \"SNAKE\","),
        ("\t\tname = \"@@\",\n\t\tplace = \"@P\",\n\t\ttitle = \"@T\",", "\t\tname = \"invaders\",\n\t\tplace = \"Invaders\",\n\t\ttitle = \"INVADERS\","),
    ], None, GAMES),
    # Server
    ("S1 the attributes read on every ask", SV, "\t\tlocal slot = slots[player]\n",
     "\t\tids = Places.read(function(attribute: string): any\n\t\t\treturn ServerScriptService:GetAttribute(attribute)\n\t\tend)\n\t\tfor _, entry in Games.LIST do\n\t\t\tpublished[entry.name] = Card.published(entry, ids :: any)\n\t\tend\n\t\tlocal slot = slots[player]\n", SRV),
    ("S2 its own id check, not Places", SV, "published[entry.name] = Card.published(entry, ids :: any)",
     "published[entry.name] = (tonumber(ServerScriptService:GetAttribute(entry.place .. \"PlaceId\")) or 0) > 0", SRV),
    ("S3 unpublished games read too", SV, "if published[name] and not mine.reading[name] then", "if not mine.reading[name] then", SRV),
    ("S4 a read under way read again", SV, "if published[name] and not mine.reading[name] then", "if published[name] then", SRV),
    ("S5 the status at os.clock()", SV, "PaidPlay.status(record, os.time())", "PaidPlay.status(record, os.clock())", SRV),
    ("S6 a failed read leaves the state unknown", SV, "\t\t\t\t\tmine.free[name] = record ~= nil and PaidPlay.status(record, os.time()).free == true",
     "\t\t\t\t\tif record ~= nil then\n\t\t\t\t\t\tmine.free[name] = PaidPlay.status(record, os.time()).free == true\n\t\t\t\t\tend", SRV),
    ("S7 no answer until a read comes back", SV, "\t\tlocal mine: Slot = slot\n\t\tsend(player, mine)\n", "\t\tlocal mine: Slot = slot\n", SRV),
    ("S8 answers sent to everyone", SV, "remote:FireClient(player, Card.states(Games.LIST, published, slot.free))", "remote:FireAllClients(Card.states(Games.LIST, published, slot.free))", SRV),
    ("S9 a player who left still sent to", SV, "if player.Parent ~= nil and slots[player] == slot then", "if true then", SRV),
    ("S10 an ask from a player who left read", SV, "\t\tif player.Parent == nil then\n\t\t\treturn\n\t\tend\n\t\tlocal slot", "\t\tlocal slot", SRV),
    ("S12 the client's claim trusted", SV, "remote.OnServerEvent:Connect(function(player: Player)\n",
     "remote.OnServerEvent:Connect(function(player: Player, claim: any)\n\t\tif type(claim) == \"table\" then\n\t\t\tfor k, v in claim do\n\t\t\t\tpublished[k] = type(v) == \"table\" and v.published == true\n\t\t\tend\n\t\tend\n", SRV),
    ("S13 started twice listens twice", SV, "\tif started then\n\t\treturn\n\tend\n\tstarted = true\n\tlocal remote", "\tstarted = true\n\tlocal remote", SRV),
    ("S14 the place ids sent along", SV, "remote:FireClient(player, Card.states(Games.LIST, published, slot.free))", "remote:FireClient(player, Card.states(Games.LIST, published, slot.free), ids)", SRV),
    ("S15 the Wallet read by title", SV, "local record = Wallet.read(player, name)", "local record = Wallet.read(player, entry.title)", SRV),
    ("S16 the free state from the record, not its status", SV, "PaidPlay.status(record, os.time()).free == true", "(record :: any).free == nil", SRV),
    # Client
    ("V1 the sale's words written in", CV_, "local badge = Card.badge(states[entry.name], Prices)", "local badge = Card.badge(states[entry.name], { struck = \"5 R$\", price = \"1 R$\", sale = \"SALE\" })", CLI),
    ("V2 the struck price not rich text", CV_, "\t\tstruck.RichText = true\n", "", CLI),
    ("V3 bound at the test screen's priority", CV_, "\t\tCarousel.PRIORITY,\n", "\t\t3000,\n", CLI),
    ("V4 the wheel not bound", CV_, "local inputs: { any } = { Enum.UserInputType.MouseWheel }", "local inputs: { any } = {}", CLI),
    ("V5 keys act on the release too", CV_, "\t\t\telseif state == Enum.UserInputState.Begin then", "\t\t\telseif true then", CLI),
    ("V6 a card not published plays", CV_, "if state ~= nil and state.published then", "if true then", CLI),
    ("V7 the first card always plays", CV_, "\t\tlocal name = CarouselView.focused()\n\t\tlocal state", "\t\tlocal name = Games.LIST[1].name\n\t\tlocal state", CLI),
    ("V8 a swipe over a button ignored", CV_, "UserInputService.TouchSwipe:Connect(function(direction: Enum.SwipeDirection)\n",
     "UserInputService.TouchSwipe:Connect(function(direction: Enum.SwipeDirection, _: number, processed: boolean)\n\t\tif processed then\n\t\t\treturn\n\t\tend\n", CLI),
    ("V9 asks before it listens", CV_, [
        ("\t\tremote.OnClientEvent:Connect(function(raw: any)", "\t\tremote:FireServer()\n\t\tremote.OnClientEvent:Connect(function(raw: any)"),
        ("\t\tend)\n\t\tremote:FireServer()\n\tend)", "\t\tend)\n\tend)"),
    ], None, CLI),
    ("V10 the boot waits for the remote", CV_, [
        ("\ttask.spawn(function()\n\t\tlocal remote", "\tdo\n\t\tlocal remote"),
        ("\t\tremote:FireServer()\n\tend)\nend", "\t\tremote:FireServer()\n\tend\nend"),
    ], None, CLI),
    ("V11 no new layout on a resize", CV_, "gui:GetPropertyChangedSignal(\"AbsoluteSize\")", "gui:GetPropertyChangedSignal(\"Parent\")", CLI),
    ("V12 hidden previews turn too", CV_, "\t\t\tif frames[name].Visible then\n", "\t\t\tif true then\n", CLI),
    ("V13 the preview never turns", CV_, "local angle = Card.angle(os.clock())", "local angle = Card.angle(0)", CLI),
    ("V14 no safe insets", CV_, "\tgui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets\n", "", CLI),
    ("V15 started twice draws twice", CV_, "\tif started then\n\t\treturn\n\tend\n\tstarted = true\n\tlocal gui", "\tstarted = true\n\tlocal gui", CLI),
    ("V16 no Boards slot", CV_, "\t\tslot(card, \"Boards\", Card.REGIONS.Boards)\n", "", CLI),
    ("V17 card() gives nothing", CV_, "\treturn frames[name]\n", "\treturn nil\n", CLI),
    ("V18 an answer merged into the last", CV_, "\t\t\tstates = Card.parse(raw, Games.LIST)\n", "\t\t\tfor k, v in Card.parse(raw, Games.LIST) do\n\t\t\t\tstates[k] = v\n\t\t\tend\n", CLI),
    ("V19 the dim the wrong way", CV_, "dim.BackgroundTransparency = 1 - box.dim", "dim.BackgroundTransparency = box.dim", CLI),
    ("V21 the preview's camera not its own", CV_, "\tview.CurrentCamera = camera\n", "", CLI),
    ("V22 parts not anchored", CV_, "\t\tpart.Anchored = true\n", "", CLI),
    ("V23 a part's size axes swapped", CV_, "part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])", "part.Size = Vector3.new(p.size[1], p.size[3], p.size[2])", CLI),
    ("V24 the cards not where Carousel puts them", CV_, "local box = Carousel.box(Carousel.offset(row, i), size.X, size.Y)", "local box = Carousel.box(i - row.index, size.X, size.Y)", CLI),
    ("V25 the play listeners hear only the first", CV_, "\t\t\tfor _, fn in listeners do\n\t\t\t\ttask.spawn(fn, name)\n\t\t\tend", "\t\t\tif listeners[1] then\n\t\t\t\ttask.spawn(listeners[1], name)\n\t\t\tend", CLI),
    # Place
    ("P1 the remote is a RemoteFunction", PJ, "\"Cards\": { \"$className\": \"RemoteEvent\" }", "\"Cards\": { \"$className\": \"RemoteFunction\" }", PLC),
    ("P2 Card requires Carousel", CD, "local Card = {}\n", "local Card = {}\nlocal _row = require(\"./Carousel\")\n", PLC),
    ("P3 the server's Main does not boot Cards", SMAIN, "require(\"./Cards\").start()", "local _ = require(\"./Cards\")", PLC),
    ("P4 the client's Main does not boot the view", CMAIN, "require(\"./CarouselView\").start()", "local _ = require(\"./CarouselView\")", PLC),
    ("P5 Games requires Carousel too", GA, "local Card = require(\"./Logic/Card\")\n", "local Card = require(\"./Logic/Card\")\nlocal _row = require(\"./Logic/Carousel\")\n", PLC),
    ("P6 the view requires the Wallet", CV_, "local Prices = require(\"@game/ReplicatedStorage/Arcade/Prices\")\n", "local Prices = require(\"@game/ReplicatedStorage/Arcade/Prices\")\nlocal _w = require(\"@game/ServerStorage/Arcade/Wallet\")\n", PLC),
    ("P7 the features not in the map", AM, "### Carousel and Card (f0205)", "### Carousel (f0205)", PLC),
    ("P8 an edge from Card", AM, "# Carousel and Card are leaves", "# Carousel and Card are leaves\nCard -> Carousel", PLC),
    ("P9 the server adapter without the Wallet", SV, "local Wallet = require(\"@game/ServerStorage/Arcade/Wallet\")",
     "local Wallet = { read = function(_: Player, _: string): any\n\treturn nil\nend }", PLC),
    # Meta
    ("M1 Logic says game", CD, "-- A title is an `Entry`", "-- A game is an `Entry`", META),
]

CV = [
    ("CV1 the view requires a sibling adapter a later issue adds", CV_, "local Prices = require(\"@game/ReplicatedStorage/Arcade/Prices\")\n",
     "local Prices = require(\"@game/ReplicatedStorage/Arcade/Prices\")\nlocal _boards = require(\"./BoardsView\")\n", CLI),
    ("CV2 the server sends one more field per state", CD, "out[e.name] = { published = p, free = if p then known[e.name] else nil }",
     "out[e.name] = { published = p, free = if p then known[e.name] else nil, wait = 0 } :: any", CARD + SRV + CLI),
    ("CV3 the badge gains a note", CD, "return { kind = \"sale\", struck = Card.strike(prices.struck), text = `{prices.price} {prices.sale}` }",
     "return { kind = \"sale\", struck = Card.strike(prices.struck), text = `{prices.price} {prices.sale}`, note = \"\" } :: any", CARD + CLI),
    ("CV4 the view adds a Note label to the badge", CV_, "\t\tslot(card, \"Buttons\", Card.REGIONS.Buttons)\n",
     "\t\tlabel(badge, \"Note\", { top = 0, height = 1 }, \"\")\n\t\tslot(card, \"Buttons\", Card.REGIONS.Buttons)\n", CLI),
    ("CV5 the server requires one more arcade module", SV, "local Wallet = require(\"@game/ServerStorage/Arcade/Wallet\")\n",
     "local Wallet = require(\"@game/ServerStorage/Arcade/Wallet\")\nlocal _receipts = require(\"@game/ServerStorage/Arcade/Receipts\")\n", SRV),
]


def run(specs):
    try:
        return subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=180).stdout
    except subprocess.TimeoutExpired:
        return "TIMEOUT: the spec run did not end within 180 s"


def verdict(out, correct):
    lines = out.strip().splitlines()
    sums = [l for l in lines if " passed, " in l and " failed, " in l and "spec files" in l]
    last = sums[-1] if sums else (lines[-1] if lines else "NO OUTPUT")
    failed = "0 failed" not in last
    if correct:
        return ("ok (green)" if not failed else "RED: " + last), not failed
    if not failed:
        return "SURVIVED", False
    msgs = [l for l in lines if l.startswith("     ")]
    if any("expected" in m for m in msgs) and not any(("attempt to" in m or "Unknown require" in m or "syntax" in m.lower()) for m in msgs):
        return "killed", True
    return "ERROR (not an assertion): " + (msgs[0].strip() if msgs else last), False


def main():
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    item = os.path.join(HOME, ".tracker", "issues", "f0205")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    f0201 = os.path.join(CLONE, "arcade", ".tracker", "issues", "f0201", "experiments", "prototype.patch")
    for patch in (f0201, os.path.join(HERE, "f0199-standin.patch"), os.path.join(HERE, "prototype.patch")):
        subprocess.run(["git", "-C", CLONE, "apply", patch], check=True)
    only = sys.argv[1:]
    out = run(ALL)
    print("intended".ljust(64), verdict(out, True)[0], flush=True)
    bad = 0
    for mid, rel, old, new, specs in M + CV:
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        pairs = old if isinstance(old, list) else [(old, new)]
        edited, anchors = src, True
        for o, n in pairs:
            if edited.count(o) != 1:
                print(mid.ljust(64), "ANCHOR", edited.count(o), repr(o[:50]), flush=True)
                anchors = False
                break
            edited = edited.replace(o, n)
        if not anchors:
            bad += 1
            continue
        open(f, "w").write(edited)
        try:
            msg, good = verdict(run(specs), mid.startswith("CV"))
        finally:
            open(f, "w").write(src)
        if not good:
            bad += 1
        print(mid.ljust(64), msg, flush=True)
    print(f"{len(M)} mutants, {len(CV)} correct variants, {bad} not as intended")
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        code = main()
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    sys.exit(code)
