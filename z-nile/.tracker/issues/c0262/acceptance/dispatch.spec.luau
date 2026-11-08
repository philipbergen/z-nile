--!strict
-- c0262 AC8: `./zn dispatch zz-review <issue> --mode final` run for real with a fake CLI in a fixture (tests/lib/fakecli):
-- the CLI starts in the view folder under the state folder (not the worktree), finds the five kinds of file there, the
-- review lands in the ticket's own folder as final-review-001.md, and the record: line carries the issue. The old
-- modes still land where they did (the code review in the issue's folder).
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude"]
[dispatch]
auto_merge = []
stall_seconds = 60
tool_seconds = 60
[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 100000
]]
local ISSUE = trackerfix.stub("c0010", "first-thing", "active-quiet-copper-falcon"):gsub("raft: \n", "raft: R0010\n")
	.. "\n### Touched modules\n- `pickman/src/foo.luau`\n\n## Verification log\nthe author's words\n"
local RAFT = "---\nid: R0010\ntype: chore\ntitle: demo\nslug: demo\nsingle: true\nissues: [c0010]\ndesign: ready\ncreated: 2026-11-08\nstatus: active-quiet-copper-falcon\n---\n\n# R0010\n"

local h: fakecli.Harness
local wt: string
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
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

return t.spec("c0262 AC8 the dispatcher runs a final review in the view and lands it in the raft's folder", function(it)
	it("sets up an active raft with one member, a worktree on the raft's branch and a change in the member's module", function()
		h = fakecli.new("c0262-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/active/c0010/c0010.md"] = ISSUE,
			["pickman/.tracker/rafts/active/R0010/R0010.md"] = RAFT,
		})
		fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "R0010", ".worktree/R0010", "origin/main" })
		wt = fixture.physical(`{h.f.main}/.worktree/R0010`) :: string
		fs.writeDir(`{wt}/pickman/src`)
		fs.writeFile(`{wt}/pickman/src/foo.luau`, "return 'foo'\n")
		fs.writeFile(`{wt}/pickman/src/bar.luau`, "return 'bar'\n")
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "-c", "user.name=e2e", "-c", "user.email=e2e@example.invalid", "commit", "-qm", "work" })
	end)

	it("AC8: the CLI starts in <state>/view-<n> with the view's files, and the review lands as final-review-001.md", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			table.concat({
				'pwd -P > "$FAKE_DIR/cwd"',
				'ls > "$FAKE_DIR/files"',
				'cp implementation.patch "$FAKE_DIR/patch" 2>/dev/null',
				`printf '# Review\\n\\nVerdict: on-course\\n' > "$ZN_DISPATCH_DIR/review.md"`,
				"",
			}, "\n")
		)
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "final" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local cwd = string.gsub(fs.readFile(`{h.fakes}/cwd`), "%s+$", "")
		t.expect(string.match(cwd, "/view%-%d+$") ~= nil).toBe(true)
		t.expect(has(cwd, "/.cache/dispatch/")).toBe(true)
		t.expect(cwd == wt).toBe(false)
		local files = fs.readFile(`{h.fakes}/files`)
		for _, name in { "README.md", "ask.md", "design.md", "check.sh", "implementation.patch", "skill.md" } do
			t.expect(has(files, name)).toBe(true)
		end
		local patch = fs.readFile(`{h.fakes}/patch`)
		t.expect(has(patch, "foo.luau") and not has(patch, "bar.luau")).toBe(true)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/issues/active/c0010/final-review-001.md`)).toBe(true)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/rafts/active/R0010/final-review-001.md`)).toBe(false)
		local line = string.match(r.stdout, "record: [^\n]+") or ""
		t.expect(has(line, '-m "c0010: final-review-001"')).toBe(true)
		t.expect(has(line, "--phase code-review")).toBe(true)
		t.expect(has(line, "--issue c0010")).toBe(true)
		t.expect(has(line, "--model claude-opus-5-5")).toBe(true)
		-- the second round is numbered 002, built in a fresh view from round 2's tree
		local cwd1 = string.gsub(fs.readFile(`{h.fakes}/cwd`), "%s+$", "")
		fs.writeFile(`{wt}/pickman/src/foo.luau`, "return 'foo two'\n")
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "-c", "user.name=e2e", "-c", "user.email=e2e@example.invalid", "commit", "-qm", "work 2" })
		local again = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "final" })
		t.expect(again.ok).toBe(true)
		local cwd2 = string.gsub(fs.readFile(`{h.fakes}/cwd`), "%s+$", "")
		t.expect(cwd2 == cwd1).toBe(false)
		t.expect(has(fs.readFile(`{h.fakes}/patch`), "foo two")).toBe(true)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/issues/active/c0010/final-review-002.md`)).toBe(true)
	end)

	it("AC8: a code review still lands in the issue's folder and runs in the worktree", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			`pwd -P > "$FAKE_DIR/cwd"; printf '# Review\\n\\nVerdict: on-course\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
		)
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
		t.expect(r.ok).toBe(true)
		t.expect((string.gsub(fs.readFile(`{h.fakes}/cwd`), "%s+$", ""))).toBe(wt)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/issues/active/c0010/review-001.md`)).toBe(true)
	end)
end)
