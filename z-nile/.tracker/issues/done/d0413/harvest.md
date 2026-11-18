# Harvest: d0413
- design-review-001 F1 (erred zz-test, upstream z-design): zz-test/promoted-specs-pin-rules-not-sets
- design-review-001 F2 (erred z-design): z-design/quote-other-preps-before-promising
- design-review-001 F3 (erred z-design): z-design/confirm-overrides-with-a-suite-run
- design-review-001 F4 (erred zz-test, upstream z-design): zz-test/no-vacuous-pass
- design-review-001 F5 (erred z-design): z-design/spec-design-correspondence
- design-review-001 F6 (erred z-design): one-off: one implementation step named the wrong gate scope and no rule for a foreign red
- note f0399's two loops landed with the scan red because the affected gate does not select the scan specs (erred zz-execute): zz-execute/run-the-loop-scan-after-adding-a-loop
- note a scripted edit cut a case out of the acceptance spec and check.sh still passed, because it only looked for FAIL lines; the check now counts the file's five cases (erred zz-test, upstream z-design): zz-test/no-vacuous-pass
