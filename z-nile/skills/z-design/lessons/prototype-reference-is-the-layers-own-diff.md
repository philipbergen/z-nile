---
title: An implementation step points at the layer's own commits, not a diff against a lower branch
when: design
tags: [prototype, stack, executability]
check: Does the diff the first implementation step names contain only this layer's changes (run it and count the files), or does it carry the lower layers' and main's work because the prototype merged them?
---
A prototype built on its dependencies' prototypes, with main merged in more than once, differs from the dependency branch by far more than the layer: following "apply the diff against the lower prototype" re-applies the lower layers inside this layer's commit.

**Why:** c0284 design review 001 F8: `git diff origin/proto-c0280 origin/proto-c0284` was 31 files (+1,687), the layer's own was 8 files (+212).

**How to apply:** save the layer's own diff as `prototype.patch` in the issue folder (as c0138 does) and name the files it leaves out (the docs hunks, a line inside a function a lower layer moved).
