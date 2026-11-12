--!strict
-- c0277: real-time proofs, run once by check.sh and never promoted (a spec waits for nothing). Nothing beats from a discarded
-- worktree: (1) a claim's real background beater ends, saying so, when its worktree carries the discard marker (the
-- marker is planted by hand: a takeover refuses a claim whose beater keeps it alive); (2) the dispatcher stops beating
-- the claim of a step whose worktree is renamed away, instead of falling back to the stamp the step started with.
-- Fixtures under .cache/c0277-proof-beater and .cache/c0277-proof-dispatch.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local P = "pickman/.tracker/issues"
local STAMP = "preparing-lucky-violet-heron"
local MARKER = "." .. "cache/discarded"
local BEATER = "." .. "cache/tracker-beater"
local MODELS = [[
[dispatch]
stall_seconds = 20

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
]]

local h: fakecli.Harness
local wt = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
local function pushes(): number
	local text = if fs.isFile(`{h.fakes}/beatpush`) then fs.readFile(`{h.fakes}/beatpush`) else ""
	return #string.gsub(text, "[^\n]", "")
end
local function alive(pid: string): boolean
	return process.exec("kill", { "-0", pid }).ok
end
local function endsWithin(pid: string, seconds: number): boolean
	local deadline = os.time() + seconds
	while os.time() < deadline do
		if not alive(pid) then
			return true
		end
		task.wait(0.5)
	end
	return not alive(pid)
end
local SHIM =
	'#!/bin/sh\nif [ "$1" = push ]; then case "$*" in *":refs/heads/hb/"*) echo p >> "$FAKE_DIR/beatpush";; esac; fi\n'

return t.spec("c0277 real-time proofs: nothing beats from a discarded worktree", function(it)
	it("a claim's beater ends, saying why, when its worktree is discarded, and beats no more", function()
		h = fakecli.new("c0277-proof-beater", {
			[`{P}/c0100/c0100.md`] = trackerfix.stub("c0100", "c0100", "new-a-b-c"),
		})
		fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		fs.writeFile(`{h.bin}/git`, (string.gsub(fs.readFile(`{h.bin}/git`), "^#!/bin/sh\n", SHIM, 1)))
		wt = trim(fixture.exec(h.f.main, "bash", { "scripts/tracker.sh", "worktree", "c0277-beater" }, {
			env = { FAKE_DIR = h.fakes, PATH = `{h.bin}:{process.env.PATH}` },
		}).stdout)
		local r = fixture.exec(wt, "bash", { "scripts/tracker.sh", "status", "c0100", "preparing" }, {
			env = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_BEATER = "1",
				ZN_BEAT_EVERY = "1",
			},
		})
		if not r.ok then
			error(`claim failed: {r.stderr}{r.stdout}`)
		end
		local pid = string.match(fs.readFile(`{wt}/{BEATER}/c0100`), "^(%d+) %d+") or error("no beater")
		t.expect(alive(pid)).toBe(true)
		task.wait(3)
		local before = pushes()
		t.expect(before >= 2).toBe(true) -- it is beating
		fs.writeFile(
			`{wt}/{MARKER}`,
			heartbeat.discardText({
				path = wt,
				copy = `{wt}-1`,
				branch = "",
				base = "",
				items = { "c0100" },
				since = os.time(),
				pushedSha = "",
				pushed = {},
				unpushed = {},
				dirty = {},
			})
		)
		t.expect(endsWithin(pid, 20)).toBe(true)
		t.expect(has(fs.readFile(`{wt}/{BEATER}/c0100.log`), "was discarded")).toBe(true)
		local after = pushes()
		task.wait(3)
		t.expect(pushes()).toBe(after) -- and nothing beats after it
	end)

	it("the dispatcher stops beating a step whose worktree was renamed away", function()
		local fx = fakecli.new("c0277-proof-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0050/c0050.md"] = trackerfix.stub("c0050", "claimed", STAMP),
		})
		h = fx
		local function epoch(): number
			local s =
				fixture.git(h.f.origin, { "for-each-ref", "--format=%(subject)", `refs/heads/hb/{STAMP}` })
			return tonumber(string.match(s, "(%d+)%s*$")) or 0
		end
		-- the step beats for its claim; its worktree is then renamed away, as a takeover does; after that no beat may land
		fs.writeFile(
			`{h.f.base}/fakes/script.sh`,
			table.concat({
				'main="$(cd ../.. && pwd -P)"; here="$PWD"; sleep 3',
				'mv "$here" "$here-discarded-1"; sleep 2',
				'git -C "$main" fetch -q origin \'+refs/heads/hb/'
					.. STAMP
					.. ":refs/zn/hb-seen/"
					.. STAMP
					.. "'",
				'a=$(git -C "$main" log -1 --format=%s refs/zn/hb-seen/' .. STAMP .. ")",
				"sleep 5",
				'git -C "$main" fetch -q origin \'+refs/heads/hb/'
					.. STAMP
					.. ":refs/zn/hb-seen/"
					.. STAMP
					.. "'",
				'b=$(git -C "$main" log -1 --format=%s refs/zn/hb-seen/' .. STAMP .. ")",
				'[ "$a" = "$b" ] && echo quiet > "$FAKE_DIR/no-beat-after"',
				"",
			}, "\n")
		)
		fakecli.mode(h, "claude", "script")
		local started = os.time()
		fakecli.zn(h, { "dispatch", "z-design", "c0050" }, { ZN_BEAT_EVERY = "1" })
		t.expect(epoch() >= started).toBe(true) -- it beat while the worktree was there
		t.expect(fs.isFile(`{h.f.base}/fakes/no-beat-after`)).toBe(true) -- and not after it was renamed away
	end)
end)
