# Design checklist: feature

Answer each in the issue's Design before the first review round (z-design step 3).
- **Behaviour**: every player-facing or developer-facing outcome the capture names, each with a Design paragraph and a Checked criterion (Judged or Observed only where the zz-test skill allows it).
- **Interfaces**: the public types and signatures each new or changed module exports, and who calls them.
- **The split**: what is pure and unit-tested, and what is a thin adapter; for a game, what the server decides and what a client may only ask for (the project's own architecture rules: `pickman-arch` for pickman).
- **Scalability, Maintainability, Usability**: answered for this feature, from the design checklist of the project's architecture rules (`pickman-arch` for pickman, `zz-arch` for the tooling).
- **Edge cases**: empty input, bounds, simultaneous events, a player who leaves or respawns, frame-rate independence.
- **Measurable proxies**: every "feels right" turned into a number a spec can check, with what is left for Observed kept to the minimum.
- **Overrides**: a promoted spec the feature turns red is changed by its own chore, named in `depends_on` (z-design step 3, Override check).
