---
title: A single-instance guard is held on every path and checked by the instance itself
when: both
tags: [locks, processes, pid-file, beater]
check: For a process that must run once per claim (a lock, a pid file), is the lock released when the start fails or is interrupted, is the pid file read again under the lock, and does a second instance that gets past both end itself at its first look?
---
A starter can only prevent a second instance it knows about. A lock taken over as stale, a start that throws between the lock and the pid file, or a command cancelled while it forks leave a process no pid file names; the starter cannot write a pid before the daemon exists.

**Why:** R0100 review-005 F2 and final-review F6. `hb.ensureBeater` read the pid file before taking the lock, kept the lock on an error, and treated a pid file for a process that was still the perl starter as "not a beater". Two beaters could beat one branch for an hour.

**How to apply:** run the body under a pcall and remove the lock after it; read the state again inside the lock; count a state younger than the starter's window as running; and make the instance end when the pid file names a live runner that is not its own ancestor. Test the process-table part with a stand-in `ps`, since the spec jail denies the real one.
