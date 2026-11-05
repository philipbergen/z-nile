--!strict
-- Fake model CLIs for the dispatcher's specs (c0117): `claude`, `grok` and `agent` scripts that print the stream
-- lines each real CLI prints (from c0117's probes) and act as a mode file says: `<fakes>/<cli>.<step>`, else
-- `<fakes>/<cli>`, else `ok`. Each logs how it was started to `<fakes>/log`. No real CLI and no network: a spec puts
-- the fakes first on PATH, under its own .cache folder, and the dispatcher refuses any CLI outside .cache in a check.
-- The tracker fixture under them is @tests/lib/trackerfix's.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local serde = require("@lune/serde")
local trackerfix = require("@tests/lib/trackerfix")

local fakecli = {}

local OK = {
	claude = [[echo '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":5000,"output_tokens":3},"content":[{"type":"text","text":"ok"}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"modelUsage":{"m":{"inputTokens":100,"cacheCreationInputTokens":20,"cacheReadInputTokens":5000,"outputTokens":3}}}']],
	grok = [[echo '{"type":"usage","usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":900,"output_tokens":7}}'
echo '{"type":"end","usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":900,"output_tokens":7}}']],
	agent = [[echo '{"type":"result","subtype":"success","is_error":false,"usage":{"inputTokens":300,"outputTokens":9,"cacheReadTokens":0,"cacheWriteTokens":0}}']],
}

-- The script of the fake `cli`.
function fakecli.script(cli: string): string
	local ok = OK[cli]
	-- claude spends 42 tokens before the rejection (a quota hit mid-session); the others spend nothing first
	local spent = if cli == "claude"
		then [[echo '{"type":"assistant","message":{"id":"m0","usage":{"input_tokens":40,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2},"content":[{"type":"text","text":"working"}]}}'; ]]
		else ""
	local quota = if cli == "claude"
		then [[echo '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","rateLimitType":"five_hour","resetsAt":1}}'; sleep 20]]
		else [[echo "Error: rate limit exceeded (too many requests)" >&2; exit 1]]
	local heavy = if cli == "claude"
		then [[echo "{\"type\":\"assistant\",\"message\":{\"id\":\"m$i\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":1}}}"]]
		else [[echo "{\"type\":\"usage\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":1}}"]]
	local commit = "git -c user.name=c0117-fake -c user.email=c0117-fake@example.invalid commit -q -m"
	return table.concat({
		"#!/bin/sh",
		'step=$(printf "%s" "$*" | sed -n "s/.*z-nile step \\([a-z-]*\\).*/\\1/p" | head -n 1)',
		'id=$(printf "%s" "$*" | sed -n "s/.* for \\([cfdR][0-9][0-9][0-9][0-9]\\).*/\\1/p" | head -n 1)',
		'mode=ok; [ -f "$FAKE_DIR/' .. cli .. '" ] && mode=$(cat "$FAKE_DIR/' .. cli .. '")',
		'[ -f "$FAKE_DIR/' .. cli .. '.$step" ] && mode=$(cat "$FAKE_DIR/' .. cli .. '.$step")',
		'{ echo "'
			.. cli
			.. ' step=$step mode=$mode cwd=$(pwd -P)"; echo "args=$*"; echo "dir=$ZN_DISPATCH_DIR"; '
			.. 'echo "path0=${PATH%%:*}"; echo "token=${GH_TOKEN:-} ${GITHUB_TOKEN:-}"; echo "ghdir=${GH_CONFIG_DIR:-}"; echo "broker=${ZN_PUBLISH_BROKER:-}"; echo "bashmax=${BASH_MAX_TIMEOUT_MS:-}"; } >> "$FAKE_DIR/log"',
		'case "$mode" in',
		"ok) " .. ok .. " ;;",
		"quota) " .. quota .. " ;;",
		"spentquota) " .. spent .. quota .. " ;;",
		-- the step's script (a reviewer writing its review), then tokens spent and quota: a fallthrough's first attempt
		'scriptquota) ( while :; do echo \'{"type":"system"}\'; sleep 0.5; done ) & hb=$!; id="$id" step="$step" sh "$FAKE_DIR/script.sh" >> "$FAKE_DIR/log" 2>&1; kill $hb; '
			.. spent
			.. quota
			.. " ;;",
		'fail) echo "boom" >&2; exit 1 ;;',
		"nocount) echo 'not json'; exit 0 ;;",
		'questions) printf "## Q1\\nWhich scope?\\n" > "$ZN_DISPATCH_DIR/questions.md"; ' .. ok .. " ;;",
		'cap) i=0; ( sleep 2; touch "$FAKE_DIR/grandchild-cap" ) & while [ $i -lt 20 ]; do '
			.. heavy
			.. "; i=$((i+1)); done; sleep 20 ;;",
		-- the CLI's own wait message (stdout, not JSON): a stall after it is quota
		"wait) echo 'Usage limit reached, retrying in 60s'; sleep 20 ;;",
		"stall) echo 'thinking'; sleep 20 ;;",
		-- a cursor stream with no model_call_id at all: four turns, then quiet (the call cap can't be trusted)
		[[noids) for c in 1 2 3 4; do echo '{"type":"thinking","subtype":"delta"}'; echo '{"type":"tool_call","subtype":"started","call_id":"x'$c'"}'; echo '{"type":"tool_call","subtype":"completed","call_id":"x'$c'"}'; done; sleep 20 ;;]],
		-- a detached process pushes code to main after the step has ended (the watermark's to catch at the next run)
		[[late) git fetch -q origin main; git checkout -q -B late FETCH_HEAD; echo late > late.lua; git add late.lua; git -c user.name=c0117-fake -c user.email=c0117-fake@example.invalid commit -q -m late; perl -e 'setpgrp(0,0); exec @ARGV' sh -c "sleep 1; \"$ZN_REAL_GIT\" push -q origin HEAD:main" > /dev/null 2>&1 < /dev/null & ]]
			.. OK.claude
			.. " ;;",
		-- three model calls (distinct model_call_id), then quiet: a cursor step's max_calls is what stops it
		[[calls) for c in 1 1 2 3; do echo "{\"type\":\"tool_call\",\"subtype\":\"started\",\"call_id\":\"t$c\",\"model_call_id\":\"m-$c\"}"; done; sleep 20 ;;]],
		-- the model's own words about waiting and trying again: a stall after them is a stall, not quota
		[[prose) echo '{"type":"assistant","message":{"id":"m9","content":[{"type":"text","text":"Rate limit? I will try again, waiting for the gate"}]}}'; sleep 20 ;;]],
		-- a quiet tool call longer than the stall limit, under the tool limit
		[[tool) echo '{"type":"assistant","message":{"id":"m9","content":[{"type":"tool_use","id":"t1","name":"Bash"}]}}'; sleep 3; echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}'; ]]
			.. ok
			.. " ;;",
		'stop) ( sleep 2; touch "$FAKE_DIR/grandchild-stop" ) & echo \'{"type":"system"}\'; sleep 0.5; ./zn dispatch stop "$FAKE_STOP" >> "$FAKE_DIR/log" 2>&1; sleep 20 ;;',
		-- the dispatcher dies mid-step: the supervisor's lifeline kills the group
		'orphan) ( sleep 3; touch "$FAKE_DIR/grandchild-orphan" ) & echo \'{"type":"system"}\'; kill -9 "$ZN_DISPATCHER_PID"; sleep 20 ;;',
		'ticket) ( while :; do echo \'{"type":"system"}\'; sleep 0.5; done ) & hb=$!; ./zn new issue c dispatched-thing --project pickman --desc \'from the fake\' >> "$FAKE_DIR/log" 2>&1; kill $hb; '
			.. ok
			.. " ;;",
		-- a claim through the publish broker (the agent's credential can't push to main)
		'claim) ( while :; do echo \'{"type":"system"}\'; sleep 0.5; done ) & hb=$!; ./zn status "$id" preparing >> "$FAKE_DIR/log" 2>&1; echo "claim=$?" >> "$FAKE_DIR/log"; kill $hb; '
			.. ok
			.. " ;;",
		"push) echo note > notes.txt; git add notes.txt; "
			.. commit
			.. ' note; git push -q origin HEAD:main 2>> "$FAKE_DIR/log"; echo "push=$?" >> "$FAKE_DIR/log"; gh pr merge 7 --squash 2>> "$FAKE_DIR/log"; echo "merge=$?" >> "$FAKE_DIR/log"; '
			.. ok
			.. " ;;",
		-- past the wrapper with the real git: the tripwire's to catch
		"tripwire) git fetch -q origin main; git checkout -q -B tripwire FETCH_HEAD; echo code > code.lua; git add code.lua; "
			.. commit
			.. ' code; "$ZN_REAL_GIT" push -q origin HEAD:main 2>> "$FAKE_DIR/log"; echo "realpush=$?" >> "$FAKE_DIR/log"; '
			.. ok
			.. " ;;",
		-- an author that starts its review through the dispatcher, as the headless rule says
		'author) ( while :; do echo \'{"type":"system"}\'; sleep 0.5; done ) & hb=$!; ./zn dispatch zz-review "$id" --mode design >> "$FAKE_DIR/log" 2>&1; echo "review=$?" >> "$FAKE_DIR/log"; kill $hb; '
			.. ok
			.. " ;;",
		'reviewer) git status --short > /dev/null; echo "gitstatus=$?" >> "$FAKE_DIR/log"; printf "# Review 001\\n\\nVerdict: approve\\n" > "$ZN_DISPATCH_DIR/review.md"; '
			.. ok
			.. " ;;",
		-- whatever <fakes>/script.sh does, inside the step (a spec's own misbehaving step), with a heartbeat
		'script) ( while :; do echo \'{"type":"system"}\'; sleep 0.5; done ) & hb=$!; id="$id" step="$step" sh "$FAKE_DIR/script.sh" >> "$FAKE_DIR/log" 2>&1; echo "script=$?" >> "$FAKE_DIR/log"; kill $hb; '
			.. ok
			.. " ;;",
		-- an author that runs a tool (its review, one shell command) and waits on it in silence, as a real CLI does
		[[waitreview) echo '{"type":"assistant","message":{"id":"m9","content":[{"type":"tool_use","id":"t1","name":"Bash"}]}}'; ./zn dispatch zz-review "$id" --mode design >> "$FAKE_DIR/log" 2>&1; echo "review=$?" >> "$FAKE_DIR/log"; echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}'; ]]
			.. ok
			.. " ;;",
		-- a reviewer that works for 16 s, printing every second, then writes its review
		'slowreview) for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do echo \'{"type":"system"}\'; sleep 1; done; printf "# Review 001\\n\\nVerdict: approve\\n" > "$ZN_DISPATCH_DIR/review.md"; '
			.. ok
			.. " ;;",
		-- an author that waits on its review outside any tool call (its own limit is stall_seconds)
		[[waitplain) echo '{"type":"system"}'; ./zn dispatch zz-review "$id" --mode design >> "$FAKE_DIR/log" 2>&1; echo "review=$?" >> "$FAKE_DIR/log"; ]]
			.. ok
			.. " ;;",
		-- a reviewer silent for 18 s inside one tool call (within its tool_seconds), then its review
		[[silenttool) echo '{"type":"assistant","message":{"id":"m9","content":[{"type":"tool_use","id":"t1","name":"Bash"}]}}'; sleep 18; echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}'; printf "# Review 001\n\nVerdict: approve\n" > "$ZN_DISPATCH_DIR/review.md"; ]]
			.. ok
			.. " ;;",
		-- a reviewer that goes quiet past its own stall limit
		"quietreview) sleep 20; " .. ok .. " ;;",
		"esac",
		"",
	}, "\n")
end

export type Harness = {
	f: trackerfix.Fixture,
	bin: string,
	fakes: string,
	token: string, -- the agent's token file
}

-- A tracker fixture `.cache/<name>` with `seed`, the three fakes, a fake gh and an agent token file.
function fakecli.new(name: string, seed: { [string]: string }): Harness
	local f = trackerfix.new(name, seed)
	local bin, fakes = `{f.base}/bin`, `{f.base}/fakes`
	fs.writeDir(bin)
	fs.writeDir(fakes)
	for _, cli in { "claude", "grok", "agent" } do
		fs.writeFile(`{bin}/{cli}`, fakecli.script(cli))
		process.exec("chmod", { "+x", `{bin}/{cli}` })
	end
	-- a fake real gh: `pr view <branch>` prints <fakes>/pr-<branch>.json; `pr merge` logs and marks it merged
	fs.writeFile(
		`{bin}/gh`,
		table.concat({
			"#!/bin/sh",
			'echo "realgh $*" >> "$FAKE_DIR/log"',
			-- `api …/commits/<sha>/pulls` prints <fakes>/pulls-<sha>.json, else [] (the watermark's PR rule)
			'if [ "$1" = api ]; then sha=$(printf "%s" "$2" | sed -n "s#.*/commits/\\([0-9a-f]*\\)/pulls#\\1#p"); cat "$FAKE_DIR/pulls-$sha.json" 2>/dev/null || echo "[]"; exit 0; fi',
			'if [ "$1" = pr ] && [ "$2" = view ]; then cat "$FAKE_DIR/pr-$3.json" 2>/dev/null || exit 1; exit 0; fi',
			'if [ "$1" = pr ] && [ "$2" = merge ]; then for p in "$FAKE_DIR"/pr-*.json; do sed -i.bak "s/\\"OPEN\\"/\\"MERGED\\"/" "$p"; done; exit 0; fi',
			"exit 0",
			"",
		}, "\n")
	)
	process.exec("chmod", { "+x", `{bin}/gh` })
	-- git itself, but a fetch into a run's own ref fails while <fakes>/fetchfail counts down (a lock another process
	-- holds: review 005 F1's retry)
	local real = (string.gsub(process.exec("sh", { "-c", "command -v git" }).stdout, "%s+$", ""))
	fs.writeFile(
		`{bin}/git`,
		table.concat({
			"#!/bin/sh",
			'if [ "$1" = fetch ] && [ -f "$FAKE_DIR/fetchfail" ]; then case "$*" in *refs/zn-dispatch/run-*) '
				.. 'n=$(cat "$FAKE_DIR/fetchfail"); if [ "$n" -gt 0 ]; then echo $((n-1)) > "$FAKE_DIR/fetchfail"; '
				.. 'echo "error: cannot lock ref (fake)" >&2; exit 1; fi ;; esac; fi',
			`exec "{real}" "$@"`,
			"",
		}, "\n")
	)
	process.exec("chmod", { "+x", `{bin}/git` })
	local token = `{f.base}/agent-token`
	fs.writeFile(token, "fake-agent-token\n")
	local h = { f = f, bin = bin, fakes = fakes, token = token }
	-- the user's first vet: no run trusts a missing watermark (review 003 F2)
	local vet = fakecli.zn(h, { "dispatch", "vet" })
	assert(vet.ok, `dispatch vet failed in the fixture: {vet.stdout}{vet.stderr}`)
	fakecli.clear(h)
	return h
end

-- A pull request `n` on the fixture's origin: a commit on main's tip with `files` written and `moves` (from -> to)
-- made, pushed to `refs/pull/<n>/head` as GitHub keeps it. Returns its sha.
function fakecli.pullRequest(
	h: Harness,
	n: number,
	files: { [string]: string },
	moves: { [string]: string }?,
	message: string?,
	deletes: { string }?
): string
	local other = h.f.other
	fixture.git(other, { "fetch", "-q", "origin", "main" })
	fixture.git(other, { "checkout", "-q", "-B", `pr-{n}`, "FETCH_HEAD" })
	local gone_: { string } = deletes or {}
	for _, gone in gone_ do
		fixture.git(other, { "rm", "-q", gone })
	end
	local renames: { [string]: string } = moves or {}
	for from, to in renames do
		local parent = string.match(to, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{other}/{parent}`)
		end
		fixture.git(other, { "mv", from, to })
	end
	for path, text in files do
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{other}/{parent}`)
		end
		fs.writeFile(`{other}/{path}`, text)
	end
	fixture.git(other, { "add", "-A" })
	fixture.git(other, { "commit", "-q", "-m", message or `pull request {n}` })
	local sha = fixture.git(other, { "rev-parse", "HEAD" })
	fixture.git(other, { "push", "-q", "-f", "origin", `HEAD:refs/pull/{n}/head` })
	fixture.git(other, { "checkout", "-q", "main" })
	return sha
end

-- A forward commit on origin's main (what z-ready or another rafting PR does while a PR waits): `files` written and
-- `moves` (from -> to) made on main's tip, pushed to main.
function fakecli.advanceMain(h: Harness, files: { [string]: string }, moves: { [string]: string }?)
	local other = h.f.other
	fixture.git(other, { "fetch", "-q", "origin", "main" })
	fixture.git(other, { "checkout", "-q", "-B", "advance", "FETCH_HEAD" })
	local moved: { [string]: string } = moves or {}
	for from, to in moved do
		local parent = string.match(to, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{other}/{parent}`)
		end
		fixture.git(other, { "mv", from, to })
	end
	for path, text in files do
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{other}/{parent}`)
		end
		fs.writeFile(`{other}/{path}`, text)
	end
	fixture.git(other, { "add", "-A" })
	fixture.git(other, { "commit", "-q", "-m", "main moves on" })
	fixture.git(other, { "push", "-q", "origin", "HEAD:refs/heads/main" })
	fixture.git(other, { "checkout", "-q", "main" })
end

function fakecli.mode(h: Harness, name: string, value: string?)
	local p = `{h.fakes}/{name}`
	if value then
		fs.writeFile(p, value)
	elseif fs.isFile(p) then
		fs.removeFile(p)
	end
end

function fakecli.clear(h: Harness)
	for _, name in fs.readDir(h.fakes) do
		fs.removeFile(`{h.fakes}/{name}`)
	end
end

-- `./zn <args>` in the fixture's main checkout, with the fakes first on PATH, the agent's token file, and the user's
-- (fake) token in GH_TOKEN, which a step must never see.
function fakecli.zn(h: Harness, args: { string }, extra: { [string]: string }?): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		-- the watermark lives outside the repository; in a spec, in the fixture's own folder (the jail closes $HOME)
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
		GH_TOKEN = "the-users-token",
	}
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	return fixture.exec(h.f.main, "bash", argv, { env = env })
end

function fakecli.log(h: Harness): string
	return if fs.isFile(`{h.fakes}/log`) then fs.readFile(`{h.fakes}/log`) else ""
end

function fakecli.state(h: Harness, id: string, sub: string?): any
	local dir = `{h.f.main}/.cache/dispatch/{id}` .. (if sub then "/" .. sub else "")
	return serde.decode("json", fs.readFile(`{dir}/state.json`))
end

-- The rows of an issue's spend.md on origin/main, or nil.
function fakecli.rows(h: Harness, id: string): { ledger.Row }?
	local r = fixture.exec(h.f.origin, "git", { "show", `main:pickman/.tracker/issues/{id}/spend.md` })
	if not r.ok then
		return nil
	end
	return (ledger.parse(r.stdout .. "\n") :: ledger.Ledger).rows
end

return fakecli
