---
title: Sequestered specs type-check before the code exists
when: design
tags: [sequestration, promote-check, types, specs]
check: Does every sequestered spec type-check with none of the issue's code present, reading each new export or new field through `any` (`(models :: any).quotaCapHours`, fixtures typed `any`), so that `promote-check` in the prep fails only on the require of a module the issue creates?
---
`promote-check` type-checks the sequestered specs against main. A spec that calls a function the issue adds to an existing module, or builds a typed fixture with a field the issue adds, fails the type check there, and that failure hides whether the spec is otherwise sound.

**Why:** c0250's prep: the work-board spec called `models.quotaCapHours` and built `readycheck` fixtures with a `blocked` field, so `promote-check` failed on them as well as on the one require of the new `escalation` module.

**How to apply:** reach new exports of existing modules through a cast to `any`, type fixtures that carry new fields as `any`, and confirm that `promote-check` in the prep lists only the missing new module. Related: [[sequestered-specs-use-mains-test-lib]].

**Note (c0325's prep, 2026-11-15):** a loop like `for _, x in t.field or {}` over a `{ string }` field read through `any` fails `promote-check`'s type check. Bind it to a typed local first.

**Note (c0251's prep, round 2, 2026-11-15):** `t.expect(next(x))` and `t.expect(string.find(...))` pass two values, so `promote-check` refuses the spec. Wrap the call in parentheses to keep one value.

**Note** (c0249 prep, 2026-11-16): `t.expect(f())` where `f` returns two values fails `promote-check`'s type check. Wrap the call in parentheses, `t.expect((f()))`, to keep the first value.

**Note** (c0254 design refute 001): two forms that type-check under the spec runner fail `promote-check`'s strict typing: `table.expect(string.find(s, p))` (parenthesise the call, so only its first result is passed) and `pcall(body)` on a body typed `() -> ()` (cast the body). Run `promote-check` after every spec edit, not only the runner.
