--!strict
-- c0120 AC12: CI follows the homes. One gate job per project (decided with the user, 2026-10-21: "One job per project"):
-- the matrix lists exactly the registry's projects, and each job runs that project's gate. A push touching only a
-- project root (pickman/.tracker, z-nile/.tracker) or the counter skips the gate, and one touching the retired tracker/
-- runs it. A dispatched raft branch runs its members' sequestered specs from their project's home, with paths relative
-- to it, in its project's job. The beta job deploys and runs the runtime tests from pickman/, and deploy-beta builds a
-- project's "$path"s relative to the project file's own folder. The stop hook gates pickman/ and z-nile/ too. These
-- specs run from z-nile/: the repository is read from its top. Fixtures under .cache/c0120-ci (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local wf = serde.decode("yaml", fs.readFile(`{TOP}/.github/workflows/check.yml`)) :: any
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function step(job: string, needle: string): any
	for _, s in wf.jobs[job].steps do
		if type(s.run) == "string" and has(s.run, needle) then
			return s
		end
	end
	error(`no {job} step runs {needle}`)
end

return t.spec("c0120 CI follows the homes", function(it)
	it("pushes touching only a project root or the counter skip the gate; tracker/ is not ignored", function()
		t.expect(wf["on"].push["paths-ignore"]).toEqual({ "pickman/.tracker/**", "z-nile/.tracker/**", "z-nile/next" })
	end)

	it("one gate job per project: the matrix is the registry's projects, each job its project's gate", function()
		local projects = require("@znile/engine/projects")
		local names: { string } = {}
		for _, p in projects.load(TOP, true).projects do
			table.insert(names, p.name)
		end
		local gate = wf.jobs.gate
		t.expect(gate.strategy.matrix.project).toEqual(names)
		t.expect(gate.strategy["fail-fast"]).toBe(false)
		t.expect(gate.name).toBe("gate (${{ matrix.project }})")
		t.expect(step("gate", "z-nile/check.sh --project").run)
			.toBe("z-nile/check.sh --project ${{ matrix.project }} --full")
		-- the beta job waits for every project's job
		t.expect(wf.jobs.beta.needs).toBe("gate")
	end)

	it("the beta job deploys and runs the runtime tests from pickman/, and sets up from the root", function()
		t.expect(step("beta", "lune run scripts/deploy-beta")["working-directory"]).toBe("pickman")
		t.expect(step("beta", 'runtime-test -- "$VERSION"')["working-directory"]).toBe("pickman")
		t.expect(step("beta", "runtime-test -- --lobby")["working-directory"]).toBe("pickman")
		t.expect(step("beta", "z-nile/setup.sh --tools")["working-directory"]).toBe(nil)
		t.expect(step("gate", "z-nile/setup.sh --tools")["working-directory"]).toBe(nil)
	end)

	it("deploy-beta builds a project's paths relative to the project file's folder", function()
		local text = fs.readFile(`{TOP}/pickman/scripts/deploy-beta.luau`)
		t.expect(has(text, 'local dir = string.match(source, "^(.*)/[^/]+$") or root')).toBe(true)
		t.expect(has(text, "pcall(Beta.project, fs.readFile(source), dir, target.attributes)")).toBe(true)
	end)

	it("the stop hook gates a change in pickman/ or z-nile/, never one to a project root's documents alone", function()
		local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
		local dir = `{root}/.cache/c0120-ci-hook`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
		fixture.git(dir, { "config", "user.name", "c0120-ci" })
		fixture.git(dir, { "config", "user.email", "c0120-ci@example.invalid" })
		-- a stub gate at the path the hook calls, recording that it ran; the registry and its shell reader
		local function put(rel: string, text: string)
			fs.writeDir(string.match(`{dir}/{rel}`, "^(.*)/[^/]+$") :: string)
			fs.writeFile(`{dir}/{rel}`, text)
		end
		put("scripts/check.sh", '#!/usr/bin/env bash\necho "$@" >> "$(dirname "$0")/../gate.log"\n')
		process.exec("chmod", { "+x", `{dir}/scripts/check.sh` })
		for _, rel in { "z-nile/roots.luau", "z-nile/engine/projects.luau", "z-nile/projects.toml" } do
			put(rel, fs.readFile(`{TOP}/{rel}`))
		end
		put("readme", "x\n")
		fixture.git(dir, { "add", "-A" })
		fixture.git(dir, { "commit", "-q", "-m", "base" })
		local function gated(): boolean
			fixture.exec(dir, "bash", { `{TOP}/scripts/hooks/stop.sh` }, { stdin = '{"cwd": "' .. dir .. '"}' })
			local ran = fs.isFile(`{dir}/gate.log`)
			if ran then
				fs.removeFile(`{dir}/gate.log`)
			end
			return ran
		end
		put("pickman/.tracker/issues/f0001/f0001.md", "doc\n")
		t.expect(gated()).toBe(false) -- pickman's root alone: documents select no spec
		put("pickman/src/shared/X.luau", "--!strict\nreturn 1\n")
		t.expect(gated()).toBe(true) -- pickman's code: the gate runs
		fs.removeDir(`{dir}/pickman/src`)
		put("z-nile/lib/x.luau", "--!strict\nreturn 1\n")
		t.expect(gated()).toBe(true) -- the tooling's code: the gate runs
		fs.removeFile(`{dir}/z-nile/lib/x.luau`)
		put("z-nile/.tracker/issues/c0001/c0001.md", "doc\n")
		t.expect(gated()).toBe(false) -- z-nile's root alone
		put("src/x.luau", "--!strict\nreturn 1\n")
		t.expect(gated()).toBe(true) -- the old place: gated, and the old-roots check fails there
		fs.removeDir(`{dir}/src`)
		put("tests/x.luau", "--!strict\nreturn 1\n")
		t.expect(gated()).toBe(true) -- the root's old tests/: gated too
		fs.removeDir(dir)
	end)

	it("a dispatched raft branch runs its members' sequestered specs from their home, paths relative to it", function()
		local seed: { [string]: string } = {
			["z-nile/projects.toml"] = REGISTRY,
			["pickman/.tracker/rafts/active/R0010/R0010.md"] = trackerfix.stub("R0010", "demo", "active-a-b-c"),
			["pickman/.tracker/issues/active/f0010/f0010.md"] = string.gsub(
				trackerfix.stub("f0010", "alpha", "active-a-b-c"),
				"raft: \n",
				"raft: R0010\n"
			) :: string,
			["pickman/.tracker/issues/active/f0010/acceptance/a.spec.luau"] = "--!strict\nreturn nil\n",
			["pickman/.tracker/issues/active/f0010/acceptance/notes.md"] = "not a spec\n",
			-- and a z-nile raft, whose members' specs run from z-nile/
			["z-nile/.tracker/rafts/active/R0020/R0020.md"] = trackerfix.stub("R0020", "tool", "active-a-b-c"),
			["z-nile/.tracker/issues/active/c0021/c0021.md"] = string.gsub(
				trackerfix.stub("c0021", "beta", "active-a-b-c"),
				"raft: \n",
				"raft: R0020\n"
			) :: string,
			["z-nile/.tracker/issues/active/c0021/acceptance/b.spec.luau"] = "--!strict\nreturn nil\n",
		}
		local f = trackerfix.new("c0120-ci", seed)
		-- the step's script as CI runs it (bash -eo pipefail), with a lune that records where it ran and what
		local script = step("gate", "z-nile/roots -- --projects").run :: string
		fs.writeFile(`{f.main}/dispatch.sh`, script)
		fs.writeDir(`{f.base}/bin`)
		fs.writeDir(`{f.base}/tmp`)
		local real = (string.gsub(process.exec("bash", { "-c", "command -v lune" }).stdout, "%s+$", ""))
		fs.writeFile(
			`{f.base}/bin/lune`,
			'#!/bin/sh\nif [ "$2" = tests/run ]; then printf "%s|%s\\n" "$(pwd -P)" "$*" >> "$LUNE_LOG"; exit 0; fi\n'
				.. `exec "{real}" "$@"\n`
		)
		process.exec("chmod", { "+x", `{f.base}/bin/lune` })
		local log = `{f.base}/lune.log`
		-- the step as one project's job runs it (its matrix entry in PROJECT)
		local function dispatch(branch: string, project: string): fixture.Result
			return fixture.exec(f.main, "bash", { "-eo", "pipefail", "dispatch.sh" }, {
				env = {
					GITHUB_REF_NAME = branch,
					GITHUB_WORKSPACE = fixture.physical(f.main) :: string,
					RUNNER_TEMP = `{f.base}/tmp`,
					PATH = `{f.base}/bin:{process.env.PATH or ""}`,
					LUNE_LOG = log,
					PROJECT = project,
				},
			})
		end
		local r = dispatch("R0010-demo", "pickman")
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local main = fixture.physical(f.main) :: string
		t.expect(fs.readFile(log))
			.toBe(`{main}/pickman|run tests/run -- .tracker/issues/active/f0010/acceptance/a.spec.luau\n`)
		-- the other project's job runs none of them
		fs.removeFile(log)
		t.expect(dispatch("R0010-demo", "z-nile").ok).toBe(true)
		t.expect(fs.isFile(log)).toBe(false)
		-- a z-nile raft's members run from z-nile/, in z-nile's job
		t.expect(dispatch("R0020-tool", "z-nile").ok).toBe(true)
		t.expect(fs.readFile(log))
			.toBe(`{main}/z-nile|run tests/run -- .tracker/issues/active/c0021/acceptance/b.spec.luau\n`)
		-- a branch that is not a raft's runs nothing
		fs.removeFile(log)
		local other = dispatch("some-branch", "pickman")
		t.expect(other.ok).toBe(true)
		t.expect(fs.isFile(log)).toBe(false)
		fs.removeDir(f.base)
	end)
end)
