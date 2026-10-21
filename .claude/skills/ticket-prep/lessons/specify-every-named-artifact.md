---
title: Every artifact the design names has its content written down
when: design
tags: [completeness, executability]
check: Does every file, table, config, data source or input the design names have its content (or its schema and an example) and its fallback written down, so an executor need not invent it?
---
A design that names a file or a data source without saying what is in it leaves the executor to invent it, and the invention is a product or architecture decision nobody reviewed.

**Why:** R0042 design reviews 001 F14 (the board's data sources: worktrees, GitHub, checks) and 002 F11 (the root `.models.toml`, which says which model runs which skill) each found a named artifact with no specified content.

**How to apply:** list every path, table and source the Design mentions. For each, write its content, or its schema with one example, where it comes from, and what happens when it is missing. Content that is a user choice (a model table) goes to the user.
