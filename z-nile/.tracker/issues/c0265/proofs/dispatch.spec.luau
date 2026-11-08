--!strict
-- c0265: a model step the dispatcher runs on a claimed item beats for it while the step works (ZN_BEAT_EVERY=1 makes the
-- interval one second), with the fake CLIs of @tests/lib/fakecli. Fixture under .cache/c0265-dispatch.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local STAMP = "preparing-lucky-violet-heron"
local MODELS = [[
order = ["claude"]

[dispatch]
stall_seconds = 10

[z-design.claude]
model = "claude-opus-5-5"
rank = 3
runtime = "claude-cli"
max_tokens = 5000
]]

local h: fakecli.Harness
-- the epochs of the beats origin holds for STAMP
local function epochs(): { number }
	local out = {}
	local subjects =
		fixture.git(h.f.origin, { "for-each-ref", "--format=%(subject)", `refs/heads/hb/{STAMP}` })
	for line in string.gmatch(subjects, "[^\n]+") do
		table.insert(out, tonumber(string.match(line, "(%d+)$")) :: number)
	end
	return out
end

return t.spec("c0265 the dispatcher beats", function(it)
	it("sets up a claimed issue and the fake CLIs", function()
		h = fakecli.new("c0265-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0050/c0050.md"] = trackerfix.stub("c0050", "claimed", STAMP),
		})
		-- the step waits (up to 30 s) until origin holds a beat dated two seconds after the step began: a dispatcher that
		-- beats only before or after the step never satisfies it
		fs.writeFile(
			`{h.f.base}/fakes/script.sh`,
			table.concat({
				"start=$(date +%s); i=0",
				"while [ $i -lt 15 ]; do",
				'  git fetch -q origin "+refs/heads/hb/'
					.. STAMP
					.. ":refs/zn/hb-seen/"
					.. STAMP
					.. '" 2>/dev/null',
				"  s=$(git log -1 --format=%s refs/zn/hb-seen/" .. STAMP .. " 2>/dev/null); e=${s##* }",
				'  if [ -n "$e" ] && [ "$e" -ge $((start+2)) ]; then echo seen > "$FAKE_DIR/beat-seen"; exit 0; fi',
				"  sleep 1; i=$((i+1))",
				"done",
				"",
			}, "\n")
		)
		fakecli.mode(h, "claude", "script")
	end)

	it("a model step on a claimed item leaves a beat dated after it started, and keeps one ref", function()
		t.expect(#epochs()).toBe(0)
		local started = os.time()
		fakecli.zn(h, { "dispatch", "z-design", "c0050" }, { ZN_BEAT_EVERY = "1" })
		t.expect(fs.isFile(`{h.f.base}/fakes/beat-seen`)).toBe(true) -- a beat came while the step worked
		local seen = epochs()
		t.expect(seen[1] >= started).toBe(true)
		t.expect(seen[1] <= os.time()).toBe(true)
	end)
end)
