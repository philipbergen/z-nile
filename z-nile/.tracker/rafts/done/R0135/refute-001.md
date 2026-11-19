# Refute 001

- F1: fixed 4d703b3b6: the Risks bullet in R0135.md now says a raft folder shows as a count off by one with no id, and an issue folder by its id; the spec is unchanged; consequences: none, a sentence in the raft document.
- F2: fixed 4d703b3b6: the comment about the ids and their order moved to `ondisk.items`, `shown` has its own one-line comment, and the header is rewrapped under 110 columns; consequences: the layer no longer equals the prototype patch byte for byte (comments only); `./zn check c0388` reran 3/3 and stylua passes.
