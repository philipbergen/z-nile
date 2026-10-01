--!strict
-- c0360 AC1: `tracker.sh done` accepts `- F<n>: deferred <id>: <why>` for a medium or low finding
-- when <id> is an existing backlog issue, and refuses it in every other case. Driven for real in a
-- throwaway clone (no remote, so done skips push and gh).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local work = `{root}/.cache/c0360-deferred`

local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'

local REVIEW = "# Review 001\n\n"
	.. "### F1 [high] a high finding\nEvidence: x\n\n"
	.. "### F2 [medium] a medium finding\nEvidence: y\n\n"
	.. "### F3 [low] a low finding\nEvidence: z\n\n"
	.. "Verdict: changes requested\n"

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(args: { string }): string
	return must(process.exec("git", args, { cwd = work }), "git " .. table.concat(args, " "))
end

local function tr(args: { string }): Result
	return process.exec("bash", { "scripts/tracker.sh", table.unpack(args) }, { cwd = work })
end

local function read(path: string): string
	return fs.readFile(`{work}/{path}`)
end

local function write(path: string, text: string)
	fs.writeFile(`{work}/{path}`, text)
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(read(path), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	write(path, text)
end

-- answers: the lines of refute-001.md. Commits them (done needs a clean tree), then runs done.
local function attempt(answers: { string }, review: string?): Result
	write("tracker/rafts/active/R0010/review-001.md", review or REVIEW)
	write("tracker/rafts/active/R0010/refute-001.md", table.concat(answers, "\n") .. "\n")
	must(tr({ "commit", "-m", "round", "--time", "1" }), "commit")
	return tr({ "done", "R0010" })
end

local function refused(r: Result, ...: string)
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		t.expect(string.find(r.stderr, needle, 1, true) ~= nil).toBe(true)
	end
	t.expect(fs.isDir(`{work}/tracker/rafts/active/R0010`)).toBe(true) -- nothing was moved
end

return t.spec("c0360 done accepts deferred answers", function(it)
	it("sets up a clone with a started raft and a backlog follow-up issue", function()
		if fs.isDir(work) then
			fs.removeDir(work)
		end
		must(process.exec("git", { "clone", "-q", "--no-hardlinks", root, work }), "clone")
		git({ "remote", "remove", "origin" })
		local listed = process.exec(
			"git",
			{ "ls-files", "-co", "--exclude-standard", "scripts", "tracker/templates" },
			{ cwd = root }
		)
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{work}/{parent}`)
				end
				fs.writeFile(`{work}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		git({ "config", "user.name", "e2e" })
		git({ "config", "user.email", "e2e@example.invalid" })
		git({ "config", "gc.auto", "0" })
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local dir = `{work}/tracker/{kind}/{state}`
				for _, name in fs.readDir(dir) do
					if string.match(name, "^[fdcR]%d%d%d%d$") then
						fs.removeDir(dir .. name)
					end
				end
			end
		end
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker", "--allow-empty" })
		must(tr({ "new", "issue", "f", "alpha" }), "new issue")
		must(tr({ "new", "issue", "c", "followup" }), "new follow-up")
		must(tr({ "new", "raft", "feature", "demo", "f0010", "--single" }), "new raft")
		for _, doc in { "tracker/issues/f0010/f0010.md", "tracker/rafts/R0010/R0010.md" } do
			edit(doc, "design: draft", "design: ready")
		end
		edit(
			"tracker/issues/f0010/f0010.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		write("tracker/issues/f0010/check.sh", TRIVIAL_CHECK)
		write("tracker/rafts/R0010/check.sh", TRIVIAL_CHECK)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		t.expect(fs.isDir(`{work}/tracker/issues/c0020`)).toBe(true) -- the follow-up stays in the backlog
	end)

	it("refuses to defer a high finding", function()
		refused(
			attempt({ "- F1: deferred c0020: later", "- F2: fixed abc: ok", "- F3: fixed abc: ok" }),
			"F1",
			"high"
		)
	end)

	it("refuses to defer to an issue that does not exist", function()
		refused(
			attempt({ "- F1: fixed abc: ok", "- F2: deferred c0999: later", "- F3: fixed abc: ok" }),
			"F2",
			"c0999"
		)
	end)

	it("refuses to defer to an issue that is not in the backlog", function()
		refused(
			attempt({ "- F1: fixed abc: ok", "- F2: deferred f0010: later", "- F3: fixed abc: ok" }),
			"F2",
			"f0010"
		)
	end)

	it("refuses a deferral that names no issue or gives no reason", function()
		refused(attempt({ "- F1: fixed abc: ok", "- F2: deferred", "- F3: fixed abc: ok" }), "F2")
		refused(attempt({ "- F1: fixed abc: ok", "- F2: deferred c0020", "- F3: fixed abc: ok" }), "F2")
		refused(attempt({ "- F1: fixed abc: ok", "- F2: deferred c0020:   ", "- F3: fixed abc: ok" }), "F2")
	end)

	it("refuses to defer a finding whose severity is not stated", function()
		local review =
			"# Review 001\n\n### F1 an unrated finding\nEvidence: x\n\nVerdict: changes requested\n"
		refused(attempt({ "- F1: deferred c0020: later" }, review), "F1")
	end)

	it("still accepts fixed and refuted for any severity, and rejects other words", function()
		refused(attempt({ "- F1: ignored", "- F2: fixed abc: ok", "- F3: fixed abc: ok" }), "F1")
		refused(
			attempt({ "- F1: fixed abc: ok", "- F2: deferred-ish c0020: later", "- F3: fixed abc: ok" }),
			"F2"
		)
	end)

	it(
		"finishes when a medium and a low finding are deferred to a backlog issue and the high one is fixed",
		function()
			local r = attempt({
				"- F1: refuted: the reviewer misread the spec (test: x)",
				"- F2: deferred c0020: needs its own design",
				"- F3: deferred c0020: same follow-up",
			})
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			t.expect(fs.isDir(`{work}/tracker/rafts/done/R0010`)).toBe(true)
			t.expect(fs.isDir(`{work}/tracker/issues/done/f0010`)).toBe(true)
			t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: done R0010")
			t.expect(fs.isDir(`{work}/tracker/issues/c0020`)).toBe(true) -- the follow-up is still in the backlog
		end
	)

	it("cleans up", function()
		fs.removeDir(work)
	end)
end)
