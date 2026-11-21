--!strict
-- d0383 F2, the fixture-level proof the jail does not allow in a spec (it denies /bin/ps): a net started by the real kick
-- is not listed by `./zn reap --dry-run`, and an ordinary orphan of the same age is. Run from z-nile/ as
--   GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=gc.auto GIT_CONFIG_VALUE_0=0 GIT_CONFIG_KEY_1=maintenance.auto GIT_CONFIG_VALUE_1=false \
--     ./zn run --time 240 -- lune run .tracker/issues/d0383/experiments/reap-net-proof.luau
-- (the settings keep a detached `git gc` from packing the fixture's seed while its origin is cloned; the runner sets its own)
-- It works only in a throwaway fixture under .cache/ (the reaper is given that fixture as its one --root) and stops what it started.
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local process = require("@lune/process")

local function check(ok: boolean, what: string)
	print(`{if ok then "PASS" else "FAIL"} {what}`)
	if not ok then
		process.exit(1)
	end
end

local w = netfix.world("d0383-reap-proof", { standing = true })
netfix.holdOn(w)
local kicked = netfix.kick(w, w.raft)
check(kicked.code == 0 and netfix.has(kicked.stdout, "started"), "the kick started the net")
check(netfix.waitFor(`{w.hold}/started`), "the net's suite is running (held on a marker)")
-- an ordinary orphan in the fixture: a sleep whose parent shell is gone
process.exec("sh", { "-c", "sleep 60 >/dev/null 2>&1 &" }, { cwd = w.main })
local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local listed = ""
for _ = 1, 20 do
	process.exec("sleep", { "1" }) -- the orphan must be older than --min-age
	local r = process.exec(`{top}/zn`, { "reap", "--dry-run", "--root", w.main, "--min-age", "1" })
	listed = r.stdout .. r.stderr
	if string.find(listed, "sleep 60", 1, true) then
		break
	end
end
print(listed)
check(string.find(listed, "sleep 60", 1, true) ~= nil, "an ordinary orphan of the same age is listed")
check(
	string.find(listed, "--time 3600", 1, true) == nil,
	"the net's group shell is not listed (the reaper shows its first 100 characters)"
)
check(string.find(listed, "watch-net", 1, true) == nil, "nothing of the net is listed")
-- let the held suite go and wait for the net to end, then stop the orphan
fs.writeFile(`{w.hold}/release`, "go\n")
netfix.settle(netfix.logOf(kicked.stdout) :: string)
local orphan = string.match(listed, "would stop pid (%d+)[^\n]*sleep 60")
if orphan then
	process.exec("kill", { orphan })
end
