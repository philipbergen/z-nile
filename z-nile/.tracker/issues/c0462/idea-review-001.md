# Idea review 001

## Findings

- F1: Solution sentence 4 is false as written. The rule it retires is the lesson `zz-test/no-vacuous-pass` ("A check must not pass because it found nothing", cited by 48 harvests). Most of that lesson covers things an assertion count cannot see: `check.sh` greps that find nothing, `|| true`, `diff <(a) <(b)`, cases whose assertions exist but cannot fail, and cases that read each other's output file. The runner would enforce only the zero-assertion slice, and the second non-goal says it will not judge the rest, so "because the runner now enforces it" does not hold.
- F2: Solution sentences 1 and 3 cannot both hold on what the idea states. Specs outside the exemption also assert only through local error helpers: `z-nile/tests/tooling/models-skills.spec.luau` (local `has`/`absent`), `app-md`, `app-copy` and `app-links` call `expect(` nowhere. A textual count finds about 64 of 1,377 non-acceptance cases with no `expect(` in their body. The idea neither says these are rewritten nor exempts them, so the work is unsized and the reader cannot tell which sentence gives way.
- F3: "A registered assertion helper" in sentence 2 cannot be judged true or false. No register exists, and the idea does not say what makes a helper count. The issue's own example, `fixture.exec` (`z-nile/tests/lib/fixture.luau:87`), "never raises for the command's own failure", so counting it lets a case that only runs a command pass, which is the vacuous pass the Problem names.
- F4: The exception and the first non-goal name different sets, so the fence is not fixed. Sentence 1 exempts every existing promoted acceptance spec, about 4,602 of 5,979 cases by the same textual count. The non-goal protects only those that check solely through local error helpers, about 235 cases. A reader cannot tell whether an existing acceptance case that runs nothing at all passes or fails. "Existing" also has no cutoff: prepared items whose sequestered acceptance specs are promoted later are not placed on either side.

## Verdict

revise
