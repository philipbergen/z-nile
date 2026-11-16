# f0206 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, checks out this checkout's HEAD there, copies this item's folder in, and applies the bases in
# order, all in-repo, each three-way with any conflict resolved by keeping both sides: f0201's prototype (arcade's
# PaidPlay, Prices, Wallet, Catalog), f0205's f0199-standin.patch and prototype.patch (f0205, prepared and on main since
# PR #494), f0197's prototype (arcade's Hiscores, Boards, HiscoreGames) and this issue's prototype.patch (its portal
# code). f0208 (prepared, PR #512) is not applied here; E12 runs the two together. It runs the intended state, then applies each mutant (and each correct variant) to that
# clone, runs the row's spec files from the clone's portal/, restores the file, and deletes the clone at the end.
# A mutant is killed when its spec run reports a FAIL whose message is an assertion ("expected ..."), not a syntax,
# type or require error. A correct variant (CV) must stay green.
# Usage, from the repository root:
#   ./zn run --time 1800 -- python3 -I portal/.tracker/issues/f0206/experiments/mutants.py [id prefixes...]
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
HEAD = subprocess.run(["git", "-C", HERE, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="f0206-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "portal")
A = ".tracker/issues/f0206/acceptance/"
BRD = [A + "board.spec.luau"]
PAR = [A + "parse.spec.luau"]
PLN = [A + "plan.spec.luau"]
SRV = [A + "server.spec.luau"]
BUD = [A + "budget.spec.luau"]
CLI = [A + "client.spec.luau"]
PLC = [A + "place.spec.luau"]
META = ["tests/meta/architecture.spec.luau"]
ALL = BRD + PAR + PLN + SRV + BUD + CLI + PLC + META
BO = "src/shared/Logic/Board/init.luau"
RE = "src/server/BoardRelay.luau"
VI = "src/client/BoardsView.luau"
SMAIN = "src/server/Main.server.luau"
CMAIN = "src/client/Main.client.luau"
PJ = "default.project.json"
AM = ".tracker/architecture.md"

M = [
    # Board: what a board shows
    ("B1 the tabs out of order", BO, 'Board.TABS = table.freeze({ "all", "day", "week" })', 'Board.TABS = table.freeze({ "all", "week", "day" })', BRD),
    ("B2 no wrap", BO, "return Board.TABS[(at - 1 + by) % #Board.TABS + 1]", "return Board.TABS[math.clamp(at + by, 1, #Board.TABS)]", BRD),
    ("B3 a step that is not whole moves", BO, "\tif not whole(by) then\n\t\treturn Board.TABS[at]", "\tif not finite(by) then\n\t\treturn Board.TABS[at]", BRD),
    ("B4 W steps forward", BO, "Board.KEYS = table.freeze({ W = -1,", "Board.KEYS = table.freeze({ W = 1,", BRD),
    ("B5 Tab steps too", BO, "S = 1, Down = 1, ButtonR2 = 1 })", "S = 1, Down = 1, ButtonR2 = 1, Tab = 1 })", BRD),
    ("B6 bound at the default controls' priority", BO, "Board.PRIORITY = 2500", "Board.PRIORITY = 2000", BRD),
    ("B6b bound at the test screen's priority", BO, "Board.PRIORITY = 2500", "Board.PRIORITY = 3000", BRD),
    ("B7 no revives shows 0", BO, "\tif whole(n) and n >= 1 then\n\t\treturn int(n)", "\tif whole(n) and n >= 0 then\n\t\treturn int(n)", BRD),
    ("B8 junk revives shown", BO, "\tif whole(n) and n >= 1 then\n\t\treturn int(n)", "\tif type(n) == \"number\" and n >= 1 then\n\t\treturn tostring(n)", BRD),
    ("B9 the figure not upper case", BO, 'return { "#", "NAME", "SCORE", string.upper(progress), "REVIVES" }', 'return { "#", "NAME", "SCORE", progress, "REVIVES" }', BRD),
    ("B10 score and figure swapped", BO, "return { int(row.rank), row.name, int(row.score), int(row.level), Board.revives(row.revives) }",
     "return { int(row.rank), row.name, int(row.level), int(row.score), Board.revives(row.revives) }", BRD),
    ("B11 no best shows no line", BO, "\t\treturn { \"\", Board.BEST, Board.NONE, Board.NONE, Board.NONE }", "\t\treturn { \"\", \"\", \"\", \"\", \"\" }", BRD),
    ("B12 the best's revives as a bare count", BO, "int(best.level), Board.revives(best.revives) }", "int(best.level), int(best.revives) }", BRD),
    ("B13 a wait shows its rows", BO, "\tif answer ~= nil and answer.status ~= \"wait\" then", "\tif answer ~= nil then", BRD),
    ("B14 a failed empty board says no scores", BO, "\t\telseif answer.status == \"failed\" then\n\t\t\tnote = Board.DOWN", "\t\telseif false then\n\t\t\tnote = Board.DOWN", BRD),
    ("B15 the player's row never marked", BO, "mine = answer.rank ~= nil and row.rank == answer.rank", "mine = false", BRD),
    ("B16 a pending best drawn as no best", BO, "else Board.pendingCells()", "else Board.bestCells(nil)", BRD),
    ("B17 no smallest line", BO, "math.clamp((h - Board.TAB_PX) / (Board.N + 2), Board.MIN_LINE_PX, Board.MAX_LINE_PX)",
     "math.min((h - Board.TAB_PX) / (Board.N + 2), Board.MAX_LINE_PX)", BRD),
    ("B18 the tab bar not left out of the lines", BO, "math.clamp((h - Board.TAB_PX) / (Board.N + 2),", "math.clamp(h / (Board.N + 2),", BRD),
    ("B19 a wait waits REASK", BO, "(if last.wait then Board.WAIT_RETRY else Board.REASK)", "Board.REASK", BRD),
    ("B20 a clock that went back waits", BO, "\tif last == nil or now < last.at then", "\tif last == nil then", BRD),
    ("B21 the all-time board not asked while the best is unknown", BO, "\t\t\ttable.insert(out, { name = name, id = \"all\" })\n", "", BRD),
    ("T1 the text as tall as the line, whatever the width", BO, "text = math.floor(math.min(line, w / (g * Board.CHARS))),", "text = math.floor(line),", BRD),
    ("T2 the glyph width ignored", BO, "\tlocal g = if finite(glyph) and glyph > 0 then glyph else 1\n", "\tlocal g = 0.5\n", BRD),
    ("T3 a name column too narrow", BO, '{ name = "Name", chars = 7, align = "Left" }', '{ name = "Name", chars = 5, align = "Left" }', BRD),
    ("T4 a text size that is not whole", BO, "text = math.floor(math.min(line, w / (g * Board.CHARS))),", "text = math.min(line, w / (g * Board.CHARS)),", BRD),
    ("P12 a pending best read as none", BO, "\t\tpending = rawBest == false,", "\t\tpending = false,", PAR + CLI),
    ("P13 a pending answer forgets the best", BO, "\tif answer.pending then\n\t\treturn mine or { known = false, best = nil }\n\tend\n", "", BRD + CLI),
    ("F1a the relay sends a pending best as none", RE, "\t\tif slot == nil or not slot.heard[name] then\n\t\t\treturn false", "\t\tif slot == nil or not slot.heard[name] then\n\t\t\treturn nil", SRV + BUD),
    ("F1b heard counted from the forward", RE, "\t\tif slot == nil or not slot.heard[name] then", "\t\tif slot == nil or not (slot.heard[name] or slot.last[name] ~= nil) then", SRV + BUD),
    ("F1c a pending answer re-asked only after REASK", VI, "\t\t\t\tlast.wait = answer.status == \"wait\" or answer.pending", "\t\t\t\tlast.wait = answer.status == \"wait\"", CLI + BUD),
    ("F2a the version raised on every answer", RE, "\t\tif not snap.known or not Board.sameRows(snap.rows, given) then", "\t\tif true then", SRV),
    ("F2b the version never raised", RE, "\t\tif not snap.known or not Board.sameRows(snap.rows, given) then", "\t\tif not snap.known then", SRV),
    ("F2c rows compared by reference", BO, "function Board.sameRows(a: { Row }, b: { Row }): boolean\n\tif #a ~= #b then", "function Board.sameRows(a: { Row }, b: { Row }): boolean\n\tif a ~= b then", PLN),
    ("F3a no floor at all", BO, "Board.FLOOR = 4", "Board.FLOOR = 0", PLN + BUD),
    ("F3b one token per title", BO, "Board.BURST = 12", "Board.BURST = 4", PLN + BUD),
    ("F3c KEEP for one board", BO, "Board.KEEP = 4", "Board.KEEP = 1", PLN),
    ("F5a a tab gamepad-selectable", VI, "\t\tb.Selectable = false", "\t\tb.Selectable = true", CLI),
    ("F5b the rows gamepad-selectable", VI, "\trows.Selectable = false", "\trows.Selectable = true", CLI),
    ("F6a no gutter", BO, "Board.GUTTER = 0.4", "Board.GUTTER = 0", BRD),
    ("F6b the rank aligned left", BO, '{ name = "Rank", chars = 2, align = "Right" }', '{ name = "Rank", chars = 2, align = "Left" }', BRD),
    ("F6c the view aligns nothing", VI, "\t\tl.TextXAlignment = ALIGN[c.align]\n", "", CLI),
    ("F6d labels placed without their inset", VI, "\t\tl.Position = UDim2.fromScale(c.x, 0)", "\t\tl.Position = UDim2.fromScale(c.x - Board.GUTTER / 2 / Board.CHARS, 0)", CLI),
    ("F7 a refresh charged one sorted read", BO, "Board.COST = table.freeze({ standard = 12, sorted = 2 })", "Board.COST = table.freeze({ standard = 12, sorted = 1 })", PLN),
    ("B22 the view's rows not cut at the header", BO, "view = math.max(0, h - Board.TAB_PX - 2 * line),", "view = math.max(0, h - Board.TAB_PX),", BRD),
    # Board.parse: the client's read
    ("P1 any title read", BO, "\tif type(name) ~= \"string\" or names[name] ~= true then", "\tif type(name) ~= \"string\" then", PAR),
    ("P2 any status read", BO, "\telse\n\t\treturn nil\n\tend\n\tlocal rows: { Row } = {}", "\telse\n\t\tstatus = \"ok\"\n\tend\n\tlocal rows: { Row } = {}", PAR),
    ("P3 a rank past ten kept", BO, "rank < 1 or rank > Board.N or type(name)", "rank < 1 or type(name)", PAR),
    ("P4 rows not sorted", BO, "\ttable.sort(rows, function(a: Row, b: Row): boolean\n\t\treturn a.rank < b.rank\n\tend)\n", "", PAR),
    ("P5 rows not cut to ten", BO, "\twhile #rows > Board.N do\n\t\ttable.remove(rows)\n\tend\n", "", PAR),
    ("P6 junk revives kept", BO, "\tlocal revives = if whole(raw.revives) and raw.revives >= 0 then raw.revives else 0\n\treturn { rank = rank,",
     "\tlocal revives = raw.revives\n\treturn { rank = rank,", PAR),
    ("P7 a rank kept that is no row's", BO, "\t\tif r.rank == rawRank then\n\t\t\trank = r.rank", "\t\tif true then\n\t\t\trank = rawRank", PAR),
    ("P8 the best kept on the all-time board only", BO, "\t\tbest = best(rawBest),", "\t\tbest = if id == \"all\" then best(rawBest) else nil,", PAR),
    ("P9 the best not checked", BO, "\tif not whole(raw.score) or raw.score < 0 or not whole(raw.level) or raw.level < 1 then\n\t\treturn nil\n\tend\n\tlocal revives = if whole(raw.revives) and raw.revives >= 0 then raw.revives else 0\n\treturn { score",
     "\tlocal revives = if whole(raw.revives) and raw.revives >= 0 then raw.revives else 0\n\treturn { score", PAR),
    ("P10 a row that is no table read", BO, "local function row(raw: any): Row?\n\tif type(raw) ~= \"table\" then\n\t\treturn nil\n\tend", "local function row(raw: any): Row?", PAR),
    ("P11 a score that is not whole kept", BO, "\tif not whole(score) or score < 0 or not whole(level)", "\tif type(score) ~= \"number\" or score < 0 or not whole(level)", PAR),
    # Board.plan: the server's read policy
    ("L1 a failed answer keeps the window open", BO, "\tif snap ~= nil and snap.at ~= nil and not snap.failed then", "\tif snap ~= nil and snap.at ~= nil then", PLN),
    ("L2 the window to the arcade's whole cache time", BO, "now - at < a.ttl - Board.MARGIN then", "now - at < a.ttl then", PLN),
    ("L3 no REFRESH wait", BO, "\t\tor now - (snap.at :: number) >= Board.REFRESH", "\t\tor true", PLN + BUD),
    ("L4 a refresh takes no token", BO, "bucket = { tokens = bucket.tokens - 1, at = bucket.at },", "bucket = bucket,", PLN + BUD),
    ("L5 no allowance", BO, "\t\tand bucket.tokens >= 1 + (if snap ~= nil and snap.known then Board.KEEP else 0)\n", "", PLN + BUD),
    ("L6 the rate not per player", BO, "local per = math.max(Board.RATE * count, Board.FLOOR) / 60", "local per = Board.FLOOR / 60", PLN),
    ("L6b no floor", BO, "local per = math.max(Board.RATE * count, Board.FLOOR) / 60", "local per = Board.RATE * math.max(count, 1) / 60", PLN + BUD),
    ("L7 no BURST cap", BO, "return { tokens = math.min(Board.BURST, b.tokens + per * (now - at)), at = now }", "return { tokens = b.tokens + per * (now - at), at = now }", PLN),
    ("L8 the sorted budget not read", BO, "\t\tand a.budget.sorted >= Board.RESERVE.sorted + Board.COST.sorted\n", "", PLN),
    ("L9 the standard budget not read", BO, "\t\tand a.budget.standard >= Board.RESERVE.standard + Board.COST.standard\n", "", PLN),
    ("L10 a held best forwarded", BO, "if reads == \"hold\" or (reads == \"read\"", "if (reads == \"read\"", PLN),
    ("L11 a best read with no budget", BO, " or (reads == \"read\" and a.budget.standard < Board.RESERVE.standard + 1)", "", PLN),
    ("L12 no KEEP", BO, "bucket.tokens >= 1 + (if snap ~= nil and snap.known then Board.KEEP else 0)", "bucket.tokens >= 1", PLN + BUD),
    ("L13 a clock that went back waits", BO, "\t\tor now < (snap.at :: number)\n", "", PLN),
    ("L14 a refresh never marks the best", BO, "\t\t\tbest = reads ~= \"fresh\",", "\t\t\tbest = false,", PLN),
    ("L15 rows not answered say ok", BO, "\tif snap == nil or not snap.known then\n\t\treturn \"wait\"", "\tif snap == nil then\n\t\treturn \"wait\"", PLN),
    ("L16 a rank kept over changed rows", BO, "if held == nil or snap == nil or held.version ~= snap.version then", "if held == nil or snap == nil then", PLN),
    ("L17 a refilled allowance re-dated wrong", BO, "\tif now < at then\n\t\treturn { tokens = b.tokens, at = now }", "\tif now < at then\n\t\treturn { tokens = Board.BURST, at = now }", PLN),
    ("L18 a held best inside BEST_GAP read", BO, "\telseif now - last >= Board.BEST_GAP then\n\t\treturn \"read\"\n\tend\n\treturn \"hold\"", "\tend\n\treturn \"read\"", PLN + SRV),
    # BoardRelay: the server adapter
    ("S1 the arcade serves the client's remote", RE, "Boards.open(hiscores.prefix).serve(relay :: any)", "Boards.open(hiscores.prefix).serve(remote)", SRV),
    ("S2 opened by name", RE, "Boards.open(hiscores.prefix)", "Boards.open(name)", SRV),
    ("S3 every arcade answer says ok", RE, "\t\tsnap.failed = failed == true\n", "", SRV),
    ("S4 the best only with all-time answers", RE, "Board.status(snap), mineOf(slot, name))", "Board.status(snap), if id == \"all\" then mineOf(slot, name) else nil)", SRV),
    ("S5 a held answer without the held rank", RE, "\t\t\t\tBoard.rankFor(slot.ranks[`{name}|{key}`], snap),", "\t\t\t\tnil,", SRV),
    ("S6 a held answer without the held best", RE, "\t\t\t\tmineOf(slot, name)\n", "\t\t\t\tnil\n", SRV),
    ("S7 a refresh not dated", RE, "\t\tif plan.act == \"refresh\" then\n\t\t\tsnap.at = now\n\t\tend", "", SRV + BUD),
    ("S8 the wrong sorted budget read", RE, "Enum.DataStoreRequestType.OrderedList", "Enum.DataStoreRequestType.OrderedRead", SRV),
    ("S9 an answer sent to a player who left", RE, "\t\tif player.Parent ~= nil then\n\t\t\tremote:FireClient(", "\t\tif true then\n\t\t\tremote:FireClient(", SRV),
    ("S10 the arcade's rows not held", RE, "\t\tsnap.rows = given\n", "", SRV),
    ("S11 a best read not recorded", RE, "\t\tif plan.best then\n\t\t\tslot.last[name] = now\n\t\tend", "", SRV),
    ("S12 every ask forwarded to the first title", RE, "\t\tfor _, fn in handlers[name] do", "\t\tfor _, fn in handlers[Games.LIST[1].name] do", SRV),
    ("S13 start twice listens twice", RE, "\tif started then\n\t\treturn\n\tend\n\tstarted = true", "\tstarted = true", SRV),
    ("S14 a failed open stops the boot", RE, "\t\t\tlocal ok, err = pcall(function()\n\t\t\t\tBoards.open(hiscores.prefix).serve(relay :: any)\n\t\t\tend)",
     "\t\t\tBoards.open(hiscores.prefix).serve(relay :: any)\n\t\t\tlocal ok, err = true, nil", SRV),
    ("S15 a budget that cannot be read stops the ask", RE, "\t\tif not ok then\n\t\t\treturn { standard = 0, sorted = 0 }\n\t\tend", "\t\tif not ok then\n\t\t\terror(standard)\n\t\tend", SRV),
    ("S16 every ask forwarded", RE, "\t\tif plan.act == \"answer\" then\n\t\t\tremote:FireClient(", "\t\tif false then\n\t\t\tremote:FireClient(", SRV + BUD),
    ("S17 one player always", RE, "players = #Players:GetPlayers(),", "players = 1,", BUD),
    ("S18 a player who left still asks", RE, "\t\tif player.Parent == nil or type(rawName)", "\t\tif type(rawName)", SRV),
    ("S20 the arcade's cache time read as a minute", RE, "ttl = Hiscores.CACHE_TTL,", "ttl = 60,", SRV + BUD),
    ("S21 no ask counted as the all-time board", RE, 'all = id == "all",', "all = false,", SRV),
    ("S22 the board keyed by its id alone", RE, "\t\tlocal key = Hiscores.cacheKey(id :: any, now)\n\t\tlocal snap = snapOf(name, key)\n\t\tlocal slot = slotOf(player)", "\t\tlocal key = id\n\t\tlocal snap = snapOf(name, key)\n\t\tlocal slot = slotOf(player)", SRV),
    ("S19 the allowance never kept", RE, "\t\tbucket = plan.bucket\n", "", SRV + BUD),
    # BoardsView: the client adapter
    ("V1 the carousel not started", VI, "\tstarted = true\n\tCarouselView.start()", "\tstarted = true", CLI),
    ("V2 the figure by the title's name", VI, "local progress = if hiscores ~= nil then hiscores.progress else \"\"", "local progress = name", CLI),
    ("V3 bound at the test screen's priority", VI, "\t\tBoard.PRIORITY,\n\t\ttable.unpack(keys)", "\t\t3000,\n\t\ttable.unpack(keys)", CLI),
    ("V4 keys on the release too", VI, "\t\t\tif state == Enum.UserInputState.Begin then\n\t\t\t\tlocal step", "\t\t\tif true then\n\t\t\t\tlocal step", CLI),
    ("V5 a tab chosen for its card only", VI, "local function choose(id: Board.Id)\n\ttab = id\n\tdrawAll()", "local function choose(id: Board.Id)\n\ttab = id\n\tdraw(CarouselView.focused())", CLI),
    ("V6 asks every frame", VI, "\t\t\tif Board.askDue(asked[key], now) then", "\t\t\tif true then", CLI),
    ("V7 a wait not marked", VI, "\t\t\t\tlast.wait = answer.status == \"wait\" or answer.pending", "\t\t\t\tlast.wait = answer.pending", CLI),
    ("V8 a wait marks the front card's board", VI, "local last = asked[`{answer.name}|{answer.id}`]", "local last = asked[`{CarouselView.focused()}|{tab}`]", CLI),
    ("V9 an answer drawn on the front card", VI, "\t\t\tdraw(answer.name)\n", "\t\t\tdraw(CarouselView.focused())\n", CLI),
    ("V10 no layout on a resize", VI, "\tslot:GetPropertyChangedSignal(\"AbsoluteSize\"):Connect(function()\n\t\tplace(p)\n\tend)", "", CLI),
    ("V11 the rows never scroll", VI, "p.rows.ScrollingEnabled = layout.canvas > layout.view", "p.rows.ScrollingEnabled = false", CLI),
    ("V12 the player's row not marked", VI, "if shown ~= nil and shown.mine then 0.5 else 1", "if shown ~= nil and shown.mine then 1 else 1", CLI),
    ("V13 the boot waits for the remote", VI, "\ttask.spawn(function()\n\t\tlocal found", "\tpcall(function()\n\t\tlocal found", CLI),
    ("V14 started twice fills twice", VI, "\tif started then\n\t\treturn\n\tend\n\tstarted = true\n\tCarouselView.start()", "\tstarted = true\n\tCarouselView.start()", CLI),
    ("V15 the chosen tab not shown", VI, "button.BackgroundTransparency = if id == tab then 0 else 0.6", "button.BackgroundTransparency = 0.6", CLI),
    ("V16 rows placed at a fixed line", VI, "\t\tline.frame.Position = UDim2.fromOffset(0, (i - 1) * layout.line)", "\t\tline.frame.Position = UDim2.fromOffset(0, (i - 1) * Board.MIN_LINE_PX)", CLI),
    ("V17 an answer not read through parse", VI, "\t\t\tlocal answer = Board.parse(names, ...)", "\t\t\tlocal raw = table.pack(...)\n\t\t\tlocal answer: any = { name = raw[1], id = raw[2], rows = raw[3] or {}, rank = raw[4], status = raw[5], best = raw[6] }", CLI),
    ("V19 labels scaled to their boxes", VI, "\tl.TextScaled = false", "\tl.TextScaled = true", CLI),
    ("V20 the rows' text size not set", VI, "\tfor _, line in p.lines do\n\t\tfor _, cell in line.cells do\n\t\t\tcell.TextSize = layout.text", "\tfor _, line in p.lines do\n\t\tfor _, cell in line.cells do\n\t\t\tcell.TextSize = 14", CLI),
    ("V21 the tab keys act while the player types", VI, "\t\t\tif UserInputService:GetFocusedTextBox() ~= nil then", "\t\t\tif false then", CLI),
    ("V22 YOUR BEST in the name column only", VI, "\tbestCells[2].Position = UDim2.fromScale(rank.x, 0)\n", "", CLI),
    ("V23 the layout with a glyph width of its own", VI, "p.slot.AbsoluteSize.Y, Card.GLYPH)", "p.slot.AbsoluteSize.Y, 0.5)", CLI),
    ("V24 the best line never hidden", VI, "\tp.best.frame.Visible = best ~= nil\n", "", CLI),
    ("V18 a long name not cut", VI, "\tl.TextTruncate = Enum.TextTruncate.AtEnd\n", "", CLI),
    # the place
    ("X1 the server's Main never starts the relay", SMAIN, 'require("./BoardRelay").start()', 'local _ = require("./BoardRelay")', PLC),
    ("X2 Board requires outside Logic", BO, "local Board = {}\n", "local _ = require(\"../Games\")\nlocal Board = {}\n", PLC),
    ("X3 no Boards remote", PJ, ',\n        "Boards": { "$className": "RemoteEvent" }', "", PLC),
    ("X4 the client's Main starts the view twice", CMAIN, 'require("./BoardsView").start()', 'require("./BoardsView").start()\nrequire("./BoardsView").start()', PLC),
    ("X5 not in the map", AM, "### Board (f0206)", "### Boards", PLC),
    ("X6 the view requires the arcade's Boards", VI, 'local HiscoreGames = require("@game/ReplicatedStorage/Arcade/HiscoreGames")',
     'local HiscoreGames = require("@game/ReplicatedStorage/Arcade/HiscoreGames")\nlocal _ = require("@game/ServerStorage/Arcade/Boards")', PLC),
    # Logic text
    ("M1 a comment says game", BO, "-- Board (f0206): a card's hiscores.", "-- Board (f0206): a card's hiscores, per game.", META),
]

CV = [
    ("CV1 the view requires a sibling adapter a later issue adds", VI, 'local CarouselView = require("./CarouselView")', 'local CarouselView = require("./CarouselView")\nlocal _ = require("./PlayButtons")', CLI + PLC),
    ("CV2 the server's answer gains a field", RE, "Board.status(snap), mineOf(slot, name))", "Board.status(snap), mineOf(slot, name), \"extra\")", SRV + BUD),
    ("CV3 the view gains a field", BO, "return { header = Board.header(progress), lines = lines, note = note, best = best }", "return { header = Board.header(progress), lines = lines, note = note, best = best, title = \"\" } :: any", BRD + CLI),
    ("CV4 the relay requires one more arcade module", RE, 'local Boards = require("@game/ServerStorage/Arcade/Boards")', 'local Boards = require("@game/ServerStorage/Arcade/Boards")\nlocal _ = require("@game/ServerStorage/Arcade/Receipts")', SRV + PLC),
    ("CV5 the client's Main starts the view before the carousel", CMAIN, 'require("./CarouselView").start()\nrequire("./BoardsView").start()', 'require("./BoardsView").start()\nrequire("./CarouselView").start()', PLC),
    ("CV7 Board requires Card for its text model", BO, "local Board = {}\n", "local _Card = require(\"./Card\")\nlocal Board = {}\n", BRD + PLC),
    ("CV6 the tab bar's buttons in a list layout", VI, '\t\tb.Position = UDim2.fromScale((i - 1) / #Board.TABS, 0)', '\t\tb.Position = UDim2.new((i - 1) / #Board.TABS, 0, 0, 0)', CLI),
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
    failed = re.search(r"(?<!\d)0 failed", last) is None
    if correct:
        return ("ok (green)" if not failed else "RED: " + last), not failed
    if not failed:
        return "SURVIVED", False
    msgs = [l for l in lines if l.startswith("     ")]
    if any("expected" in m or "read at" in m for m in msgs) and not any(("attempt to" in m or "Unknown require" in m or "syntax" in m.lower()) for m in msgs):
        return "killed", True
    return "ERROR (not an assertion): " + (msgs[0].strip() if msgs else last), False


def main():
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    subprocess.run(["git", "-C", CLONE, "checkout", "--quiet", HEAD], check=True)
    item = os.path.join(HOME, ".tracker", "issues", "f0206")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    bases = [
        os.path.join(CLONE, "arcade", ".tracker", "issues", "f0201", "experiments", "prototype.patch"),
        os.path.join(HOME, ".tracker", "issues", "f0205", "experiments", "f0199-standin.patch"),
        os.path.join(HOME, ".tracker", "issues", "f0205", "experiments", "prototype.patch"),
        os.path.join(CLONE, "arcade", ".tracker", "issues", "f0197", "experiments", "prototype.patch"),
        os.path.join(HERE, "prototype.patch"),
    ]
    for patch in bases:
        # three-way, and each conflict resolved by keeping both sides, the tree's first: the rule the design states for
        # lines two issues add at one place (f0205's map line beside f0208's `Play -> Card`, which main already has)
        subprocess.run(["git", "-C", CLONE, "apply", "-3", patch], capture_output=True, text=True, timeout=120)
        listed = subprocess.run(["git", "-C", CLONE, "diff", "--name-only", "--diff-filter=U"], capture_output=True, text=True, timeout=60).stdout.split()
        for rel in listed:
            f = os.path.realpath(os.path.join(CLONE, rel))
            if not f.startswith(TMP + os.sep):
                sys.exit(f"refusing to write outside the clone: {f}")
            text = open(f).read()
            text = re.sub(r"^<<<<<<< [^\n]*\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]*\n", lambda m: m.group(1) + m.group(2), text, flags=re.S | re.M)
            open(f, "w").write(text)
        subprocess.run(["git", "-C", CLONE, "add", "-A"], check=True, timeout=60)
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
        if src.count(old) != 1:
            print(mid.ljust(64), "ANCHOR", src.count(old), repr(old[:50]), flush=True)
            bad += 1
            continue
        open(f, "w").write(src.replace(old, new))
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
