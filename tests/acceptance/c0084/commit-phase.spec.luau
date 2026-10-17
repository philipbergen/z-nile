--!strict
-- c0084: inside a raft, `tracker.sh commit` tags its spend rows with a phase (build by default, code-review for
-- review rounds, deliver for the delivery commits) and optional tokens; `done` records its own commit as deliver,
-- and the raft's summary shows each phase. Fixture under .cache/c0084-commit: a repository with this tree's tooling
-- and no remote, so start and done stay local (as in c0001's lifecycle spec). Ids come from the commands' output.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@scripts/tracker/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local dir = `{root}/.cache/c0084-commit`

-- the identity rides in the environment: a runner nested in the fixture refuses a fixture identity in its config
local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "commit",
	GIT_AUTHOR_EMAIL = "commit@example.invalid",
	GIT_COMMITTER_NAME = "commit",
	GIT_COMMITTER_EMAIL = "commit@example.invalid",
}

local function run(cmd: string, args: { string }): Result
	return fixture.exec(dir, cmd, args, { env = ID })
end
local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function tr(args: { string }): Result
	return run("bash", { "scripts/tracker.sh", table.unpack(args) })
end
local function git(args: { string }): string
	return must(run("git", args), "git " .. table.concat(args, " "))
end
local function write(path: string, text: string)
	local full = `{dir}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(fs.readFile(`{dir}/{path}`), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	fs.writeFile(`{dir}/{path}`, text)
end
local function rows(path: string): { any }
	local l, err = ledger.parse(fs.readFile(`{dir}/{path}`))
	if not l then
		error(`{path} does not parse: {err}`, 2)
	end
	return l.rows
end

local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'

local a, b, raft = "", "", ""
local function active(id: string): string
	return `tracker/issues/active/{id}/spend.md`
end

return t.spec("tracker commit phases", function(it)
	it("sets up a started raft of two issues, offline", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		process.exec("git", { "init", "-q", "-b", "main", dir }) -- raw: init to a named path
		for _, p in { "scripts", ".claude", ".luaurc", ".gitignore", "rokit.toml" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{dir}/{p}` })
		end
		fs.writeDir(`{dir}/tracker`)
		process.exec("cp", { "-R", `{root}/tracker/templates`, `{dir}/tracker/templates` })
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			write(`tracker/{d}/.gitkeep`, "")
		end
		git({ "add", "-A" })
		git({ "commit", "-q", "-m", "seed" })
		a = string.match(must(tr({ "new", "issue", "f", "alpha" }), "new"), "(f%d%d%d%d)") :: string
		b = string.match(must(tr({ "new", "issue", "f", "beta" }), "new"), "(f%d%d%d%d)") :: string
		raft =
			string.match(must(tr({ "new", "raft", "feature", "demo", a, b }), "new raft"), "(R%d%d%d%d)") :: string
		for _, doc in
			{ `tracker/issues/{a}/{a}.md`, `tracker/issues/{b}/{b}.md`, `tracker/rafts/{raft}/{raft}.md` }
		do
			edit(doc, "design: draft", "design: ready")
		end
		edit(`tracker/issues/{a}/{a}.md`, "### Touched modules\n", "### Touched modules\n- `notes/alpha`\n")
		edit(`tracker/issues/{b}/{b}.md`, "### Touched modules\n", "### Touched modules\n- `notes/beta`\n")
		for _, p in
			{ `tracker/issues/{a}/check.sh`, `tracker/issues/{b}/check.sh`, `tracker/rafts/{raft}/check.sh` }
		do
			write(p, TRIVIAL_CHECK)
		end
		git({ "add", "-A" })
		git({ "commit", "-q", "-m", "prep ready" })
		must(tr({ "start", raft }), "start")
		t.expect(fs.isDir(`{dir}/tracker/rafts/active/{raft}`)).toBe(true)
	end)

	it("records build by default, with no tokens and the trailer as before", function()
		write("notes/alpha/a.txt", "1\n2\n3\n")
		must(tr({ "commit", "-m", "work", "--issue", a, "--time", "2" }), "commit")
		local r = rows(active(a))
		t.expect(r[#r].phase).toBe("build")
		t.expect(r[#r].tokens).toBe(nil)
		t.expect(r[#r].added).toBe(3)
		t.expect(string.find(git({ "log", "-1", "--format=%B" }), `Issue: {a} +3/-0 2.0m`, 1, true) ~= nil)
			.toBe(true)
	end)

	it("records the phase and tokens it is given, and names them in the trailer", function()
		write(`tracker/rafts/active/{raft}/review-001.md`, "# Review 001\n\nVerdict: approve\n")
		must(
			tr({
				"commit",
				"-m",
				"review-001",
				"--issue",
				a,
				"--phase",
				"code-review",
				"--time",
				"5",
				"--tokens",
				"777",
			}),
			"commit"
		)
		local r = rows(active(a))
		t.expect(r[#r].phase).toBe("code-review")
		t.expect(r[#r].tokens).toBe(777)
		t.expect(r[#r].minutes).toBe(5)
		t.expect(r[#r].added).toBe(0) -- the review file is under tracker/
		local body = git({ "log", "-1", "--format=%B" })
		t.expect(string.find(body, `Issue: {a} +0/-0 5.0m code-review 777 tokens`, 1, true) ~= nil).toBe(true)
	end)

	it("splits tokens over the issues exactly, as minutes are split", function()
		write("notes/alpha/b.txt", "1\n2\n3\n")
		write("notes/beta/b.txt", "1\n")
		must(tr({ "commit", "-m", "both", "--time", "8", "--tokens", "1001" }), "commit")
		local ra, rb = rows(active(a)), rows(active(b))
		t.expect((ra[#ra].tokens or 0) + (rb[#rb].tokens or 0)).toBe(1001)
		t.expect(ra[#ra].minutes).toBeNear(6, 0.01)
		t.expect(rb[#rb].minutes).toBeNear(2, 0.01)
		t.expect(ra[#ra].phase).toBe("build")
	end)

	it(
		"refuses an unknown phase, a phase recorded outside a raft, and bad tokens, committing nothing",
		function()
			write("notes/alpha/c.txt", "x\n")
			local head = git({ "rev-parse", "HEAD" })
			for _, extra in
				{
					{ "--phase", "bogus" },
					{ "--phase", "capture" },
					{ "--phase", "prep" },
					{ "--phase", "design-review" },
					{ "--tokens", "abc" },
					{ "--tokens", "-3" },
					{ "--tokens", "2.5" },
				}
			do
				local r = tr({ "commit", "-m", "nope", "--time", "1", extra[1], extra[2] })
				if r.ok then
					error(`accepted: commit {extra[1]} {extra[2]}`)
				end
				t.expect(git({ "rev-parse", "HEAD" })).toBe(head)
				t.expect(git({ "diff", "--cached", "--name-only" })).toBe("") -- refused before anything was staged
			end
			local r = tr({ "commit", "-m", "nope", "--phase", "capture", "--time", "1" })
			t.expect(string.find(r.stderr, "tracker.sh spend", 1, true) ~= nil).toBe(true)
			-- dated ten minutes back, so done's own row (minutes since this commit) is never too small to record
			local env = table.clone(ID)
			env.GIT_COMMITTER_DATE = `@{os.time() - 600} +0000`
			local args = {
				"scripts/tracker.sh",
				"commit",
				"-m",
				"verification logs",
				"--phase",
				"deliver",
				"--time",
				"1",
			}
			must(fixture.exec(dir, "bash", args, { env = env }), "commit")
			local ra = rows(active(a))
			t.expect(ra[#ra].phase).toBe("deliver")
		end
	)

	it("done records its own commit as deliver, and the raft summary shows each phase", function()
		must(tr({ "done", raft }), "done")
		local ra = rows(`tracker/issues/done/{a}/spend.md`)
		t.expect(ra[#ra].phase).toBe("deliver")
		t.expect(ra[#ra].subject).toBe(`tracker: done {raft}`)
		local summary = fs.readFile(`{dir}/tracker/rafts/done/{raft}/spend.md`)
		t.expect(string.find(summary, "| phase | +lines | -lines | minutes | tokens |", 1, true) ~= nil)
			.toBe(true)
		t.expect(string.find(summary, "| code-review | 0 | 0 | 5.0 | 777 |", 1, true) ~= nil).toBe(true)
		t.expect(string.find(summary, "| build | 7 | 0 | 10.0 | 1001 |", 1, true) ~= nil).toBe(true)
		t.expect(string.find(summary, "| deliver |", 1, true) ~= nil).toBe(true)
		t.expect((string.find(summary, "| capture |", 1, true))).toBe(nil) -- phases without records are left out
	end)

	it("cleans up", function()
		fs.removeDir(dir)
	end)
end)
