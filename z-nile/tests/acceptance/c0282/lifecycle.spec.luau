--!strict
-- c0282 AC6 (offline path): a `rafted` row from the offline `new raft` and from an emergent `new issue --raft`, and a
-- `delivered` row from `done` on every member of a two-member raft, in a
-- throwaway clone with no remote (so every move is local), like c0001's lifecycle spec. The published paths are
-- record.spec.luau.
local clone = require("@tests/lib/clone")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local dir = `{fixture.physical(".")}/.cache/c0282-lifecycle`

local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "e2e",
	GIT_AUTHOR_EMAIL = "e2e@example.invalid",
	GIT_COMMITTER_NAME = "e2e",
	GIT_COMMITTER_EMAIL = "e2e@example.invalid",
	CLAUDECODE = "",
	AI_AGENT = "",
	CLAUDE_EFFORT = "",
	ZN_ACTOR = "",
}
local SONNET = "agent:claude-sonnet-5-5 effort high"
local OPUS = "agent:claude-opus-5-5 effort high"
local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local ISSUES, RAFTS = "pickman/.tracker/issues", "pickman/.tracker/rafts"

local function run(cmd: string, args: { string }, env: { [string]: string }?): Result
	local all: { [string]: string } = table.clone(ID)
	local extra: { [string]: string } = env or {}
	for k, v in extra do
		all[k] = v
	end
	return fixture.exec(dir, cmd, args, { env = all })
end
local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function tr(args: { string }, env: { [string]: string }?): Result
	return run("bash", { "scripts/tracker.sh", table.unpack(args) }, env)
end
local function git(args: { string }): string
	return must(run("git", args), "git " .. table.concat(args, " "))
end
local function read(path: string): string
	return fs.readFile(`{dir}/{path}`)
end
local function write(path: string, text: string)
	fs.writeFile(`{dir}/{path}`, text)
end
local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(read(path), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	write(path, text)
end
local function has(path: string, needle: string): boolean
	return fs.isFile(`{dir}/{path}`) and string.find(read(path), needle, 1, true) ~= nil
end
local function count(path: string, event: string): number
	if not fs.isFile(`{dir}/{path}`) then
		return 0
	end
	local _, n = string.gsub(read(path), `| {event} |`, "")
	return n
end

return t.spec("c0282 the offline lifecycle stamps provenance", function(it)
	it("offline new raft appends a rafted row for every member", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		clone.isolated(root, dir)
		git({ "remote", "remove", "origin" })
		local listed = process.exec("git", {
			"ls-files",
			"-co",
			"--exclude-standard",
			"zn",
			"scripts",
			"z-nile",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{dir}/{parent}`)
				end
				fs.writeFile(`{dir}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		engine.empty(dir)
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker", "--allow-empty" })
		must(tr({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new alpha")
		must(tr({ "new", "issue", "f", "gamma", "--project", "pickman" }), "new gamma")
		must(
			tr(
				{ "new", "raft", "feature", "demo", "f0010", "f0020", "--project", "pickman" },
				{ ZN_ACTOR = SONNET }
			),
			"new raft"
		)
		for _, id in { "f0010", "f0020" } do
			local p = `{ISSUES}/{id}/provenance.md`
			t.expect(count(p, "rafted")).toBe(1)
			t.expect(has(p, `| rafted | {SONNET} | raft=R0010`)).toBe(true)
			-- the idea is git's to say, nothing is stored for it
			t.expect(count(p, "idea")).toBe(0)
		end
	end)

	it(
		"an emergent issue in an active raft gets a rafted row, and done appends a delivered row to every member",
		function()
			for _, id in { "f0010", "f0020" } do
				edit(`{ISSUES}/{id}/{id}.md`, "design: draft", "design: ready")
				edit(
					`{ISSUES}/{id}/{id}.md`,
					"### Touched modules\n",
					`### Touched modules\n- \`notes/{id}\`\n`
				)
				write(`{ISSUES}/{id}/check.sh`, TRIVIAL_CHECK)
			end
			edit(`{RAFTS}/R0010/R0010.md`, "design: draft", "design: ready")
			write(`{RAFTS}/R0010/check.sh`, TRIVIAL_CHECK)
			git({ "add", "-A" })
			git({ "commit", "-qm", "prep ready" })
			must(tr({ "start", "R0010" }), "start")
			local emergent = must(
				tr(
					{ "new", "issue", "d", "found", "--raft", "R0010", "--project", "pickman" },
					{ ZN_ACTOR = OPUS }
				),
				"emergent"
			)
			local epath = string.match(emergent, "(%S+%.md)") :: string
			local eid = string.match(epath, "(d%d+)") :: string
			local eprov = `{string.match(epath, "^(.*)/[^/]+$")}/provenance.md`
			t.expect(has(eprov, `| rafted | {OPUS} | raft=R0010`)).toBe(true)
			write(`{string.match(epath, "^(.*)/[^/]+$")}/check.sh`, TRIVIAL_CHECK)
			fs.writeDir(`{dir}/notes/f0010`)
			write("notes/f0010/a.txt", "1\n")
			must(tr({ "commit", "-m", "work", "--time", "1" }), "commit")
			write(
				`{RAFTS}/active/R0010/review-001.md`,
				"# Review 001\n\n### F1 [low] x\nEvidence: y\n\nVerdict: approve\n"
			)
			write(`{RAFTS}/active/R0010/refute-001.md`, "- F1: refuted: by design\n")
			must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit review")
			-- a done that fails and rolls back leaves no delivered row (the rows are staged with the moves), and the retry
			-- appends exactly one per member, including the members that had no record of their own yet
			local REQ = "req" .. "uire"
			local function alpha(expected: number): string
				return "--!strict\nlocal t = "
					.. REQ
					.. '("@tests/lib/t")\n\nreturn t.spec("alpha", function(it)\n\tit("holds", function()\n\t\tt.expect(1).toBe('
					.. tostring(expected)
					.. ")\n\tend)\nend)\n"
			end
			-- f0020 is an old member with no record at all (a raft made before records existed): done creates its file
			git({ "rm", "-q", `{ISSUES}/active/f0020/provenance.md` })
			git({ "commit", "-qm", "an old member with no record" })
			fs.writeDir(`{dir}/{ISSUES}/active/f0010/acceptance`)
			write(`{ISSUES}/active/f0010/acceptance/alpha.spec.luau`, alpha(2))
			must(tr({ "commit", "-m", "a failing promoted spec", "--time", "1" }), "commit")
			-- a bad actor refuses done before it moves anything
			local bad = tr({ "done", "R0010" }, { ZN_ACTOR = "robot:x" })
			t.expect(bad.ok).toBe(false)
			t.expect(string.find(bad.stderr .. bad.stdout, "not an actor", 1, true) ~= nil).toBe(true)
			t.expect(fs.isDir(`{dir}/{ISSUES}/done/f0010`)).toBe(false)
			t.expect(git({ "status", "--porcelain" })).toBe("")
			local failed = tr({ "done", "R0010" }, { ZN_ACTOR = OPUS })
			t.expect(failed.ok).toBe(false)
			t.expect(has(`{ISSUES}/active/f0010/provenance.md`, "| delivered |")).toBe(false)
			t.expect(fs.isFile(`{dir}/{ISSUES}/active/f0020/provenance.md`)).toBe(false) -- the created file is rolled back too
			t.expect(fs.isDir(`{dir}/{ISSUES}/done/f0010`)).toBe(false)
			t.expect(git({ "status", "--porcelain" })).toBe("")
			write(`{ISSUES}/active/f0010/acceptance/alpha.spec.luau`, alpha(1))
			must(tr({ "commit", "-m", "the spec passes", "--time", "1" }), "commit")
			must(tr({ "done", "R0010" }, { ZN_ACTOR = OPUS }), "done")
			-- one row per member, riding the raft PR into done/, with the actor and the raft
			for _, id in { "f0010", "f0020", eid } do
				local p = `{ISSUES}/done/{id}/provenance.md`
				t.expect(count(p, "delivered")).toBe(1)
				t.expect(has(p, `| delivered | {OPUS} | raft=R0010 |`)).toBe(true)
				t.expect(has(p, "worker=")).toBe(false) -- the worker is read from spend rows by who, never stored
			end
			-- the raft itself is delivered by its members' rows, never by a record of its own
			t.expect(fs.isFile(`{dir}/{RAFTS}/done/R0010/provenance.md`)).toBe(false)
			-- the rafted rows survived the move
			t.expect(count(`{ISSUES}/done/f0010/provenance.md`, "rafted")).toBe(1)
		end
	)
end)
