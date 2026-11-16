---
title: A reader of a tool's JSON must not depend on the build that wrote it
when: both
tags: [json, sqlite, adapters, fail-closed]
check: Is every nested value in the tool's JSON wrapped in a call that fixes its type (sqlite's `json(...)`) or decoded by one shared reader, is each call of the tool guarded so a failure turns the feature off instead of failing the caller, and is there a case with a stub tool that answers the other encoding?
---
The same query can return a nested array as an array on one build and as text on another (sqlite3's JSON subtype is lost through a subquery in 3.54).

**Why:** R0081 code review 001 F1: on Homebrew's sqlite3 3.54.1 `resultsdb.rows` iterated a string and crashed the orchestrator, and with it the affected gate, before any spec ran. The Design said a db failure turns reuse off; one call was not guarded.

**How to apply:** wrap each nested subquery in `json(...)`, decode a text result too, run every call of the tool under `pcall`, and keep a stub tool in an unsequestered spec for each encoding.
