---
title: Rerun a derivation on the finished layer and log what it prints
when: build
tags: [verification, ids]
check: When a design's step or experiment names ids or row numbers derived from the document (c0330:AC9: None.), did the build rerun the derivation on the finished layer, and do the ids in the Verification log match what `./zn trace <R-id>` prints on the top layer's commit?
---
A design's experiment ran before the document gained criteria, so its step named `c0330:AC9` and `c0330:AC10` for rows that are `c0330:AC11` and `c0330:AC12` on the finished layer, and the E3 confirmation the raft asked for was not logged.

**Why:** R0103 code review 001 F4.

**How to apply:** run the derivation on the finished layer, log the ids and the run in the Verification log, and do not edit the contract text that names the old ones.
