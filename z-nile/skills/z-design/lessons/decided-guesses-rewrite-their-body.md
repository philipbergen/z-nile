---
title: A decided guess rewrites its body; a decision prefixed to the replaced guess leaves two rules in one bullet
when: design
tags: [guesses, decisions, documents]
check: Does any decided guess's body still state the choice the user didn't take, or point at sections, lines or experiments that the decision removed?
---
A guess records what the author would do; the user's answer replaces it. Writing the answer in front of the old text leaves the bullet saying both, and the executor, the code reviewer and the skills that quote the document read the old one as the rule.

**Why:** c0117 design review 006 F4: five decided guesses (G7, G8, G9, G11, G13) carried the user's answer in their heading and the replaced guess in their body: "Any grok at xhigh" above "grok means grok-4.7 … a newer grok needs the rule changed"; "Split into a follow-up" above "get the command lines in §4", which no longer had them; "Skip missing CLIs" above "a CLI that is not installed is a failure that stops the chain". f0158 design review 001 F8: after the user chose G1 (replace the edge glows), E3 still ended "If the user keeps the edge glows (G1 b), none turn red."

**How to apply:** when the user decides a guess, rewrite its body as the rule in force; keep what was asked as one past-tense clause ("The guess asked: …"). Then grep the document for the replaced wording (Test plan, Verification log pointers, Overrides) and fix each.
