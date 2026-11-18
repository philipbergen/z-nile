--!strict
-- c0411 E5 (prep only, run from the scratch worktree; never promoted): the case 'lists every raft once, sorted by id' of c0043/rounds.spec reads the rafts of EVERY registered project,
-- and still fails when `metrics` leaves a raft out, lists one twice or lists them out of order. Fixtures under
-- .cache/c0411-rounds: one copy of this checkout's tooling and tracker items (the working tree as it is), on which the
-- promoted rounds.spec runs from the copy's z-nile/ home, once per scenario; engine and spec mutants are applied to the
-- copy, never to the real tree. A scenario's verdict is that one case's line in the runner's output.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{fixture.physical(".") :: string}/.cache/c0411-rounds`
local work = `{base}/work`
local SPEC = "z-nile/tests/" .. "acceptance/c0043/rounds.spec.luau"
local ENGINE = "z-nile/engine/main.luau"
local CASE = ":: lists every raft once, sorted by id"
local ID = { "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end

local function cp(from: string, to: string)
	must(process.exec("cp", { "-R", from, to }), `cp {from}`)
end

-- The tooling and every registered root's items, from the working tree (committed or not), in a repository of its own.
local function copyTree()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(work)
	must(process.exec("git", { "init", "-q" }, { cwd = work }), "git init")
	for _, name in { "zn", "scripts", ".luaurc", "rokit.toml" } do
		cp(`{root}/{name}`, `{work}/{name}`)
	end
	fs.writeDir(`{work}/z-nile`)
	for _, name in fs.readDir(`{root}/z-nile`) do
		if name ~= ".cache" then
			cp(`{root}/z-nile/{name}`, `{work}/z-nile/{name}`)
		end
	end
	local toml = fs.readFile(`{root}/z-nile/projects.toml`)
	for r in string.gmatch(toml, 'root = "([^"]+)"') do
		local project = string.match(r, "^([^/]+)/") :: string
		if project ~= "z-nile" then
			fs.writeDir(`{work}/{project}`)
			cp(`{root}/{r}`, `{work}/{r}`)
		end
	end
	must(fixture.exec(work, "git", { "add", "-A" }), "git add")
	local commit = table.clone(ID)
	for _, a in { "commit", "-qm", "the working tree" } do
		table.insert(commit, a)
	end
	must(fixture.exec(work, "git", commit), "git commit")
end

-- replace `from` (which must occur exactly once) with `to` in the copy's `rel` file
local function sub(rel: string, from: string, to: string)
	local text = fs.readFile(`{work}/{rel}`)
	local at = string.find(text, from, 1, true)
	assert(at ~= nil, `{rel}: {from} not found`)
	assert(string.find(text, from, (at :: number) + 1, true) == nil, `{rel}: {from} occurs more than once`)
	fs.writeFile(
		`{work}/{rel}`,
		string.sub(text, 1, (at :: number) - 1) .. to .. string.sub(text, (at :: number) + #from)
	)
end

local function restore()
	-- a mutant is undone by checking the copy's two files out of its one commit
	must(fixture.exec(work, "git", { "checkout", "-q", "--", SPEC, ENGINE }), "git checkout")
end

local function raft(dir: string, id: string)
	fs.writeDir(`{work}/{dir}/{id}`)
	fs.writeFile(`{work}/{dir}/{id}/{id}.md`, `---\nid: {id}\ntype: raft\ntitle: T\nslug: t\n---\n\n# {id}\n`)
end

-- the case runs in the copy's z-nile home: fixture.exec checks the directory is a fixture repository, and the home is
-- inside it, so the runner is started from the copy's top with the home as cwd through `cd`
local function runHome(): string
	local r = fixture.exec(
		work,
		"sh",
		{ "-c", `cd z-nile && lune run tests/run -- {"tests/" .. "acceptance/c0043/rounds.spec.luau"}` }
	)
	return r.stdout .. r.stderr
end

-- a pass is the runner's own summary: no FAIL line at all, `0 failed` over the one spec file (design review 001 F4: the
-- absence of one message would also read a case that raised, or a spec that never loaded, as passing)
local function passed(out: string): boolean
	return string.find(out, "FAIL", 1, true) == nil
		and string.find(out, " 0 failed, 1 spec files", 1, true) ~= nil
		and string.find(out, " passed, ", 1, true) ~= nil
end

local function caseFails(out: string): boolean
	-- the case's own FAIL line, on its assertion (not a spec that could not load, which names no case)
	return string.find(out, "FAIL", 1, true) ~= nil
		and string.find(out, CASE, 1, true) ~= nil
		and string.find(out, "expected deep-equal values", 1, true) ~= nil
end

return t.spec("c0411 the rounds spec's raft list is every registered project's", function(it)
	it(
		"passes on the copy, and again with a raft added to a root and a new project with rafts in all four folders",
		function()
			copyTree()
			local plain = runHome()
			t.expect(passed(plain)).toBe(true)
			-- a raft in a registered project's root, and a project nobody listed in the spec
			raft("arcade/.tracker/rafts/active", "R9901")
			fs.writeFile(
				`{work}/z-nile/projects.toml`,
				fs.readFile(`{work}/z-nile/projects.toml`)
					.. '\n[[project]]\nname = "ghost"\nroot = "ghost/.tracker"\n'
			)
			raft("ghost/.tracker/rafts", "R9902")
			raft("ghost/.tracker/rafts/active", "R9903")
			raft("ghost/.tracker/rafts/done", "R9904")
			raft("ghost/.tracker/rafts/retired", "R9905")
			local added = runHome()
			t.expect(passed(added)).toBe(true)
			-- the rows really are there: the engine lists the new rafts (so a pass is not a spec that never looked)
			local m = must(fixture.exec(work, "bash", { "scripts/tracker.sh", "metrics" }), "metrics")
			for _, id in { "R9901", "R9902", "R9903", "R9904", "R9905" } do
				t.expect(string.find(m, `| {id} |`, 1, true) ~= nil).toBe(true)
			end
		end
	)

	-- the registry and rafts of the last case stay in the copy, so each mutant below runs against all seven projects and ghost
	it("fails when metrics leaves a raft out", function()
		sub(
			ENGINE,
			"\tfor _, row in roundRows do\n",
			"\ttable.remove(roundRows, 1)\n\tfor _, row in roundRows do\n"
		)
		t.expect(caseFails(runHome())).toBe(true)
		restore()
	end)

	it("fails when metrics lists a raft twice", function()
		sub(
			ENGINE,
			"\ttable.sort(roundRows, function(a, b)\n",
			"\ttable.insert(roundRows, roundRows[1])\n\ttable.sort(roundRows, function(a, b)\n"
		)
		t.expect(caseFails(runHome())).toBe(true)
		restore()
	end)

	it("fails when metrics lists the rafts out of order", function()
		sub(
			ENGINE,
			"\ttable.sort(roundRows, function(a, b)\n\t\treturn a.id < b.id",
			"\ttable.sort(roundRows, function(a, b)\n\t\treturn a.id > b.id"
		)
		t.expect(caseFails(runHome())).toBe(true)
		restore()
	end)

	it("fails for a spec that reads a hand-written list of roots, or leaves a folder out", function()
		sub(SPEC, "projects.roots(projects.load(TOP))", '{ "pickman/.tracker", "z-nile/.tracker" }')
		t.expect(caseFails(runHome())).toBe(true)
		restore()
		sub(
			SPEC,
			'{ "rafts", "rafts/active", "rafts/done", "rafts/retired" }',
			'{ "rafts", "rafts/active", "rafts/done" }'
		)
		t.expect(caseFails(runHome())).toBe(true)
		restore()
	end)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
	end)
end)
