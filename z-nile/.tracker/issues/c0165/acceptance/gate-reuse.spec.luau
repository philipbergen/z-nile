--!strict
-- c0165 AC5 and AC7 (reuse): through the orchestrator (`z-nile/specs`) and the gate (`z-nile/check.sh`) in fixture
-- repositories (gatefix.luau): same content reuses every spec, an edit reruns only its specs, a whole affected gate is
-- reused with its static report, its digest is scoped by projects and base, and every way a run could leave a wrong
-- pass behind records none (reuse off, a failed blob read, inputs changed mid-run, a runner that fails after every spec
-- passed). Fixtures under .cache/c0165-gate-reuse.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-reuse`
local has, count, ran, clearRan, write =
	gatefix.has, gatefix.count, gatefix.ran, gatefix.clearRan, gatefix.write
local AB = gatefix.AB

return t.spec("c0165 reuse through the orchestrator and the gate", function(it)
	it(
		"AC5: a second run on the same content reuses every spec and runs none; an edit reruns only its specs",
		function()
			local dir = gatefix.make(base, "reuse")
			local ok1, out1 = gatefix.specs(dir, AB)
			t.expect(ok1).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(1)
			t.expect(has(out1, "2 passed, 0 failed, 2 spec files")).toBe(true)
			t.expect(fs.isFile(`{dir}/.claude/.znile_tests.sqlite`)).toBe(true)
			clearRan(dir)
			local ok2, out2 = gatefix.specs(dir, AB)
			t.expect(ok2).toBe(true)
			t.expect(ran(dir)).toBe("")
			t.expect(has(out2, "reused tests/unit/a.spec.luau")).toBe(true)
			t.expect(has(out2, "reused tests/unit/b.spec.luau")).toBe(true)
			t.expect(has(out2, "2 passed, 0 failed, 2 spec files")).toBe(true)
			-- an uncommitted edit of A: a reruns, b is reused
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local ok3, _ = gatefix.specs(dir, AB)
			t.expect(ok3).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(0)
			-- --fresh runs both again
			clearRan(dir)
			local ok4, _ = gatefix.specs(dir, { "--fresh", table.unpack(AB) })
			t.expect(ok4).toBe(true)
			t.expect(count(ran(dir), "a") + count(ran(dir), "b")).toBe(2)
		end
	)

	it(
		"AC5: through check.sh --affected: the edit's selection runs, and an unchanged second gate is reused whole, its static report shown",
		function()
			local dir = gatefix.make(base, "affected")
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local ok1, out1 = gatefix.gate(dir, { "--affected" })
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "GATE PASSED (affected)")).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
			t.expect(count(ran(dir), "b")).toBe(0)
			clearRan(dir)
			local ok2, out2 = gatefix.gate(dir, { "--affected" })
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(true)
			-- the static stages' report is shown from the record (the lint summary zz-execute Phase 4 reads)
			t.expect(has(out2, "== lint (selene)")).toBe(true)
			t.expect(has(out2, "GATE PASSED (affected)")).toBe(true)
			t.expect(ran(dir)).toBe("")
			-- --fresh runs the selection again
			local ok3, _ = gatefix.gate(dir, { "--affected", "--fresh" })
			t.expect(ok3).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(1)
		end
	)

	it("AC7: a whole-gate record is scoped by its projects and its base", function()
		local dir = gatefix.make(base, "scope")
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		fixture.git(dir, { "commit", "-qam", "edit" })
		local ok1, _ = gatefix.gate(dir, { "--affected" })
		t.expect(ok1).toBe(true)
		local ok2, out2 = gatefix.gate(dir, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(true)
		-- every project (no --project): another set of projects, so pickman's record doesn't stand for it
		local okAll, outAll = gatefix.gateRaw(dir, { "--affected" })
		t.expect(okAll).toBe(true)
		t.expect(has(outAll, "reused: an affected gate passed on this content")).toBe(false)
		-- another base: the same content, compared with another commit, is another gate
		local okBase, outBase = gatefix.gate(dir, { "--affected", "--base", "HEAD" })
		t.expect(okBase).toBe(true)
		t.expect(has(outBase, "reused: an affected gate passed on this content")).toBe(false)
	end)

	it("AC7: an affected whole-gate digest holds HEAD and only declared refs", function()
		local dir = gatefix.make(base, "headgate", {
			setup = function(d: string)
				write(
					`{d}/pickman/tests/inputs.tsv`,
					"# extra inputs per spec\ntests/unit/b.spec.luau\t*\ntests/unit/b.spec.luau\tref:refs/remotes/origin/main\ntests/unit/b.spec.luau\tref:refs/heads/declared\n"
				)
			end,
		})
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		fixture.git(dir, { "update-ref", "refs/remotes/origin/main", "HEAD" })
		fixture.git(dir, { "update-ref", "refs/heads/declared", "HEAD" })
		local ok1, _ = gatefix.gate(dir, { "--affected" })
		t.expect(ok1).toBe(true)
		t.expect(count(ran(dir), "b")).toBe(1)
		fixture.git(dir, { "update-ref", "refs/heads/unrelated", "HEAD" })
		local okUnrelated, outUnrelated = gatefix.gate(dir, { "--affected" })
		t.expect(okUnrelated).toBe(true)
		t.expect(has(outUnrelated, "reused: an affected gate passed on this content")).toBe(true)
		t.expect(count(ran(dir), "b")).toBe(1)
		fixture.git(dir, { "commit", "-qam", "same content, new HEAD" })
		local ok2, out2 = gatefix.gate(dir, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(false)
		t.expect(count(ran(dir), "b")).toBe(2)
		-- a declared ref that is not the base moves while HEAD and the base stand still: no reuse, b runs again
		fixture.git(dir, { "update-ref", "refs/heads/declared", "HEAD" })
		local okDeclared, outDeclared = gatefix.gate(dir, { "--affected" })
		t.expect(okDeclared).toBe(true)
		t.expect(has(outDeclared, "reused: an affected gate passed on this content")).toBe(false)
		t.expect(count(ran(dir), "b")).toBe(3)
		-- the base moves to HEAD, so the change set is empty: a spec with a ref: entry is still selected and reruns
		fixture.git(dir, { "update-ref", "refs/remotes/origin/main", "HEAD" })
		local ok3, out3 = gatefix.gate(dir, { "--affected" })
		t.expect(ok3).toBe(true)
		t.expect(has(out3, "reused: an affected gate passed on this content")).toBe(false)
		t.expect(count(ran(dir), "b")).toBe(4)
	end)

	it("AC5: a weak-jail run records neither spec rows nor a whole-gate row, affected or full", function()
		local affected = gatefix.make(base, "norecord-affected")
		write(`{affected}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		local weakA = { PATH = gatefix.weakJail(affected) }
		local ok1, out1 = gatefix.gate(affected, { "--affected" }, weakA)
		t.expect(ok1).toBe(true)
		t.expect(has(out1, "not recorded: outer sandbox (protects the repository)")).toBe(true)
		t.expect(gatefix.sql(affected, "select count(*) from specs")).toBe("0")
		t.expect(gatefix.sql(affected, "select count(*) from gates")).toBe("0")
		local ok2, out2 = gatefix.gate(affected, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(false)
		t.expect(count(ran(affected), "a")).toBe(2)

		local full = gatefix.make(base, "norecord-full")
		local weakF = { PATH = gatefix.weakJail(full) }
		local okF, _ = gatefix.gate(full, { "--full" }, weakF)
		t.expect(okF).toBe(true)
		t.expect(gatefix.sql(full, "select count(*) from specs")).toBe("0")
		t.expect(gatefix.sql(full, "select count(*) from gates")).toBe("0")
		clearRan(full)
		local okR, outR = gatefix.gate(full, { "--full", "--reuse" })
		t.expect(okR).toBe(true)
		t.expect(has(outR, "reused: a full gate passed on this content")).toBe(false)
		t.expect(count(ran(full), "a")).toBe(1)
	end)

	it("AC5: with reuse off (no sqlite3) every given spec runs and the result is unchanged", function()
		local dir = gatefix.make(base, "off")
		local miss = { PICKMAN_SQLITE3 = `{dir}/no-such-sqlite3` }
		local ok1, out1 = gatefix.specs(dir, AB, miss)
		t.expect(ok1).toBe(true)
		t.expect(has(out1, "reuse off:")).toBe(true)
		local ok2, _ = gatefix.specs(dir, AB, miss)
		t.expect(ok2).toBe(true)
		t.expect(count(ran(dir), "a")).toBe(2)
		t.expect(count(ran(dir), "b")).toBe(2)
		t.expect(fs.isFile(`{dir}/.claude/.znile_tests.sqlite`)).toBe(false)
		-- a failing spec still fails the run with reuse off
		write(`{dir}/pickman/src/A.luau`, "return { value = 2 }\n")
		local ok3, _ = gatefix.specs(dir, AB, miss)
		t.expect(ok3).toBe(false)
	end)

	it(
		"AC5: a failed blob read (hash-object) turns reuse off: every spec runs and nothing is recorded",
		function()
			local dir = gatefix.make(base, "gitfail")
			local realGit = gatefix.trim(process.exec("sh", { "-c", "command -v git" }).stdout)
			write(
				`{dir}/bin-gitfail/git`,
				'#!/bin/sh\nif [ "$1" = hash-object ]; then exit 1; fi\n' .. `exec "{realGit}" "$@"\n`
			)
			process.exec("chmod", { "+x", `{dir}/bin-gitfail/git` })
			write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
			local env1 = { PATH = `{dir}/bin-gitfail:{dir}/bin:{process.env.PATH or ""}` }
			local ok1, out1 = gatefix.specs(dir, AB, env1)
			t.expect(ok1).toBe(true)
			t.expect(has(out1, "reuse off:")).toBe(true)
			local ok2, _ = gatefix.specs(dir, AB, env1)
			t.expect(ok2).toBe(true)
			t.expect(count(ran(dir), "a")).toBe(2)
			t.expect(count(ran(dir), "b")).toBe(2)
		end
	)

	it(
		"AC5: a spec whose input changed during the run is not recorded, so the old content runs it again",
		function()
			local dir = gatefix.make(base, "changed", {
				extra = { cdep = { needs = "C", expect = 2 } },
				setup = function(d: string)
					-- aa_edit runs first in path order and rewrites C.luau, an input of cdep, before cdep loads it
					write(
						`{d}/pickman/tests/unit/aa_edit.spec.luau`,
						gatefix.specText(
							d,
							"aa_edit",
							{ writes = { path = `{d}/pickman/src/C.luau`, text = "return { value = 2 }\\n" } }
						)
					)
				end,
			})
			-- one job, path order: aa_edit rewrites C.luau to value 2, then cdep loads C and passes only with value 2
			local ok1, _ = gatefix.specs(
				dir,
				{ "--", "tests/unit/aa_edit.spec.luau", "tests/unit/cdep.spec.luau" },
				{ PICKMAN_JOBS = "1" }
			)
			t.expect(ok1).toBe(true)
			t.expect(count(ran(dir), "cdep")).toBe(1)
			-- back to the content the run was claimed under: a pass recorded under that fingerprint would be reused here
			write(`{dir}/pickman/src/C.luau`, "return { value = 1 }\n")
			local ok2, _ = gatefix.specs(dir, { "--", "tests/unit/cdep.spec.luau" }, { PICKMAN_JOBS = "1" })
			t.expect(count(ran(dir), "cdep")).toBe(2)
			t.expect(ok2).toBe(false)
		end
	)

	it("AC5: a run the runner fails after every spec passed (the browser guard) records no pass", function()
		local dir = gatefix.make(base, "opener", { extra = { opener = { opens = true } } })
		local one = { "--", "tests/unit/opener.spec.luau" }
		local ok1, out1 = gatefix.specs(dir, one)
		t.expect(ok1).toBe(false)
		t.expect(has(out1, "results not recorded")).toBe(true)
		local ok2, _ = gatefix.specs(dir, one)
		t.expect(ok2).toBe(false)
		t.expect(count(ran(dir), "opener")).toBe(2)
		t.expect(gatefix.sql(dir, "select count(*) from specs where state = 'passed'")).toBe("0")
		-- through the full gate too: red, and no passed row
		local okF, _ = gatefix.gate(dir, { "--full" })
		t.expect(okF).toBe(false)
		t.expect(
			gatefix.sql(
				dir,
				"select count(*) from specs where state = 'passed' and spec = 'tests/unit/opener.spec.luau'"
			)
		).toBe("0")
	end)
end)
