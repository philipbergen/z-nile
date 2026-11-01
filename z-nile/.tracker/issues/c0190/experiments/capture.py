# c0190: capture c0183's step-2 issues (the arcade block's "Tracker work", Step 2) in their projects. Run from the root
# of a capture worktree (z-ticket skill) cut from origin/main after c0183 merged:
#   python3 <this file> create   -> ./zn new issue for each (each stub publishes at once); ids kept in .cache/c0190-ids.json
#   python3 <this file> fill     -> writes each Problem and Non-goals, and depends_on (ids resolved from the keys)
#   python3 <this file> subject  -> prints the capture commit subject, every id written out (z-ticket lesson
#                                   capture-subject-lists-every-id)
# create is resumable: a key already in the ids file is skipped, so a failure part-way is rerun, never duplicated.
import json, pathlib, re, subprocess, sys
USER = ('The user, 2026-10-31: "I want to branch out into multiple games, they will each have their own directory in the '
        'project: first person snake, first person asteroids. I also want a new project for a landing portal where you can '
        'scroll between the games and see the highscores for each, the same cost model remains but it shoudl show 5 robux '
        'for each game witha slash through showing it is currently on sale for 1 robux. highscores shoudl show how many '
        'revives were used. I want you to design a full fun playable game for both of those two new game ideas. I also want '
        'both snake and asteroids to be a two player game, snakes can even be n-player up to a high number just make the '
        'wold bigger. Snakes should have maps that once you have reached a certain length the game ends and we move to a new '
        'map, the first is empty, then one wall somewhere in the middle, then two, then three and so on. The walls can be '
        'vertical and horizontal but do not connect. for asteroids we could have a two player version where each player is '
        'attacking the aliens from opposing sides. You can shoot each other\'s barriers. the aliens would then come in from '
        'the side and and split into two groups that move toward either player". Then: "Add a third game first person '
        'asteroids." Decided with the user (2026-10-31): the 2-player aliens game is pure Space Invaders (`invaders`); '
        'Asteroids is its own game (`asteroids`); one Roblox experience with the portal as start place, replacing pickman\'s '
        'lobby; every board shows revives used; one free game per hour per game.')
GD = lambda p, s: f"The approved design is `{p}/.tracker/game-design.md`, section **{s}** (c0183); it is binding, and this issue builds exactly what it says there."
ARCH = "The library's design is `arcade/.tracker/architecture.md` (c0183), Technical skeleton."
I = [
 # key, project, type, slug, title, deps(keys or ids), outcomes, nongoals
 ("A1","arcade","f","hiscores-with-revives","Hiscores with revives",[],
  ["A shared Hiscores feature (pure Logic, from pickman's `Logic/Hiscores`) and one generic server `Boards` adapter, used by every place.",
   "Each game has its own stores (per-game store names); pickman keeps today's names, so its boards keep their rows.",
   "Every board row records and shows **revives used** (paid continues of that run); rows written before it show as no revives.",
   "Each game's progress figure is stored with the row (Pickman level, Snake map, Invaders wave, Asteroids wave)."],
  ["Pickman switching to it: its own chore.", "The portal's board screens: portal issues."]),
 ("K1","pickman","c","switch-to-arcade-hiscores","Switch to arcade hiscores",["A1"],
  ["Pickman's game place and its submit path use arcade's Hiscores and Boards; pickman's own copy is deleted.",
   "No behaviour change for players: the same boards, the same rows (plus revives once f0186 lands)."],
  ["The revives figure itself: f0186."]),
 ("A2","arcade","f","shared-travel","Shared travel",[],
  ["Travel (teleport request, timeout, cool-down, place-id checks; pickman's `Logic/Travel`) moves into arcade so every place teleports by the same rules, to and from the portal.",
   "A place learns every other place's id from attributes (`PortalPlaceId`, `PickmanPlaceId`, `SnakePlaceId`, `InvadersPlaceId`, `AsteroidsPlaceId`; 0 means not published)."],
  ["The publish that writes those attributes: portal's deploy manifest issue."]),
 ("K2","pickman","c","switch-to-arcade-travel","Switch to arcade travel",["A2"],
  ["Pickman's lobby and game place use arcade's Travel; pickman's `Logic/Travel` is deleted; no behaviour change."],[]),
 ("A3","arcade","f","paid-play-and-receipts","Paid play and receipts",[],
  ["The cost model, shared by every game: **one free game per hour per game** per player, then **1 Robux per game**, and a **revive** (3 new lives / a new start as each game defines, keeping score and progress) for **1 Robux**.",
   "The price is shown as **5 R$ struck through, on sale for 1 R$** (the charge is 1 R$); the badge text sits in one config table.",
   "Purchases go through Developer Products; the server grants exactly once (an idempotent `ProcessReceipt` installed in every place, with a receipt ledger); the client never decides a grant; TeleportData is never trusted for an entitlement.",
   "The free-hour claim is atomic per player and game.",
   "**Playtests never charge**: the purchase screens show and accept their controls exactly as live, and nothing is deducted (f0145).",
   "Each run counts its revives for the boards (A1)."],
  ["Each game's own revive screen: that game's issues.", "The live publish of the products: f0169."]),
 ("K3","pickman","c","switch-to-arcade-paid-play","Switch to arcade paid play",["A3","f0145","f0186"],
  ["Pickman's paid play (f0145, with f0186's revives and per-game free hour) runs on arcade's PaidPlay and Receipts, with no pickman-only copy."],[]),
 ("A4","arcade","f","input-and-look-cores","Input and look cores",[],
  ["The game-neutral parts of input and first-person look move into arcade: a seeded Rng, the gamepad fold (Pad), the touch zones and swipes (Touch), and first-person free look and smoothing (Look).",
   "Every game supports keyboard, gamepad and touch for every feature (pickman's rule, f0146), from these cores; each game keeps its own key map."],
  []),
 ("K4","pickman","c","switch-to-arcade-input-cores","Switch to arcade input cores",["A4"],
  ["Pickman uses arcade's Rng, Pad, Touch and Look cores; its own copies of the generic parts are deleted; no behaviour change."],[]),
 ("P1","portal","f","game-carousel","Game carousel",["A3"],
  ["The portal shows **a carousel with one card per game** (Pickman, Snake, Invaders, Asteroids), scrolled with A/D, the arrows, the mouse wheel, a swipe or the gamepad's shoulders; Enter or A plays.",
   "Each card shows the title, a tagline and a live 3-D preview or art, and **the price badge: \"5 R$\" struck through, then \"1 R$ SALE\"**, or \"FREE GAME READY\" when that game's free hour is available, else \"Next free game in mm:ss\".",
   "A card whose place is not published (id 0) shows \"coming soon\"."],
  ["The boards on the card: P2.", "Playing: P4."]),
 ("P2","portal","f","boards-per-game","Boards per game",["A1","P1"],
  ["Each card shows **the game's hiscores** with tabs All-time / Today / This week: rank, name, score, the game's progress figure and **revives used** (\"—\" for none), and the \"your best\" line below.",
   "The portal reads every game's boards within Roblox's DataStore budget (c0183 E3: cache or snapshot per board)."],[]),
 ("P3","portal","f","free-game-timer","Free game timer",["A3","P1"],
  ["Each card counts down to that game's next free game, per player, and flips to FREE GAME READY when it is due."],[]),
 ("P4","portal","f","play-buttons","Play buttons",["A2","A3","P1"],
  ["PLAY on a card starts that game: free when the hour allows, else the 1 R$ play product (5 R$ struck through on the button); the server records the entitlement and teleports; the game place consumes it on arrival.",
   "**ARENA** on Snake joins a shared arena; **2 PLAYERS** on Invaders and Asteroids puts the player on a waiting card until a second player in the portal server (or an invited friend) joins, then both teleport together to a reserved server.",
   "Playtests never charge."],[]),
 ("P5","portal","f","portal-start-place","Portal start place",["Z3","P4"],
  ["The portal is the experience's start place (Beta first), and every game's game over returns there."],
  ["Retiring pickman's lobby: c0188."]),
 ("Z3","portal","c","n-place-deploy","N-place deploy",[],
  ["The Beta publish handles every place of the experience from one manifest (`portal/experience.json`: each place's project file and env var), not pickman's fixed lobby and game pair.",
   "Every place gets every place id as attributes (`PortalPlaceId`, `PickmanPlaceId`, `SnakePlaceId`, `InvadersPlaceId`, `AsteroidsPlaceId`); `LobbyPlaceId` becomes `PortalPlaceId`; the old `ROBLOX_BETA_GAME_PLACE_ID` is still accepted for pickman.",
   "The deploy scripts and the runtime-test runner (`--place <name>`) move to `portal/scripts/`."],
  ["The live (production) publish: f0169, which builds on this."]),
 ("S1","snake","f","arena-maps-growth","Arena maps and growth",[],
  ["The Snake rules in pure Logic: the grid arena sized from the player count, movement with two buffered turns, apples and growth, death on walls, borders and bodies (heads meeting kill both), lives and respawn.",
   "**Maps**: map 1 is empty and **map k has k−1 straight walls**, horizontal or vertical, that **never connect** (one empty tile all round, diagonals included); reaching the goal length ends the map and the next one starts."],[]),
 ("S2","snake","f","shared-snake-arena","Shared snake arena",["S1"],
  ["**N players** (up to a tuning cap, 24 to start) share one arena whose size grows with the player count; the first to the goal length wins the map and everyone moves on together; joining mid-map spawns at the safest tile.",
   "A load experiment (c0183 E6) sets the cap: step cost and snapshot bytes per tick."],[]),
 ("S3","snake","f","snake-first-person-view","Snake first person view",["S1"],
  ["The game seen from the snake's head, with the minimap, the eased turn, the HUD (length / goal, map, lives, score, top 3), and every input: A/D, the arrows to look, Space to boost; gamepad; touch LEFT, RIGHT and BOOST."],[]),
 ("S4","snake","f","boost-golden-apples-crumbs","Boost golden apples crumbs",["S1"],
  ["Boost (double speed, sheds a segment every 0.5 s, never below 4), golden apples (+3, every 20 s for 6 s) and crumbs from a dead snake's body."],[]),
 ("S5","snake","f","snake-scores-and-revives","Snake scores and revives",["S1","A1","A2","A3"],
  ["Snake's runs go to Snake's boards (score, map, revives); game over offers the 1 R$ revive (3 lives, keeping score and map; 10 s in an arena); game over returns to the portal."],[]),
 ("I1","invaders","f","invaders-classic-rules","Invaders classic rules",[],
  ["Solo Space Invaders in pure Logic: the 5 × 11 formation and its march, shots (one for the player, up to three for the aliens), four erodible barriers, the mystery ship, lives with the extra at 1,500, invasion as game over, and the waves."],[]),
 ("I2","invaders","f","invaders-two-players","Invaders two players",["I1"],
  ["Two players at opposite ends of a field twice as deep; **each wave flies in from the side and splits into two groups**, one toward each player; **a shot crosses the whole field and can hit the other player's barriers** (not the player, by default); own scores, lives and revives; a lone survivor plays on."],[]),
 ("I3","invaders","f","invaders-cannon-view","Invaders cannon view",["I1"],
  ["The cannon's first-person view and field radar, with every input: A/D or the arrows and Space; gamepad; touch LEFT, RIGHT and FIRE."],[]),
 ("I4","invaders","f","invaders-scores-and-revives","Invaders scores and revives",["I1","A1","A2","A3"],
  ["Invaders' runs go to its boards (score, wave, revives); game over (including invasion) offers the 1 R$ revive; game over returns to the portal."],[]),
 ("T1","asteroids","f","asteroids-classic-rules","Asteroids classic rules",[],
  ["Solo Asteroids in pure Logic: the wrap-around field, the ship's turn, thrust and drag, up to four shots, rocks that split large → medium → small, both saucers, hyperspace with its risk, lives with an extra every 10,000, and the waves."],[]),
 ("T2","asteroids","f","asteroids-two-players","Asteroids two players",["T1"],
  ["Two ships share one field from opposite sides with 1.5 × the rocks; own scores, lives and revives; no friendly fire by default, ships bounce; a lone survivor plays on."],[]),
 ("T3","asteroids","f","asteroids-cockpit-view","Asteroids cockpit view",["T1"],
  ["The cockpit view with the wrap-around drawn tiled at true distance, the radar and the rear-danger glow, with every input: A/D, W, Space, Shift, the arrows to look; gamepad; touch rotate, THRUST, FIRE and HYPER. A Studio prototype settles the tiled-field cost (c0183 E7)."],[]),
 ("T4","asteroids","f","asteroids-scores-and-revives","Asteroids scores and revives",["T1","A1","A2","A3"],
  ["Asteroids' runs go to its boards (score, wave, revives); game over offers the 1 R$ revive; game over returns to the portal."],[]),
]
SECTION = {"S":"Game design: Snake (`snake/`)","I":"Game design: Invaders (`invaders/`)","T":"Game design: Asteroids (`asteroids/`)","P":"Design: Portal (`portal/`)"}
def body(e):
    key, proj, typ, slug, title, deps, outs, ngs = e
    ref = GD(proj, SECTION[key[0]]) if key[0] in SECTION else ARCH
    pr = USER + "\n\n" + ref + "\n\nWhat should happen:\n" + "\n".join("- " + o for o in outs)
    ng = "\n".join("- " + n for n in ngs) if ngs else "<!-- Explicit scope fences. Anything tempting that belongs to another issue. -->"
    return f"## Problem\n{pr}\n\n## Non-goals\n{ng}\n\n## Solution\n<!-- The approach in one paragraph. -->\n"
if __name__ == "__main__":
    ids = pathlib.Path(".cache/c0190-ids.json")
    ids.parent.mkdir(exist_ok=True)
    if sys.argv[1] == "create":
        got = json.loads(ids.read_text()) if ids.exists() else {}
        for e in I:
            if e[0] in got: continue
            out = subprocess.run(["./zn","new","issue",e[2],e[3],"--project",e[1],"--desc",e[4]],capture_output=True,text=True)
            if out.returncode: sys.exit(f"{e[0]}: {out.stderr}")
            got[e[0]] = out.stdout.strip(); ids.write_text(json.dumps(got, indent=1)); print(e[0], got[e[0]])
    elif sys.argv[1] == "fill":
        got = json.loads(ids.read_text())
        idof = {k: re.search(r"([fdc]\d{4})\.md$", v).group(1) for k, v in got.items()}
        for e in I:
            p = pathlib.Path(got[e[0]]); t = p.read_text()
            t = t[:t.index("## Problem\n")] + body(e) + "\n" + t[t.index("## Design\n"):]
            deps = [idof.get(d, d) for d in e[5]]
            if deps: t = t.replace("depends_on: []", "depends_on: [" + ", ".join(deps) + "]", 1)
            p.write_text(t); print("filled", e[0], p)
    elif sys.argv[1] == "subject":
        got = json.loads(ids.read_text())
        idof = [re.search(r"([fdc]\d{4})\.md$", got[e[0]]).group(1) for e in I]
        print("tracker: new " + " ".join(idof))
    else:
        sys.exit("usage: create | fill | subject")
