# f0208 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, copies this item's folder in, applies f0201's prototype (on main:
# arcade/.tracker/issues/f0201/experiments/prototype.patch), f0205's two patches (on main:
# portal/.tracker/issues/f0205/experiments/f0199-standin.patch, arcade's Travel and Places as f0199's Design states
# them, and prototype.patch, the carousel), then this issue's prototype.patch; runs the intended state (this issue's
# specs, portal's meta and f0205's acceptance specs), then applies each mutant (and each correct variant) to the
# clone, runs the row's spec files from the clone's portal/, restores the file, and deletes the clone at the end.
# A mutant is killed when its spec run reports a FAIL whose message is an assertion ("expected ..."), not a syntax,
# type or require error. A correct variant (CV) must stay green.
# Usage, from the repository root:
#   ./zn run --time 1800 -- python3 -I portal/.tracker/issues/f0208/experiments/mutants.py [id prefixes...]
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0208-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "portal")
A = ".tracker/issues/f0208/acceptance/"
PLAY = [A + "play.spec.luau"]
PAIR = [A + "pairing.spec.luau"]
SRV = [A + "server.spec.luau"]
INV = [A + "invites.spec.luau"]
CLI = [A + "client.spec.luau"]
PLC = [A + "place.spec.luau"]
META = ["tests/meta/architecture.spec.luau"]
ALL = PLAY + PAIR + SRV + INV + CLI + PLC + META
F0205 = ".tracker/issues/f0205/acceptance/"
PL = "src/shared/Logic/Play/init.luau"
PA = "src/shared/Logic/Pairing/init.luau"
AR = "src/shared/Logic/Arena/init.luau"
MO = "src/shared/Modes.luau"
SV = "src/server/Plays.luau"
IV = "src/server/Invites.luau"
CV_ = "src/client/PlayButtons.luau"
SMAIN = "src/server/Main.server.luau"
CMAIN = "src/client/Main.client.luau"
PJ = "default.project.json"
AM = ".tracker/architecture.md"

M = [
    # Play
    ("P1 a free start is not enough", PL, "if read.free == true or read.plays >= 1 then", "if read.plays >= 1 then", PLAY),
    ("P2 closed mode refuses a free start", PL, "\tif read.free == true or read.plays >= 1 then\n\t\treturn \"go\"\n\tend\n\tif mode == \"closed\" then\n\t\treturn \"closed\"\n\tend",
     "\tif mode == \"closed\" then\n\t\treturn \"closed\"\n\tend\n\tif read.free == true or read.plays >= 1 then\n\t\treturn \"go\"\n\tend", PLAY),
    ("P3 a failed read buys", PL, "return if problem == \"busy\" then \"busy\" else \"pass\"", "return if problem == \"busy\" then \"busy\" else \"buy\"", PLAY),
    ("P4 a busy read goes on the pass", PL, "return if problem == \"busy\" then \"busy\" else \"pass\"", "return \"pass\"", PLAY),
    ("P5 only live mode sells", PL, "\tif mode == \"closed\" then\n\t\treturn \"closed\"", "\tif mode ~= \"live\" then\n\t\treturn \"closed\"", PLAY),
    ("P6 any mode for any title", PL, "\tif list == nil or not has(list, mode) then\n\t\treturn nil\n\tend\n\treturn { action = \"play\"", "\tif list == nil then\n\t\treturn nil\n\tend\n\treturn { action = \"play\"", PLAY),
    ("P7 cancel keeps what the client sent", PL, "\t\treturn { action = action }", "\t\treturn { action = action, name = name }", PLAY),
    ("P9 any phase read", PL, "if type(raw) ~= \"table\" or not has(Play.PHASES, raw.phase) then", "if type(raw) ~= \"table\" then", PLAY),
    ("P10 the price not struck", PL, "return `{Card.strike(prices.struck)} {prices.price}`", "return `{prices.struck} {prices.price}`", PLAY),
    ("P11 the price says SALE", PL, "return `{Card.strike(prices.struck)} {prices.price}`", "return `{Card.strike(prices.struck)} {prices.price} {prices.sale}`", PLAY),
    ("P12 an unpublished card shows buttons", PL, "\tif state ~= nil and not state.published then\n\t\treturn { buttons = {}, note = \"\" }\n\tend\n", "", PLAY),
    ("P13 enabled before the state is known", PL, "local enabled = state ~= nil and state.free ~= nil", "local enabled = true", PLAY),
    ("P14 no INVITE on the waiting card", PL, "\t\tif status and status.mode == \"pair\" then\n\t\t\ttable.insert(out, button(\"invite\", \"\", true))\n\t\tend\n", "", PLAY),
    ("P15 checking shows the buttons", PL, "if phase == \"checking\" or phase == \"buying\" or phase == \"going\" then", "if phase == \"buying\" or phase == \"going\" then", PLAY),
    ("P16 another title's play drawn on every card", PL, "local mine = status ~= nil and status.name == name and status.phase ~= \"idle\"", "local mine = status ~= nil and status.phase ~= \"idle\"", PLAY),
    ("P17 a waiting count on every card", PL, "elseif others > 0 and has(modes, \"pair\") then", "elseif others > 0 then", PLAY),
    ("P18 no gap", PL, "local width = (1 - Play.GAP * (count - 1)) / count", "local width = 1 / count", PLAY),
    ("P19 the note ignored", PL, "local y = if noted then 0.5 else 0", "local y = 0", PLAY + CLI),
    ("P27 the price kept under a note", PL, "local price = if note == \"\" then Play.price(state, prices) else \"\"", "local price = Play.price(state, prices)", PLAY + CLI),
    ("P28 INVITE A FRIEND", PL, "\tinvite = \"INVITE FRIEND\",", "\tinvite = \"INVITE A FRIEND\",", PLAY),
    ("P29 the note always the top half", PL, "height = if count < 1 then 1 else 0.5", "height = 0.5", PLAY + CLI),
    ("P30 a wide gap", PL, "Play.GAP = 0.02", "Play.GAP = 0.3", PLAY),
    ("P20 Return is a card key too", PL, "\tTwo = \"second\",", "\tTwo = \"second\",\n\tReturn = \"second\",", PLAY),
    ("P21 bound at the test screen's priority", PL, "Play.PRIORITY = 2500", "Play.PRIORITY = 3000", PLAY + CLI),
    ("P31 bound at the default controls' priority", PL, "Play.PRIORITY = 2500", "Play.PRIORITY = 2000", PLAY + CLI),
    ("P22 the first mode is the second button", PL, "return modes[2]", "return modes[1]", PLAY + CLI),
    ("P23 any number is an inviter", PL, "if type(raw) ~= \"string\" or not string.match(raw, \"^[1-9]%d*$\") or #raw > 15 then", "if tonumber(raw) == nil then", PLAY),
    ("P24 an invite with no job", PL, " or raw.job == \"\" or", " or", PLAY),
    ("P25 Snake's second button is 2 PLAYERS", MO, "snake = modes({ \"solo\", \"arena\" }),", "snake = modes({ \"solo\", \"pair\" }),", PLAY),
    ("P26 a title's modes not frozen", MO, "\treturn table.freeze(list)", "\treturn list", PLAY),
    # Pairing and Arena
    ("Q1 the pair in the wrong order", PA, "return { lines = lines }, { first, id }", "return { lines = lines }, { id, first }", PAIR),
    ("Q2 joining keeps the other lines and pairs with oneself", PA, "\tlocal lines = without(q, id)\n\tlocal line = lines[name]", "\tlocal lines = table.clone(q.lines)\n\tlocal line = lines[name]", PAIR),
    ("Q3 leaving does nothing", PA, "\treturn { lines = without(q, id) }", "\treturn q", PAIR),
    ("Q4 the input mutated", PA, "\tlocal out: { [string]: { string } } = {}\n\tfor name, line in q.lines do", "\tlocal out: { [string]: { string } } = q.lines\n\tfor name, line in table.clone(q.lines) do", PAIR),
    ("A1 a full arena still takes one", AR, "raw.count >= Arena.CAP", "raw.count > Arena.CAP", PAIR),
    ("A2 the open span inclusive", AR, "now - raw.opened >= Arena.OPEN_SECONDS", "now - raw.opened > Arena.OPEN_SECONDS", PAIR),
    ("A3 an opening in the future is open", AR, "if raw.opened > now or now", "if now", PAIR),
    ("A4 a fraction of a count is a count", AR, "if not whole(raw.count) or raw.count < 0", "if type(raw.count) ~= \"number\" or raw.count < 0", PAIR),
    ("A5 a join sends no one", AR, "return { id = r.id, count = r.count + 1, opened = r.opened }", "return { id = r.id, count = r.count, opened = r.opened }", PAIR),
    ("A6 a cap of 25", AR, "Arena.CAP = 24", "Arena.CAP = 25", PAIR),
    # Plays
    ("S1 the free state ignored", SV, "read = { free = status.free, plays = status.plays }", "read = { free = false, plays = status.plays }", SRV),
    ("S2 the status at os.clock()", SV, "local status = PaidPlay.status(record, os.time())", "local status = PaidPlay.status(record, os.clock())", SRV),
    ("S3 no pass on a failed read", SV, "\t\t\tif decision == \"pass\" then\n\t\t\t\tWallet.pass(player, name)\n\t\t\tend\n", "", SRV),
    ("S4 the pass after the teleport", SV, "\t\t\tif decision == \"pass\" then\n\t\t\t\tWallet.pass(player, name)\n\t\t\tend\n\t\t\tproceed(player, flight)",
     "\t\t\tproceed(player, flight)\n\t\t\tif decision == \"pass\" then\n\t\t\t\tWallet.pass(player, name)\n\t\t\tend", SRV),
    ("S5 a buy goes", SV, "elseif decision == \"buy\" then", "elseif decision == \"never\" then", SRV),
    ("S6 any title's grant starts the play", SV, "slot.phase == \"buying\" and slot.name == name then\n\t\t\t\tproceed", "slot.phase == \"buying\" then\n\t\t\t\tproceed", SRV),
    ("S7 a grant with no purchase open starts it", SV, "if kind == \"play\" and slot ~= nil and slot.phase == \"buying\" and slot.name == name then",
     "if kind == \"play\" and slot ~= nil and slot.name == name then", SRV),
    ("S8 a close not bought keeps buying", SV, "\t\t\tif not bought then\n\t\t\t\tset(player, \"idle\")\n\t\t\t\treturn\n\t\t\tend\n", "", SRV),
    ("S9 every close ends the purchase", SV, "\t\t\tif not bought then\n\t\t\t\tset(player, \"idle\")", "\t\t\tif true then\n\t\t\t\tset(player, \"idle\")", SRV),
    ("S10 no receipt wait's end", SV, "\t\t\ttask.delay(Play.RECEIPT_SECONDS, function()", "\t\t\tlocal _ = (function()", SRV),
    ("S11 a busy read fails at once", SV, "if decision ~= \"busy\" or os.clock() - began >= Play.CHECK_SECONDS then", "if true then", SRV),
    ("S12 no bound on the busy wait", SV, "if decision ~= \"busy\" or os.clock() - began >= Play.CHECK_SECONDS then", "if decision ~= \"busy\" then", SRV),
    ("S13 the attributes read on every press", SV, "\t\tlocal title = intent.name :: string\n",
     "\t\tlocal title = intent.name :: string\n\t\tPlaces.read(function(a: string): any\n\t\t\treturn ServerScriptService:GetAttribute(a)\n\t\tend)\n", SRV),
    ("S14 an unpublished title read", SV, "\t\tif destination[title] == nil then\n\t\t\treturn\n\t\tend\n", "", SRV),
    ("S15 a press while checking starts another", SV, "(slot.phase == \"checking\" or slot.phase == \"buying\" or slot.phase == \"going\")", "(slot.phase == \"buying\" or slot.phase == \"going\")", SRV),
    ("S16 no cool-down", SV, "\t\tif Travel.status(travel, idOf(player), os.clock()) ~= \"idle\" then\n\t\t\treturn\n\t\tend\n\t\tif slot ~= nil and slot.phase == \"waiting\" then", "\t\tif slot ~= nil and slot.phase == \"waiting\" then", SRV),
    ("S17 TeleportInitFailed ignored", SV, "\t\tif slot ~= nil and slot.phase == \"going\" then\n\t\t\tset(player, \"failed\")\n\t\tend\n\tend)\n\n\tPlayers.PlayerAdded",
     "\tend)\n\n\tPlayers.PlayerAdded", SRV),
    ("S18 no timeout sweep", SV, "if slot.phase == \"going\" and Travel.status(travel, idOf(player), now) == \"cooling\" then", "if false then", SRV),
    ("S19 a player who left during the check still asked to buy", SV, "\t\t\tlocal record, problem = Wallet.read(player, name)\n\t\t\tif not current(player, flight) then\n\t\t\t\treturn nil\n\t\t\tend\n",
     "\t\t\tlocal record, problem = Wallet.read(player, name)\n", SRV),
    ("S20 data rides along", SV, "TeleportService:TeleportAsync(destination[name], players, options)", "TeleportService:TeleportAsync(destination[name], players, options, { name = name })", SRV),
    ("S21 statuses to everyone", SV, "remote:FireClient(player, \"status\", { phase = slot.phase, name = slot.name, mode = slot.mode })",
     "remote:FireAllClients(\"status\", { phase = slot.phase, name = slot.name, mode = slot.mode })", SRV),
    ("S22 a new arena for every player", SV, "go({ player }, name, (last :: Arena.Record).id)", "go({ player }, name, fresh)", SRV),
    ("S23 the first transform call decides", SV, "\t\t\t\t\tlast = Arena.join(raw, fresh, os.time())", "\t\t\t\t\tlast = last or Arena.join(raw, fresh, os.time())", SRV),
    ("S24 an unwritten arena still goes", SV, "\t\t\tif not ok or last == nil then\n\t\t\t\tset(player, \"failed\")\n\t\t\t\treturn\n\t\t\tend\n\t\t\tgo({ player }, name, (last :: Arena.Record).id)",
     "\t\t\tgo({ player }, name, if last then (last :: Arena.Record).id else fresh)", SRV),
    ("S25 the arena record never expires", SV, "\t\t\t\tend, Arena.OPEN_SECONDS)", "\t\t\t\tend)", SRV),
    ("S26 a pair in two teleports", SV, "\t\t\tgo({ first, player }, name, HttpService:GenerateGUID(false))",
     "\t\t\tlocal id = HttpService:GenerateGUID(false)\n\t\t\tgo({ first }, name, id)\n\t\t\tgo({ player }, name, id)", SRV),
    ("S27 a pair to a public server", SV, "\t\t\tgo({ first, player }, name, HttpService:GenerateGUID(false))", "\t\t\tgo({ first, player }, name, nil)", SRV),
    ("S28 every pair of a title to one server", SV, "\t\t\tgo({ first, player }, name, HttpService:GenerateGUID(false))", "\t\t\tgo({ first, player }, name, \"pair-\" .. name)", SRV),
    ("S29 CANCEL ignored", SV, "\t\t\tif slot ~= nil and slot.phase == \"waiting\" then\n\t\t\t\tunwait(player)\n\t\t\t\tset(player, \"idle\")\n\t\t\tend\n", "", SRV),
    ("S30 a leaver stays in the line", SV, "\t\tif Pairing.line(queue, idOf(player)) ~= nil then\n\t\t\tunwait(player)\n\t\tend\n", "", SRV),
    ("S31 the count not told when a pair forms", SV, "\t\t\tremote:FireAllClients(\"waiting\", counts())\n\t\t\tlocal first", "\t\t\tlocal first", SRV),
    ("S32 an invite recorded on every press", SV, "\t\t\t\tif not slot.invited then", "\t\t\t\tif true then", SRV),
    ("S33 an invite with no wait", SV, "if slot ~= nil and slot.phase == \"waiting\" and slot.mode == \"pair\" then", "if slot ~= nil then", SRV),
    ("S34 started twice installs twice", SV, "\tif started then\n\t\treturn\n\tend\n\tstarted = true\n\tlocal remote", "\tstarted = true\n\tlocal remote", SRV),
    ("S35 a joiner not told who waits", SV, "\t\tremote:FireClient(player, \"waiting\", counts())", "\t\tlocal _ = player", SRV),
    ("S36 a play while waiting stays in the line", SV, "\t\tif slot ~= nil and slot.phase == \"waiting\" then\n\t\t\tunwait(player)\n\t\tend\n\t\trun(", "\t\trun(", SRV),
    ("S37 a failed teleport not told", SV, "\t\t\t\tTravel.failed(travel, idOf(p), os.clock(), tickets[p])\n\t\t\t\tset(p, \"failed\")", "\t\t\t\tTravel.failed(travel, idOf(p), os.clock(), tickets[p])", SRV),
    ("S38 the purchase of the wrong kind", SV, "if not Receipts.ask(player, name, \"play\") then", "if not Receipts.ask(player, name, \"revive\") then", SRV),
    ("S39 the arena keyed by mode", SV, "\t\t\t\tarenas:UpdateAsync(name, function", "\t\t\t\tarenas:UpdateAsync(\"arena\", function", SRV),
    # Invites
    ("I1 no friend check", IV, "if not okFriends or friends ~= true or friend.Parent == nil then", "if friend.Parent == nil then", INV),
    ("I2 an invite for this server followed", IV, "if record == nil or record.job == game.JobId then", "if record == nil then", INV),
    ("I3 the inviter here still looked up", IV, " or Players:GetPlayerByUserId(inviter) ~= nil then", " then", INV),
    ("I4 an invite with no expiry", IV, "{ job = game.JobId, name = name }, Invites.SECONDS)", "{ job = game.JobId, name = name })", INV),
    ("I5 the friend sent to any server", IV, "\t\toptions.ServerInstanceId = record.job\n", "", INV),
    ("I6 a friend who left still sent", IV, "if not okFriends or friends ~= true or friend.Parent == nil then", "if not okFriends or friends ~= true then", INV),
    ("I7 the invite write unguarded", IV, "\tpcall(function()\n\t\tinvites():SetAsync(tostring(player.UserId), { job = game.JobId, name = name }, Invites.SECONDS)\n\tend)",
     "\tinvites():SetAsync(tostring(player.UserId), { job = game.JobId, name = name }, Invites.SECONDS)", INV),
    # PlayButtons
    ("V1 gamepad-selectable", CV_, "b.Selectable = false", "b.Selectable = true", CLI),
    ("V2 no rich text", CV_, "b.RichText = true", "b.RichText = false", CLI),
    ("V3 sent while the test screen is open", CV_, "if remote == nil or TestPurchase.isOpen() then", "if remote == nil then", CLI),
    ("V4 keys on the release too", CV_, "\t\t\t\tstate == Enum.UserInputState.Begin\n\t\t\t\tand not", "\t\t\t\tnot", CLI),
    ("V5 every key sunk", CV_, "\t\t\treturn Enum.ContextActionResult.Pass\n", "\t\t\treturn Enum.ContextActionResult.Sink\n", CLI),
    ("V6 the carousel's PLAY whatever the card", CV_, "\t\tif pressable(name, \"solo\") then\n\t\t\tsend(\"solo\", name)\n\t\tend", "\t\tsend(\"solo\", name)", CLI),
    ("V7 a disabled button sends", CV_, "\t\t\t\tif button.kind == kind and button.enabled then\n\t\t\t\t\tsend", "\t\t\t\tif button.kind == kind then\n\t\t\t\t\tsend", CLI),
    ("V8 cancel keys with no wait", CV_, "elseif which ~= nil and status ~= nil and status.phase == \"waiting\" then", "elseif which ~= nil then", CLI),
    ("V9 no ask of the cards' states", CV_, "\t\tcards:FireServer()\n", "", CLI),
    ("V10 the ask before listening", CV_, "\t\tlocal cards = remotes:WaitForChild(\"Cards\") :: RemoteEvent\n", "\t\tlocal cards = remotes:WaitForChild(\"Cards\") :: RemoteEvent\n\t\tcards:FireServer()\n", CLI),
    ("V11 no invite check", CV_, "\t\tif ok and can == true then", "\t\tif true then", CLI),
    ("V12 no launch data", CV_, "\t\t\t\toptions.LaunchData = tostring(me.UserId)\n", "", CLI),
    ("V13 the status not drawn", CV_, "\t\t\t\tstatus = Play.parse(raw, Modes)\n\t\t\t\tdraw()", "\t\t\t\tstatus = Play.parse(raw, Modes)", CLI),
    ("V15 started twice builds twice", CV_, "\tif started then\n\t\treturn\n\tend\n\tstarted = true\n\tfor _, entry", "\tstarted = true\n\tfor _, entry", CLI),
    ("V16 start waits for the remotes", CV_, "\ttask.spawn(function()\n\t\tlocal remotes", "\tlocal _ = (function(f: () -> ()) f() end)(function()\n\t\tlocal remotes", CLI),
    ("V18 the note does not wrap", CV_, "\tnote.TextWrapped = true\n", "\tnote.TextWrapped = false\n", CLI),
    ("V19 a button wraps", CV_, "\t\tb.TextWrapped = false", "\t\tb.TextWrapped = true", CLI),
    ("V20 the note's box ignored", CV_, "local box = Play.noteBox(#view.buttons)", "local box = Play.noteBox(1)", CLI),
    ("V21 the buttons' height ignored", CV_, "UDim2.fromScale(places[i].x, places[i].y)", "UDim2.fromScale(places[i].x, 0)", CLI),
    ("V17 keys while typing", CV_, "\t\t\tif UserInputService:GetFocusedTextBox() ~= nil then\n\t\t\t\treturn Enum.ContextActionResult.Pass -- typing (the chat box): the keys are the text's\n\t\t\tend\n", "", CLI),
    # Place and map
    ("L1 Play requires Carousel too", PL, "local Card = require(\"./Card\")\n", "local Card = require(\"./Card\")\nlocal _ = require(\"./Carousel\")\n", PLC),
    ("L2 Modes requires Games", MO, "local Play = require(\"./Logic/Play\")\n", "local Play = require(\"./Logic/Play\")\nlocal _ = require(\"./Games\")\n", PLC),
    ("L3 the server's Main does not boot Plays", SMAIN, "require(\"./Plays\").start()\n", "", PLC),
    ("L4 the client's Main does not boot the test screen", CMAIN, "require(\"@game/ReplicatedStorage/Arcade/TestPurchase\").start()\n", "", PLC),
    ("L5 no Play remote", PJ, ",\n        \"Play\": { \"$className\": \"RemoteEvent\" }", "", PLC),
    ("L6 the edge not in the map", AM, "Play -> Card\n", "", PLC + META),
    ("L7 the client reaches the Wallet", CV_, "local TestPurchase = require(\"@game/ReplicatedStorage/Arcade/TestPurchase\")\n",
     "local TestPurchase = require(\"@game/ReplicatedStorage/Arcade/TestPurchase\")\nlocal _ = require(\"@game/ServerStorage/Arcade/Wallet\")\n", PLC),
    ("L8 the test screen booted after the buttons", CMAIN, "require(\"@game/ReplicatedStorage/Arcade/TestPurchase\").start()\nrequire(\"./CarouselView\").start()\nrequire(\"./PlayButtons\").start()\n",
     "require(\"./CarouselView\").start()\nrequire(\"./PlayButtons\").start()\nrequire(\"@game/ReplicatedStorage/Arcade/TestPurchase\").start()\n", PLC),
    ("L9 the map not declared as the spec's input", "tests/inputs.tsv", "tests/acceptance/f0208/place.spec.luau\tportal/.tracker/architecture.md\n", "", PLC),
    # Meta
    ("M1 Logic says game", PA, "-- Pairing (f0208): the 2 PLAYERS waiting lines", "-- Pairing (f0208): the game's waiting lines", META),
]

CV = [
    ("CV1 the server's Main boots a further adapter", SMAIN, "require(\"./Plays\").start()\n", "require(\"./Plays\").start()\nrequire(\"./Boards\").start()\n", PLC),
    ("CV2 the client's Main boots a further adapter", CMAIN, "require(\"./PlayButtons\").start()\n", "require(\"./PlayButtons\").start()\nrequire(\"./BoardsView\").start()\n", PLC),
    ("CV3 the status gains a field", SV, "{ phase = slot.phase, name = slot.name, mode = slot.mode }", "{ phase = slot.phase, name = slot.name, mode = slot.mode, at = os.clock() }", SRV + CLI),
    ("CV4 the server requires one more arcade module", SV, "local Wallet = require(\"@game/ServerStorage/Arcade/Wallet\")\n",
     "local Wallet = require(\"@game/ServerStorage/Arcade/Wallet\")\nlocal _catalog = require(\"@game/ServerStorage/Arcade/Catalog\")\n", SRV),
    ("CV5 the buttons require a sibling adapter", CV_, "local CarouselView = require(\"./CarouselView\")\n", "local CarouselView = require(\"./CarouselView\")\nlocal _boards = require(\"./BoardsView\")\n", CLI),
    ("CV6 the waiting counts carry another field", SV, "\t\tlocal out: { [string]: number } = {}\n\t\tfor name, list in Modes do", "\t\tlocal out: { [string]: number } = { total = 0 } :: any\n\t\tfor name, list in Modes do", SRV + CLI),
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
    failed = re.search(r"(^|[^0-9])0 failed", last) is None  # "20 failed" is not "0 failed"
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
    item = os.path.join(HOME, ".tracker", "issues", "f0208")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    f0201 = os.path.join(CLONE, "arcade", ".tracker", "issues", "f0201", "experiments", "prototype.patch")
    f0205 = os.path.join(HOME, ".tracker", "issues", "f0205", "experiments")
    for patch in (f0201, os.path.join(f0205, "f0199-standin.patch"), os.path.join(f0205, "prototype.patch"), os.path.join(HERE, "prototype.patch")):
        subprocess.run(["git", "-C", CLONE, "apply", patch], check=True)
    dest = os.path.join(HOME, F0205)
    extra = sorted(F0205 + f for f in os.listdir(dest) if f.endswith(".spec.luau"))
    only = sys.argv[1:]
    out = run(ALL + extra)
    print("intended (with f0205's specs)", verdict(out, True)[0], sep=": ", flush=True)
    bad = 0
    for mid, rel, old, new, specs in M + CV:
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        if src.count(old) != 1:
            print(mid.ljust(64), "ANCHOR", src.count(old), repr(old[:50]), flush=True)
            bad += 1
            continue
        open(f, "w").write(src.replace(old, new))
        try:
            out = run(specs)
            msg, good = verdict(out, mid.startswith("CV"))
            if os.environ.get("MUTANTS_DEBUG") and not good:
                print(out[-3000:], flush=True)
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
