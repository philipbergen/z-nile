--!strict
-- c0194: nothing the tooling runs makes a temporary tree outside .cache/.tmp. par.sh keeps its buffers in TMPDIR's
-- tree; the only lines that name mktemp or a system temp folder in the tooling are the reviewed ones; an agent
-- session gets TMPDIR and the mktemp shim from its SessionStart hook; `./zn tmp` reaches the command line.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local here = trim(process.exec("pwd", { "-P" }).stdout)
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{here}/.cache/c0194-callers`

local tmp = require("@znile/lib/tmp")

local function tmpRoot(dir: string): string
	return tmp.root(dir) :: string
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end

-- a stand-in project: the files the hook and ./zn tmp need, copied from the tooling
local function project(name: string): string
	local dir = `{base}/{name}`
	process.exec("rm", { "-rf", dir })
	for _, d in { "z-nile/lib", "z-nile/bin", "scripts/hooks", ".cache" } do
		fs.writeDir(`{dir}/{d}`)
	end
	for _, rel in
		{
			"z-nile/lib/tmp.luau",
			"z-nile/lib/tmpcli.luau",
			"z-nile/lib/replace-file.pl",
			"z-nile/bin/mktemp",
			"scripts/hooks/session-tmp.sh",
			"zn",
		}
	do
		fs.writeFile(`{dir}/{rel}`, read(rel))
		process.exec("chmod", { "+x", `{dir}/{rel}` })
	end
	return dir
end

-- Every line in the tooling that makes a temporary tree by another route than z-nile/lib/tmp.luau: a flagged line is
-- allowed when it contains one of its file's fragments (the reason is beside each). Fragments, not whole lines, so
-- rewording the code around them does not break this sequestered spec.
local ALLOWED: { [string]: { [string]: string } } = {
	["z-nile/lib/tmp.luau"] = {
		['"mktemp", "-d"'] = "the one maker: a fresh name inside the checked folder",
		['"/tmp"'] = "leftovers reads the system temp folder to list the old trees; it makes none",
	},
	["z-nile/setup.sh"] = {
		[".cache/.tmp/rokit.XXXXXX"] = "a template under .cache/.tmp: setup runs before lune exists",
	},
	["z-nile/lib/fence.sh"] = {
		[".sentinel.XXXXXX"] = "a file beside the sentinel, renamed in; not a tree",
	},
	["z-nile/lib/tmp.sh"] = {
		['mktemp -d "$root/$kind.XXXXXX"'] = "the gate's maker: a fresh name inside the checked folder",
	},
}

local function allowedLine(path: string, code: string): boolean
	local fragments: { [string]: string } = ALLOWED[path] or {}
	for fragment in fragments do
		if has(code, fragment) then
			return true
		end
	end
	return false
end

local function scan(): { string }
	local out: { string } = {}
	local function walk(dir: string)
		for _, name in fs.readDir(`{root}/{dir}`) do
			local path = `{dir}/{name}`
			if
				name == ".cache"
				or name == ".tracker"
				or name == "skills"
				or path == "z-nile/tests"
				or path == "z-nile/bin"
			then
				continue
			elseif fs.isDir(`{root}/{path}`) then
				walk(path)
			elseif
				string.match(name, "%.luau$")
				or string.match(name, "%.sh$")
				or string.match(name, "%.pl$")
			then
				for line in string.gmatch(fs.readFile(`{root}/{path}`), "[^\n]+") do
					local code = trim(line)
					local comment = string.sub(code, 1, 2) == "--" or string.sub(code, 1, 1) == "#"
					if
						not comment
						and (has(code, "mktemp") or has(code, "os.tmpname") or has(code, ":-/tmp") or has(
							code,
							'"/tmp"'
						))
						and not allowedLine(path, code)
					then
						table.insert(out, `{path}: {code}`)
					end
				end
			end
		end
	end
	for _, d in { "z-nile", "scripts", "pickman/scripts" } do
		walk(d)
	end
	table.sort(out)
	return out
end

return t.spec("c0194 callers of the temporary trees", function(it)
	it("par.sh keeps its buffers in the tree under TMPDIR's .cache/.tmp, and removes them", function()
		process.exec("rm", { "-rf", base })
		local run = `{base}/co/.cache/.tmp/pickman-run.X`
		fs.writeDir(run)
		local r = process.exec("/bin/bash", {
			"-c",
			'set -euo pipefail\nsource z-nile/lib/par.sh\npar_start one true\necho "DIR=$PAR_DIR"\npar_wait >/dev/null',
		}, { cwd = root, env = { TMPDIR = run } })
		t.expect(r.ok).toBe(true)
		local dir = string.match(r.stdout, "DIR=([^\n]+)") or ""
		t.expect((string.find(dir, `{run}/par.`, 1, true))).toBe(1)
		t.expect(fs.isDir(dir)).toBe(false)
	end)

	it("no tooling line makes a temporary tree outside z-nile/lib/tmp.luau but the reviewed ones", function()
		t.expect(table.concat(scan(), "\n")).toBe("")
	end)

	it("the gate sweeps stale trees at its start and builds in trees from the one maker", function()
		local gate = read("z-nile/check.sh")
		t.expect(has(gate, 'pickman_tmp_sweep "$(pwd -P)"')).toBe(true)
		t.expect(has(gate, "pickman_tmp_new check-build")).toBe(true)
		t.expect(has(gate, "pickman_tmp_new globaltypes")).toBe(true)
		t.expect(has(gate, "source z-nile/lib/tmp.sh")).toBe(true)
	end)

	it("the SessionStart hook is registered, and gives a session TMPDIR and the shim on PATH", function()
		local settings = serde.decode("json", read(".claude/settings.json")) :: any
		local command = settings.hooks.SessionStart[1].hooks[1].command :: string
		t.expect(has(command, "scripts/hooks/session-tmp.sh")).toBe(true)
		local proj = project("hook")
		local envFile = `{base}/hook-env`
		fs.writeFile(envFile, "")
		local r = process.exec("bash", { `{proj}/scripts/hooks/session-tmp.sh` }, {
			env = {
				CLAUDE_PROJECT_DIR = proj,
				CLAUDE_ENV_FILE = envFile,
				PATH = process.env.PATH or "",
				HOME = process.env.HOME or "",
			},
		})
		t.expect(r.ok).toBe(true)
		t.expect(r.stdout).toBe("") -- a SessionStart hook's output goes into the model's context
		local lines = fs.readFile(envFile)
		t.expect(has(lines, `export TMPDIR={proj}/.cache/.tmp\n`)).toBe(true)
		t.expect(has(lines, `{proj}/z-nile/bin`)).toBe(true)
		-- the commands of the session source the file: a plain mktemp then lands in the folder
		local made = trim(
			process.exec(
				"sh",
				{ "-c", `. {envFile}; mktemp -d` },
				{ env = { PATH = process.env.PATH or "" } }
			).stdout
		)
		t.expect((string.find(made, `{proj}/.cache/.tmp/tmp.`, 1, true))).toBe(1)
		t.expect(fs.isDir(made)).toBe(true)
	end)

	it(
		"the hook is quiet and leaves TMPDIR alone when it cannot make the folder, and does nothing outside a session",
		function()
			local proj = project("hookfail")
			local stand = `{base}/hookfail-target`
			fs.writeDir(stand)
			must(process.exec("rm", { "-rf", `{proj}/.cache` }), "rm")
			must(process.exec("ln", { "-s", stand, `{proj}/.cache` }), "ln")
			local envFile = `{base}/hookfail-env`
			fs.writeFile(envFile, "")
			local env = {
				CLAUDE_PROJECT_DIR = proj,
				CLAUDE_ENV_FILE = envFile,
				PATH = process.env.PATH or "",
				HOME = process.env.HOME or "",
			}
			local r = process.exec("bash", { `{proj}/scripts/hooks/session-tmp.sh` }, { env = env })
			t.expect(r.ok).toBe(true)
			t.expect(fs.readFile(envFile)).toBe("")
			t.expect(has(r.stderr, "TMPDIR left as it was")).toBe(true)
			t.expect(#fs.readDir(stand)).toBe(0)
			env.CLAUDE_ENV_FILE = nil :: any
			local none = process.exec("bash", { `{proj}/scripts/hooks/session-tmp.sh` }, { env = env })
			t.expect(none.ok and none.stdout == "" and none.stderr == "").toBe(true)
		end
	)

	it(
		"the hook exports one clean line even when the command prints a warning on stderr, and refuses a stranger's answer",
		function()
			local proj = project("hookwarn")
			local stubs = `{base}/hookwarn-stubs`
			must(process.exec("rm", { "-rf", stubs }), "rm")
			fs.writeDir(stubs)
			-- a lune that warns on stderr and answers with the folder; HOME is the stand-in so the real Rokit lune is not first
			fs.writeFile(
				`{stubs}/lune`,
				`#!/bin/sh\necho 'notice: something' >&2\necho '{proj}/.cache/.tmp'\n`
			)
			must(process.exec("chmod", { "+x", `{stubs}/lune` }), "chmod")
			local envFile = `{base}/hookwarn-env`
			fs.writeFile(envFile, "")
			local env = {
				CLAUDE_PROJECT_DIR = proj,
				CLAUDE_ENV_FILE = envFile,
				PATH = `{stubs}:{process.env.PATH or ""}`,
				HOME = proj,
			}
			local r = process.exec("bash", { `{proj}/scripts/hooks/session-tmp.sh` }, { env = env })
			t.expect(r.ok and r.stdout == "").toBe(true)
			t.expect(has(fs.readFile(envFile), `export TMPDIR={proj}/.cache/.tmp\n`)).toBe(true)
			t.expect(has(fs.readFile(envFile), "notice")).toBe(false)
			-- an answer that is not this project's .cache/.tmp is not exported
			fs.writeFile(envFile, "")
			fs.writeFile(`{stubs}/lune`, "#!/bin/sh\necho '/somewhere/else'\n")
			local bad = process.exec("bash", { `{proj}/scripts/hooks/session-tmp.sh` }, { env = env })
			t.expect(bad.ok and fs.readFile(envFile) == "").toBe(true)
			t.expect(has(bad.stderr, "TMPDIR left as it was")).toBe(true)
		end
	)

	it(
		"the shell maker needs no Lune: it uses TMPDIR's tree or the checkout's, writes the marker, and refuses a link",
		function()
			local co = `{base}/shellnew`
			must(process.exec("rm", { "-rf", co }), "rm")
			fs.writeDir(`{co}/.cache`)
			local function make(script: string, tmpdir: string?): Result
				local env: { [string]: string } = { PATH = "/usr/bin:/bin" } -- no lune on PATH at all
				if tmpdir then
					env.TMPDIR = tmpdir
				end
				return process.exec(
					"/bin/bash",
					{ "-c", `source {root}/z-nile/lib/tmp.sh\n{script}` },
					{ cwd = co, env = env }
				)
			end
			-- no session TMPDIR: this checkout's own folder, with the marker
			local own = make("pickman_tmp_new gate", "/c0194-no-such-tmpdir")
			t.expect(own.ok).toBe(true)
			t.expect((string.find(trim(own.stdout), `{co}/.cache/.tmp/gate.`, 1, true))).toBe(1)
			t.expect(fs.isFile(`{co}/.cache/.tmp/.metadata_never_index`)).toBe(true)
			-- a TMPDIR inside a .cache/.tmp is used as it is
			local run = `{co}/.cache/.tmp/pickman-run.X`
			fs.writeDir(run)
			local inside = make("pickman_tmp_new par", run)
			t.expect((string.find(trim(inside.stdout), `{run}/par.`, 1, true))).toBe(1)
			-- a link at .tmp refuses and writes nothing through it
			local stand = `{base}/shellnew-target`
			must(process.exec("rm", { "-rf", stand }), "rm")
			fs.writeDir(stand)
			must(process.exec("rm", { "-rf", `{co}/.cache/.tmp` }), "rm")
			must(process.exec("ln", { "-s", stand, `{co}/.cache/.tmp` }), "ln")
			local linked = make("pickman_tmp_new gate", "/c0194-no-such-tmpdir")
			t.expect(linked.ok).toBe(false)
			t.expect(has(linked.stderr, "is not a plain folder")).toBe(true)
			t.expect(#fs.readDir(stand)).toBe(0)
		end
	)

	it("the hook sweeps the stale trees of the project's folder as it starts", function()
		local proj = project("hooksweep")
		local r0 = tmpRoot(proj)
		fs.writeDir(`{r0}/old.A`)
		must(process.exec("touch", { "-t", "202601010000", `{r0}/old.A` }), "touch")
		local stubs = `{base}/hooksweep-stubs`
		must(process.exec("rm", { "-rf", stubs }), "rm")
		fs.writeDir(stubs)
		fs.writeFile(`{stubs}/lsof`, "#!/bin/sh\ntrue\n")
		must(process.exec("chmod", { "+x", `{stubs}/lsof` }), "chmod")
		local envFile = `{base}/hooksweep-env`
		fs.writeFile(envFile, "")
		local env = {
			CLAUDE_PROJECT_DIR = proj,
			CLAUDE_ENV_FILE = envFile,
			PATH = `{stubs}:{process.env.PATH or ""}`,
			HOME = process.env.HOME or "",
		}
		local r = process.exec("bash", { `{proj}/scripts/hooks/session-tmp.sh` }, { env = env })
		t.expect(r.ok and r.stdout == "").toBe(true)
		t.expect(fs.isDir(`{r0}/old.A`)).toBe(false)
	end)

	it("./zn tmp reaches the command line from anywhere in a checkout", function()
		local proj = project("zn")
		local r = process.exec("bash", { `{proj}/zn`, "tmp", "root" }, {
			cwd = `{proj}/z-nile`,
			env = {
				PATH = process.env.PATH or "",
				HOME = process.env.HOME or "",
				TMPDIR = "/c0194-no-such-tmpdir",
			},
		})
		t.expect(trim(r.stdout)).toBe(`{proj}/.cache/.tmp`)
	end)
end)
