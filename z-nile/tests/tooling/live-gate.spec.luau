--!strict
-- f0424 AC24 and AC25: the gate lists the live layer's Go stages for a change under z-nile/go and none of gofmt, vet
-- and test for a change elsewhere in z-nile (the build for both), and the docs name the Go module and the toolchain.
-- `--plan` only, in a fixture repository under .cache.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

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
				t.expect(has(inGo, "go not found: the Go stages are skipped")).toBe(true)
				return
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
end)
