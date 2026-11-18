# Refute 001

- F1: fixed 1f27c5881: the harvest records it; the spend rows stay as they are (append-only), as the review recommends. The runs were started with HEAD on each layer's own branch (after `./zn start`), so the booking is the tool's, not the order of work; consequences: `./zn metrics` under-counts c0374's test seconds and over-counts c0304's for this raft.
