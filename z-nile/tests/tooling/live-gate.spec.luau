--!strict
-- f0424 AC24 and AC25 (and the gate without Go): the gate lists the live layer's Go stages for a change under z-nile/go and none of gofmt, vet
-- and test for a change elsewhere in z-nile (the build for both), and the docs name the Go module and the toolchain.
-- `--plan` only, in a fixture repository under .cache.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local homeDir = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function plan(dir: string, args: { string }): string
	local argv = { "z-nile/check.sh", "--plan" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = fixture.exec(dir, "bash", argv)
	return r.stdout .. r.stderr
end

return t.spec("f0424 the gate's Go stages and the docs", function(it)
	it(
		"AC24: gofmt, vet and test for a change under z-nile/go, none elsewhere in z-nile, the build for both",
		function()
			local f = trackerfix.new("f0424-gate")
			local hasGo = process.exec("sh", { "-c", "command -v go" }).ok
			local goLines = { "go format:", "go vet:", "go test:" }
			fs.writeDir(`{f.main}/z-nile/go/internal/x`)
			fs.writeFile(`{f.main}/z-nile/go/internal/x/x.go`, "package x\n")
			local inGo = plan(f.main, { "--affected" })
			fs.removeFile(`{f.main}/z-nile/go/internal/x/x.go`)
			fs.writeFile(`{f.main}/z-nile/elsewhere.txt`, "a change in z-nile, not in z-nile/go\n")
			local elsewhere = plan(f.main, { "--affected" })
			if not hasGo then
				return -- with no Go a change under z-nile/go fails the gate by design: the F10 cases cover it
			end
			for _, line in goLines do
				t.expect(has(inGo, line)).toBe(true)
				t.expect(has(elsewhere, line)).toBe(false)
			end
			t.expect(has(inGo, "go build:")).toBe(true)
			t.expect(has(elsewhere, "go build:")).toBe(true)
			-- a full gate always has all four, and a static one follows the change like an affected one
			local full = plan(f.main, { "--full" })
			for _, line in goLines do
				t.expect(has(full, line)).toBe(true)
			end
			t.expect(has(plan(f.main, { "--static" }), "go vet:")).toBe(false)
		end
	)

	it(
		"AC25: zz-arch's layout and rule 2 name z-nile/go/ as the tooling's Go module, and SETUP.md names the Go toolchain",
		function()
			local arch = fs.readFile(`{root}/z-nile/skills/zz-arch/SKILL.md`)
			local layoutRow = string.match(arch, "\n(| `z%-nile/go/` |[^\n]*)\n")
			t.expect(layoutRow ~= nil).toBe(true)
			t.expect(has(layoutRow :: string, "module znile")).toBe(true)
			t.expect(has(layoutRow :: string, "standard library only")).toBe(true)
			local rule2 = string.match(arch, "\n2%. ([^\n]*)\n")
			t.expect(rule2 ~= nil).toBe(true)
			t.expect(has(rule2 :: string, "Luau on Lune")).toBe(true)
			t.expect(has(rule2 :: string, "`z-nile/go/`")).toBe(true)
			t.expect(has(rule2 :: string, "gofmt")).toBe(true)
			local setup = fs.readFile(`{root}/SETUP.md`)
			t.expect(string.match(setup, "\n| Go 1%.24 or newer %(`go`%)") ~= nil).toBe(true)
		end
	)

	-- The gate without a usable Go: a change that needs the Go stages fails with one line naming SETUP.md; any other
	-- change skips them with one line and passes. The plan reports both; `--plan` exits 1 where the gate would fail.
	local function withoutGo(old: boolean): ({ [string]: string }?, string)
		local base = process.exec("sh", { "-c", "PATH=/usr/bin:/bin command -v go" })
		if base.ok and not old then
			return nil, "" -- a system Go lives in /usr/bin: it cannot be hidden by the path alone
		end
		local shadow = `{homeDir}/.cache/f0424-nogo-shadow`
		if fs.isDir(shadow) then
			fs.removeDir(shadow)
		end
		fs.writeDir(shadow)
		if old then
			fs.writeFile(`{shadow}/go`, '#!/bin/sh\n[ "$1 $2" = "env GOVERSION" ] && echo go1.22.0\nexit 0\n')
			process.exec("chmod", { "+x", `{shadow}/go` })
		end
		return { PATH = `{shadow}:/usr/bin:/bin:/usr/sbin:/sbin` }, shadow
	end
	local function planWith(dir: string, args: { string }, env: { [string]: string }): (boolean, string)
		local argv = { "z-nile/check.sh", "--plan" }
		for _, a in args do
			table.insert(argv, a)
		end
		local r = fixture.exec(dir, "bash", argv, { env = env })
		return r.ok, r.stdout .. r.stderr
	end

	it(
		"F10: with no Go, a change under z-nile/go and a full gate fail naming SETUP.md; another change skips",
		function()
			local env = withoutGo(false)
			if not env then
				return
			end
			local f = trackerfix.new("f0424-nogo")
			fs.writeDir(`{f.main}/z-nile/go/internal/x`)
			fs.writeFile(`{f.main}/z-nile/go/internal/x/x.go`, "package x\n")
			local ok, out = planWith(f.main, { "--affected" }, env)
			t.expect(ok).toBe(false)
			t.expect(has(out, "go not found")).toBe(true)
			t.expect(has(out, "SETUP.md")).toBe(true)
			ok, out = planWith(f.main, { "--full" }, env)
			t.expect(ok).toBe(false)
			fs.removeFile(`{f.main}/z-nile/go/internal/x/x.go`)
			fs.writeFile(`{f.main}/z-nile/elsewhere.txt`, "a change in z-nile, not in z-nile/go\n")
			ok, out = planWith(f.main, { "--affected" }, env)
			t.expect(ok).toBe(true)
			t.expect(
				has(
					out,
					"go not found: the Go stages are skipped; the live layer is unavailable on this machine"
				)
			).toBe(true)
			t.expect(has(out, "go test:")).toBe(false)
			t.expect(has(out, "go build:")).toBe(false)
		end
	)

	it("F10: an older Go fails with the version sentence and never downloads a toolchain", function()
		local env = withoutGo(true)
		if not env then
			return
		end
		local f = trackerfix.new("f0424-oldgo")
		fs.writeDir(`{f.main}/z-nile/go/internal/x`)
		fs.writeFile(`{f.main}/z-nile/go/internal/x/x.go`, "package x\n")
		local ok, out = planWith(f.main, { "--affected" }, env)
		t.expect(ok).toBe(false)
		t.expect(has(out, "Go 1.24 or newer is needed (SETUP.md)")).toBe(true)
		fs.removeFile(`{f.main}/z-nile/go/internal/x/x.go`)
		fs.writeFile(`{f.main}/z-nile/elsewhere.txt`, "x\n")
		local ok2, out2 = planWith(f.main, { "--affected" }, env)
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "the Go stages are skipped")).toBe(true)
		local gate = fs.readFile(`{root}/z-nile/lib/goenv.sh`)
		t.expect(has(gate, "export GOTOOLCHAIN=local")).toBe(true)
		t.expect(has(fs.readFile(`{root}/z-nile/lib/gobuild.sh`), "goenv.sh")).toBe(true)
	end)
end)
