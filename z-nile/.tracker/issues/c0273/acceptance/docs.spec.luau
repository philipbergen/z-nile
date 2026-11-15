--!strict
-- c0273 AC6: every document that restates which files are a home's project files names `*.project.jsonc` too: the
-- README's home paragraph, zz-test's Places bullet (c0185's pinned sentence kept as it is), pickman-arch's two
-- restatements (a further place, the server-file rule) and arcade's architecture (a place's project files, the forcing
-- rule). This spec runs from z-nile/; the checkout is read from its top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(rel: string, needle: string): boolean
	return string.find(fs.readFile(`{TOP}/{rel}`), needle, 1, true) ~= nil
end

return t.spec("c0273 the documents name *.project.jsonc", function(it)
	it("AC6: the README's home paragraph states the rule", function()
		t.expect(
			has(
				"z-nile/README.md",
				"and a project file Rojo loads from a mapped folder. A `*.project.jsonc` is a project file too (c0273): the rule, the gate's builds, the server-file rule and the static-run forcing read both names, a home holds at most one of `<name>.project.json` and `<name>.project.jsonc`, and a project file Lune's JSON decoder refuses (a comment or a trailing comma, which Rojo builds) is reported as mapping no `$path` and as not JSON to Lune's decoder: only what Rojo reads of it is judged."
			)
		).toBe(true)
	end)

	it("AC6: zz-test's Places bullet names it, and keeps c0185's sentence", function()
		t.expect(
			has(
				"z-nile/skills/zz-test/SKILL.md",
				"`.luaurc` or any `*.project.json` (under its home) selects a spec only when that spec's watch file names it. A `*.project.jsonc` is a project file as much as a `*.project.json` (c0273)."
			)
		).toBe(true)
	end)

	it("AC6: pickman-arch names it for a further place and for the server-file rule", function()
		local arch = "pickman/skills/pickman-arch/SKILL.md"
		t.expect(
			has(
				arch,
				"A further place is a further `<name>.project.json` (or `<name>.project.jsonc`, which Rojo builds too, c0273) and `src/<name>/`"
			)
		).toBe(true)
		t.expect(has(arch, "each `*.project.json` and `*.project.jsonc`, puts under")).toBe(true)
	end)

	it(
		"AC6: arcade's architecture names it for a place's project files and states the forcing rule",
		function()
			local arch = "arcade/.tracker/architecture.md"
			t.expect(
				has(arch, "- Each place's `*.project.json` (or `*.project.jsonc`, c0273) maps both with")
			)
				.toBe(true)
			t.expect(
				has(
					arch,
					"  - A change to a home's `*.project.json` or `*.project.jsonc` forces that home's static run (`HOME_FULL` in `z-nile/lib/select.luau`, c0273), and selects a spec only when that spec's watch file names it."
				)
			).toBe(true)
			t.expect(has(arch, "`z-nile/affected.luau` matches every `*.project.json`")).toBe(false)
		end
	)
end)
