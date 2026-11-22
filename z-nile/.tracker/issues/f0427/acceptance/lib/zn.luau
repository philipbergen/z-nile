--!strict
-- f0427: building zn for the specs. Every build goes through z-nile/lib/znbuild.sh into a folder under this home's
-- .cache/zn-test, in a copy of z-nile/go (the build writes the embedded files into the module), with Go's caches under
-- .cache too. Nothing outside .cache is written, and nothing is downloaded.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")

local zn = {}

export type Built = { ok: boolean, code: number, stderr: string, stdout: string, bin: string, godir: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- The checkout's top (the spec runs inside it).
function zn.checkout(): string
	return trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
end

-- This home's physical path.
function zn.home(): string
	return fixture.physical(".") :: string
end

-- A fresh folder .cache/<name> under this home.
function zn.fresh(name: string): string
	local dir = `{zn.home()}/.cache/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	return dir
end

-- Builds zn into .cache/zn-test/<label>/zn. `args` are znbuild.sh's (--goos, --lune-zip, --sum, ...). The Go module is a
-- copy of this checkout's, so the embedded files land in the copy.
function zn.build(label: string, args: { string }): Built
	local checkout = zn.checkout()
	local dir = zn.fresh(`zn-test/{label}`)
	local godir = `{dir}/go`
	local cp = process.exec("cp", { "-R", `{checkout}/z-nile/go`, godir })
	if not cp.ok then
		error(`cp of z-nile/go failed: {cp.stderr}`, 2)
	end
	process.exec("rm", { "-rf", `{godir}/internal/payload/embedded` })
	local argv =
		{ `{checkout}/z-nile/lib/znbuild.sh`, "--out", `{dir}/zn`, "--go-dir", godir, "--checkout", checkout }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, {
		env = {
			GOCACHE = `{zn.home()}/.cache/zn-test/go-build`,
			GOFLAGS = "-modcacherw",
		},
	})
	return { ok = r.ok, code = r.code, stderr = r.stderr, stdout = r.stdout, bin = `{dir}/zn`, godir = godir }
end

-- A tracker-shaped fixture checkout with one ticket, f0001, and nothing else: the engine's `list` finds it.
function zn.tracker(name: string): string
	local dir = zn.fresh(name)
	fs.writeDir(`{dir}/z-nile`)
	fs.writeDir(`{dir}/demo/.tracker/issues/f0001`)
	fs.writeDir(`{dir}/demo/.tracker/rafts`)
	fs.writeFile(`{dir}/z-nile/projects.toml`, '[[project]]\nname = "demo"\nroot = "demo/.tracker"\n')
	fs.writeFile(`{dir}/z-nile/next`, "issue 1 aa-bb-cc\nraft 0 aa-bb-cc\n")
	fs.writeFile(
		`{dir}/demo/.tracker/issues/f0001/f0001.md`,
		"---\nid: f0001\ntype: feature\ntitle: Hello fixture\nslug: hello-fixture\nraft: \ndepends_on: []\nemergent: false\ndesign: none\nrisk: normal\ncreated: 2026-11-21\nstatus: new-aa-bb-cc\n---\n\n# f0001: Hello fixture\n\n## Problem\n- a fixture ticket\n"
	)
	local init = process.exec("git", { "init", "-q", "-b", "main", dir })
	if not init.ok then
		error(`git init of {dir} failed: {init.stderr}`, 2)
	end
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "fixture" })
	return dir
end

-- Runs a built zn in a fixture checkout with no Lune on PATH and its cache in a throwaway folder.
function zn.run(bin: string, dir: string, cache: string, args: { string }): fixture.Result
	return fixture.exec(dir, bin, args, { env = { PATH = "/usr/bin:/bin", ZN_CACHE = cache } })
end

return zn
