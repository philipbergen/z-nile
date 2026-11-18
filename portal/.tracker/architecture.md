# Portal architecture

No code yet: c0184 scaffolds this home and c0185 gates code shared across homes. Shared code comes from the `arcade` library (`arcade/.tracker/architecture.md`). This file grows with the project's first design.

## Features

### Carousel and Card (f0205)
The game carousel, the portal's one screen: one card per game, scrolled by key, wheel, swipe and shoulder.
- `src/shared/Logic/Carousel` (a leaf): which card is in front, how the inputs move the row, and where each card sits.
- `src/shared/Logic/Card` (a leaf): what a card shows: the price badge for a game's state (the arcade's Prices words), the states the server sends and the client's read of them, the card's regions and the preview's turn.
- `src/shared/Games.luau`: one entry per game (its paid-play name and title, its place, its tagline, its preview's parts). A new game is one entry.
- `src/server/Cards.luau`: which places are published (Places) and each player's free starts (Wallet), sent to that player on each ask over `ReplicatedStorage.Remotes.Cards`.
- `src/client/CarouselView.luau`: the screen, its inputs, and the seams the rest of the portal plugs into: `onPlay`, `focused`, `card` (its `Buttons` and `Boards` slots).

### Play buttons (f0208)
The card's play buttons: PLAY, ARENA on Snake, 2 PLAYERS on Invaders and Asteroids; the purchase, the entitlement and the teleport.
- `src/shared/Logic/Play` (requires Card): the server's decision from a player's record (go, go on the portal's pass, buy, store unavailable), the client's intents and the server's statuses checked, each card's buttons and note, the keys.
- `src/shared/Logic/Pairing` (a leaf): the 2 PLAYERS waiting lines of one portal server.
- `src/shared/Logic/Arena` (a leaf): which shared arena (a reserved server) an ARENA player joins.
- `src/shared/Modes.luau`: each game's play buttons. A new game is one entry.
- `src/server/Plays.luau`: the play intents over `ReplicatedStorage.Remotes.Play`, the record check (Wallet), the purchase (Receipts, installed here), the teleport (Travel, Places), the waiting lines and the arenas.
- `src/server/Invites.luau`: an invited friend reaches the inviter's portal server.
- `src/client/PlayButtons.luau`: the buttons in each card's `Buttons` slot, their keys, and the invite prompt.

### Board (f0206)
Each card's hiscores, read within the DataStore budget (the arcade's E3).
- `src/shared/Logic/Board` (a leaf; Card's text model reaches it as a parameter): what a board shows (the tabs, the header named by the title's progress figure, the rows with revives used, "—" for none, the "your best" line under every tab, pending until heard, every text at least Card.MIN_TEXT), the client's read of an answer, the layout in the card's Boards slot, when the client asks again, and the server's read policy (`Board.plan`: refresh, forward or answer).
- `src/server/BoardRelay.luau`: serves each title's arcade `Boards` on a server-only relay and answers the clients' asks over `ReplicatedStorage.Remotes.Boards` with (title, board id, rows, rank, status, best).
- `src/client/BoardsView.luau`: the tabs, rows and best line in every card's `Boards` slot (CarouselView's `card`), one tab for every card, asking for every card's board on it.

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
# Carousel and Card are leaves; so are Pairing and Arena
Play -> Card
```
