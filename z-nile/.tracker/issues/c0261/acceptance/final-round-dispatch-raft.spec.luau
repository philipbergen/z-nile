--!strict
-- c0261 (design review 006 F1): `./zn dispatch zz-review <R-id> --mode raft` on a NEW raft records the review's row from
-- the author's worktree, so each member's spend rows there hold "<R-id>: design-review-NNN" with the reviewer's model
-- (`./zn spend` commits on the author's branch and pushes nothing), once, with nothing pending for `flush` to write again. Fake CLIs (@tests/lib/fakecli), fixture
-- under .cache/c0261-dispatch-raft.
local costrow = require("@znile/engine/costrow")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local MODELS = [[
order = ["claude"]

[dispatch]
stall_seconds = 5
tool_seconds = 8

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000
]]
local function issue(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 200\nstatus: {PREPARED}\n---\n\n# {id}\n`
end

return t.spec("c0261 a dispatched raft review of a new raft is recorded at once", function(it)
	it("writes the row into each member from the author's worktree and leaves nothing pending", function()
		local h = fakecli.new("c0261-dispatch-raft", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0011/c0011.md"] = issue("c0011"),
			["pickman/.tracker/issues/c0011/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0012/c0012.md"] = issue("c0012"),
			["pickman/.tracker/issues/c0012/check.sh"] = CHECK,
		})
		local function znIn(dir: string, args: { string }): fixture.Result
			local argv = { "scripts/tracker.sh" }
			for _, a in args do
				table.insert(argv, a)
			end
			return fixture.exec(dir, "bash", argv, {
				env = {
					FAKE_DIR = h.fakes,
					PATH = `{h.bin}:{process.env.PATH}`,
					ZN_AGENT_TOKEN_FILE = h.token,
					ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
					GH_TOKEN = "the-users-token",
				},
			})
		end
		local function must(r: fixture.Result): string
			if not r.ok then
				error(r.stdout .. r.stderr, 2)
			end
			return r.stdout
		end
		local wt = trackerfix.trOk(h.f, h.f.main, { "worktree", "prep-raft" })
		must(znIn(wt, { "sync" }))
		local rid = string.match(
			must(znIn(wt, { "new", "raft", "chore", "pair", "c0011", "c0012", "--project", "pickman" })),
			"(R%d+)"
		) :: string
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			`sleep 1; printf '# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
		)
		must(znIn(wt, { "dispatch", "zz-review", rid, "--mode", "raft" }))
		for _, id in { "c0011", "c0012" } do
			-- `./zn spend` commits its row on the current branch and pushes nothing (#294): it is in the author's worktree,
			-- once, and not on the dispatcher's own branch
			local dir = `{wt}/pickman/.tracker/issues/{id}`
			local rows = costrow.readMeasured(dir)
			if fs.isFile(`{dir}/spend.md`) then
				local l = ledger.parse(fs.readFile(`{dir}/spend.md`)) :: ledger.Ledger
				for _, r in l.rows do
					table.insert(rows, r)
				end
			end
			local n = 0
			for _, r in rows do
				if r.subject == `{rid}: design-review-001` then
					n += 1
					t.expect(r.model).toBe("claude-opus-5-5")
					t.expect(r.phase).toBe("design-review")
				end
			end
			t.expect(n).toBe(1) -- once: nothing is left for flush to write again
			t.expect(fakecli.rows(h, id)).toBe(nil)
		end
		local state = fakecli.state(h, rid)
		t.expect(#(state.pending or {})).toBe(0)
	end)
end)
