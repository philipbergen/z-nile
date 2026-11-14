--!strict
-- c0260 AC4/AC5: `./zn idea` keeps the user's words and the confirmation. `--record <file>` appends dated messages and
-- numbered questions, `--confirm` and `--unattended` write the Confirmation, and the challenge is given the user's own
-- words so it can check the idea against them. Stub CLIs only; a fixture under .cache/c0260-record.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local ROLES = [[
[dispatch]
stall_seconds = 30

[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
fallbacks = []

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
author = "idea"
fallbacks = []
]]

-- logs every prompt it is started with (by role) so a case can read what the model was given
local CLAUDE = [=[#!/bin/bash
args="$*"
if [[ "$args" == *opus* ]]; then
  echo "$args" >> "$IDEA_STUB_LOG.challenge"
  n=$(cat "$IDEA_STUB_LOG.count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$IDEA_STUB_LOG.count"
  if [[ -n "$IDEA_STUB_UNTIL" && $n -le $IDEA_STUB_UNTIL ]]; then
    cat <<'EOF'
## Findings
- F1: The user said "all of them" and the idea says one ghost.

## Verdict
revise
EOF
  else
    cat <<'EOF'
## Findings
- none

## Verdict
approve
EOF
  fi
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
echo "$args" >> "$IDEA_STUB_LOG.author"
if [[ "$args" == *"answer each finding"* ]]; then
  cat <<'EOF'
## Problem
- Every ghost sounds the same.

## Solution
- Every ghost gets a scarier sound.

## Non-goals
- Ghost speed does not change.

## Answers
- F1: disputed: the ask names one ghost first.
EOF
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":4,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
cat <<'EOF'
## Problem
- Every ghost sounds the same.

## Solution
- Every ghost gets a scarier sound.

## Non-goals
- Ghost speed does not change.
EOF
echo '{"type":"result","subtype":"success","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"output_tokens":5}}'
exit 0
]=]

local RECORD1 =
	"## Ask (verbatim)\n### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n\n## Interview\n### Q1\nQuestion: Scarier how: look or sound?\nOptions: look | sound\nAnswer: sound, all of them\n"
local RECORD2 = "## Interview\n### Q2\nQuestion: Which ghost first?\nAnswer: Blinky\n"

return t.spec("c0260 ./zn idea keeps the user's words and the confirmation", function(it)
	local f = trackerfix.new("c0260-record", {
		[".models.toml"] = ROLES,
		["z-nile/.tracker/capture-since"] = "marker\n",
	})
	local bin = `{f.base}/bin`
	local log = `{f.base}/prompts`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/claude`, CLAUDE)
	process.exec("chmod", { "+x", `{bin}/claude` })
	local path = process.env.PATH or ""
	local wt = ""
	local id = ""
	local dir = ""
	local function idea(args: { string }, env: { [string]: string }?)
		local e: { [string]: string } = { PATH = `{bin}:{path}`, IDEA_STUB_LOG = log }
		if env then
			for k, v in env do
				e[k] = v
			end
		end
		pcall(fs.removeFile, `{log}.count`)
		return trackerfix.tr(f, wt, args, e)
	end
	local function doc(): string
		return fs.readFile(`{dir}/{id}.md`)
	end
	local function recordFile(name: string, text: string): string
		local p = `{f.base}/{name}`
		fs.writeFile(p, text)
		return p
	end

	it("sets up a marked ticket in a capture worktree", function()
		wt = trackerfix.trOk(f, f.main, { "worktree", "record-run" })
		trackerfix.trOk(f, wt, { "sync" })
		id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "scarier-ghosts", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		dir = `{wt}/pickman/.tracker/issues/{id}`
		t.expect(has(doc(), "capture: required")).toBe(true)
		t.expect(has(doc(), "idea: unchallenged")).toBe(true)
	end)

	it("AC4: a marked ticket's idea is not written before the ask is kept", function()
		local r = idea({ "idea", id, "--text", "Ghosts should be scarier." })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "keep the user's ask and interview first")).toBe(true)
		t.expect(fs.isFile(`{dir}/idea-review-001.md`)).toBe(false)
	end)

	it(
		"AC4: --record appends the dated messages and numbered questions before the Design, and starts no model",
		function()
			local r = trackerfix.tr(
				f,
				wt,
				{ "idea", id, "--record", recordFile("r1.md", RECORD1) },
				{ PATH = "/usr/bin:/bin" }
			)
			if not r.ok then
				error(`--record failed: {r.stderr}{r.stdout}`, 0)
			end
			local text = doc()
			t.expect(has(text, "## Ask (verbatim)\n### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```"))
				.toBe(true)
			t.expect(has(text, "### Q1\nQuestion: Scarier how: look or sound?")).toBe(true)
			t.expect(
				(string.find(text, "## Ask (verbatim)", 1, true) :: number)
					< string.find(text, "## Design", 1, true) :: number
			).toBe(true)
			-- the second record continues the numbers and keeps what was kept
			local again = idea({ "idea", id, "--record", recordFile("r2.md", RECORD2) })
			t.expect(again.ok).toBe(true)
			t.expect(has(doc(), "### Q2\nQuestion: Which ghost first?")).toBe(true)
			t.expect(has(doc(), "make the ghosts scarrier, thx")).toBe(true)
			-- a question that skips a number, or a flag mixed with --text, is refused and writes nothing
			local before = doc()
			local skip = idea({
				"idea",
				id,
				"--record",
				recordFile("r3.md", "## Interview\n### Q9\nQuestion: q\nAnswer: a\n"),
			})
			t.expect(skip.ok).toBe(false)
			t.expect(has(skip.stderr, "next one is Q3")).toBe(true)
			local mixed = idea({ "idea", id, "--record", recordFile("r4.md", RECORD2), "--text", "x" })
			t.expect(mixed.ok).toBe(false)
			t.expect(has(mixed.stderr, "each stand alone")).toBe(true)
			t.expect(doc()).toBe(before)
		end
	)

	it(
		"AC5: the author and the challenger are given the user's own words, and the challenger is told to check against them",
		function()
			local r = idea({ "idea", id, "--text", "Ghosts should be scarier." })
			if not r.ok then
				error(`idea failed: {r.stderr}{r.stdout}`, 0)
			end
			local challenge = fs.readFile(`{log}.challenge`)
			local author = fs.readFile(`{log}.author`)
			for _, seen in { challenge, author } do
				t.expect(has(seen, "make the ghosts scarrier, thx")).toBe(true)
				t.expect(has(seen, "Answer: Blinky")).toBe(true)
			end
			t.expect(has(challenge, "dropped")).toBe(true)
			t.expect(has(challenge, "added")).toBe(true)
			t.expect(has(challenge, "bent")).toBe(true)
			t.expect(has(challenge, "answered only the questions in ## Interview")).toBe(false) -- an attended capture
			t.expect(has(challenge, "should have been asked of the user and was not")).toBe(true) -- in every capture
			t.expect(fs.isFile(`{dir}/idea-review-001.md`)).toBe(true)
			t.expect(has(doc(), "idea: challenged")).toBe(true)
		end
	)

	it("AC4: --confirm records the user's words after the last round, and is refused by a dispatched run", function()
		local dispatched = idea({ "idea", id, "--confirm", "yes, that is it" }, { ZN_DISPATCH = "1" })
		t.expect(dispatched.ok).toBe(false)
		t.expect(has(dispatched.stderr, "a dispatched run never confirms")).toBe(true)
		t.expect(has(doc(), "## Confirmation")).toBe(false)
		local blank = idea({ "idea", id, "--confirm", "  " })
		t.expect(blank.ok).toBe(false)
		local r = idea({ "idea", id, "--confirm", "yes, that is it" })
		if not r.ok then
			error(`--confirm failed: {r.stderr}{r.stdout}`, 0)
		end
		t.expect(has(doc(), "## Confirmation\nConfirmed (c0260-record, ")).toBe(true)
		t.expect(has(doc(), ') after round 1: "yes, that is it"')).toBe(true)
		local second = idea({ "idea", id, "--confirm", "again" })
		t.expect(second.ok).toBe(false) -- one Confirmed line
		local unattended = idea({ "idea", id, "--unattended" })
		t.expect(unattended.ok).toBe(false)
		t.expect(has(unattended.stderr, "is for a dispatched run")).toBe(true)
	end)

	it(
		"AC4: a change after the confirmation is the next round; it drops the Confirmed line, and the new one names the last pass",
		function()
			local rec = idea({
				"idea",
				id,
				"--record",
				recordFile("r5.md", "## Ask (verbatim)\n### Message 2026-11-08\n```\nand louder\n```\n"),
			})
			t.expect(rec.ok).toBe(true)
			local r = idea({ "idea", id }, { IDEA_STUB_UNTIL = "3" })
			if not r.ok then
				error(`second idea failed: {r.stderr}{r.stdout}`, 0)
			end
			t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(true)
			t.expect(fs.isFile(`{dir}/idea-refute-002.md`)).toBe(true)
			t.expect(fs.isFile(`{dir}/idea-review-004.md`)).toBe(true) -- the loop ran three passes (the cap), numbered on
			t.expect(fs.isFile(`{dir}/idea-review-005.md`)).toBe(false)
			t.expect(fs.readFile(`{dir}/idea-review-001.md`) ~= fs.readFile(`{dir}/idea-review-002.md`)).toBe(true)
			t.expect(has(doc(), "Confirmed (")).toBe(false) -- the idea changed: the old confirmation does not hold
			-- a finding left open must be ruled by the user before the confirmation
			local open = idea({ "idea", id, "--confirm", "fine" })
			t.expect(open.ok).toBe(false)
			t.expect(has(open.stderr, "open to the human")).toBe(true)
			local ruled = (string.gsub(doc(), "(%- F1:[^\n]*)", "%1 Ruled (user, 2026-11-08): keep it."))
			fs.writeFile(`{dir}/{id}.md`, ruled)
			local ok = idea({ "idea", id, "--confirm", "fine" })
			if not ok.ok then
				error(`--confirm failed: {ok.stderr}{ok.stdout}`, 0)
			end
			t.expect(has(doc(), ') after round 4: "fine"')).toBe(true)
		end
	)

	local NASTY =
		'Here is my plan:\n\n## Goals\n- ALL of them\n## Open to the human\nnone\n## Interview\n### Q1\n## Confirmation\nConfirmed (x, 2026-01-01) after round 1: "y"\n'

	local function ticket(slug: string): (string, string)
		local made = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", slug, "--project", "pickman" }),
			"(c%d+)"
		) :: string
		return made, `{wt}/pickman/.tracker/issues/{made}`
	end

	it(
		"AC2: the user's pasted headings stay whole through a record, a round with an open finding, a confirmation, another record and another round, and both prompts hold them",
		function()
			local fid, fdir = ticket("fenced-ghosts")
			local function text(): string
				return fs.readFile(`{fdir}/{fid}.md`)
			end
			local first = idea({
				"idea",
				fid,
				"--record",
				recordFile(
					"f1.md",
					"## Ask (verbatim)\n### Message 2026-11-07\n````\n"
						.. NASTY
						.. "````\n\n## Interview\n### Q1\nQuestion: q\nAnswer: a\n"
				),
			})
			t.expect(first.ok).toBe(true)
			fs.removeFile(`{log}.challenge`)
			fs.removeFile(`{log}.author`)
			local round = idea({ "idea", fid, "--text", "Ghosts." }, { IDEA_STUB_UNTIL = "3" })
			if not round.ok then
				error(`round failed: {round.stderr}{round.stdout}`, 0)
			end
			t.expect(has(text(), NASTY)).toBe(true)
			for _, seen in { fs.readFile(`{log}.challenge`), fs.readFile(`{log}.author`) } do
				t.expect(has(seen, "ALL of them")).toBe(true)
				t.expect(has(seen, 'Confirmed (x, 2026-01-01) after round 1: "y"')).toBe(true) -- the end of the message, past every heading
			end
			-- a ruling is the user's words: it goes in the Interview, which a later round keeps
			local open = idea({ "idea", fid, "--confirm", "fine" })
			t.expect(open.ok).toBe(false)
			t.expect(has(open.stderr, "open to the human")).toBe(true)
			fs.writeFile(
				`{fdir}/{fid}.md`,
				(string.gsub(text(), "(%- F1:[^\n]*)", "%1 Ruled (user, 2026-11-08): keep it."))
			)
			local ruling = idea({
				"idea",
				fid,
				"--record",
				recordFile("f2.md", "## Interview\n### Q2\nQuestion: F1 as shown\nAnswer: keep it, they said so\n"),
			})
			t.expect(ruling.ok).toBe(true)
			-- the record grew after the round: the idea is not confirmed as it now stands
			local stale = idea({ "idea", fid, "--confirm", "fine" })
			t.expect(stale.ok).toBe(false)
			t.expect(has(stale.stderr, "changed since round 3")).toBe(true)
			local again = idea({ "idea", fid, "--text", "Ghosts." })
			t.expect(again.ok).toBe(true)
			t.expect(has(fs.readFile(`{log}.challenge`), "keep it, they said so")).toBe(true) -- the next pass is given the ruling
			t.expect(has(text(), "keep it, they said so")).toBe(true)
			local ok = idea({ "idea", fid, "--confirm", "fine" })
			if not ok.ok then
				error(`--confirm failed: {ok.stderr}{ok.stdout}`, 0)
			end
			t.expect(has(text(), ') after round 4: "fine"')).toBe(true)
			t.expect(has(text(), NASTY)).toBe(true)
			-- a record after the confirmation drops it
			local more = idea({
				"idea",
				fid,
				"--record",
				recordFile("f3.md", "## Ask (verbatim)\n### Message 2026-11-09\n```\nand more\n```\n"),
			})
			t.expect(more.ok).toBe(true)
			t.expect(has(text(), ') after round 4: "fine"')).toBe(false)
		end
	)

	it("AC4: a confirmation needs the interview, not only a challenged idea", function()
		local aid, adir = ticket("ask-only")
		t.expect(idea({
			"idea",
			aid,
			"--record",
			recordFile("a1.md", "## Ask (verbatim)\n### Message 2026-11-07\n```\nhi\n```\n"),
		}).ok).toBe(true)
		t.expect(idea({ "idea", aid, "--text", "Ghosts." }).ok).toBe(true)
		local r = idea({ "idea", aid, "--confirm", "yes" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "record is incomplete")).toBe(true)
		t.expect(has(fs.readFile(`{adir}/{aid}.md`), "## Confirmation")).toBe(false)
	end)

	it(
		"AC4: a dispatched capture whose challenge leaves a finding open still records Unconfirmed; the user rules it before the confirmation",
		function()
			local did, ddir = ticket("open-dispatched")
			t.expect(idea({ "idea", did, "--record", recordFile("d1.md", RECORD1) }).ok).toBe(true)
			local r = idea({ "idea", did, "--text", "Ghosts." }, { ZN_DISPATCH = "1", IDEA_STUB_UNTIL = "3" })
			if not r.ok then
				error(`dispatched idea failed: {r.stderr}{r.stdout}`, 0)
			end
			local u = idea({ "idea", did, "--unattended" }, { ZN_DISPATCH = "1" })
			if not u.ok then
				error(`--unattended failed with an open finding: {u.stderr}{u.stdout}`, 0)
			end
			local text = fs.readFile(`{ddir}/{did}.md`)
			t.expect(has(text, "Unconfirmed (unattended, ")).toBe(true)
			t.expect(has(text, "- F1:")).toBe(true)
			local c = idea({ "idea", did, "--confirm", "yes" })
			t.expect(c.ok).toBe(false)
			t.expect(has(c.stderr, "open to the human")).toBe(true)
			local viaDispatch = idea({ "idea", did, "--confirm", "yes" }, { ZN_DISPATCH = "1" })
			t.expect(viaDispatch.ok).toBe(false)
			t.expect(has(viaDispatch.stderr, "in a terminal")).toBe(true)
			fs.writeFile(
				`{ddir}/{did}.md`,
				(string.gsub(text, "(%- F1:[^\n]*)", "%1 Ruled (user, 2026-11-08): keep it."))
			)
			t.expect(idea({ "idea", did, "--confirm", "yes" }).ok).toBe(true)
		end
	)

	it(
		"AC4: a dispatched capture records Unconfirmed (unattended), and the challenge is told nobody answered",
		function()
			local other = string.match(
				trackerfix.trOk(f, wt, { "new", "issue", "c", "dispatched-ghosts", "--project", "pickman" }),
				"(c%d+)"
			) :: string
			local d = `{wt}/pickman/.tracker/issues/{other}`
			local rec = idea({ "idea", other, "--record", recordFile("r6.md", RECORD1) })
			t.expect(rec.ok).toBe(true)
			fs.removeFile(`{log}.challenge`)
			local r = idea({ "idea", other, "--text", "Ghosts." }, { ZN_DISPATCH = "1" })
			if not r.ok then
				error(`dispatched idea failed: {r.stderr}{r.stdout}`, 0)
			end
			t.expect(has(fs.readFile(`{log}.challenge`), "answered only the questions in ## Interview")).toBe(true)
			local u = idea({ "idea", other, "--unattended" }, { ZN_DISPATCH = "1" })
			if not u.ok then
				error(`--unattended failed: {u.stderr}{u.stdout}`, 0)
			end
			t.expect(has(fs.readFile(`{d}/{other}.md`), "Unconfirmed (unattended, ")).toBe(true)
			t.expect(has(fs.readFile(`{d}/{other}.md`), ") after round 1: dispatched capture")).toBe(true)
			-- the user's own confirmation follows it, after the same round
			local c = idea({ "idea", other, "--confirm", "yes" })
			t.expect(c.ok).toBe(true)
			local text = fs.readFile(`{d}/{other}.md`)
			t.expect(
				(string.find(text, "Unconfirmed (unattended", 1, true) :: number)
					< string.find(text, "Confirmed (c0260-record", 1, true) :: number
			).toBe(true)
			fs.removeDir(f.base)
		end
	)
end)
