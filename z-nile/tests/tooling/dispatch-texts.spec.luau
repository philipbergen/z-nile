--!strict
-- R0052 code review 001 (c0117): F5, the model steps' skills and zz-rules' Landing say that under the dispatcher a
-- step neither asks nor merges at its PR (the user's G4), and z-design's scope question goes to questions.md; F6,
-- `.models.toml` takes only a model id the ledger takes (one predicate); F8, no comment states a decided guess as
-- pending or two runtimes per CLI. Reads the real tree.
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} is missing: {needle}`)
	end
end
local HEADLESS =
	"Under the dispatcher, don't ask and don't merge: once the PR is open and your spend is recorded, end the step; the dispatcher passes the gate (the user started it)."

return t.spec("c0117 the dispatcher's texts and model ids (R0052 code review 001)", function(it)
	it(
		"z-design, z-raft and zz-rules say a dispatched step neither asks nor merges at its PR (F5)",
		function()
			local zd = read("z-nile/skills/z-design/SKILL.md")
			at(zd, "Ask the user before merging prep they didn't request. " .. HEADLESS, "z-design §6")
			at(
				zd,
				"ask the user before you answer it (under the dispatcher: write the question to `$ZN_DISPATCH_DIR/questions.md` and stop)",
				"z-design §5"
			)
			at(read("z-nile/skills/z-raft/SKILL.md"), HEADLESS, "z-raft §5")
			at(
				read("z-nile/skills/zz-rules/SKILL.md"),
				"Under the dispatcher, a step neither asks nor merges: once its PR is open and its spend recorded it ends, and the dispatcher passes the prep and rafting gates itself (the user started it, c0117 G4).",
				"zz-rules Landing step 3"
			)
		end
	)

	it("a model id the ledger refuses is refused in .models.toml, with its effort (F6)", function()
		local function parse(model: string, effort: string?): (boolean, string)
			local text =
				`order = ["claude"]\n[z-design.claude]\nmodel = "{model}"\nrank = 1\nruntime = "claude-cli"\nmax_tokens = 9\n`
			if effort then
				text ..= `effort = "{effort}"\n`
			end
			local ok, e = pcall(models.parse, text, "x/.models.toml")
			return ok, tostring(e)
		end
		local ok, why = parse("claude opus/5")
		t.expect(ok).toBe(false)
		t.expect(string.find(why, "not a model id the ledger takes", 1, true) ~= nil).toBe(true)
		t.expect((parse("claude-opus-5-5", "very high"))).toBe(false)
		t.expect((parse("claude-opus-5-5", "high"))).toBe(true)
		t.expect(ledger.isModel("claude opus/5")).toBe(false)
	end)

	it("no comment calls a decided guess pending, or gives a CLI two runtimes (F8)", function()
		t.expect(string.find(read(".models.toml"), "Guess (pending user)", 1, true)).toBe(nil)
		t.expect(string.find(read("z-nile/engine/models.luau"), "each with its two runtimes", 1, true))
			.toBe(nil)
	end)
end)
