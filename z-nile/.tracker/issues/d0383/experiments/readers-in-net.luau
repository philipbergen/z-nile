--!strict
-- d0383 F1: a promoted spec that drives a nested `./zn watch-net` in a fixture (c0278/readers) passes when it runs as the
-- suite of a net started by the real kick, because the kick passes its marker as a flag, never in the environment.
-- On the first prototype (PICKMAN_WATCH_NET_READY in the net's environment) the same spec failed inside the net.
-- The fixture's suite is replaced by a run of the spec from this checkout's own z-nile/ (the fixture carries no tests/run), in the net's environment; the net then records a pass on the fixture's origin. Run from z-nile/:
--   GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=gc.auto GIT_CONFIG_VALUE_0=0 GIT_CONFIG_KEY_1=maintenance.auto GIT_CONFIG_VALUE_1=false \
--     ./zn run --time 400 -- lune run .tracker/issues/d0383/experiments/readers-in-net.luau
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local process = require("@lune/process")

local w = netfix.world("d0383-readers-in-net", { standing = true })
fs.writeFile(
	`{w.main}/z-nile/check.sh`,
	`#!/usr/bin/env bash\ncd '{process.cwd}' && lune run tests/run -- tests/acceptance/c0278/readers.spec.luau\n`
)
fixture.git(w.f.main, { "add", "-A" })
fixture.git(w.f.main, { "commit", "-q", "-m", "the suite is the readers spec" })
fixture.git(w.f.main, { "push", "-q", "origin", "HEAD:main" })
fs.writeDir(`{w.main}/pickman/src`)
fs.writeFile(`{w.main}/pickman/src/x.luau`, "return {}\n") -- a source change since the (empty) record, so the suite runs
fixture.git(w.f.main, { "add", "-A" })
fixture.git(w.f.main, { "commit", "-q", "-m", "a source" })
fixture.git(w.f.main, { "push", "-q", "origin", "HEAD:main" })
local r = netfix.kick(w, w.raft)
print(r.stdout, r.stderr)
local log = netfix.logOf(r.stdout) :: string
local code = netfix.settle(log)
print(netfix.read(log))
local subjects = fixture.git(w.f.main, { "log", "origin/main", "--format=%s", "-3" })
print(subjects)
-- the pass commit exists once the fast suite (the readers spec) passed; the net goes on into its slow tier, a second run of it
local ok = string.find(subjects, "watch-net: the suite passed", 1, true) ~= nil
print(`net exit file: {code}`)
print(if ok then "PASS the readers spec passed inside a net started by the kick" else "FAIL")
process.exit(if ok then 0 else 1)
