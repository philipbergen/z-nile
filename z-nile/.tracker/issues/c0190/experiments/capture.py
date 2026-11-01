# c0190: capture c0183's step-2 issues (the arcade block's "Tracker work", Step 2) in their projects. Run from the root
# of a capture worktree (z-ticket skill) cut from origin/main after c0183 merged, after `./zn sync`:
#   python3 <this file> create          -> ./zn new issue for each issue not yet captured (found by its slug in its
#                                          project's root, so a rerun from any worktree never makes a duplicate)
#   python3 <this file> fill            -> each document's title, Problem, Non-goals and Solution, and depends_on (keys
#                                          resolved to ids); c0188 and f0187 gain their portal dependencies
#   python3 <this file> subject         -> the capture commit's subject, every id written out (z-ticket lesson
#                                          capture-subject-lists-every-id)
#   python3 <this file> spend <minutes> -> ./zn spend <id> --phase capture for each, the minutes shared evenly
#   python3 <this file> digests         -> the SHA-256 of each issue's title line and Problem to Solution (ids masked),
#                                          as check.sh's AC6 computes them from the landed documents (prep pins them)
import hashlib, pathlib, re, subprocess, sys

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

ARCH = "arcade/.tracker/architecture.md"
SECTION = {
    "snake": "Game design: Snake (`snake/`)",
    "invaders": "Game design: Invaders (`invaders/`)",
    "asteroids": "Game design: Asteroids (`asteroids/`)",
    "portal": "Design: Portal (`portal/`)",
}

# key, project, type, slug, title, depends_on (keys of this list or ids), design file, the parts of it this issue owns,
# outcomes, non-goals. Every part of each design has one owner (c0190's Design, item 2's ownership table).
I = [
 dict(key="A1", project="arcade", type="f", slug="hiscores-with-revives", title="Hiscores with revives", deps=["c0184"],
  file=ARCH, parts="**Technical skeleton**, \"What moves into arcade\", item 1 (Hiscores)",
  outs=["A shared Hiscores feature (pure Logic, from pickman's `Logic/Hiscores`) and one generic server `Boards` adapter, used by every place.",
        "Each game has its own stores (per-game store names); pickman keeps today's names, so its boards keep their rows.",
        "Every board row records and shows **revives used** (paid revives of that run); rows written before it show as no revives.",
        "Each game's progress figure is stored with the row (Pickman level, Snake map, Invaders wave, Asteroids wave)."],
  ngs=["Pickman switching to it: K1 (Switch to arcade hiscores).", "The portal's board screens: P2 (Boards per game).",
       "Each game's runs reaching its boards: S5, I4 and T4."]),
 dict(key="K1", project="pickman", type="c", slug="switch-to-arcade-hiscores", title="Switch to arcade hiscores", deps=["A1", "c0185"],
  file=ARCH, parts="**Technical skeleton**, \"Pickman migrates one feature at a time\", for Hiscores",
  outs=["Pickman's game place and its submit path use arcade's Hiscores and Boards; pickman's own copy is deleted.",
        "No behaviour change for players: the same boards, the same rows (plus revives once f0186 lands)."],
  ngs=["The revives figure itself: f0186 (Boards show revives)."]),
 dict(key="A2", project="arcade", type="f", slug="shared-travel", title="Shared travel", deps=["c0184"],
  file=ARCH, parts="**Technical skeleton**, \"What moves into arcade\", item 2 (Travel), and from **Places and publishing** the place-id attributes every place reads",
  outs=["Travel (teleport request, timeout, cool-down, place-id checks; pickman's `Logic/Travel`) moves into arcade so every place teleports by the same rules, to and from the portal.",
        "A place learns every other place's id from attributes (`PortalPlaceId`, `PickmanPlaceId`, `SnakePlaceId`, `InvadersPlaceId`, `AsteroidsPlaceId`; 0 means not published)."],
  ngs=["The publish that writes those attributes: Z3 (N-place deploy).", "Pickman switching to it: K2 (Switch to arcade travel)."]),
 dict(key="K2", project="pickman", type="c", slug="switch-to-arcade-travel", title="Switch to arcade travel", deps=["A2", "c0185"],
  file=ARCH, parts="**Technical skeleton**, \"Pickman migrates one feature at a time\", for Travel",
  outs=["Pickman's lobby and game place use arcade's Travel; pickman's `Logic/Travel` is deleted; no behaviour change."],
  ngs=["`LobbyPlaceId` becoming `PortalPlaceId`: f0187 (Game over returns to portal)."]),
 dict(key="A3", project="arcade", type="f", slug="paid-play-and-receipts", title="Paid play and receipts", deps=["c0184"],
  file=ARCH, parts="**Technical skeleton**, \"What moves into arcade\", item 3 (PaidPlay and Receipts), and **Unknowns**, E4",
  outs=["The cost model, shared by every game: **one free game per hour per game** per player, then **1 Robux per game**, and a **revive** (3 new lives, keeping score and progress) for **1 Robux**.",
        "The price is shown as **5 R$ struck through, on sale for 1 R$** (the charge is 1 R$); the badge text sits in one config table.",
        "Purchases go through Developer Products; the server grants exactly once (an idempotent `ProcessReceipt` installed in every place, with a receipt ledger; E4 settles a receipt retried in another place); the client never decides a grant; TeleportData is never trusted for an entitlement.",
        "The free-hour claim is atomic per player and game.",
        "**Playtests never charge**: the purchase screens show and accept their controls exactly as live, and nothing is deducted (f0145).",
        "Each run counts its revives for the boards (A1)."],
  ngs=["Each game's own revive screen: S5, I4 and T4.", "The portal's badge, timer and play buttons: P1, P3 and P4.",
       "Pickman switching to it: K3 (Switch to arcade paid play).", "The live publish of the products: f0169."]),
 dict(key="K3", project="pickman", type="c", slug="switch-to-arcade-paid-play", title="Switch to arcade paid play", deps=["A3", "f0145", "f0186", "c0185"],
  file=ARCH, parts="**Technical skeleton**, \"Pickman migrates one feature at a time\", for PaidPlay and Receipts",
  outs=["Pickman's paid play (f0145, with f0186's revives and per-game free hour) runs on arcade's PaidPlay and Receipts, with no pickman-only copy."],
  ngs=["f0145 (Paid play and continues) and f0186 (Boards show revives) themselves."]),
 dict(key="A4", project="arcade", type="f", slug="input-and-look-cores", title="Input and look cores", deps=["c0184"],
  file=ARCH, parts="**Technical skeleton**, \"What moves into arcade\", items 4 to 6 (Rng, the Pad and Touch cores, first-person Look)",
  outs=["The game-neutral parts of input and first-person look move into arcade: a seeded Rng, the gamepad fold (Pad), the touch zones and swipes (Touch), and first-person free look and smoothing (Look).",
        "Every game supports keyboard, gamepad and touch for every feature (pickman's rule, f0146), from these cores; each game keeps its own key map."],
  ngs=["Each game's key map and controls: S3, I3 and T3.", "Pickman switching to them: K4 (Switch to arcade input cores).",
       "The Session clock and intent limiter (they move only when Snake needs them: S2)."]),
 dict(key="K4", project="pickman", type="c", slug="switch-to-arcade-input-cores", title="Switch to arcade input cores", deps=["A4", "c0185"],
  file=ARCH, parts="**Technical skeleton**, \"Pickman migrates one feature at a time\", for Rng, Pad, Touch and Look",
  outs=["Pickman uses arcade's Rng, Pad, Touch and Look cores; its own copies of the generic parts are deleted; no behaviour change."],
  ngs=[]),
 dict(key="P1", project="portal", type="f", slug="game-carousel", title="Game carousel", deps=["A3", "c0185"],
  file="portal", parts="\"A carousel with one card per game\", and from \"Each card shows\" the title, tagline and preview and the price badge's sale text; \"Open item for the user\"",
  outs=["The portal shows **a carousel with one card per game** (Pickman, Snake, Invaders, Asteroids), scrolled with A/D, the arrows, the mouse wheel, a swipe or the gamepad's shoulders; Enter or A plays.",
        "Each card shows the title, a tagline and a live 3-D preview or art, and **the price badge: \"5 R$\" struck through, then \"1 R$ SALE\"**, or \"FREE GAME READY\" when that game's free game is due (P3 decides when).",
        "A card whose place is not published (id 0) shows \"coming soon\".",
        "The badge text sits in one config table, because \"permanent sale\" pricing is an open decision for the user."],
  ngs=["The boards on the card: P2 (Boards per game).", "The countdown to the next free game: P3 (Free game timer).", "The play buttons and purchase: P4 (Play buttons)."]),
 dict(key="P2", project="portal", type="f", slug="boards-per-game", title="Boards per game", deps=["A1", "P1"],
  file="portal", parts="from \"Each card shows\", the game's hiscores; **Unknowns** E3 is in `arcade/.tracker/architecture.md`",
  outs=["Each card shows **the game's hiscores** with tabs All-time / Today / This week: rank, name, score, the game's progress figure and **revives used** (\"—\" for none), and the \"your best\" line below.",
        "The portal reads every game's boards within Roblox's DataStore budget (E3: a cache or a snapshot per board)."],
  ngs=["The boards' store and rows: A1.", "The rest of the card: P1, P3 and P4."]),
 dict(key="P3", project="portal", type="f", slug="free-game-timer", title="Free game timer", deps=["A3", "P1"],
  file="portal", parts="from \"Each card shows\", \"FREE GAME READY\" and \"Next free game in mm:ss\"",
  outs=["Each card counts down to that game's next free game, per player (\"Next free game in mm:ss\"), and flips to FREE GAME READY when it is due."],
  ngs=["The free-hour rule itself: A3.", "The rest of the card: P1, P2 and P4."]),
 dict(key="P4", project="portal", type="f", slug="play-buttons", title="Play buttons", deps=["A2", "A3", "P1"],
  file="portal", parts="from \"Each card shows\", the play buttons, and \"Purchase\"; the portal's side of the games' \"Pairing\"; **Unknowns** E5 is in `arcade/.tracker/architecture.md`",
  outs=["PLAY on a card starts that game: free when the hour allows, else the 1 R$ play product (5 R$ struck through on the button); the server records the entitlement and teleports; the game place consumes it on arrival; TeleportData is never trusted.",
        "**ARENA** on Snake joins a shared arena; **2 PLAYERS** on Invaders and Asteroids puts the player on a waiting card until a second player in the portal server (or an invited friend) joins, then both teleport together to a reserved server (E5, tested on Beta with I2 and T2).",
        "Playtests never charge."],
  ngs=["The arrival side (a shared arena, a 2-player match started for the party): S2, I2 and T2.", "The revive product, bought in each game place: S5, I4 and T4."]),
 dict(key="P5", project="portal", type="f", slug="portal-start-place", title="Portal start place", deps=["Z3", "P4"],
  file="portal", parts="\"The experience's start place\"",
  outs=["The portal is the experience's start place (Beta first), and every game's game over returns there."],
  ngs=["Retiring pickman's lobby: c0188 (Retire lobby place).", "Each game's return to the portal: f0187, S5, I4 and T4."]),
 dict(key="Z3", project="portal", type="c", slug="n-place-deploy", title="N-place deploy", deps=["c0184"],
  file=ARCH, parts="**Technical skeleton**, **Places and publishing**",
  outs=["The Beta publish handles every place of the experience from one manifest (`portal/experience.json`: each place's project file and env var), not pickman's fixed lobby and game pair.",
        "Every place gets every place id as attributes (`PortalPlaceId`, `PickmanPlaceId`, `SnakePlaceId`, `InvadersPlaceId`, `AsteroidsPlaceId`); `LobbyPlaceId` becomes `PortalPlaceId`; the old `ROBLOX_BETA_GAME_PLACE_ID` is still accepted for pickman.",
        "The deploy scripts and the runtime-test runner (`--place <name>`) move to `portal/scripts/`."],
  ngs=["The live (production) publish: f0169, which builds on this.", "Reading the attributes: A2 (Shared travel)."]),
 dict(key="S1", project="snake", type="f", slug="arena-maps-growth", title="Arena, maps and growth", deps=["c0184"],
  file="snake", parts="**Arena and view** (the grid, its border and its size for N players), **Movement** (speed, the turns and their buffer; not Boost, not the keys), **Food** (apples), **Maps** (not \"Shared arena\"), and **Death, lives and revives** (death, lives and respawn; not the revive offer)",
  outs=["The Snake rules in pure Logic: the grid arena sized from the player count, movement with two buffered turns, apples and growth, death on walls, borders and bodies (heads meeting kill both), lives and respawn.",
        "**Maps**: map 1 is empty and **map k has k−1 straight walls**, horizontal or vertical, that **never connect** (one empty tile all round, diagonals included); reaching the goal length ends the map and the next one starts."],
  ngs=["Boost, golden apples and crumbs: S4.", "The shared arena: S2.", "The view, input, HUD and the place: S3.", "Boards, the revive offer and the portal return: S5."]),
 dict(key="S2", project="snake", type="f", slug="shared-snake-arena", title="Shared snake arena", deps=["c0184"],
  file="snake", parts="**Maps** (\"Shared arena\") and **Players** (\"Arena\"); in `arcade/.tracker/architecture.md`, **Unknowns** E6 and the Session clock and intent limiter",
  outs=["**N players** (up to a tuning cap, 24 to start) share one arena whose size grows with the player count; the first to the goal length wins the map and everyone moves on together; joining mid-map spawns at the safest tile.",
        "The arena's server session, and a player arriving from the portal's ARENA button joins it.",
        "A load experiment (E6) sets the cap: step cost and snapshot bytes per tick.",
        "If the arena needs pickman's Session clock or intent limiter, they move into arcade first (\"The Session clock and intent limiter move only when Snake needs them\")."],
  ngs=["The rules every arena runs: S1 and S4.", "The ARENA button: P4."]),
 dict(key="S3", project="snake", type="f", slug="snake-first-person-view", title="Snake first person view", deps=["S1", "A4", "c0185"],
  file="snake", parts="**Arena and view** (the camera, the minimap and the eased turn), **Movement** (the keys, gamepad and touch), and **Players** (\"Solo\", and each snake's colour, name and the HUD)",
  outs=["The game seen from the snake's head, with the minimap, the eased turn, the HUD (length / goal, map, lives, score, top 3), and every input: A/D, the arrows to look, Space to boost; gamepad; touch LEFT, RIGHT and BOOST.",
        "The Snake place: its project file, and the server session that runs each solo game in its own arena (pickman's solo-instances model) and replicates it to the player."],
  ngs=["The rules: S1 and S4.", "The shared arena: S2.", "Boards, revives and the portal return: S5."]),
 dict(key="S4", project="snake", type="f", slug="boost-golden-apples-crumbs", title="Boost, golden apples and crumbs", deps=["S1"],
  file="snake", parts="**Movement** (\"Boost\") and **Food** (\"Golden apple\" and \"Crumbs\")",
  outs=["Boost (double speed, sheds a segment every 0.5 s, never below 4), golden apples (+3, every 20 s for 6 s) and crumbs from a dead snake's body."],
  ngs=["The rest of the rules: S1."]),
 dict(key="S5", project="snake", type="f", slug="snake-scores-and-revives", title="Snake scores and revives", deps=["S1", "A1", "A2", "A3", "c0185"],
  file="snake", parts="**Death, lives and revives** (the game over and the revive offer) and **Players** (\"Every run, solo or arena, goes to Snake's boards\")",
  outs=["Snake's runs go to Snake's boards (score, map, revives); game over offers the 1 R$ revive (3 lives, keeping score and map; 10 s in an arena while play goes on); game over returns to the portal."],
  ngs=["The boards' store: A1.", "Paid play: A3."]),
 dict(key="I1", project="invaders", type="f", slug="invaders-classic-rules", title="Invaders classic rules", deps=["c0184"],
  file="invaders", parts="**The field and view** (\"The rules are 2-D\") and **Solo (the classic)** (the revive's restart of the wave as a rule; not the offer)",
  outs=["Solo Space Invaders in pure Logic: the 5 × 11 formation and its march, shots (one for the player, up to three for the aliens), four erodible barriers, the mystery ship, lives with the extra at 1,500, invasion as game over, and the waves."],
  ngs=["Two players: I2.", "The view, input and the place: I3.", "Boards, the revive offer and the portal return: I4."]),
 dict(key="I2", project="invaders", type="f", slug="invaders-two-players", title="Invaders two players", deps=["c0184"],
  file="invaders", parts="**2 players (the user's design)**, with the game's side of \"Pairing\"; **Unknowns** E5 is in `arcade/.tracker/architecture.md`",
  outs=["Two players at opposite ends of a field twice as deep; **each wave flies in from the side and splits into two groups**, one toward each player; **a shot crosses the whole field and can hit the other player's barriers** (not the player, by default); own scores, lives and revives; a lone survivor plays on.",
        "A party arriving in a reserved server from the portal's 2 PLAYERS starts one 2-player match (E5, on Beta, with P4)."],
  ngs=["The solo rules: I1.", "The portal's waiting card and teleport: P4."]),
 dict(key="I3", project="invaders", type="f", slug="invaders-cannon-view", title="Invaders cannon view", deps=["I1", "A4", "c0185"],
  file="invaders", parts="**The field and view** (the camera, the radar and the controls)",
  outs=["The cannon's first-person view and field radar, with every input: A/D or the arrows and Space; gamepad; touch LEFT, RIGHT and FIRE.",
        "The Invaders place: its project file, and the server session that runs each solo game and replicates it to the player."],
  ngs=["The rules: I1 and I2.", "Boards, revives and the portal return: I4."]),
 dict(key="I4", project="invaders", type="f", slug="invaders-scores-and-revives", title="Invaders scores and revives", deps=["I1", "A1", "A2", "A3", "c0185"],
  file="invaders", parts="**Solo (the classic)** (\"Invasion\": the revive offer) and the boards every game keeps",
  outs=["Invaders' runs go to its boards (score, wave, revives); game over (including invasion) offers the 1 R$ revive; game over returns to the portal."],
  ngs=["The boards' store: A1.", "Paid play: A3."]),
 dict(key="T1", project="asteroids", type="f", slug="asteroids-classic-rules", title="Asteroids classic rules", deps=["c0184"],
  file="asteroids", parts="**The field and view** (\"The rules are 2-D\") and **Rules (the classic)** (not the revive offer)",
  outs=["Solo Asteroids in pure Logic: the wrap-around field, the ship's turn, thrust and drag, up to four shots, rocks that split large → medium → small, both saucers, hyperspace with its risk, lives with an extra every 10,000, and the waves."],
  ngs=["Two players: T2.", "The view, input and the place: T3.", "Boards, the revive offer and the portal return: T4."]),
 dict(key="T2", project="asteroids", type="f", slug="asteroids-two-players", title="Asteroids two players", deps=["c0184"],
  file="asteroids", parts="**2 players**, with the game's side of \"Pairing\"",
  outs=["Two ships share one field from opposite sides with 1.5 × the rocks; own scores, lives and revives; no friendly fire by default, ships bounce; a lone survivor plays on.",
        "A party arriving in a reserved server from the portal's 2 PLAYERS starts one 2-player game (with I2's E5 result)."],
  ngs=["The solo rules: T1.", "The portal's waiting card and teleport: P4."]),
 dict(key="T3", project="asteroids", type="f", slug="asteroids-cockpit-view", title="Asteroids cockpit view", deps=["T1", "A4", "c0185"],
  file="asteroids", parts="**The field and view** (the cockpit camera, the wrap drawn tiled, the radar, the rear-danger glow and the controls); **Unknowns** E7 is in `arcade/.tracker/architecture.md`",
  outs=["The cockpit view with the wrap-around drawn tiled at true distance, the radar and the rear-danger glow, with every input: A/D, W, Space, Shift, the arrows to look; gamepad; touch rotate, THRUST, FIRE and HYPER. A Studio prototype settles the tiled-field cost (E7).",
        "The Asteroids place: its project file, and the server session that runs each solo game and replicates it to the player."],
  ngs=["The rules: T1 and T2.", "Boards, revives and the portal return: T4."]),
 dict(key="T4", project="asteroids", type="f", slug="asteroids-scores-and-revives", title="Asteroids scores and revives", deps=["T1", "A1", "A2", "A3", "c0185"],
  file="asteroids", parts="**Rules (the classic)** (\"Game over\": the revive offer) and the boards every game keeps",
  outs=["Asteroids' runs go to its boards (score, wave, revives); game over offers the 1 R$ revive; game over returns to the portal."],
  ngs=["The boards' store: A1.", "Paid play: A3."]),
]
# the plan's order "Z3 and P5 -> retire the lobby": pickman's issues captured with c0183 gain the portal's ids
EXTRA = [("c0188", ["P5", "Z3"]), ("f0187", ["Z3"])]

IDS = re.compile(r"^[fdc]\d{4}$")


def pointer(e):
    if e["file"] == ARCH:
        where = f"`{ARCH}`"
    else:
        where = f"`{e['file']}/.tracker/game-design.md`, section **{SECTION[e['file']]}**"
    return (f"The approved design is {where} (c0183). This issue owns these parts of it, as they are said there: "
            f"{e['parts']}. The rest belongs to the sibling issues named under Non-goals.")


KEY = re.compile(r"\b([AKPZSIT][1-5])\b")


def ids_for_keys(text, idof):
    """the list's keys (S4, A1, ...) in text written as the issues' ids"""
    return KEY.sub(lambda m: idof.get(m.group(1), m.group(1)), text)


def body(e):
    pr = USER + "\n\n" + pointer(e) + "\n\nWhat should happen:\n" + "\n".join("- " + o for o in e["outs"])
    ng = "\n".join("- " + n for n in e["ngs"]) if e["ngs"] else "- None: the issue is the whole of its part."
    return f"## Problem\n{pr}\n\n## Non-goals\n{ng}\n\n## Solution\n<!-- The approach in one paragraph. -->\n"


def found(e):
    """the document of e's issue in its project's root (any state), or None; refuses two"""
    root = pathlib.Path(f"{e['project']}/.tracker/issues")
    hits = [p for p in root.glob("**/*.md") if IDS.match(p.stem) and p.parent.name == p.stem
            and re.search(rf"^slug: {re.escape(e['slug'])}$", p.read_text(), re.M)]
    if len(hits) > 1:
        sys.exit(f"{e['key']}: {len(hits)} issues with slug {e['slug']}: {hits}")
    return hits[0] if hits else None


def doc_of(i):
    out = subprocess.run(["./zn", "find", i], capture_output=True, text=True, check=True).stdout.strip()
    return pathlib.Path(out) / f"{i}.md"


def setdeps(p, add):
    t = p.read_text()
    m = re.search(r"^depends_on: \[(.*)\]$", t, re.M)
    have = [x.strip() for x in m.group(1).split(",") if x.strip()]
    new = have + [d for d in add if d not in have]
    p.write_text(t[:m.start()] + "depends_on: [" + ", ".join(new) + "]" + t[m.end():])


def section(p):
    """the title line and the text from ## Problem up to ## Design, every id masked (ids are allocated at capture time),
    exactly as check.sh's AC6 builds it"""
    t = p.read_text()
    title = re.search(r"^title: .*$", t, re.M).group(0)
    return re.sub(r"[fdcR]\d{4}", "ID", title + "\n" + t[t.index("## Problem\n"):t.index("## Design\n")])


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "create":
        for e in I:
            if found(e):
                continue
            out = subprocess.run(["./zn", "new", "issue", e["type"], e["slug"], "--project", e["project"], "--desc", e["title"]],
                                 capture_output=True, text=True)
            if out.returncode:
                sys.exit(f"{e['key']}: {out.stderr}{out.stdout}")
            print(e["key"], out.stdout.strip())
    elif cmd == "fill":
        docs = {e["key"]: found(e) for e in I}
        missing = [k for k, p in docs.items() if p is None]
        if missing:
            sys.exit(f"not created: {missing}")
        idof = {k: p.stem for k, p in docs.items()}
        for e in I:
            p = docs[e["key"]]
            t = p.read_text()
            t = re.sub(r"^title: .*$", "title: " + e["title"], t, count=1, flags=re.M)
            t = re.sub(r"^# ([fdc]\d{4}): .*$", lambda m: f"# {m.group(1)}: {e['title']}", t, count=1, flags=re.M)
            t = t[:t.index("## Problem\n")] + ids_for_keys(body(e), idof) + "\n" + t[t.index("## Design\n"):]
            p.write_text(t)
            setdeps(p, [idof.get(d, d) for d in e["deps"]])
            print("filled", e["key"], p)
        for i, keys in EXTRA:
            p = doc_of(i)
            if not re.search(r"^design: draft$", p.read_text(), re.M) or "/active/" in str(p) or "/done/" in str(p):
                sys.exit(f"{i} is no longer a draft backlog issue: stop and escalate (c0190 Design, item 1)")
            setdeps(p, [idof[k] for k in keys])
            print("depends", i, [idof[k] for k in keys])
    elif cmd == "subject":
        print("tracker: new " + " ".join(found(e).stem for e in I))
    elif cmd == "spend":
        each = round(float(sys.argv[2]) / len(I), 1)
        for e in I:
            subprocess.run(["./zn", "spend", found(e).stem, "--phase", "capture", "--time", str(each)], check=True)
    elif cmd == "digests":
        for e in I:
            print(hashlib.sha256(section(found(e)).encode()).hexdigest(), e["project"], e["slug"])
    else:
        sys.exit("usage: create | fill | subject | spend <minutes> | digests")
