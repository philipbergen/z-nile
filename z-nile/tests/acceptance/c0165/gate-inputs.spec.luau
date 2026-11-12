--!strict
-- c0165 AC5 (what a result may stand for, in fixture repositories, gatefix.luau): a spec whose input changed during
-- the run records nothing, the runner's output is forwarded live, a `*` spec and a declared-folder spec rerun when
-- they must. Fixtures under .cache/c0165-gate-inputs.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-inputs`
local has, count, ran, write = gatefix.has, gatefix.count, gatefix.ran, gatefix.write

return t.spec("c0165 inputs, live output and always-run specs", function(it)
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
					write(`{d}/pickman/tests/unit/aa_edit.watch.txt`, "pickman/src/A.luau\n")
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
			-- back to the content the run started under: a pass recorded under that fingerprint would be reused here
			write(`{dir}/pickman/src/C.luau`, "return { value = 1 }\n")
			local ok2, _ = gatefix.specs(dir, { "--", "tests/unit/cdep.spec.luau" }, { PICKMAN_JOBS = "1" })
			t.expect(count(ran(dir), "cdep")).toBe(2)
			t.expect(ok2).toBe(false)
		end
	)

	it("AC5: the runner's output is forwarded while it runs, not held until it ends", function()
		local dir =
			gatefix.make(base, "live", { extra = { afail = { broken = true }, bhold = { hold = true } } })
		fs.writeFile(`{dir}/hold.marker`, "")
		-- one job, path order: afail fails at once, then bhold holds; afail's FAIL line must be out while bhold holds
		local r = process.exec("bash", {
			"-c",
			'd=$1; (cd "$d"; PICKMAN_JOBS=1 PATH="$d/bin:$PATH" lune run z-nile/specs -- run --project pickman -- tests/unit/afail.spec.luau tests/unit/bhold.spec.luau > "$d/../live.out" 2>&1) & '
				.. 'pid=$!; seen=1; for i in $(seq 1 300); do grep -q "FAIL tests/unit/afail.spec.luau" "$d/../live.out" 2>/dev/null && { seen=0; break; }; kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done; '
				.. 'rm -f "$d/hold.marker"; wait; exit $seen',
			"_",
			dir,
		}, { env = { PICKMAN_OPEN_GUARD = "" } })
		-- 0: seen within 30 s, while bhold still held (its hold lasts up to 60 s, so held output would show only after);
		-- 1: not seen in that time
		t.expect(r.code).toBe(0)
		t.expect(count(ran(dir), "bhold")).toBe(1)
	end)

	it("AC5: a tracker file selects nothing, and a watched file's unchanged bytes are reused", function()
		local dir = gatefix.make(base, "always")
		t.expect(gatefix.affected(dir, { "pickman/.tracker/issues/f0009/f0009.md" })).toBe("")
		t.expect(gatefix.affected(dir, { "pickman/src/B.luau" })).toBe("tests/unit/b.spec.luau")
		local one = { "--", "tests/unit/b.spec.luau" }
		local ok1, _ = gatefix.specs(dir, one)
		local ok2, out2 = gatefix.specs(dir, one)
		t.expect(ok1 and ok2).toBe(true)
		t.expect(count(ran(dir), "b")).toBe(1)
		t.expect(has(out2, "reused tests/unit/b.spec.luau")).toBe(true)
		fixture.git(dir, { "commit", "-q", "--allow-empty", "-m", "move HEAD" })
		local ok4, out4 = gatefix.specs(dir, one)
		t.expect(ok4).toBe(true)
		t.expect(has(out4, "reused tests/unit/b.spec.luau")).toBe(true)
		t.expect(count(ran(dir), "b")).toBe(1)
	end)

	it(
		"AC5: a watched file changes the fingerprint; a file the watch list does not name does not select it",
		function()
			local dir = gatefix.make(base, "folder", {
				setup = function(d: string)
					write(
						`{d}/pickman/tests/unit/scan.spec.luau`,
						"--!strict\n"
							.. "local fs = req"
							.. 'uire("@lune/fs")\n'
							.. "local process = req"
							.. 'uire("@lune/process")\n'
							.. "local t = req"
							.. 'uire("@tests/lib/t")\n'
							.. 'return t.spec("scan", function(it)\n'
							.. '\tit("runs", function()\n'
							.. `\t\tprocess.exec("sh", \{ "-c", 'echo scan >> "$1"', "_", "{d}/ran.log" })\n`
							.. '\t\tt.expect(fs.readFile("data/x.txt")).toBe("ok\\n")\n'
							.. "\tend)\nend)\n"
					)
					write(`{d}/pickman/tests/unit/scan.watch.txt`, "pickman/data/x.txt\n")
				end,
			})
			local scan = { "--", "tests/unit/scan.spec.luau" }
			local ok1, _ = gatefix.specs(dir, scan)
			t.expect(ok1).toBe(true)
			local ok2, out2 = gatefix.specs(dir, scan)
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused tests/unit/scan.spec.luau")).toBe(true)
			write(`{dir}/pickman/data/new.txt`, "bad\n")
			t.expect(gatefix.affected(dir, { "pickman/data/new.txt" })).toBe("")
			write(`{dir}/pickman/data/x.txt`, "bad\n")
			t.expect(gatefix.affected(dir, { "pickman/data/x.txt" }))
				.toBe("tests/unit/scan.spec.luau\ntests/unit/text.spec.luau")
			local ok3, _ = gatefix.specs(dir, scan)
			t.expect(ok3).toBe(false)
			t.expect(count(ran(dir), "scan")).toBe(2)
		end
	)
end)
