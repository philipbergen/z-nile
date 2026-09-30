# Refute 004: R0050 (answers design-review-004)
- F1: fixed: c0390's skill-edit section now tells the executor to qualify rule 5's "Roblox and Lune resolve them the same way": it holds for relative paths and `@self`, not for `@game`, which Lune can't resolve. It gives the consequences (adapters are never required from tests, and graph/place resolve `@game` through `default.project.json`).
