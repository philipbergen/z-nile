---
title: A stand-in that forwards to the real command can never find itself again
when: both
tags: [stand-ins, specs, path, processes]
check: For each stand-in a spec puts on PATH that calls the real command (`exec git "$@"`), does it remove its own folder from every position of PATH (not only the front), and refuse to run when it finds itself nested, so a command under test that prepends PATH entries (`zn` adds `~/.rokit/bin`) cannot make it call itself until fork fails?
---
A stand-in `git` that strips only a leading `"$self:"` from PATH and then runs `git` finds itself again whenever the command under test has put something in front of it. With `exec` it replaces itself forever; with a plain call it forks a child that does the same, a chain that grows until the user's process limit refuses every fork (`Resource temporarily unavailable`, os error 35). Every other process of the run then fails at random, the runner's own reads included.

**Why:** c0258's prep (2026-11-15): the land spec's stand-in `git` was put first on PATH for `./zn land`, but `zn` runs `export PATH="$HOME/.rokit/bin:$PATH"`, so `${PATH#"$self:"}` stripped nothing. The run took three minutes, seven cases failed with EAGAIN, and the runner's tripwire read the checkout's HEAD as detached (its own git call had failed), which stopped the prep. The repository had not changed.

**How to apply:** strip the stand-in's folder wherever it is (`p=":$PATH:"; p=${p//":$self:"/":"}`), export a marker before forwarding and exit non-zero at once when the marker is already set, and run the spec once with the command's own PATH prefix in place before relying on it.
