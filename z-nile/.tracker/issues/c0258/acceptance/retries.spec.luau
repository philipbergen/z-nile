--!strict
-- c0258 AC3 through the command: one `./zn land` makes exactly landrace.TRIES pushes, each lost race merging the new main
-- and pushing again with no new gate run when every move was tracker state, and a land whose every push loses gives up
-- after the last one, pushes nothing of its own and leaves the tree clean; run again, it lands.
-- (That the last try may still land is landrace.spec's: a case here for it would cost another ten pushes.)
-- One fixture (trackerfix, .cache/c0258-retries): one draft backlog issue seeded on origin, the case a capture worktree
-- made with raw git from origin/main. The gate is PICKMAN_LAND_GATE, a script that counts its runs.
-- A stand-in git first on PATH for land alone counts land's pushes and, before each of the first LAND_RACES of them,
-- pushes a tracker-state commit from the other clone, so those pushes lose.
-- Reviewed exception to the fixture rule (as c0072's race case): the stand-in runs raw git only in the fixture's
-- `other` clone under this spec's .cache folder, and forwards every other call to the real git.
-- `./zn` runs with a plain session's environment (no publish broker, no dispatcher git on PATH: d0355).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local landrace = require("@znile/engine/landrace")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local IDS = { "c0001" }
local function doc(id: string): string
	return `pickman/.tracker/issues/{id}/{id}.md`
end
local seed: { [string]: string } = {}
for _, id in IDS do
	seed[doc(id)] = trackerfix.stub(id, `topic-{id}`, "new-plain-quiet-otter")
end
local F = trackerfix.new("c0258-retries", seed)

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return git(F.origin, { "rev-parse", "main" })
end
local function said(r: Result): string
	return `exit {r.code}\n{r.stdout}\n{r.stderr}`
end
-- a capture worktree from origin/main whose one commit adds a line to issue `id`'s document
local function capture(name: string, id: string): string
	git(F.main, { "fetch", "-q", "origin" })
	local wt = `{F.main}/.worktree/{name}`
	git(F.main, { "worktree", "add", "-q", "-b", name, wt, "origin/main" })
	local path = `{wt}/{doc(id)}`
	fs.writeFile(path, fs.readFile(path) .. `\nMore about {id}.\n`)
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-q", "-m", `tracker: new {id} topic-{id}` })
	return wt
end
-- bash that appends one measured gate row for this branch to the checkout's buffer, as check.sh's measure does
local ROW =
	[[mkdir -p .cache && printf '%s000\ttest\ttest\tstatic\t3\t2\t\t\t\t\t\t\t%s\t\n' "$(date +%s)" "$(git rev-parse --abbrev-ref HEAD)" >> .cache/measure.tsv]]
-- a gate script that counts its runs in <base>/<name>.count and records its spend row, so land has a fold to undo
local function gate(name: string): (string, string)
	local count = `{F.base}/{name}.count`
	local path = `{F.base}/{name}.sh`
	fs.writeFile(
		path,
		`#!/bin/bash\nn=$(( $(cat "{count}" 2>/dev/null || echo 0) + 1 ))\necho "$n" > "{count}"\n{ROW}\nexit 0\n`
	)
	return `bash {path}`, count
end
local function runs(count: string): number
	return if fs.isFile(count) then tonumber((string.gsub(fs.readFile(count), "%s", ""))) or 0 else 0
end
-- the stand-in git: before each of the first LAND_RACES pushes it pushes a tracker-state commit from the other clone
local FAKE = `{F.base}/fakebin`
fs.writeDir(FAKE)
fs.writeFile(
	`{FAKE}/git`,
	table.concat({
		"#!/bin/bash",
		-- never itself again (lesson zz-test/forwarding-stand-ins-never-find-themselves): zn puts ~/.rokit/bin in
		-- front of this folder, so the folder leaves every position of PATH, and a nested run stops at once
		'[[ -n ${LAND_FAKE_IN:-} ]] && { echo "stand-in git ran inside itself" >&2; exit 97; }',
		"export LAND_FAKE_IN=1",
		'self=$(cd "$(dirname "$0")" && pwd -P)',
		'p=":$PATH:"; p=${p//":$self:"/":"}; p=${p#:}; PATH=${p%:}',
		"if [[ $1 == push ]]; then",
		'  echo x >> "$LAND_RACE_COUNT.pushes"',
		'  n=$(cat "$LAND_RACE_COUNT" 2>/dev/null || echo 0)',
		"  if (( n < LAND_RACES )); then",
		'    echo $((n + 1)) > "$LAND_RACE_COUNT"',
		'    ( cd "$LAND_OTHER" && git pull -q origin main && echo "$n" > "pickman/.tracker/raced-${LAND_RACE_COUNT##*/}-$n.txt" && git add -A && git commit -qm "race $n" && git push -q origin HEAD:main ) || exit 9',
		"  fi",
		"fi",
		'exec git "$@"',
		"",
	}, "\n")
)
process.exec("chmod", { "+x", `{FAKE}/git` })
-- a plain session's environment (d0355) with the stand-in first on PATH
local function faked(env: { [string]: string }): { [string]: string }
	local keep: { string } = { FAKE }
	for part in string.gmatch(process.env.PATH or "", "[^:]+") do
		if not string.match(part, "/z%-nile/bin/?$") then
			table.insert(keep, part)
		end
	end
	env.PATH = table.concat(keep, ":")
	env.ZN_PUBLISH_BROKER = ""
	env.ZN_PUBLISH_TOKEN = ""
	-- land kicks the watch net after a push: not in a fixture
	env.PICKMAN_WATCH_NET = "off"
	env.ZN_DISPATCH = ""
	return env
end

local function pushes(races: string): number
	local path = `{races}.pushes`
	return if fs.isFile(path) then #string.split(string.gsub(fs.readFile(path), "%s+$", ""), "\n") else 0
end

return t.spec("c0258 land retries", function(it)
	it(
		"AC3: a land whose every push loses makes exactly ten pushes and one gate run, then gives up cleanly; run again it lands",
		function()
			local wt = capture("capture-lost", "c0001")
			local before = tip()
			local cmd, count = gate("lost")
			local races = `{F.base}/lost.races`
			local r = trackerfix.tr(
				F,
				wt,
				{ "land" },
				faked({
					PICKMAN_LAND_GATE = cmd,
					LAND_RACES = tostring(landrace.TRIES + 5),
					LAND_RACE_COUNT = races,
					LAND_OTHER = F.other,
				})
			)
			if r.ok or not has(r.stderr, "lost the race") then
				error(said(r))
			end
			t.expect(
				has(r.stderr, `lost the race to main {landrace.TRIES} times: run land again (last push: `)
			)
				.toBe(true)
			t.expect(pushes(races)).toBe(landrace.TRIES)
			t.expect(runs(count)).toBe(1)
			t.expect(git(F.origin, { "rev-list", "--count", `{before}..main` }))
				.toBe(tostring(landrace.TRIES))
			t.expect(has(git(F.origin, { "log", "--format=%s", `{before}..main` }), "tracker: new c0001"))
				.toBe(false)
			t.expect(git(wt, { "status", "--porcelain", "--untracked-files=all" })).toBe("")
			-- the races stop: the same branch lands on its next run, after its one gate run
			local again = trackerfix.tr(
				F,
				wt,
				{ "land" },
				faked({
					PICKMAN_LAND_GATE = cmd,
					LAND_RACES = "0",
					LAND_RACE_COUNT = races,
					LAND_OTHER = F.other,
				})
			)
			if not again.ok then
				error(said(again))
			end
			t.expect(runs(count)).toBe(2)
			t.expect(git(F.origin, { "log", "-1", "--format=%s", "main" }))
				.toBe("tracker: new c0001 topic-c0001")
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(tip())
			local landed = git(F.origin, { "diff", "--name-only", "main^", "main" })
			t.expect(has(landed, "pickman/.tracker/issues/c0001/spend.d/")).toBe(true)
		end
	)
end)
