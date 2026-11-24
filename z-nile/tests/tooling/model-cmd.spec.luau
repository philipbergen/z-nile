--!strict
-- f0421 slice 2, step 5 (A): `./zn model`. Real git in a fixture under .cache (a bare origin, a main checkout), as
-- rounds-work-next does. The fixture's .models.toml is the design's seed text: claude has all four aliases, grok only light,
-- agent and kimi only heavy. The command reads it as pinned on origin/main, prints one line, and exits 1 when the CLI cannot
-- deliver the activity and 2 on a usage or configuration error.
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local legacyroot = require("@tests/lib/legacyroot")
local modelcmd = require("@znile/engine/modelcmd")
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
[clis.agy]
light = { model = "gemini-4-neon-medium" }
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
			"model: grok cannot deliver code-review/normal (heavy): grok does not define heavy; waiting for a worker with code-review/normal (heavy: claude, agent, kimi)"
		)
	end)

	it(
		"AC23: with no --cli, no ZN_CLI and no session variable it exits 2; ZN_CLI and the session variables name it",
		function()
			local r = zn({ "model", "design" })
			t.expect(r.code).toBe(2)
			t.expect(err(r))
				.toBe("model: which CLI is this? pass --cli <name> or set ZN_CLI (claude, grok, agent, kimi, agy)")
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

	it(
		"f0421 agy: a fifth CLI with only light, named by --cli or ZN_CLI, never by a guessed session variable",
		function()
			local code = zn({ "model", "code", "--risk", "normal" }, { ZN_CLI = "agy" })
			t.expect(code.code).toBe(0)
			t.expect(out(code)).toBe(
				"activity=code level=normal cli=agy alias=light model=gemini-4-neon-medium effort=- context=- subagent=-"
			)
			t.expect(out(zn({ "model", "light", "--cli", "agy" }))).toBe(
				"activity=- level=- cli=agy alias=light model=gemini-4-neon-medium effort=- context=- subagent=-"
			)
			-- each of these needs an alias agy does not define: exit 1 and the waiting line
			for _, c in
				{
					{ { "model", "design", "--risk", "easy" }, "design/easy (xlight: claude)" },
					{
						{ "model", "code-review", "--risk", "normal" },
						"code-review/normal (heavy: claude, agent, kimi)",
					},
					{
						{ "model", "final-review", "--risk", "normal" },
						"final-review/normal (ultra: claude)",
					},
				} :: { { any } }
			do
				local r = zn(c[1] :: { string }, { ZN_CLI = "agy" })
				t.expect(r.code).toBe(1)
				t.expect(out(r)).toBe("")
				t.expect(has(err(r), `waiting for a worker with {c[2]}`)).toBe(true)
			end
			-- the capability list is exactly what light delivers (the same as grok's)
			t.expect(out(zn({ "model", "--can" }, { ZN_CLI = "agy" })))
				.toBe("design/normal,design-review/easy,raft/normal,raft-review/easy,code/normal,code-review/easy")
			t.expect(zn({ "model", "code", "--cli", "agi" }).code).toBe(2)
		end
	)

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

	it(
		"F1: more than one session variable and no --cli or ZN_CLI exits 2 naming them; exactly one is that CLI",
		function()
			local two = zn({ "model", "design" }, { CLAUDE_CODE_SESSION_ID = "a", GROK_SESSION_ID = "b" })
			t.expect(two.code).toBe(2)
			t.expect(out(two)).toBe("")
			t.expect(err(two)).toBe(
				"model: CLAUDE_CODE_SESSION_ID and GROK_SESSION_ID are both set (a CLI started from another's shell): pass --cli <name> or set ZN_CLI"
			)
			local three = zn(
				{ "model", "--can" },
				{ CLAUDE_CODE_SESSION_ID = "a", KIMI_SESSION_ID = "k", GROK_SESSION_ID = "b" }
			)
			t.expect(three.code).toBe(2)
			t.expect(
				has(err(three), "CLAUDE_CODE_SESSION_ID, KIMI_SESSION_ID and GROK_SESSION_ID are all set")
			)
				.toBe(true)
			-- --cli and ZN_CLI still settle it
			t.expect(
				zn(
					{ "model", "design", "--cli", "grok" },
					{ CLAUDE_CODE_SESSION_ID = "a", GROK_SESSION_ID = "b" }
				).code
			).toBe(0)
			t.expect(
				zn(
					{ "model", "design" },
					{ ZN_CLI = "claude", CLAUDE_CODE_SESSION_ID = "a", GROK_SESSION_ID = "b" }
				).code
			).toBe(0)
			t.expect(has(out(zn({ "model", "design" }, { KIMI_SESSION_ID = "k" })), "cli=kimi")).toBe(false) -- kimi has no light/design: exit 1, no line
		end
	)

	it("F9: on a legacy walk a role the file lacks exits 1 naming the need, not 2", function()
		setup()
		trackerfix.elsewhere(f, {
			[".models.toml"] = '[roles.design]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 1\nmax_tokens = 5\n',
		}, "legacy models without approve")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local r = zn({ "model", "approve", "--cli", "claude" })
		t.expect(r.code).toBe(1)
		t.expect(has(err(r), "claude cannot deliver approve/normal (role approve)")).toBe(true)
		t.expect(has(err(r), "waiting for a worker with approve/normal (role approve: none)")).toBe(true)
		t.expect(zn({ "model", "design", "--cli", "claude" }).code).toBe(0)
		trackerfix.elsewhere(f, { [".models.toml"] = SEED }, "seed again")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
	end)

	it(
		"F3 (step 6): on a legacy walk ./zn model light answers from the implementation role, and says so",
		function()
			setup()
			trackerfix.elsewhere(f, {
				[".models.toml"] = legacyroot.text(TOP),
			}, "the legacy root file")
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			local r = zn({ "model", "light", "--cli", "claude" })
			t.expect(r.code).toBe(0)
			t.expect(has(out(r), "alias=light model=claude-sonnet-5-5 effort=high")).toBe(true)
			t.expect(has(err(r), "no [activities] yet: light is the implementation role's model")).toBe(true)
			t.expect(zn({ "model", "heavy", "--cli", "claude" }).code).toBe(1)
			trackerfix.elsewhere(f, { [".models.toml"] = SEED }, "seed again")
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
		end
	)

	it(
		"a spec never sees the caller's CLI: no CLI variable, no account label, and an unnamed CLI exits 2",
		function()
			for _, name in { "ZN_CLI", "ZN_ACCOUNT", table.unpack(fence.CLI_VARS) } do
				t.expect(`{name}={process.env[name] or "<unset>"}`).toBe(`{name}=<unset>`)
			end
			setup()
			-- the process's own environment, not NONE's empty strings: what a spec that forgets --cli gets
			local r = trackerfix.tr(f, f.main, { "model", "design", "--risk", "easy" }, nil)
			t.expect(r.code).toBe(2)
			t.expect(err(r))
				.toBe("model: which CLI is this? pass --cli <name> or set ZN_CLI (claude, grok, agent, kimi, agy)")
		end
	)

	it(
		"the runner clears every session variable modelcmd reads (one list there, one here, they agree)",
		function()
			local theirs: { string } = {}
			for _, pair in modelcmd.SESSION_VARS do
				table.insert(theirs, pair[1])
			end
			local ours: { string } = {}
			for _, name in fence.CLI_VARS do
				if name ~= "ZN_ACCOUNT" then
					table.insert(ours, name)
				end
			end
			table.sort(theirs)
			table.sort(ours)
			t.expect(table.concat(ours, " ")).toBe(table.concat(theirs, " "))
			t.expect(table.find(fence.STEP_VARS, "ZN_CLI") ~= nil).toBe(true)
			t.expect(table.find(fence.CLI_VARS, "ZN_ACCOUNT") ~= nil).toBe(true)
		end
	)

	it("F8: with no origin/main to read it says so, not 'no .models.toml on the walk'", function()
		setup()
		fixture.git(f.main, { "branch", "-dr", "origin/main" })
		local r = zn({ "model", "design", "--cli", "claude" })
		t.expect(r.code).toBe(2)
		t.expect(err(r)).toBe("model: cannot read .models.toml from origin/main: fetch, or check the remote")
		fixture.git(f.main, { "fetch", "-q", "origin" })
		t.expect(zn({ "model", "design", "--cli", "claude" }).code).toBe(0)
	end)
end)
