---
title: A prep experiment that publishes from a throwaway clone first drops the dispatched step's environment
when: design
tags: [experiments, dispatch, environment, safety]
check: Does every experiment that runs a publishing `./zn` command (`status`, `land`, `new`, `ready`) in a throwaway clone unset every `ZN_` variable and `GH_CONFIG_DIR`, take `z-nile/bin` off `PATH`, and refuse to publish unless the clone's `origin` is under its temporary folder (a guard that can fail, not a re-test of what it just unset)?
---
Under `./zn dispatch`, a step's `./zn` sends its pushes to `main` to the dispatcher's publish broker (zz-rules, Tracker state from inside a step), which pushes them to the real origin. A clone under `mktemp -d` inherits that environment, so its tracker commands publish through the broker, not to the clone's own bare origin.

**Why:** c0272's prep (2026-11-15): E1's first run of `./zn status c0272 new` in a throwaway clone went to the broker. The broker refused it only because the commit was not a fast-forward of the real `main`. A clone whose `main` matched the real one would have pushed a stamp to the real repository.

**How to apply:** at the top of such an experiment, `for v in $(compgen -e | grep '^ZN_'); do unset "$v"; done`, `unset GH_CONFIG_DIR` (the step's GitHub credential), and drop `z-nile/bin` from `PATH`. Then, before the first publish, exit unless `git remote get-url origin` is under the temporary folder, and exit if `env | grep '^ZN_'` still finds one (c0272's `experiments/E1-takeover.sh`). Testing `ZN_PUBLISH_BROKER` right after unsetting it can never fire (c0272 design review 001 F7). Specs have the same gap, which d0355 fixes.
