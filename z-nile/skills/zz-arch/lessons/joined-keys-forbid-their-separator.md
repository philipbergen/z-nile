---
title: A key built by joining names forbids the separator in a name
when: both
tags: [paths, identity, rojo]
check: Can any component of this joined key itself contain the separator, and what does a key that collides with a real one get past?
---
An identity built by joining names with a separator (`A/B`) cannot tell a child `B` of `A` from one node named `A/B`. A rule that compares such a key to an allowed one is then fooled by a name that spells the allowed key.

**Why:** R0088 code review 002 F1 (c0246): Rojo accepts a project key `"ServerStorage/Arcade"`, so a node at the root could pass the library-node test as a child of the service in both the reader and the Rojo-driven check, though the built place has no `ServerStorage.Arcade`.

**How to apply:** compare names as a list, or fail closed on any name that holds the separator, and add a case whose name spells the allowed key.
