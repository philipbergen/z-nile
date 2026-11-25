# Idea review 001

## Findings

- F1: Solution sentences 3 and 4 and the last non-goal cannot be found true or false, because nothing says what separates the owner's click from an agent's request to the same local page. On main the app's server is read-only on purpose: `TestNoRouteOrMethodCanApprove` in `z-nile/go/internal/web/approvals_test.go` fails if any route can approve or send back. f0437's guess G13 chose that because an agent's curl to 127.0.0.1 is the same request as a click. So either the view only hands the owner the bound ruling and apply commands to confirm in a terminal, and the sentences should say that, or the idea reverses that guard, which is more than the Problem asks for and makes the last non-goal a promise the Solution does not keep.
- F2: Problem sentence 4 and Solution sentence 5 restate f0432's deliverable. f0432's Solution already gives the local app "a control on every item that starts that same `zn talk` command", and `zn talk` does not exist on main. The same point was raised on f0437 (idea-review-003 F1) and became a fence there; here it is still a Solution line, so two tickets own one outcome.
- F3: Solution sentence 1 ("read from the tracker") and the first non-goal claim the real-data Approvals view, which f0437 also claims. f0437's Problem calls f0425 the mockup with simulated data, and its Solution delivers "the real tracker" in the approvals view. A reader cannot tell which ticket a real-data Approvals view lands in.
- F4: Solution sentence 2 promises "every option and what that option changes" for each guess, but the tracker records only what was chosen and why: `guesses.md` has no options field (f0437 guess G15). The sentence can only come true if the idea also makes guesses record their options, which no Solution sentence says.
- F5: Solution sentence 6 answers no Problem sentence, and "bright status colours" is not something a reader can find true or false. "No purple" and the named site colours and fonts are checkable.

## Verdict

revise
