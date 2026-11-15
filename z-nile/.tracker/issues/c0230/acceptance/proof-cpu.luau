--!strict
-- c0230 AC2, the one-time proof with real CPU and real lanes: the coordinator's measurer counts the CPU of a process its
-- worker waited for, on worker lanes and without them, and a file's wall in the report is its own time, not the time it
-- waited for a lane. It spins CPU on purpose (about one second in all) and holds every lane for three seconds, so it is
-- NOT a spec: it lives
-- here only for check.sh, which runs it only before `./zn done`, under `ulimit -t 60` and `./zn run --time 120`
-- (lesson zz-test/specs-never-burn-real-resources). `tests/run` never runs it (no `.spec.luau` name), so `./zn done`
-- promotes it as a file and the suite never executes it; the suite's half of AC2 is runner-budget.spec.luau, which
-- pins the measurer's sum through a stand-in `times`. Every spinner stops itself at half a second of its own CPU and
-- after 20 s of wall time (`alarm 20`). Its only folder is a throwaway under the home's .cache, and the runner it starts
-- jails itself. Prints one line per case; exit 1 on a failure.
local fs = require("@lune/fs")
local process = require("@lune/process")

local HOME = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local NAME = `c0230-proof-{os.time()}-{math.random(1, 1e9)}`
local WORK = `{HOME}/.cache/{NAME}`
local REL = `.cache/{NAME}`
-- half a second of this perl's own user CPU, however loaded the machine is
local BURN = 'require("@lune/process").exec("perl", { "-e", "alarm 20; 1 while (times)[0] < 0.5" })'

local failed = 0
local function expect(name: string, ok: boolean, why: string?)
	print(`{if ok then "ok  " else "FAIL"} {name}{if not ok and why then `: {why}` else ""}`)
	if not ok then
		failed += 1
	end
end

local task = require("@lune/task")

local function fixture(name: string, body: string): string
	fs.writeFile(
		`{WORK}/{name}.spec.luau`,
		'return { name = "fixture", cases = { { name = "case", fn = function() ' .. body .. " end } } }"
	)
	return `{REL}/{name}.spec.luau`
end

fs.writeDir(`{WORK}/lanes`)
for n = 1, 8 do
	fs.writeFile(`{WORK}/lanes/{n}`, "")
end
local burn = fixture("burn", BURN)
local cheap = fixture("cheap", "")

for _, lanes in { `{WORK}/lanes`, "" } do
	local label = if lanes == "" then "without lanes" else "on lanes"
	local r = process.exec("lune", { "run", "tests/run", "--", "--budget", "1000:0.3", burn, cheap }, {
		cwd = HOME,
		env = { PICKMAN_JOBS = "2", PICKMAN_WORKER_LANES = lanes },
	})
	local block = {}
	local inBlock = false
	for line in string.gmatch(r.stdout, "[^\n]+") do
		if string.sub(line, 1, 13) == "over budget: " then
			inBlock = true
			table.insert(block, line)
		elseif inBlock and string.sub(line, 1, 2) == "  " then
			table.insert(block, line)
		else
			inBlock = false
		end
	end
	expect(`{label}: the run passes`, r.code == 0, `exit {r.code}\n{r.stdout}{r.stderr}`)
	expect(
		`{label}: one file over 0.3 s cpu`,
		block[1]
				== "over budget: 1 spec files over 1000 s wall or 0.3 s cpu (lesson zz-test/specs-never-burn-real-resources)"
			and #block == 2,
		table.concat(block, "\n")
	)
	local cpu = block[2]
		and string.match(block[2], "^  " .. string.gsub(burn, "%p", "%%%0") .. " %d+%.%d s wall, (%d+%.%d) s cpu$")
	expect(
		`{label}: the burning file, with its grandchild's cpu`,
		cpu ~= nil and (tonumber(cpu) :: number) >= 0.5,
		block[2]
	)
	expect(`{label}: no measurer line printed`, string.find(r.stdout, "zn-spec-cpu", 1, true) == nil)
end

-- every lane held for three seconds before the run starts: each file waits for a lane, but its own time is a 0.2 s nap,
-- so at a 1 s wall limit nothing is over unless the report used the coordinator's clock
local NAP = 'require("@lune/process").exec("sleep", { "0.2" })'
local n1 = fixture("nap1", NAP)
local n2 = fixture("nap2", NAP)
local HOLD =
	'use Fcntl qw(LOCK_EX); my $d = shift; my @held; for my $n (1 .. 8) { open(my $fh, "<", "$d/$n") or die "$d/$n: $!"; flock($fh, LOCK_EX) or die "flock: $!"; push @held, $fh } open(my $m, ">", "$d/held") or die; close $m; alarm 20; sleep 3;'
local holderDone = false
task.spawn(function()
	process.exec("perl", { "-e", HOLD, `{WORK}/lanes` })
	holderDone = true
end)
local polls = 0
while not fs.isFile(`{WORK}/lanes/held`) and polls < 200 do
	task.wait(0.05)
	polls += 1
end
expect("held: the holder has every lane", fs.isFile(`{WORK}/lanes/held`))
local started = os.clock()
local held = process.exec("lune", { "run", "tests/run", "--", "--budget", "1:1000", n1, n2 }, {
	cwd = HOME,
	env = { PICKMAN_JOBS = "2", PICKMAN_WORKER_LANES = `{WORK}/lanes` },
})
local waited = os.clock() - started
expect("held: the run passes", held.code == 0, `exit {held.code}\n{held.stdout}{held.stderr}`)
expect(`held: the run waited for the lanes ({string.format("%.1f", waited)} s)`, waited >= 2)
expect(
	"held: no file is over a 1 s wall limit for the time it waited",
	string.find(held.stdout, "over budget", 1, true) == nil,
	held.stdout
)
while not holderDone do
	task.wait(0.05)
end

pcall(fs.removeDir, WORK)
process.exit(if failed == 0 then 0 else 1)
