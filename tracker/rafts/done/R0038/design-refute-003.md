# Refute 003: R0038

- F1: fixed: the fake clipboard returns `new Promise(r => queueMicrotask(r))` on success and `Promise.reject` on failure. The design no longer names call shapes. Any handling that leaves no unhandled rejection is accepted. `node -e 'Promise.reject(new Error("denied"))'` exits 1 on Node 22, so the unhandled-rejection mutant still fails the run; consequences: none.
