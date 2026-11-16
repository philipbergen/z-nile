#!/usr/bin/env bash
# Acceptance checks for f0205. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0205 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0205"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the carousel: one row of cards with the first in front, wrapping both ways; A, Left and the left shoulder back, D, Right and the right shoulder forward, Enter, KeypadEnter and ButtonA play, nothing else; the wheel one card per roll after a 0.25 s rest; a swipe left brings the next card; the front card centred and fitting every screen, its neighbours smaller, dimmed and clear of it, the rest hidden; bound below the test purchase screen's priority" lune run tests/run -- "$A/carousel.spec.luau"
check "AC2: a card's badge: nothing until known, COMING SOON when unpublished, FREE GAME READY when due, else the arcade's Prices words, 5 R\$ struck through as escaped rich text then 1 R\$ SALE; the server's states by name and the client's defensive read of them; the regions top to bottom with room for buttons and boards; the preview's spin and a camera that frames it" lune run tests/run -- "$A/card.spec.luau"
check "AC3: the games table: Pickman, Snake, Invaders and Asteroids in that order, each its Catalog title and its Places place, a short tagline of its own, and a framed preview of valid parts, all frozen" lune run tests/run -- "$A/games.spec.luau"
check "AC4: the server adapter on a stub server: published from the place-id attributes once, through Places; each ask answered at once to that player, then one Wallet read per published game not already being read, answered as each comes back with PaidPlay's status at os.time(), a failed read showing the sale; client arguments ignored, no place id sent, nothing for a player who left" lune run tests/run -- "$A/server.spec.luau"
check "AC5: the client adapter on a stub client: one Portal screen in the safe insets, a card per game with title, tagline, a turning 3-D preview, the badge from the server's answer and the Prices words, and empty Buttons and Boards slots; cards placed by Carousel's boxes, again on a resize; one binding below priority 3000 for the nine keys and the wheel, on the press; swipes; Enter, KeypadEnter and ButtonA tell the play listeners the front published card; one ask after it listens; start returns at once" lune run tests/run -- "$A/client.spec.luau"
check "AC6: in the built portal place: ReplicatedStorage.Remotes.Cards, Carousel and Card as Logic leaves, Games requiring only Card, the server's Cards reaching the arcade's Wallet and booted by its Main, CarouselView booted by the client's Main, nothing a client reads requiring a server module, and both features in portal's architecture map with no edge" lune run tests/run -- "$A/place.spec.luau"
check "AC7: Carousel and Card have unit specs; Logic stays engine-free, every dependency is declared, and every feature has unit specs" bash -c 'test -d tests/unit/Carousel && test -d tests/unit/Card && lune run tests/run -- tests/meta/architecture.spec.luau'

finish
