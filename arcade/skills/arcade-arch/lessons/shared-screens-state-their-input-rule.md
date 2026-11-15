---
title: A library screen that takes keys says what it cannot stop, and the rule its places follow
when: design
tags: [library, input, client, consumers]
check: When a library client module sinks keys or buttons (ContextActionService at a high priority), does the Design say that UserInputService listeners and the place's own GUI buttons still see them, state the rule each consuming place follows for its own handlers (bindings below the priority, skip processed input, or an `isOpen` query), name that rule for every consumer, and give a query the places can gate on, with its own case?
---
A ContextActionService sink stops only the bindings below it. UserInputService listeners still get the key (marked processed), and a place's own buttons still get the tap, so a key meant for the library's screen can also act in the place.

**Why:** f0201 design review 001 F6: the test purchase screen bound Return, ButtonA and ButtonB at priority 3000 "above the place's own", but pickman's Controls connects `InputBegan` and ignores the processed flag, and the portal plays on Enter or A; Return on an open test screen would confirm the purchase and press PLAY, which asks again while the grant is still being written.

**How to apply:** state the consumer rule in the feature's Design and in the library's architecture text, name it under each consumer in Order & dependencies, and export `isOpen()` with a case (false before, true while open, false after each answer). A tracker that only notes the device in use is exempt (pickman-arch/count-processed-input-when-tracking).
