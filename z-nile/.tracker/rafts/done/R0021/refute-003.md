# Refute 003: R0021

The high finding blocked the merge (execute-raft Phase 4 step 7). The user chose to narrow the temp folder, then asked for one more review round (review 004).

- F1: fixed: the jail no longer allows `$TMPDIR`, `/tmp` or `/private/tmp`.
  - **What it allows:** this checkout's `.cache` (spec runs get `TMPDIR=<checkout>/.cache/tmp`, so tools that honour `TMPDIR` stay inside it) and the per-user system temp folder (`getconf DARWIN_USER_TEMP_DIR`, as written and resolved). macOS `mktemp` always uses that folder whatever `TMPDIR` says, and three specs call plain `mktemp -d` (c0060's sequestered `fixture.spec`, c0005 and `migrate-odd`), which is measured, not guessed.
  - **Shared temp is closed:** writes to `/private/tmp`, where agent sessions keep their scratch scripts, fail.
  - **Proven:** the gate's jail case and the outer-sandbox probes (`escapes`) both require that a probe file in `/private/tmp` can't be written. J12 (`/private/tmp` allowed again) is killed by the gate.
  - **Results:** full gate 936/936, 45.0 s; raft check 7/7.
  - **What stays open:** the per-user system temp folder remains writable. It isn't where scripts run by this workflow live, and closing it would break three specs (one of them sequestered).
  - On the keychain being readable: nothing in a spec can send what it reads anywhere, because IP networking is denied except loopback, proxies are stripped and banned, and nothing outside the jail runs from the folders a spec can write.
- F2: fixed: `pickman_fence` now replaces a `.cache/.git` that is a directory or a symlink (`rm -rf` of that one path inside `.cache`) before writing the sentinel, so no `commondir` or `gitdir` there can lead to the real repository.
- F3: fixed: the profile no longer allows whatever `TMPDIR` names. It names its two allowed folders itself, and the run's `TMPDIR` is set inside `.cache`.
