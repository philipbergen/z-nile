# Refute 001

- F1: fixed 8fb68da: `Beta.project` drops one trailing `/` from the directory before joining a relative `$path`, and `deploy-beta` trims `process.cwd` the same way before the source path; consequences: an absolute `$path` is still returned unchanged, a directory of `/` is not trimmed, and `project.spec` still expects `/repo/...` from a directory without a trailing slash. Checked with `scripts/tracker.sh check c0064` (8/8 PASS). A caller that passes a directory with a trailing slash now gets one slash; Rojo already treated `//` as `/`, so the built place is the same.
