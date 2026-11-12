---
title: A key built by joining names forbids the separator in a name
when: both
tags: [paths, identity, rojo]
check: Can any component of this joined key itself contain the separator, and what does a key that collides with a real one get past?
---
An identity built by joining names with a separator (`A/B`) cannot tell a child `B` of `A` from one node named `A/B`. A rule that compares such a key to an allowed one is then fooled by a name that spells the allowed key.

**Why:** R0088 code review 002 F1 (c0246): Rojo accepts a project key `"ServerStorage/Arcade"`, so a node at the root could pass the library-node test as a child of the service in both the reader and the Rojo-driven check, though the built place has no `ServerStorage.Arcade`.

**How to apply:** compare names as a list, or fail closed on any name that holds the separator, and add a case whose name spells the allowed key.

**Also:** R0088 code review 003 F1 (c0246): the fix for the separator hole still compared names only, and a `ReplicatedFirst` named `ServerStorage` spelled the allowed node and put the server library on every client, though Rojo's sourcemap printed the class. A node's identity is its path of (name, class) pairs under the root's class; when a second hole hits the same mechanism, replace the key with the list instead of patching the next spelling.

**Also:** R0088 code review 004 F1: after the identity became a (name, class) list the report still printed the joined names, so a line read "put at ServerStorage/Arcade, which is not ServerStorage/Arcade". Check that the report shows the part of the identity that failed.
