--!strict
-- c0260 AC4 (the user's ruling of 2026-11-13, F8): `./zn idea --confirm` records who confirmed in the ticket's provenance
-- when `./zn provenance` exists on the tree (c0263), and only then; it works in both landing orders. The command is a
-- stub that logs its arguments. A fixture under .cache/c0260-provenance.
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

local CLAUDE = [=[#!/bin/bash
args="$*"
if [[ "$args" == *opus* ]]; then
  printf '## Findings\n- none\n\n## Verdict\napprove\n'
else
  printf '## Problem\n- Every ghost sounds the same.\n\n## Solution\n- Every ghost gets a scarier sound.\n\n## Non-goals\n- Ghost speed does not change.\n'
fi
echo '{"type":"result","subtype":"success","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"output_tokens":2}}'
exit 0
]=]

-- stands in for ./zn: `provenance` calls are logged and answered, everything else goes to the real script
local WRAPPER = [=[#!/bin/bash
if [[ "$1" == provenance ]]; then
  echo "$*" >> "$PROV_LOG"
  exit ${STUB_RC:-0}
fi
exec bash "$(dirname "$0")/zn.real" "$@"
]=]

local RECORD =
	"## Ask (verbatim)\n### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n\n## Interview\n### Q1\nQuestion: how?\nAnswer: sound\n"

return t.spec("c0260 --confirm records the provenance when ./zn provenance exists", function(it)
	local f = trackerfix.new("c0260-provenance", {
		[".models.toml"] = ROLES,
		["z-nile/.tracker/capture-since"] = "marker\n",
	})
	local bin = `{f.base}/bin`
	local provLog = `{f.base}/provenance.log`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/claude`, CLAUDE)
	process.exec("chmod", { "+x", `{bin}/claude` })
	local path = process.env.PATH or ""
	local wt = trackerfix.trOk(f, f.main, { "worktree", "prov-run" })
	trackerfix.trOk(f, wt, { "sync" })
	pcall(fs.removeFile, `{wt}/z-nile/engine/provenance.luau`) -- whichever order the two land in, start from none
	process.exec("cp", { `{wt}/zn`, `{wt}/zn.real` })
	fs.writeFile(`{wt}/zn`, WRAPPER)
	process.exec("chmod", { "+x", `{wt}/zn`, `{wt}/zn.real` })
	local function idea(args: { string }, env: { [string]: string }?)
		local e: { [string]: string } = { PATH = `{bin}:{path}`, PROV_LOG = provLog }
		for k, v in env or {} do
			e[k] = v
		end
		return trackerfix.tr(f, wt, args, e)
	end
	local function challenged(slug: string): (string, string)
		local id =
			string.match(trackerfix.trOk(f, wt, { "new", "issue", "c", slug, "--project", "pickman" }), "(c%d+)") :: string
		local file = `{f.base}/record.md`
		fs.writeFile(file, RECORD)
		t.expect(idea({ "idea", id, "--record", file }).ok).toBe(true)
		local r = idea({ "idea", id, "--text", "Ghosts." })
		if not r.ok then
			error(`idea failed: {r.stderr}{r.stdout}`, 0)
		end
		return id, `{wt}/pickman/.tracker/issues/{id}`
	end
	local function calls(): string
		return if fs.isFile(provLog) then fs.readFile(provLog) else ""
	end

	it("AC4: without ./zn provenance on the tree the confirmation makes no call and succeeds", function()
		local id, dir = challenged("no-provenance")
		local r = idea({ "idea", id, "--confirm", "yes" })
		t.expect(r.ok).toBe(true)
		t.expect(has(fs.readFile(`{dir}/{id}.md`), ') after round 1: "yes"')).toBe(true)
		t.expect(calls()).toBe("")
	end)

	it(
		"AC4: with it, exactly one call follows the written line, naming the event, the confirmer and the round",
		function()
			fs.writeFile(`{wt}/z-nile/engine/provenance.luau`, "return {}\n")
			local id = challenged("with-provenance")
			local r = idea({ "idea", id, "--confirm", "yes" })
			t.expect(r.ok).toBe(true)
			t.expect(calls()).toBe(`provenance record {id} confirmed --actor human:c0260-provenance --detail round=1\n`)
		end
	)

	it("AC4: a call that fails leaves the line, exits 0 and tells the user to check before running it again", function()
		local id, dir = challenged("failing-provenance")
		pcall(fs.removeFile, provLog)
		local r = idea({ "idea", id, "--confirm", "yes" }, { STUB_RC = "1" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "check provenance.md on origin/main before running it again")).toBe(true)
		t.expect(has(fs.readFile(`{dir}/{id}.md`), ') after round 1: "yes"')).toBe(true)
	end)

	it("AC4: a dispatched capture's --unattended is not a confirmation and records nothing", function()
		local id = challenged("unattended-provenance")
		pcall(fs.removeFile, provLog)
		local r = idea({ "idea", id, "--unattended" }, { ZN_DISPATCH = "1" })
		t.expect(r.ok).toBe(true)
		t.expect(calls()).toBe("")
		fs.removeDir(f.base)
	end)
end)
