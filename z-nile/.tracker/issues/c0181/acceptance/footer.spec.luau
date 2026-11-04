--!strict
-- c0181 AC6: when a spec file fails and a lesson names it in `enforced_by`, the runner's failure prints that lesson
-- (id, title and its short body, which says how to fix it) under the failing case. A failure of a file no lesson
-- names prints what it printed before. `PICKMAN_LESSONS_ROOT` names the folder whose skills the runner reads
-- (default: the repository). The footer never changes a case's result.
local codify = require("@znile/engine/codify")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local lessons = require("@scripts/tracker/lessons")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local SPEC = "z-nile/tests/meta/x.spec.luau"
local function parse(id: string, ref: string): lessons.Lesson
	local l, err = lessons.parse(
		id,
		`---\ntitle: Pass plain = true\nwhen: both\ntags: [wiring]\ncheck: Is it plain?\nenforced_by: {ref}\nenforced: full\n---\nUse plain find; see the lint.\n`
	)
	return l or error(err)
end

return t.spec("c0181 failure footer", function(it)
	it(
		"names the lessons whose check is the failing case, with their title and body, and no other",
		function()
			local all = {
				parse("zz-test/one", `{SPEC} :: "[zz-test/one] fails"`),
				parse("zz-test/two", `{SPEC} :: "[zz-test/two] another case"`),
				parse("zz-test/other", `z-nile/tests/meta/y.spec.luau :: "[zz-test/other] fails"`),
			}
			local text = codify.footer(all, SPEC, "[zz-test/one] fails") or ""
			t.expect(string.find(text, "zz-test/one", 1, true) ~= nil).toBe(true)
			t.expect((string.find(text, "zz-test/two", 1, true))).toBe(nil) -- same file, another case
			t.expect((string.find(text, "zz-test/other", 1, true))).toBe(nil) -- another file
			t.expect(string.find(text, "Pass plain = true", 1, true) ~= nil).toBe(true)
			t.expect(string.find(text, "Use plain find; see the lint.", 1, true) ~= nil).toBe(true)
			t.expect(codify.footer(all, SPEC, "a case no lesson names")).toBe(nil)
			t.expect(codify.footer(all, "z-nile/tests/meta/none.spec.luau", "[zz-test/one] fails")).toBe(nil)
		end
	)

	it("the runner prints it under the failing case, and nothing for a file no lesson names", function()
		local home = fixture.physical(".") or error("no home")
		local dir = `{home}/.cache/lesson-footer`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/lessons-root/z-nile/skills/zz-test/lessons`)
		engine.registry(`{dir}/lessons-root`)
		fs.writeFile(
			`{dir}/lessons-root/z-nile/skills/zz-test/SKILL.md`,
			"---\nname: zz-test\ndescription: x\n---\n"
		)
		fs.writeFile(
			`{dir}/lessons-root/z-nile/skills/zz-test/lessons/guard.md`,
			"---\ntitle: Pass plain = true\nwhen: both\ntags: [wiring]\ncheck: Is it plain?\n"
				.. 'enforced_by: z-nile/.cache/lesson-footer/x.spec.luau :: "c"\nenforced: full\nfrom: test\n---\nUse plain find; see the lint.\n'
		)
		local failing = 'return { name = "x", cases = { { name = "c", fn = function() error("boom") end } } }'
		fs.writeFile(`{dir}/x.spec.luau`, failing)
		fs.writeFile(`{dir}/y.spec.luau`, failing)
		local function run(file: string): process.ExecResult
			return process.exec("perl", {
				"-e",
				"alarm 60; exec @ARGV",
				"lune",
				"run",
				"tests/run",
				"--",
				"--jobs",
				"1",
				`.cache/lesson-footer/{file}`,
			}, { cwd = home, env = { PICKMAN_LESSONS_ROOT = `{dir}/lessons-root` } })
		end
		local x = run("x.spec.luau")
		t.expect(x.code).toBe(1)
		t.expect(string.find(x.stdout, "x.spec.luau :: c", 1, true) ~= nil).toBe(true)
		t.expect(string.find(x.stdout, "lesson zz-test/guard is enforced here", 1, true) ~= nil).toBe(true)
		t.expect(string.find(x.stdout, "Use plain find; see the lint.", 1, true) ~= nil).toBe(true)
		t.expect((string.find(x.stdout, "1 passed, 0 failed", 1, true))).toBe(nil)
		local y = run("y.spec.luau")
		t.expect(y.code).toBe(1)
		t.expect((string.find(y.stdout, "enforced here", 1, true))).toBe(nil)
		t.expect(string.find(y.stdout, "0 passed, 1 failed, 1 spec files", 1, true) ~= nil).toBe(true)
		fs.removeDir(dir)
	end)

	it("a lessons folder that cannot be read leaves the failure as it was", function()
		local home = fixture.physical(".") or error("no home")
		local dir = `{home}/.cache/lesson-footer-none`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		fs.writeFile(
			`{dir}/z.spec.luau`,
			'return { name = "x", cases = { { name = "c", fn = function() error("boom") end } } }'
		)
		local r = process.exec("perl", {
			"-e",
			"alarm 60; exec @ARGV",
			"lune",
			"run",
			"tests/run",
			"--",
			"--jobs",
			"1",
			".cache/lesson-footer-none/z.spec.luau",
		}, { cwd = home, env = { PICKMAN_LESSONS_ROOT = `{dir}/does-not-exist` } })
		fs.removeDir(dir)
		t.expect(r.code).toBe(1)
		t.expect(string.find(r.stdout, "0 passed, 1 failed, 1 spec files", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout, "enforced here", 1, true))).toBe(nil)
	end)
	it(
		"a copy of the runner with no z-nile/engine (as seven promoted specs build) fails and prints as it did",
		function()
			local home = fixture.physical(".") or error("no home")
			local base = `{home}/.cache/lesson-footer-copy`
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			for _, rel in
				{ "z-nile/tests/run.luau", "z-nile/tests/lib", "z-nile/lib", "z-nile/.luaurc", ".luaurc" }
			do
				local dest = `{base}/{rel}`
				fs.writeDir(string.match(dest, "^(.*)/[^/]+$") :: string)
				t.expect(process.exec("cp", { "-R", `{engine.TOP}/{rel}`, dest }).ok).toBe(true)
			end
			fs.writeDir(`{base}/z-nile/.tracker`)
			fs.writeFile(
				`{base}/z-nile/tests/f.spec.luau`,
				'return { name = "x", cases = { { name = "c", fn = function() error("boom") end } } }'
			)
			fs.writeDir(`{base}/z-nile/.cache`)
			local r = process.exec("perl", {
				"-e",
				"alarm 60; exec @ARGV",
				"lune",
				"run",
				"tests/run",
				"--",
				"--jobs",
				"1",
				"tests/f.spec.luau",
			}, { cwd = `{base}/z-nile`, env = { PICKMAN_JOBS = "" } })
			fs.removeDir(base)
			t.expect(r.code).toBe(1)
			t.expect(string.find(r.stdout, "0 passed, 1 failed, 1 spec files", 1, true) ~= nil).toBe(true)
			t.expect((string.find(r.stdout, "enforced here", 1, true))).toBe(nil)
		end
	)
end)
