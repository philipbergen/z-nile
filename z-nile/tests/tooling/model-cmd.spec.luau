--!strict
-- f0421 slice 2, step 5 (A): `./zn model`. Real git in a fixture under .cache (a bare origin, a main checkout), as
-- rounds-work-next does. The fixture's .models.toml is the design's seed text: claude has all four aliases, grok only light,
-- agent and kimi only heavy. The command reads it as pinned on origin/main, prints one line, and exits 1 when the CLI cannot
-- deliver the activity and 2 on a usage or configuration error.
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
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
xlight = { model = "gemini-4-neon-low" }
light = { model = "gemini-4-neon-medium" }
heavy = { model = "gemini-4-neon-high" }
[clis.agy.review]
light = { model = "gemini-4-argon-medium" }
heavy = { model = "gemini-4-argon-high" }
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
	{ ZN_CLI = "", ZN_MODEL = "", CLAUDE_CODE_SESSION_ID = "", KIMI_SESSION_ID = "", GROK_SESSION_ID = "" }

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
			"model: grok cannot deliver code-review/normal (heavy): grok does not define heavy; waiting for a worker with code-review/normal (heavy: claude, agent, kimi, agy running gemini-4-argon-high)"
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
		"f0421 agy: a fifth CLI that writes with Neon and reviews with Argon, named by --cli or ZN_CLI only",
		function()
			local function modelOf(args: { string }, session: string): string
				local r = zn(args, { ZN_CLI = "agy", ZN_MODEL = session })
				t.expect(r.code).toBe(0)
				return string.match(out(r), "model=(%S+)") :: string
			end
			t.expect(modelOf({ "model", "code", "--risk", "normal" }, "gemini-4-neon-medium"))
				.toBe("gemini-4-neon-medium")
			t.expect(modelOf({ "model", "design", "--risk", "easy" }, "gemini-4-neon-low"))
				.toBe("gemini-4-neon-low")
			t.expect(modelOf({ "model", "code-review", "--risk", "normal" }, "gemini-4-argon-high"))
				.toBe("gemini-4-argon-high")
			t.expect(modelOf({ "model", "design-review", "--risk", "easy" }, "gemini-4-argon-medium"))
				.toBe("gemini-4-argon-medium")
			t.expect(
				out(
					zn(
						{ "model", "code", "--risk", "normal" },
						{ ZN_CLI = "agy", ZN_MODEL = "gemini-4-neon-medium" }
					)
				)
			).toBe(
				"activity=code level=normal cli=agy alias=light model=gemini-4-neon-medium effort=- context=- subagent=-"
			)
			t.expect(out(zn({ "model", "light", "--cli", "agy" }, { ZN_MODEL = "gemini-4-neon-medium" })))
				.toBe(
					"activity=- level=- cli=agy alias=light model=gemini-4-neon-medium effort=- context=- subagent=-"
				)
			-- no ultra anywhere: these wait for another worker
			for _, c in
				{
					{
						{ "model", "final-review", "--risk", "normal" },
						"final-review/normal (ultra: claude)",
					},
					{ { "model", "code-review", "--risk", "risky" }, "code-review/risky (ultra: claude)" },
				} :: { { any } }
			do
				local r = zn(c[1] :: { string }, { ZN_CLI = "agy", ZN_MODEL = "gemini-4-neon-medium" })
				t.expect(r.code).toBe(1)
				t.expect(out(r)).toBe("")
				t.expect(has(err(r), `waiting for a worker with {c[2]}`)).toBe(true)
			end
			t.expect(zn({ "model", "code", "--cli", "agi" }).code).toBe(2)
		end
	)

	it(
		"f0421: a review whose writer is unknown has no same-model field, and one that is known says yes or no",
		function()
			local plain = zn({ "model", "code-review", "--for", "c0011", "--cli", "claude" })
			t.expect(plain.code).toBe(0)
			t.expect(has(out(plain), "same-model")).toBe(false)
			local spec = require("@znile/engine/models").resolveReview
			t.expect(spec ~= nil).toBe(true)
			local line = modelcmd.line("code-review", "normal", {
				cli = "claude",
				model = "claude-opus-5-5",
				effort = "high",
				rank = 3,
				runtime = "claude-cli",
				maxTokens = 1,
			}, true)
			t.expect(line).toBe(
				"activity=code-review level=normal cli=claude alias=- model=claude-opus-5-5 effort=high context=- subagent=opus same-model=yes"
			)
			t.expect(has(
				modelcmd.line(nil, nil, {
					cli = "claude",
					model = "claude-opus-5-5",
					rank = 3,
					runtime = "claude-cli",
					maxTokens = 1,
				}, false),
				"same-model=no"
			)).toBe(true)
		end
	)

	it(
		"f0421: a CLI without subagents that runs several models needs ZN_MODEL, and is handed only that model's activities",
		function()
			local function agy(args: { string }, model: string?): fixture.Result
				return zn(args, { ZN_CLI = "agy", ZN_MODEL = model or "" })
			end
			-- no ZN_MODEL: one plain line naming the models, exit 2
			local bare = agy({ "model", "code", "--risk", "normal" })
			t.expect(bare.code).toBe(2)
			t.expect(err(bare)).toBe(
				"model: agy runs more than one model (gemini-4-argon-high, gemini-4-argon-medium, gemini-4-neon-high, gemini-4-neon-low, gemini-4-neon-medium): set ZN_MODEL to the one this session runs"
			)
			-- a model the table does not hold is refused
			local wrong = agy({ "model", "code", "--risk", "normal" }, "gemini-4-nope")
			t.expect(wrong.code).toBe(2)
			t.expect(has(err(wrong), "ZN_MODEL gemini-4-nope is not a model of agy")).toBe(true)
			-- a neon-medium session writes at normal
			local neon = agy({ "model", "code", "--risk", "normal" }, "gemini-4-neon-medium")
			t.expect(neon.code).toBe(0)
			t.expect(has(out(neon), "model=gemini-4-neon-medium")).toBe(true)
			t.expect(out(agy({ "model", "--can" }, "gemini-4-neon-medium")))
				.toBe("design/normal,raft/normal,code/normal")
			-- and is handed no review: exit 1, and the line names the worker that is needed
			local review = agy({ "model", "code-review", "--risk", "normal" }, "gemini-4-neon-medium")
			t.expect(review.code).toBe(1)
			t.expect(
				has(
					err(review),
					"waiting for a worker with code-review/normal (heavy: claude, agent, kimi, agy running gemini-4-argon-high)"
				)
			).toBe(true)
			-- an argon-high session reviews at normal and writes nothing
			t.expect(out(agy({ "model", "--can" }, "gemini-4-argon-high")))
				.toBe("design-review/normal,raft-review/normal,code-review/normal")
			t.expect(agy({ "model", "code-review", "--risk", "normal" }, "gemini-4-argon-high").code).toBe(0)
			t.expect(agy({ "model", "code", "--risk", "normal" }, "gemini-4-argon-high").code).toBe(1)
			-- the four other CLIs are as they were, with the variable and without it
			for _, cli in { "claude", "grok", "agent", "kimi" } do
				local without = zn({ "model", "--can", "--cli", cli })
				local with = zn({ "model", "--can", "--cli", cli }, { ZN_MODEL = "gemini-4-neon-medium" })
				t.expect(with.code).toBe(without.code)
				t.expect(out(with)).toBe(out(without))
			end
			t.expect(out(zn({ "model", "code", "--risk", "normal", "--cli", "claude" }, { ZN_MODEL = "x" })))
				.toBe(
					"activity=code level=normal cli=claude alias=light model=claude-sonnet-5-5 effort=medium context=- subagent=sonnet"
				)
		end
	)

	it("f0421: the writer's recorded model decides same-model, through ./zn model --for", function()
		setup()
		local dir = `{f.main}/{ROOT}/issues/c0011`
		local function row(model: string): string
			return ledger.append(nil, "c0011", "c0011", {
				when = "2026-11-21 10:00",
				subject = "build",
				added = 0,
				removed = 0,
				minutes = 0,
				how = "explicit",
				phase = "build",
				tokens = 10,
				model = model,
			})
		end
		-- code-review at normal is heavy: claude-opus-5-5 at high
		fs.writeFile(`{dir}/spend.md`, row("claude-opus-5-5-high"))
		local same = zn({ "model", "code-review", "--for", "c0011", "--cli", "claude" })
		fs.removeFile(`{dir}/spend.md`)
		t.expect(same.code).toBe(0)
		t.expect(has(out(same), " same-model=yes")).toBe(true)
		fs.writeFile(`{dir}/spend.md`, row("claude-sonnet-5-5-medium"))
		local other = zn({ "model", "code-review", "--for", "c0011", "--cli", "claude" })
		fs.removeFile(`{dir}/spend.md`)
		t.expect(other.code).toBe(0)
		t.expect(has(out(other), " same-model=no")).toBe(true)
		-- no row: the writer is unknown, and the line has no such field
		local none = zn({ "model", "code-review", "--for", "c0011", "--cli", "claude" })
		t.expect(has(out(none), "same-model")).toBe(false)
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
				-- ANTIGRAVITY_AGENT is agy's agent marker, cleared for the terminal fixtures (agentenv.spec), not a session
				-- variable modelcmd reads
				if name ~= "ZN_ACCOUNT" and name ~= "ZN_MODEL" and name ~= "ANTIGRAVITY_AGENT" then
					table.insert(ours, name)
				end
			end
			table.sort(theirs)
			table.sort(ours)
			t.expect(table.concat(ours, " ")).toBe(table.concat(theirs, " "))
			t.expect(table.find(fence.STEP_VARS, "ZN_CLI") ~= nil).toBe(true)
			t.expect(table.find(fence.CLI_VARS, "ZN_ACCOUNT") ~= nil).toBe(true)
			-- the session's model is a caller-identifying variable too: the runner clears it
			t.expect(modelcmd.MODEL_VAR).toBe("ZN_MODEL")
			t.expect(table.find(fence.CLI_VARS, modelcmd.MODEL_VAR) ~= nil).toBe(true)
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
