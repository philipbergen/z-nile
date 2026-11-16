# Harvest: c0258

- note the land spec's stand-in git stripped only a leading PATH entry, zn put ~/.rokit/bin in front of it, it called itself until fork failed (EAGAIN), and the runner's tripwire read HEAD as detached and stopped the prep (2026-11-15): zz-test/forwarding-stand-ins-never-find-themselves
- note two race cases' gate scripts used `[[ $n == 1 ]] && ( ... ) || exit 9`, which exits 9 on the second gate run, and failed a correct prototype (2026-11-15): zz-test/and-or-is-not-if
- note the retries spec's second case reused the first case's race-file names in the shared `other` clone, made an empty commit and failed before its push (2026-11-15): zz-test/shared-clone-changes-are-unique
- design-review-001 F1: zz-test/format-tracker-specs-by-path
- design-review-001 F2: z-design/own-change-reads-own-commits
- design-review-001 F3: zz-test/promoted-specs-pin-rules-not-sets, z-design/design-the-execution-window
- design-review-001 F4: z-design/design-the-execution-window
- design-review-001 F5: z-design/quote-other-preps-before-promising
- design-review-001 F6: z-design/spec-design-correspondence
- design-review-001 F7: z-design/guards-name-slow-tier-specs, z-design/confirm-overrides-with-a-suite-run
- design-review-001 F8: one-off: the publish broker's 600 s wait multiplied by land's own retry count; the bound is stated and a no-answer now ends the land
- design-review-001 F9: z-design/restated-rules-move-together
- design-review-001 F10: one-off: an unused require in a prototype, which the gate's types stage already reports as a warning
- note design review 001's reviewer suggested a zz-review lesson (run the gate's static stages over the item folder, not only its specs; F1 was found only because the gate was run): zz-test/format-tracker-specs-by-path
