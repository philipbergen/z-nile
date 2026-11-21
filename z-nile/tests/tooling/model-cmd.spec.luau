--!strict
-- f0421 slice 2, step 5 (A): `./zn model`. Real git in a fixture under .cache (a bare origin, a main checkout), as
-- rounds-work-next does. The fixture's .models.toml is the design's seed text: claude has all four aliases, grok only light,
-- agent and kimi only heavy. The command reads it as pinned on origin/main, prints one line, and exits 1 when the CLI cannot
-- deliver the activity and 2 on a usage or configuration error.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"

local CLIS = [[
[clis.claude]
xlight = { model = "claude-haiku-5-5", effort = "low" }
light = { model = "claude-sonnet-5-5", effort = "medium" }
heavy = { model = "claude-opus-5-5", effort = "high" }
ultra = { model = "claude-fable-5-2", effort = "xhigh", context = 1000000 }
[clis.grok]
light = { model = "grok-4.7", effort = "high" }
[clis.agent]
heavy = { model = "claude-opus-5-5", effort = "high" }
max_calls = 200
max_minutes = 240
[clis.kimi]
heavy = { model = "kimi-code-k3.1-pro" }
]]
local ACTIVITIES = [[
[activities.idea]
max_tokens = 300000
all = "heavy"
[activities.idea-challenge]
max_tokens = 300000
all = "ultra"
[activities.design]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.design-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.raft]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.raft-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.code]
max_tokens = 12000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.code-review]
max_tokens = 2000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.final-review]
max_tokens = 2000000
all = "ultra"
[activities.approve]
max_tokens = 3000000
all = "heavy"
]]
local SEED = CLIS .. ACTIVITIES

local function issue(id: string, risk: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-16\n{risk}status: {PREPARED}\n---\n\n# {id}\n\n## Problem\nx\n`
end

local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{string.gsub(
		issues,
		", ",
		"\n"
	)}\n`
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local f: trackerfix.Fixture = nil :: any
local NONE: { [string]: string } =
	{ ZN_CLI = "", CLAUDE_CODE_SESSION_ID = "", KIMI_SESSION_ID = "", GROK_SESSION_ID = "" }

local function setup()
	if f ~= nil then
		return
	end
	f = trackerfix.new("f0421-model-cmd", {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[".models.toml"] = SEED,
		[`{ROOT}/issues/c0010/c0010.md`] = issue("c0010", "risk: risky\n"),
		[`{ROOT}/issues/c0011/c0011.md`] = issue("c0011", ""),
		[`{ROOT}/issues/c0012/c0012.md`] = issue("c0012", "risk: easy\n"),
		[`{ROOT}/rafts/R0010/R0010.md`] = raftDoc("R0010", "c0011, c0012"),
		[`{ROOT}/rafts/R0020/R0020.md`] = raftDoc("R0020", "c0012, c0010"),
	})
end

local function zn(args: { string }, env: { [string]: string }?): fixture.Result
	setup()
	local merged: { [string]: string } = table.clone(NONE)
	for k, v in (env or {}) :: { [string]: string } do
		merged[k] = v
	end
	return trackerfix.tr(f, f.main, args, merged)
end

local function out(r: fixture.Result): string
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function err(r: fixture.Result): string
	return (string.gsub(r.stderr, "%s+$", ""))
end

return t.spec("f0421 slice 2: ./zn model", function(it)
	it("AC23: prints the design's one line and exits 0", function()
		local r = zn({ "model", "code-review", "--risk", "normal", "--cli", "claude" })
		t.expect(r.code).toBe(0)
		t.expect(out(r)).toBe(
			"activity=code-review level=normal cli=claude alias=heavy model=claude-opus-5-5 effort=high context=- subagent=opus"
		)
		local ultra = zn({ "model", "final-review", "--risk", "easy", "--cli", "claude" })
		t.expect(out(ultra)).toBe(
			"activity=final-review level=easy cli=claude alias=ultra model=claude-fable-5-2 effort=xhigh context=1000000 subagent=fable"
		)
		-- another CLI's model has no Agent-tool word, and an unset effort is a dash
		local kimi = zn({ "model", "approve", "--cli", "kimi" })
		t.expect(out(kimi)).toBe(
			"activity=approve level=normal cli=kimi alias=heavy model=kimi-code-k3.1-pro effort=- context=- subagent=-"
		)
		t.expect(select("#", string.gsub(out(r), "\n", ""))).toBe(2)
	end)

	it("AC23: a CLI that cannot deliver exits 1, naming the need and the waiting line, on stderr", function()
		local r = zn({ "model", "code-review", "--risk", "normal", "--cli", "grok" })
		t.expect(r.code).toBe(1)
		t.expect(out(r)).toBe("")
		t.expect(err(r)).toBe(
			"model: grok cannot deliver code-review/normal (heavy): grok does not define heavy; waiting for a worker with code-review/normal (heavy)"
		)
	end)

	it(
		"AC23: with no --cli, no ZN_CLI and no session variable it exits 2; ZN_CLI and the session variables name it",
		function()
			local r = zn({ "model", "design" })
			t.expect(r.code).toBe(2)
			t.expect(err(r))
				.toBe("model: which CLI is this? pass --cli <name> or set ZN_CLI (claude, grok, agent, kimi)")
			t.expect(has(out(zn({ "model", "design" }, { ZN_CLI = "grok" })), "cli=grok")).toBe(true)
			t.expect(has(out(zn({ "model", "design" }, { CLAUDE_CODE_SESSION_ID = "abc" })), "cli=claude"))
				.toBe(true)
			t.expect(zn({ "model", "approve" }, { KIMI_SESSION_ID = "abc" }).code).toBe(0)
			t.expect(has(out(zn({ "model", "design" }, { GROK_SESSION_ID = "abc" })), "cli=grok")).toBe(true)
			-- --cli beats ZN_CLI
			t.expect(
				has(out(zn({ "model", "design", "--cli", "claude" }, { ZN_CLI = "grok" })), "cli=claude")
			)
				.toBe(true)
		end
	)

	it("AC23: --for uses the item's risk, and a raft's highest member", function()
		t.expect(
			has(
				out(zn({ "model", "code", "--for", "c0010", "--cli", "claude" })),
				"level=risky cli=claude alias=heavy"
			)
		).toBe(true)
		t.expect(
			has(
				out(zn({ "model", "code", "--for", "c0012", "--cli", "claude" })),
				"level=easy cli=claude alias=xlight"
			)
		).toBe(true)
		-- no risk is normal
		t.expect(
			has(
				out(zn({ "model", "code", "--for", "c0011", "--cli", "claude" })),
				"level=normal cli=claude alias=light"
			)
		).toBe(true)
		-- R0010 is normal and easy: normal. R0020 is easy and risky: risky.
		t.expect(
			has(out(zn({ "model", "code-review", "--for", "R0010", "--cli", "claude" })), "level=normal")
		)
			.toBe(true)
		t.expect(
			has(
				out(zn({ "model", "code-review", "--for", "R0020", "--cli", "claude" })),
				"level=risky cli=claude alias=ultra"
			)
		).toBe(true)
		-- an unknown id is a usage error
		t.expect(zn({ "model", "code", "--for", "c9999", "--cli", "claude" }).code).toBe(2)
	end)

	it("AC23: --can prints canList comma-separated on one line", function()
		local r = zn({ "model", "--can", "--cli", "grok" })
		t.expect(r.code).toBe(0)
		t.expect(out(r))
			.toBe("design/normal,design-review/easy,raft/normal,raft-review/easy,code/normal,code-review/easy")
		local all = out(zn({ "model", "--can", "--cli", "claude" }))
		t.expect(#string.split(all, ",")).toBe(30)
		t.expect((string.find(all, "\n", 1, true))).toBe(nil)
		t.expect(zn({ "model", "--can", "--cli", "kimi" }).code).toBe(0)
	end)

	it(
		"an alias argument prints the alias with no activity or level; usage errors exit 2 on stderr",
		function()
			t.expect(out(zn({ "model", "light", "--cli", "grok" })))
				.toBe("activity=- level=- cli=grok alias=light model=grok-4.7 effort=high context=- subagent=-")
			local lacking = zn({ "model", "heavy", "--cli", "grok" })
			t.expect(lacking.code).toBe(1)
			t.expect(has(err(lacking), "grok does not define heavy")).toBe(true)
			for _, bad in
				{
					{ "model" },
					{ "model", "nap", "--cli", "claude" },
					{ "model", "code", "--risk", "high", "--cli", "claude" },
					{ "model", "code", "--risk", "easy", "--for", "c0010", "--cli", "claude" },
					{ "model", "code", "--cli", "gemini" },
					{ "model", "--can", "design", "--cli", "claude" },
				}
			do
				local r = zn(bad)
				if r.code ~= 2 or out(r) ~= "" then
					error(
						`{table.concat(bad, " ")}: wanted exit 2 and no stdout, got {r.code}: {out(r)} {err(r)}`
					)
				end
			end
		end
	)

	it("a configuration error exits 2 naming the file and the rule", function()
		setup()
		trackerfix.elsewhere(
			f,
			{ [".models.toml"] = '[clis.claude]\nlight = { model = "gpt-4" }\n' },
			"bad models"
		)
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local r = zn({ "model", "design", "--cli", "claude" })
		t.expect(r.code).toBe(2)
		t.expect(err(r))
			.toBe("model: .models.toml: clis.claude.light.model is gpt-4, not a model of cli claude")
	end)

	it("it reads origin/main's copy, never the working tree, and writes nothing", function()
		setup()
		trackerfix.elsewhere(f, { [".models.toml"] = SEED }, "good models again")
		fixture.git(f.main, { "fetch", "-q", "origin" })
		fs.writeFile(`{f.main}/.models.toml`, "[nope]\n")
		local before = fixture.git(f.main, { "status", "--porcelain" })
		local r = zn({ "model", "design", "--risk", "easy", "--cli", "claude" })
		t.expect(r.code).toBe(0)
		t.expect(has(out(r), "alias=xlight")).toBe(true)
		t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe(before)
		fixture.git(f.main, { "checkout", "--", ".models.toml" })
	end)

	it("./zn help still prints the usage (main.luau got no top-level local), with the model lines", function()
		local r = zn({ "help" })
		t.expect(r.code).toBe(1)
		local text = r.stdout .. r.stderr
		t.expect(has(text, "usage:")).toBe(true)
		t.expect(has(text, "model <activity|alias>")).toBe(true)
		t.expect(has(text, "Out of local registers")).toBe(false)
	end)
end)
