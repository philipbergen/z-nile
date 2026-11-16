--!strict
-- c0175 AC11: every z-nile document that lists the supported CLIs names all six (claude, grok, agent, kimi, agy, opencode) and
-- their runtimes, and says what is new about the three: the headless routes, where the token count comes from, the ids, agy's
-- effort, and who may review through each. Plain reads of the repository's documents.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} does not say: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) then
		error(`{where} still says: {needle}`, 2)
	end
end
local function skill(name: string): string
	return read(`z-nile/skills/{name}/SKILL.md`)
end

return t.spec("c0175 the documents name the six CLIs", function(it)
	it("AC11: zz-rules lists the six CLIs and their six runtimes", function()
		local rules = skill("zz-rules")
		at(
			rules,
			"the supported CLIs are `claude`, `grok` and `agent` (Cursor), `kimi`, `agy` and `opencode`",
			"zz-rules"
		)
		at(
			rules,
			"`claude-cli`, `grok-cli` and `cursor-cli`, `kimi-cli`, `agy-cli` and `opencode-cli`",
			"zz-rules"
		)
	end)

	it("AC11: zz-rules states each new CLI's headless route, with its permission-skipping flag", function()
		local rules = skill("zz-rules")
		at(rules, "- **The six CLIs** (c0175).", "zz-rules")
		at(
			rules,
			"`agy -p <prompt> --output-format stream-json --model <id> --dangerously-skip-permissions [--effort <e>]`",
			"zz-rules"
		)
		at(
			rules,
			"`opencode run <prompt> -m <provider>/<model> --format json --auto --dir <cwd> --print-logs --log-level INFO [--variant <e>]`",
			"zz-rules"
		)
		at(rules, "`kimi -p <prompt> --output-format stream-json -m kimi-code/<id>`", "zz-rules")
		at(rules, "kimi takes no effort flag", "zz-rules")
		at(rules, "`--auto` cannot combine with `-p`", "zz-rules")
	end)

	it(
		"AC11: zz-rules says where each CLI's token count comes from, and that a stream with none is read from the CLI's store",
		function()
			local rules = skill("zz-rules")
			at(rules, "agy's `step_update` events and `result` carry `usage`", "zz-rules")
			at(rules, "opencode's `step_finish` carries `tokens`", "zz-rules")
			at(rules, "cache reads out", "zz-rules")
			at(rules, "`opencode export <session>`", "zz-rules")
			at(
				rules,
				"agy's conversations are protobuf, so an agy step without a count is unmeasured",
				"zz-rules"
			)
		end
	)

	it(
		"AC11: zz-rules states the ids: agy's bare names and lowered effort, opencode's opencode-<provider>-<model> and its model lines",
		function()
			local rules = skill("zz-rules")
			at(rules, "the bare names `agy models` lists", "zz-rules")
			at(rules, "Opus tops out at `high`", "zz-rules")
			at(rules, "the spend row records the lowered one", "zz-rules")
			at(rules, "`opencode-<provider>-<model>`", "zz-rules")
			at(rules, "each provider its own model line in `[families]`", "zz-rules")
			at(rules, "none passes a review kind: opencode authors, and runs a stream review", "zz-rules")
		end
	)

	it("AC11: zz-review says who may review through agy, kimi and opencode", function()
		local review = skill("zz-review")
		at(review, "**Through agy, kimi and opencode** (c0175).", "zz-review")
		at(review, "Through `agy` only Opus is a review model", "zz-review")
		at(review, "Through `kimi` the ids starting `kimi-code-k3` are review models", "zz-review")
		at(review, "An `opencode` model (`opencode-<provider>-<model>`) is never a review model", "zz-review")
		-- the review-kind paragraph is c0306's and stays as it is
		at(
			review,
			"an id starting `claude-opus-`, `claude-fable-` or `kimi-code-k3`, or starting `grok-` at effort `xhigh`",
			"zz-review"
		)
	end)

	it("AC11: zz-test and z-work name the new CLIs where they name the others", function()
		at(
			skill("zz-test"),
			"`kimi`, `agy` and `opencode` from `~/.kimi-code`, `~/.gemini` and `~/.local/share/opencode`",
			"zz-test"
		)
		at(skill("zz-test"), "**Starting a model CLI** (`claude`, `grok`, `agent`)", "zz-test")
		at(
			skill("z-work"),
			"Neither `agy --help` nor `opencode --help` lists a command you can run to start a fresh session",
			"z-work"
		)
	end)

	it("AC11: the README says the three exist and lists the six CLIs of .models.toml", function()
		local readme = read("z-nile/README.md")
		at(
			readme,
			"`kimi`, `agy` and `opencode` (DeepSeek and the other models it reaches) run a dispatched step: *exists* (c0175).",
			"README"
		)
		at(readme, "| `agy`, `kimi` and `opencode` (deepseek) as CLIs | c0175 | exists |", "README")
		at(readme, "(`claude`, `grok`, `agent`, `kimi`, `agy`, `opencode`)", "README")
		absent(readme, "*captured* (c0175)", "README")
		absent(readme, "| c0175 | captured |", "README")
	end)

	it("AC11: the root .models.toml's comments explain the new CLIs", function()
		local file = read(".models.toml")
		at(file, "[fallback.agy]", ".models.toml")
		at(file, "an effort it does not offer for the", ".models.toml")
		at(file, "it never passes a review kind (c0306), so no review role names it", ".models.toml")
		at(file, "opencode's models are recorded as opencode-<provider>-<model>", ".models.toml")
		absent(file, "reachable once opencode is added", ".models.toml")
	end)
	it(
		"AC11: zz-rules states opencode's run: subagent tokens read after the step, the cap, the retry wait, the log lines, the project file",
		function()
			local rules = skill("zz-rules")
			at(rules, "**opencode's run.**", "zz-rules")
			at(rules, "turns its snapshots and its title call off (`OPENCODE_CONFIG_CONTENT`", "zz-rules")
			at(
				rules,
				"the runner reads their tokens with `opencode export` after the step and puts them on the row",
				"zz-rules"
			)
			at(rules, "the live `max_tokens` cap sees the parent only", "zz-rules")
			at(rules, "`over max_tokens` in its detail, not killed", "zz-rules")
			at(rules, "agy's subagents are not counted (their steps carry no usage)", "zz-rules")
			at(rules, "up to five times and as long as a `retry-after` header asks", "zz-rules")
			at(
				rules,
				"its log lines are kept apart from the stderr the quota and failure words are read from",
				"zz-rules"
			)
			at(rules, "the runner makes an existing file read-only before and after the step", "zz-rules")
			at(rules, "`_s`, `_c`, `_a` and `__`, any other byte `_xHH`", "zz-rules")
		end
	)

	it(
		"AC11: z-work says what agy's and opencode's rows record, and the README worker line names opencode, not deepseek",
		function()
			at(
				skill("z-work"),
				"agy's conversations (`~/.gemini/antigravity-cli/conversations`) and opencode's sessions",
				"z-work"
			)
			at(skill("z-work"), "their rows say unmeasured", "z-work")
			local readme = read("z-nile/README.md")
			at(
				readme,
				"`kimi`, `agy`, `claude`, `grok`, `agent` or `opencode` (DeepSeek and the other models it reaches). *captured* (c0253);",
				"README"
			)
			absent(readme, "`agent` or `deepseek`", "README")
		end
	)
end)
