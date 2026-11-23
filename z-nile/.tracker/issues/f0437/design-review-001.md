# Review 001: f0437 (design mode)
Inputs: f0437-act-design at 5a18f7337 (f0437.md "Step 6a design: act from the browser", f0432.md "Launch from the app", f0432 guesses.md G1 to G3). Also read: z-nile/engine/approvewalk.luau, approval.luau, main.luau (approve), boundcmd.luau, agentenv.luau; z-nile/go/internal/web (web.go, page.go), cmd/znlive (appd.go, client.go, serve.go). Reviewer: Fable. The review's verdict on the whole: build after these changes. The answers are in f0437.md, "Step 6a design", under "Review 001 answers".

### W1 [wrong claim] `--summary` "prints what `--apply` prints"
Where: Step 6a, B, "Confirm shows the engine's text"
Evidence: `--apply` (approvewalk.luau ~690-707) prints one line and at most five guesses cut to 80 characters: no hash, no Problem, no Solution.
Recommendation: specify the confirmation content itself.
Erred: z-design
Upstream: none

### W2 [wrong claim] "the engine passes stdin through every re-exec of the recorder"
Where: Step 6a, B, "Recording through the engine"
Evidence: the recorder re-exec is `sh -c 'exec lune ... approve "$2" </dev/tty'` (approvewalk.luau ~717), and the inner `approve <id>` does its own terminal check (main.luau ~6236). Both must change.
Erred: z-design
Upstream: none

### W3 [wrong claim] `terminalForm` covers `app --act`
Where: Step 6a, A, "Where the authority comes from"
Evidence: `terminalForm` is reached only for the sub-commands `approve` and `rework` (boundcmd.luau ~502, `formAfter`); `app --act` needs `formAfter` changed too.
Erred: z-design
Upstream: none

### F1 [serious] The approval row is unauthenticated, today
Where: approval.luau ~173 `approval.append`; main.luau ~6583
Evidence: a row is plain `when / git user.name / hash / parts`, and `who` takes its suffix from the environment variable `ZN_APPROVE_RUN`. An agent can write `approval.md` and commit it; no pairing, token or grant is involved.
Recommendation: only a signed row counts, verified at landing.
Erred: z-design
Upstream: none

### F2 [serious] The page's script is agent-writable
Where: web.go ~164, page.go ~63-75, appd.go ~60 (`SetPage`)
Evidence: the daemon reads `index.html` and `live.js` from disk at each request, from main or any `.worktree/<name>/z-nile/app/`, chosen by an unauthenticated client op. An agent edits `live.js` in its worktree, points the daemon at it, and holds the token after the next pairing; CSP does not help.
Recommendation: act-capable pages are served only from bytes embedded in the binary; `SetPage` ends every session and disables pairing.
Erred: z-design
Upstream: none

### F3 [serious] Pairing is phishable without a browser
Where: Step 6a, A, "The flow"
Evidence: `curl` forges Host, Origin and the header, gets a pair id and code, and the agent asks the owner to type that code. Or, after the idle exit, the agent listens on the last port so the open tab shows its pairing screen.
Recommendation: pairing starts in the terminal: `./zn app --act` opens the real address with a one-time secret, that page shows the code, and the owner types it into the same invocation.
Erred: z-design
Upstream: none

### F4 [moderate] The ancestor check likely refuses everyone
Where: Step 6a, A, the daemon's own peer check
Evidence: Terminal's `login` and launchd are root-owned, and `kern.procargs2` is normally denied for them.
Recommendation: make it experiment E1, say what an unreadable ancestor means, and use the audit token rather than the pid.
Erred: z-design
Upstream: none

### F5 [moderate] The grant's daemon is chosen by the caller
Where: client.go ~26, serve.go ~81
Evidence: `ZN_LIVE_DIR` and `ZN_LIVE_SOCKDIR` pick the daemon, so a fake daemon answers yes to a redeem.
Recommendation: ignore that environment under `--grant-stdin`; only F1's fix really closes it.
Erred: z-design
Upstream: none

### F6 [minor] An agent can block the owner
Evidence: it can hold every pending pairing, or trip the rate limit.
Erred: z-design
Upstream: none

### F7 [moderate] Easier than today
Evidence: a paired tab is eight hours of one-click approval, against a `y` per ticket today. The daemon writes the ruling itself, so a ticket never walked can be approved from an agent-made run. The dialog shows Problem and Solution while the hash also covers the Design, the criteria, check.sh and the specs.
Recommendation: 15 idle minutes; show which parts changed; require a walked run.
Erred: z-design
Upstream: none

### F8 [serious] The existing terminal hole is real and wider
Evidence: the hook reads only the command line. A script file run as `bash x.sh` (scrubbing markers, `script` for a pty), `tmux send-keys`, `osascript` and `open -a Terminal` all pass. The hook fails open and exists only for Claude Code; no pattern fix closes it, and the same trick pairs this design without the owner.
Recommendation: something the agent does not have. An optional setting now, required once enrolled: a small Swift helper holds a Secure Enclave P-256 key with biometric access control and signs `{ticket, hash, when}` at record time; landing verifies it with no second touch. It should work without an app bundle (as age-plugin-se does) but is untested (E3). Avoid Keychain biometric items (entitlements); a bare LAContext yes/no is worthless. Screen control cannot satisfy the prompt; an agent can still swap the pinned public key, so pin it outside the repository. Fallback: an `ed25519-sk` hardware key (also Linux), else today's bar with the row labelled "unsigned". Cost: one touch per ticket. Add a revoke row valid until landing; landing lists each approval with its path and signature state. The helper is source in the repository built locally with the system toolchain; this project downloads no executables.
Erred: z-design
Upstream: none

Verdict: changes
