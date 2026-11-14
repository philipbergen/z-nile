--!strict
-- c0306 AC6 and the commit half of AC8: ./zn done judges the code and final reviews of a marked raft (its own folder and its
-- members', every round, never a stream review) and passes an unmarked raft; ./zn commit --phase code-review stamps each
-- new review file with --model and --effort (CLAUDE_EFFORT when none), and refuses a new review file without --model.
-- Two fixtures under .cache, each a repository with this tree's tooling and no remote (as c0084's): `a` an unmarked raft,
-- `b` a marked one. Ids come from the commands' output.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache`

-- the identity rides in the environment: a runner nested in the fixture refuses a fixture identity in its config
local TERMINAL: { [string]: string } = {
	GIT_AUTHOR_NAME = "done",
	GIT_AUTHOR_EMAIL = "done@example.invalid",
	GIT_COMMITTER_NAME = "done",
	GIT_COMMITTER_EMAIL = "done@example.invalid",
	CLAUDECODE = "",
	AI_AGENT = "",
	CLAUDE_EFFORT = "",
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local TR = "pickman/.tracker"

local dir = ""
local raft, issue = "", ""

local function run(cmd: string, args: { string }, extra: { [string]: string }?): Result
	local env: { [string]: string } = table.clone(TERMINAL)
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	return fixture.exec(dir, cmd, args, { env = env })
end
local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function zn(args: { string }, extra: { [string]: string }?): Result
	return run("./zn", args, extra)
end
local function git(args: { string }): string
	return must(run("git", args), "git " .. table.concat(args, " "))
end
local function write(path: string, text: string)
	local full = `{dir}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function read(path: string): string
	return fs.readFile(`{dir}/{path}`)
end
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end
local function say(r: Result): string
	return r.stderr .. r.stdout
end
local function raftDir(): string
	return `{TR}/rafts/active/{raft}`
end
local function issueDir(): string
	return `{TR}/issues/active/{issue}`
end

local function review(model: string?, effort: string?): string
	local head = if model then `Model: {model}\n{if effort then `Effort: {effort}\n` else ""}` else ""
	return `{head}# Review 001: {raft} (code mode)\nInputs: the diff\n\nVerdict: approve\n`
end

-- a started raft of one issue, offline, with its layer built and nothing finished; `marked` writes the front-matter line
local function setup(name: string, marked: boolean)
	dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	process.exec("git", { "init", "-q", "-b", "main", dir }) -- raw: init to a named path
	for _, p in { ".claude", ".luaurc", ".gitignore", "rokit.toml" } do
		process.exec("cp", { "-R", `{root}/{p}`, `{dir}/{p}` })
	end
	fs.writeDir(`{dir}/pickman/.tracker`)
	engine.copy(root, dir)
	for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
		write(`{TR}/{d}/.gitkeep`, "")
	end
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", "seed" })
	issue = string.match(
		must(zn({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new"),
		"(f%d%d%d%d)"
	) :: string
	raft = string.match(
		must(zn({ "new", "raft", "feature", "demo", issue, "--project", "pickman" }), "new raft"),
		"(R%d%d%d%d)"
	) :: string
	local issueDoc, raftDocPath = `{TR}/issues/{issue}/{issue}.md`, `{TR}/rafts/{raft}/{raft}.md`
	for _, doc in { issueDoc, raftDocPath } do
		write(doc, (string.gsub(read(doc), "design: draft", "design: ready", 1)))
	end
	-- the local `new raft` marks the raft; an unmarked fixture stands for a raft made before c0306 landed
	t.expect(has(read(raftDocPath), "reviews: judged\n")).toBe(true)
	if not marked then
		write(raftDocPath, (string.gsub(read(raftDocPath), "reviews: judged\n", "", 1)))
	end
	write(
		issueDoc,
		(string.gsub(read(issueDoc), "### Touched modules\n", "### Touched modules\n- `notes/alpha`\n", 1))
	)
	for _, p in { `{TR}/issues/{issue}/check.sh`, `{TR}/rafts/{raft}/check.sh` } do
		write(p, TRIVIAL_CHECK)
	end
	seal.prep(dir)
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", "prep ready" })
	must(zn({ "start", raft }), "start")
	t.expect(fs.isDir(`{dir}/{raftDir()}`)).toBe(true)
	write("notes/alpha/a.txt", "1\n2\n")
end

return t.spec("c0306 done and commit judge the reviews", function(it)
	it("sets up an unmarked started raft of one issue", function()
		setup("c0306-done-a", false)
		t.expect(has(read(`{TR}/rafts/active/{raft}/{raft}.md`), "reviews: judged")).toBe(false)
	end)

	it(
		"AC8: commit --phase code-review in an unmarked raft commits an unstamped review with no --model, as today",
		function()
			local file = `{raftDir()}/review-002.md`
			write(file, review(nil, nil))
			local before = git({ "rev-parse", "HEAD" })
			must(zn({ "commit", "-m", `{raft}: review-002`, "--phase", "code-review" }), "commit")
			t.expect(git({ "rev-parse", "HEAD" }) ~= before).toBe(true)
			t.expect(read(file)).toBe(review(nil, nil)) -- committed as written, not stamped
			-- with --model it stamps, in an unmarked raft too
			local typed = `{raftDir()}/review-001.md`
			write(typed, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: review-001`,
					"--phase",
					"code-review",
					"--model",
					"claude-sonnet-5-5",
				}),
				"commit"
			)
			t.expect(read(typed)).toBe("Model: claude-sonnet-5-5\n" .. review(nil, nil))
		end
	)

	it("AC6: done passes an unmarked raft whose reviews record claude-sonnet-5-5", function()
		must(zn({ "finish", issue }), "finish")
		-- the final review is the code review, as the sealed fixtures write it (seal.trace copies review-001.md)
		seal.trace(dir, raft)
		local r = zn({ "done", raft })
		if not r.ok then
			error(`done refused an unmarked raft: {say(r)}`)
		end
		t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(true)
	end)

	it("sets up a marked started raft of one issue for the commit cases", function()
		setup("c0306-done-d", true)
		t.expect(has(read(`{TR}/rafts/active/{raft}/{raft}.md`), "reviews: judged")).toBe(true)
	end)

	it(
		"AC8: commit --phase code-review refuses a new review file without --model, committing nothing",
		function()
			local file = `{raftDir()}/review-001.md`
			write(file, review(nil, nil))
			local before = git({ "rev-parse", "HEAD" })
			local r = zn({ "commit", "-m", `{raft}: review-001`, "--phase", "code-review" })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "review-001.md")).toBe(true)
			t.expect(has(say(r), "--model")).toBe(true)
			t.expect(git({ "rev-parse", "HEAD" })).toBe(before)
			t.expect(read(file)).toBe(review(nil, nil)) -- not stamped
		end
	)

	it(
		"AC8: commit --phase code-review --model stamps every unstamped review file it commits, and leaves a stamped one alone",
		function()
			local file = `{raftDir()}/review-001.md`
			-- a second new review file that already records a model is left as it is
			local own = `{raftDir()}/final-review-001.md`
			write(own, review("claude-fable-5-2", "high"))
			-- a design review in the issue's folder is stamped too
			local design = `{issueDir()}/design-review-001.md`
			write(design, review(nil, nil))
			-- an unstamped final review is stamped too
			local final2 = `{raftDir()}/final-review-002.md`
			write(final2, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: review-001`,
					"--phase",
					"code-review",
					"--model",
					"claude-sonnet-5-5",
					"--effort",
					"high",
				}),
				"commit"
			)
			t.expect(read(file)).toBe("Model: claude-sonnet-5-5\nEffort: high\n" .. review(nil, nil))
			t.expect(read(own)).toBe(review("claude-fable-5-2", "high"))
			t.expect(read(design)).toBe("Model: claude-sonnet-5-5\nEffort: high\n" .. review(nil, nil))
			t.expect(read(final2)).toBe("Model: claude-sonnet-5-5\nEffort: high\n" .. review(nil, nil))
			-- the committed blob is the stamped text
			t.expect(git({ "show", `HEAD:{file}` })).toBe(trim(read(file)))
		end
	)

	it(
		"AC8: commit takes the effort from CLAUDE_EFFORT when none is typed, and leaves Effort: out when there is neither",
		function()
			local a, b = `{raftDir()}/review-002.md`, `{raftDir()}/review-003.md`
			write(a, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: review-002`,
					"--phase",
					"code-review",
					"--model",
					"claude-opus-5-5",
				}, { CLAUDE_EFFORT = "max" }),
				"commit"
			)
			t.expect(read(a)).toBe("Model: claude-opus-5-5\nEffort: max\n" .. review(nil, nil))
			write(b, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: review-003`,
					"--phase",
					"code-review",
					"--model",
					"claude-opus-5-5",
				}),
				"commit"
			)
			t.expect(read(b)).toBe("Model: claude-opus-5-5\n" .. review(nil, nil))
			-- a typed --effort wins over the environment
			local c = `{raftDir()}/review-004.md`
			write(c, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: review-004`,
					"--phase",
					"code-review",
					"--model",
					"claude-opus-5-5",
					"--effort",
					"low",
				}, { CLAUDE_EFFORT = "max" }),
				"commit"
			)
			t.expect(read(c)).toBe("Model: claude-opus-5-5\nEffort: low\n" .. review(nil, nil))
		end
	)

	it(
		"AC8: commit with another phase refuses an unstamped review file in a marked raft, naming --phase code-review, and commits nothing",
		function()
			local file = `{raftDir()}/review-005.md`
			write(file, review(nil, nil))
			local before = git({ "rev-parse", "HEAD" })
			for _, phase in { "build", "deliver" } do
				local r = zn({ "commit", "-m", `{raft}: not a review`, "--phase", phase })
				t.expect(r.ok).toBe(false)
				t.expect(has(say(r), "review-005.md")).toBe(true)
				t.expect(has(say(r), "--phase code-review --model")).toBe(true)
				t.expect(git({ "rev-parse", "HEAD" })).toBe(before)
				t.expect(git({ "diff", "--cached", "--name-only" })).toBe("")
			end
			t.expect(read(file)).toBe(review(nil, nil))
			-- a review that records its model commits under any phase
			write(file, review("claude-opus-5-5", "high"))
			must(zn({ "commit", "-m", `{raft}: a stamped review`, "--phase", "deliver" }), "commit")
		end
	)

	it("AC8: commit --model stamps a modified review file that has no Model: line", function()
		local file = `{raftDir()}/review-006.md`
		-- committed unstamped outside the protocol (a raw git commit), then edited
		write(file, review(nil, nil))
		git({ "add", "-A" })
		git({ "commit", "-q", "-m", "an unstamped review, raw" })
		write(file, read(file) .. "\nA later note.\n")
		must(
			zn({
				"commit",
				"-m",
				`{raft}: review-006`,
				"--phase",
				"code-review",
				"--model",
				"claude-opus-5-5",
			}),
			"commit"
		)
		t.expect(read(file)).toBe("Model: claude-opus-5-5\n" .. review(nil, nil) .. "\nA later note.\n")
		t.expect(git({ "show", `HEAD:{file}` })).toBe(trim(read(file)))
	end)

	it(
		"AC8: commit refuses a grok- review with no typed --effort in a marked raft, whatever CLAUDE_EFFORT says, and takes no effort from it for a non-claude model",
		function()
			local grok = `{raftDir()}/review-008.md`
			write(grok, review(nil, nil))
			local before = git({ "rev-parse", "HEAD" })
			local r = zn(
				{ "commit", "-m", `{raft}: review-008`, "--phase", "code-review", "--model", "grok-4.7" },
				{ CLAUDE_EFFORT = "xhigh" }
			)
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "a grok- review is judged by its effort: --effort <level>")).toBe(true)
			t.expect(git({ "rev-parse", "HEAD" })).toBe(before)
			t.expect(read(grok)).toBe(review(nil, nil))
			-- typed, it stamps with that effort
			must(
				zn({
					"commit",
					"-m",
					`{raft}: review-008`,
					"--phase",
					"code-review",
					"--model",
					"grok-4.7",
					"--effort",
					"xhigh",
				}, { CLAUDE_EFFORT = "low" }),
				"commit"
			)
			t.expect(read(grok)).toBe("Model: grok-4.7\nEffort: xhigh\n" .. review(nil, nil))
			-- a non-claude model that is not grok takes no effort from the environment
			local kimi = `{raftDir()}/review-009.md`
			write(kimi, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: review-009`,
					"--phase",
					"code-review",
					"--model",
					"kimi-code-k3.2",
				}, { CLAUDE_EFFORT = "xhigh" }),
				"commit"
			)
			t.expect(read(kimi)).toBe("Model: kimi-code-k3.2\n" .. review(nil, nil))
		end
	)

	it(
		"sets up a marked started raft of one issue, finished, with a final review on claude-opus-5-5",
		function()
			setup("c0306-done-b", true)
			write("notes/alpha/b.txt", "3\n")
			-- stream reviews off the review models, filed during the layer's work as the dispatcher files them
			write(`{raftDir()}/stream-review-{issue}-001.md`, review("claude-sonnet-5-5", "low"))
			write(`{raftDir()}/stream-review-{issue}-002.md`, review(nil, nil))
			must(zn({ "commit", "-m", "work", "--issue", issue }), "commit")
			must(zn({ "finish", issue }), "finish")
			-- the final review, on a review model; the trace is written last (seal.trace), when the files are right
			write(`{raftDir()}/final-review-001.md`, review("claude-opus-5-5", "xhigh"))
			git({ "add", "-A" })
			git({ "commit", "-q", "-m", "final review" })
		end
	)

	local function commitAll(message: string)
		git({ "add", "-A" })
		git({ "commit", "-q", "-m", message })
	end

	it(
		"AC6: done refuses a marked raft whose final review is not on a review model, naming the file and the model",
		function()
			local final = `{raftDir()}/final-review-001.md`
			local good = read(final)
			write(final, review("claude-sonnet-5-5", "high"))
			commitAll("final on sonnet")
			local r = zn({ "done", raft })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "final-review-001.md")).toBe(true)
			t.expect(has(say(r), "claude-sonnet-5-5")).toBe(true)
			t.expect(has(say(r), "claude-opus-")).toBe(true)
			t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(false)
			-- a final review that records no model is refused too (omission never passes)
			write(final, review(nil, nil))
			commitAll("final with no record")
			local none = zn({ "done", raft })
			t.expect(none.ok).toBe(false)
			t.expect(has(say(none), "no `Model:` line")).toBe(true)
			-- grok below xhigh is refused
			write(final, review("grok-4.7", "high"))
			commitAll("final on grok high")
			t.expect(zn({ "done", raft }).ok).toBe(false)
			write(final, good)
			commitAll("final restored")
		end
	)

	it("AC6: done's refusal names only a new round, committed with --phase code-review --model", function()
		local final = `{raftDir()}/final-review-001.md`
		local good = read(final)
		write(final, review("claude-sonnet-5-5", "high"))
		commitAll("final on sonnet again")
		local r = zn({ "done", raft })
		t.expect(r.ok).toBe(false)
		local said = say(r)
		t.expect(has(said, "--mode final")).toBe(true)
		t.expect(
			has(said, `./zn commit -m "{raft}: review-NNN" --phase code-review --model <id> --effort <level>`)
		)
			.toBe(true)
		t.expect(has(said, "./zn spend")).toBe(false)
		t.expect(has(said, "code|final")).toBe(false)
		t.expect(has(said, "pull request")).toBe(false)
		write(final, good)
		commitAll("final restored again")
	end)

	it(
		"AC6: only the newest review-NNN and the newest final-review-NNN are judged: a later round on a review model clears an earlier cheap one, and a later cheap round is refused",
		function()
			-- a later round on a review model clears an earlier cheap one: done goes on to its next check
			write(`{raftDir()}/review-001.md`, review("claude-sonnet-5-5", "high"))
			write(`{raftDir()}/review-002.md`, review("claude-opus-5-5", "high"))
			commitAll("two code review rounds, the later on opus")
			local cleared = zn({ "done", raft })
			t.expect(has(say(cleared), "is not a review model")).toBe(false)
			-- a later cheap round after one on a review model is refused, naming the newest
			write(`{raftDir()}/review-001.md`, review("claude-opus-5-5", "high"))
			write(`{raftDir()}/review-002.md`, review("claude-sonnet-5-5", "high"))
			commitAll("round two on sonnet")
			local later = zn({ "done", raft })
			t.expect(later.ok).toBe(false)
			t.expect(has(say(later), "review-002.md")).toBe(true)
			t.expect(has(say(later), "review-001.md")).toBe(false)
			-- the kinds are apart: a newer final review does not clear a cheap newest review-NNN
			write(`{raftDir()}/final-review-002.md`, review("claude-opus-5-5", "high"))
			commitAll("a final review on opus")
			local apart = zn({ "done", raft })
			t.expect(apart.ok).toBe(false)
			t.expect(has(say(apart), "review-002.md")).toBe(true)
			t.expect(has(say(apart), "final-review")).toBe(false)
			write(`{raftDir()}/review-002.md`, review("claude-opus-5-5", "high"))
			commitAll("round two on opus")
		end
	)

	it(
		"AC6: done never judges a stream review or a refute, and passes a marked raft whose reviews are on review models",
		function()
			-- the author's answers are never judged: a refute carries no record
			write(`{raftDir()}/refute-001.md`, "- F1: refuted: no\n")
			write(`{raftDir()}/final-refute-001.md`, "- F1: refuted: no\n")
			commitAll("refutes with no record")
			seal.trace(dir, raft) -- the trace, once the files are right (the final review is the opus layer review)
			local r = zn({ "done", raft })
			if not r.ok then
				error(`done refused a marked raft on review models: {say(r)}`)
			end
			t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(true)
		end
	)

	it(
		"AC6: done judges the review files in a member's folder too (a third fixture: a marked raft with a layer review there)",
		function()
			setup("c0306-done-c", true)
			-- a layer review in the member's folder is part of the layer's finish commit, as c0248 files them
			write(`{issueDir()}/review-001.md`, review("claude-sonnet-5-5", "high"))
			must(
				zn({
					"commit",
					"-m",
					"work",
					"--issue",
					issue,
					"--phase",
					"code-review",
					"--model",
					"claude-sonnet-5-5",
				}),
				"commit"
			)
			must(zn({ "finish", issue }), "finish")
			seal.trace(dir, raft) -- the final review is on claude-opus-5-5
			local r = zn({ "done", raft })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "review-001.md")).toBe(true)
			t.expect(has(say(r), issue)).toBe(true)
			t.expect(has(say(r), "claude-sonnet-5-5")).toBe(true)
			t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(false)
		end
	)

	it(
		"AC6: following done's refusal to a pass: a new final round, committed with the command the refusal names, clears it",
		function()
			setup("c0306-done-e", true)
			write("notes/alpha/b.txt", "3\n")
			must(zn({ "commit", "-m", "work", "--issue", issue }), "commit")
			-- a final review recorded on claude-sonnet-5-5 by the lead who typed it, committed before the layer is finished
			write(`{raftDir()}/final-review-001.md`, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: final-review-001`,
					"--phase",
					"code-review",
					"--model",
					"claude-sonnet-5-5",
					"--effort",
					"high",
				}),
				"commit"
			)
			must(zn({ "finish", issue }), "finish")
			local refused = zn({ "done", raft })
			t.expect(refused.ok).toBe(false)
			local said = say(refused)
			t.expect(has(said, "final-review-001.md")).toBe(true)
			t.expect(has(said, `./zn dispatch zz-review {raft} --mode final`)).toBe(true)
			t.expect(
				has(
					said,
					`./zn commit -m "{raft}: review-NNN" --phase code-review --model <id> --effort <level>`
				)
			).toBe(true)
			-- the fresh-subagent route writes the next-numbered round with no record; the command the refusal names records it
			write(`{raftDir()}/final-review-002.md`, review(nil, nil))
			must(
				zn({
					"commit",
					"-m",
					`{raft}: final-review-002`,
					"--phase",
					"code-review",
					"--model",
					"claude-opus-5-5",
					"--effort",
					"high",
				}),
				"commit"
			)
			t.expect(has(read(`{raftDir()}/final-review-002.md`), "Model: claude-opus-5-5\nEffort: high\n"))
				.toBe(true)
			must(zn({ "finish", issue }), "finish") -- ./zn commit rewrote the raft's spend.md: the layer is finished again
			seal.trace(dir, raft)
			local passed = zn({ "done", raft })
			if not passed.ok then
				error(`done still refuses after the named commit: {say(passed)}`)
			end
			t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(true)
		end
	)

	it("cleans up", function()
		fs.removeDir(`{base}/c0306-done-a`)
		fs.removeDir(`{base}/c0306-done-b`)
		fs.removeDir(`{base}/c0306-done-c`)
		fs.removeDir(`{base}/c0306-done-d`)
		fs.removeDir(`{base}/c0306-done-e`)
	end)
end)
