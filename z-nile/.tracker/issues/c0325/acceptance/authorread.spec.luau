--!strict
-- c0325 AC5: authorread.read finds the rows of the item folders of the checkout a review starts from, for an issue, a
-- raft's members and a stream, and hands them with the toml's first choices to authorship.of. Folders under .cache: two
-- checkouts (a dispatched review's author worktree and an interactive one) whose item folders hold different rows.
local authorship = require("@znile/engine/authorship")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local A: any = authorship
local R: any = require("@znile/engine/authorread")

local TOML = [[
[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
fallbacks = ["kimi"]

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
effort = "high"
fallbacks = ["kimi"]

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
effort = "medium"
fallbacks = []

[roles.implementation]
model = "claude-sonnet-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 12000000
effort = "high"
fallbacks = ["kimi"]
]]

local HEADER = "when\tsubject\tadded\tremoved\tphase\ttokens\tmodel\twall\tcpu\tai\ttest\tunmeasured\n"

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local BASE = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache/c0325-authorread`

-- one item folder `<checkout>/<name>` with a spend.d file holding the rows (phase, model, subject)
local function folder(checkout: string, name: string, rows: { { string } }): string
	local dir = `{BASE}/{checkout}/{name}`
	fs.writeDir(`{dir}/spend.d`)
	local text = HEADER
	for _, r in rows do
		text ..= `2026-11-15 08:00\t{r[3] or r[1]}\t0\t0\t{r[1]}\t\t{r[2]}\t\t\t\t\t\n`
	end
	fs.writeFile(`{dir}/spend.d/m.local-1.tsv`, text)
	return dir
end

local function writers(a: any): { string }
	local out = {}
	for _, w in a.writers do
		table.insert(out, `{w.step}:{w.model}`)
	end
	return out
end

return t.spec("c0325 authorread reads the item folders of the checkout it starts from", function(it)
	local layers = { models.parse(TOML, ".models.toml") }

	it(
		"AC5: the reader finds the rows in the item folders of the checkout it starts from (a dispatched review's author worktree and an interactive worktree), for an issue, a raft's members and a stream",
		function()
			if fs.isDir(BASE) then
				fs.removeDir(BASE)
			end
			-- the author's worktree of a dispatched review: the issue prepped on a fallback, built on claude; a raft whose
			-- members were built on two models; a stream issue
			local issueA = folder("author-wt", "issues/c0010", {
				{ "idea", "claude-fable-5-2-medium", "c0010 ok" },
				{ "prep", "kimi-code-k3.1-pro" },
				{ "build", "claude-sonnet-5-5" },
			})
			local m1 = folder("author-wt", "issues/c0011", { { "build", "claude-sonnet-5-5-high" } })
			local m2 = folder("author-wt", "issues/c0012", { { "build", "kimi-code-k3.1-pro-high" } })
			local raftA = folder("author-wt", "rafts/R0090", { { "prep", "claude-opus-5-5" } })
			local stream = folder("author-wt", "issues/c0013", { { "build", "kimi-code-k3.1-pro" } })
			-- an interactive worktree of the same items, whose rows name other models
			local issueB = folder("lead-wt", "issues/c0010", {
				{ "idea", "claude-fable-5-2-medium", "c0010 ok" },
				{ "prep", "claude-opus-5-5[1m]-high" },
				{ "build", "claude-opus-5-5[1m]" },
			})
			local empty = folder("lead-wt", "issues/c0099", {})

			-- an issue: design mode reads the prep rows of the folder it is given
			local design = R.read("design", { issueA }, layers, nil, nil)
			t.expect(writers(design)).toEqual({ "design:kimi-code-k3.1-pro" })
			t.expect(design.provenance).toBe("recorded")
			t.expect(writers(R.read("design", { issueB }, layers, nil, nil)))
				.toEqual({ "design:claude-opus-5-5" })
			-- code mode: each member of the raft is a folder
			local code = R.read("code", { m1, m2 }, layers, nil, nil)
			t.expect(writers(code)).toEqual({ "build:claude-sonnet-5-5", "build:kimi-code-k3.1-pro" })
			-- a raft: its own folder's prep rows
			t.expect(writers(R.read("raft", { raftA }, layers, nil, nil))).toEqual({ "raft:claude-opus-5-5" })
			-- a stream: the stream's issue
			t.expect(writers(R.read("stream", { stream }, layers, nil, nil)))
				.toEqual({ "build:kimi-code-k3.1-pro" })
			-- final: the idea, the design and the build of the folders it is given
			local final = R.read("final", { issueB }, layers, nil, nil)
			t.expect(writers(final)).toEqual({
				"idea:claude-fable-5-2",
				"design:claude-opus-5-5",
				"build:claude-opus-5-5",
			})
			t.expect(final.provenance).toBe("recorded")
			-- the answer follows the folders it is given, never a fixed place: the same item in two checkouts differs
			t.expect(
				A.isAuthor({ model = "kimi-code-k3.1-pro" }, R.read("design", { issueA }, layers, nil, nil))
			)
				.toBe(true)
			t.expect(
				A.isAuthor({ model = "kimi-code-k3.1-pro" }, R.read("design", { issueB }, layers, nil, nil))
			)
				.toBe(false)
			-- a folder with no row: the role's first choice stands in (the raft role has no `author` key), as `assumed`
			local none = R.read("raft", { empty }, layers, nil, nil)
			t.expect(writers(none)).toEqual({ "raft:claude-opus-5-5" })
			t.expect(none.provenance).toBe("assumed")
			t.expect(none.via).toBe("role")
			-- no folder, no role: unknown
			local bare = R.read(
				"design",
				{},
				{ models.parse("[dispatch]\nstall_seconds = 120\n", ".models.toml") },
				nil,
				nil
			)
			t.expect(bare.provenance).toBe("unknown")
			-- the live author wins over the rows, and a missing folder reads as no rows
			local live = R.read("code", { m1, `{BASE}/lead-wt/issues/none` }, layers, "grok-4.7", nil)
			t.expect(writers(live)).toEqual({ "build:grok-4.7" })
			t.expect(live.via).toBe("live")
			-- a mode that is no review mode is an error
			local ok = pcall(R.read, "nope", {}, layers, nil, nil)
			t.expect(ok).toBe(false)
		end
	)
end)
