# znile board

A bar icon (kanban glyph + active ticket count) that opens a tiled window with every znile **ticket** and **raft** in `~/code/pickman`. A ticket is one feature, defect or chore; a raft is a group of tickets delivered together as one PR.

- **Columns**: New · Preparing · Prepared · Active (Done behind the Done chip), each in priority order. Until znile has priority, a lower ticket number means a higher priority.
- **Cards**: type stripe and letter, id, project, title, a five-step pipeline, the raft, blockers (🔒), dependencies, and the next pipeline command.
- **Blocked**: znile blocks whole rafts. A raft can't start while any of its tickets depends on unfinished work outside it, since it ships as one PR. A dependency between tickets in the same raft only orders them. Cards show "blocked by …" (red), "after …" (in-raft order) and, on rafts, "1 of 3 tickets blocked"; the details say which ticket needs what. The **blocked** chip filters to blocked cards.
- **Click** a card for its details beside it, with the description rendered as markdown. **Double-click**, or **Dive in**, opens a new terminal (tiled as its own panel) in the repo with the chosen AI CLI running interactively, seeded with a discussion-only prompt. Click the open card again, the popup's empty areas, or the expand button for the **big view**, which fills the board so long lines fit; code blocks and diagrams wider than that scroll sideways. Prose uses the sans font and `code` stays monospace. The GitHub button opens the ticket's file on github.com. Arrow and Page keys scroll the description. The **next** command sits in a box: click it to copy the command, then paste it into your CLI.
- **Choose the AI**: "Open in" in the details, or the agent chip in the header (click to cycle). Only installed CLIs are offered (`agents.sh`); the choice is remembered in `~/.local/state/znile-board/agent`, and it starts on Omarchy's default agent. Agents start in their normal ask-before-acting mode. Kimi and Crush can't take a starting prompt, so it goes to the clipboard to paste.
- **Drag** a card within its column to reprioritize. The move only lasts for the session until `rankCommand` is set in `settings.json` (e.g. `./zn rank {id} --before {beforeId}`), which runs in the repo with each value as its own argument.
- **Keys**: Tab switches Tickets/Rafts, `/` searches, Esc clears or closes, F5 or Ctrl+R refreshes. Right-click the bar icon to refresh.

Data comes from `fetch.sh`, which reads only through `./zn board`. It uses `--json` once znile has it, and until then the JSON embedded in the rendered board page. It needs lune (`z-nile/setup.sh --tools`). The board refreshes every `refreshIntervalSec` and whenever `main` or a fetch moves.

Tests: `node --test tests/`
