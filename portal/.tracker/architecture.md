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

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
# Carousel and Card are leaves
Play -> Card
```
