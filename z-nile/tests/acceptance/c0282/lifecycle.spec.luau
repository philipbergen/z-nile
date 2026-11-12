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
local provenance = require("@znile/engine/provenance")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local dir = `{fixture.physical(".")}/.cache/c0282-lifecycle`

local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "e2e",
	GIT_AUTHOR_EMAIL = "e2e@example.invalid",
	GIT_COMMITTER_NAME = "e2e",
	GIT_COMMITTER_EMAIL = "e2e@example.invalid",
}
-- every variable a command that records reads, cleared: the one list is the engine's
for _, name in provenance.ENV_VARS do
	ID[name] = ""
end
local SONNET = "agent:claude-sonnet-5-5 effort high"
local OPUS = "agent:claude-opus-5-5 effort high"
local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local ISSUES, RAFTS = "pickman/.tracker/issues", "pickman/.tracker/rafts"

local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
local function alpha(expected: number): string
	return "--!strict\nlocal t = "
		.. REQ
		.. '("@tests/lib/t")\n\nreturn t.spec("alpha", function(it)\n\tit("holds", function()\n\t\tt.expect(1).toBe('
		.. tostring(expected)
		.. ")\n\tend)\nend)\n"
end

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
		-- the tooling as every tracker fixture gets it: engine.PATHSPECS (a sibling that adds a state file excludes it there)
		local listArgs: { string } = { "ls-files", "-co", "--exclude-standard" }
		for _, spec in engine.PATHSPECS do
			table.insert(listArgs, spec)
		end
		local listed = process.exec("git", listArgs, { cwd = root })
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
			tr({
				"new",
				"raft",
				"feature",
				"demo",
				"f0010",
				"f0020",
				"--project",
				"pickman",
				"--actor",
				SONNET,
			}, { ZN_ACTOR = OPUS }),
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
		"start opens the stack, and an emergent issue made in the raft's worktree gets a rafted row",
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
			fs.writeDir(`{dir}/{ISSUES}/f0010/acceptance`)
			write(`{ISSUES}/f0010/acceptance/alpha.spec.luau`, alpha(1))
			seal.prep(dir)
			git({ "add", "-A" })
			git({ "commit", "-qm", "prep ready" })
			must(tr({ "start", "R0010" }), "start")
			-- a bad actor or a bad ZN_VIA refuses before the counter is pushed or a folder is made
			local before = git({ "status", "--porcelain" })
			for _, env in { { ZN_ACTOR = "robot:x" }, { ZN_VIA = "dispatch" } } do
				local refused =
					tr({ "new", "issue", "d", "found", "--raft", "R0010", "--project", "pickman" }, env)
				t.expect(refused.ok).toBe(false)
				t.expect(
					string.find(refused.stderr, "ZN_VIA", 1, true) ~= nil
						or string.find(refused.stderr, "not an actor", 1, true) ~= nil
				).toBe(true)
				t.expect(git({ "status", "--porcelain" })).toBe(before)
			end
			local emergent = must(
				tr({
					"new",
					"issue",
					"d",
					"found",
					"--raft",
					"R0010",
					"--project",
					"pickman",
					"--actor",
					OPUS,
				}, { ZN_ACTOR = SONNET }),
				"emergent"
			)
			local epath = string.match(emergent, "(%S+%.md)") :: string
			local eprov = `{string.match(epath, "^(.*)/[^/]+$")}/provenance.md`
			t.expect(has(eprov, `| rafted | {OPUS} | raft=R0010`)).toBe(true)
			t.expect(count(eprov, "rafted")).toBe(1)
		end
	)

	it(
		"done appends a delivered row to every member, staged with the moves; a failed done leaves none",
		function()
			-- the emergent issue was a probe of its row: its untracked folder goes, so the stack is the two members
			git({ "reset", "-q", "--hard", "HEAD" })
			git({ "clean", "-fdq", "--", ISSUES })
			-- layer 1: f0010 with a failing promoted spec, as c0001 does
			local good = alpha(1)
			write(`{ISSUES}/active/f0010/acceptance/alpha.spec.luau`, alpha(2))
			fs.writeDir(`{dir}/notes`)
			write("notes/f0010.txt", "alpha\n")
			must(tr({ "commit", "-m", "f0010 work with a failing promoted spec" }), "commit")
			must(tr({ "finish", "f0010" }), "finish f0010")
			must(tr({ "start", "R0010" }), "start f0020")
			write("notes/f0020.txt", "gamma\n")
			git({ "add", "-A" })
			git({ "commit", "-qm", "f0020 work" })
			must(tr({ "finish", "f0020" }), "finish f0020")
			seal.trace(dir, "R0010")
			-- a member record that does not parse refuses before anything moves, naming the file
			local rec10 = `{ISSUES}/active/f0010/provenance.md`
			local goodRec = read(rec10)
			write(rec10, goodRec .. "a hand edit\n")
			local unparsable = tr({ "done", "R0010" }, { ZN_ACTOR = OPUS })
			t.expect(unparsable.ok).toBe(false)
			t.expect(string.find(unparsable.stderr, "f0010/provenance.md: line", 1, true) ~= nil).toBe(true)
			t.expect(fs.isDir(`{dir}/{ISSUES}/done/f0010`)).toBe(false)
			write(rec10, goodRec)
			t.expect(git({ "status", "--porcelain" })).toBe("")
			-- a bad actor refuses before anything moves
			local bad = tr({ "done", "R0010" }, { ZN_ACTOR = "robot:x" })
			t.expect(bad.ok).toBe(false)
			t.expect(string.find(bad.stderr .. bad.stdout, "not an actor", 1, true) ~= nil).toBe(true)
			t.expect(fs.isDir(`{dir}/{ISSUES}/done/f0010`)).toBe(false)
			t.expect(git({ "status", "--porcelain" })).toBe("")
			-- f0020 is an old member with no record of its own: a failed done creates none, and rolls the rows back
			local failed = tr({ "done", "R0010" }, { ZN_ACTOR = OPUS })
			t.expect(failed.ok).toBe(false)
			t.expect(string.find(failed.stderr .. failed.stdout, "rolled back", 1, true) ~= nil).toBe(true)
			t.expect(has(`{ISSUES}/active/f0010/provenance.md`, "| delivered |")).toBe(false)
			t.expect(fs.isFile(`{dir}/{ISSUES}/active/f0020/provenance.md`)).toBe(true)
			t.expect(has(`{ISSUES}/active/f0020/provenance.md`, "| delivered |")).toBe(false)
			t.expect(fs.isDir(`{dir}/{ISSUES}/done/f0010`)).toBe(false)
			t.expect(git({ "status", "--porcelain" })).toBe("")
			-- the retry appends exactly one row per member
			write(`{ISSUES}/active/f0010/acceptance/alpha.spec.luau`, good)
			must(tr({ "commit", "-m", "the spec passes" }), "commit")
			must(tr({ "finish", "f0020" }), "finish the fix")
			seal.trace(dir, "R0010")
			must(tr({ "done", "R0010", "--actor", OPUS }, { ZN_ACTOR = SONNET }), "done")
			for _, id in { "f0010", "f0020" } do
				local p = `{ISSUES}/done/{id}/provenance.md`
				t.expect(count(p, "delivered")).toBe(1)
				t.expect(has(p, `| delivered | {OPUS} | raft=R0010 |`)).toBe(true)
				t.expect(has(p, "worker=")).toBe(false) -- the worker is read from the spend rows by who, never stored
			end
			-- the raft is delivered by its members' rows, never by a record of its own
			t.expect(fs.isFile(`{dir}/{RAFTS}/done/R0010/provenance.md`)).toBe(false)
			-- the rafted rows survived the move
			t.expect(count(`{ISSUES}/done/f0010/provenance.md`, "rafted")).toBe(1)
		end
	)
end)
