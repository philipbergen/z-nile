--!strict
-- c0165 AC5 (results that cannot be trusted, in fixture repositories, gatefix.luau): a runner the browser guard fails
-- after every spec passed, a runner that quit early, and a results file that omits a spec. None records a pass.
-- Fixtures under .cache/c0165-gate-results.
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-results`
local has, count, ran = gatefix.has, gatefix.count, gatefix.ran
local AB = gatefix.AB

return t.spec("c0165 results that record no pass", function(it)
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
	end)

	it("AC5: a spec with no result (the runner quit early) is counted failed and not recorded", function()
		local dir = gatefix.make(base, "quitter", { extra = { quitter = { quits = true } } })
		local ok, out = gatefix.specs(
			dir,
			{ "--", "tests/unit/a.spec.luau", "tests/unit/quitter.spec.luau" },
			{ PICKMAN_JOBS = "1" }
		)
		t.expect(ok).toBe(false)
		t.expect(has(out, "results file missing")).toBe(true)
		t.expect(gatefix.sql(dir, "select count(*) from specs")).toBe("0")
	end)

	it(
		"AC5: a results file that omits a spec it was asked to run counts it failed and records nothing for it",
		function()
			local dir = gatefix.make(base, "omitted")
			local ok, out =
				gatefix.specs(dir, AB, { PATH = gatefix.omitResult(dir, "tests/unit/b.spec.luau") })
			t.expect(ok).toBe(false)
			t.expect(has(out, "FAIL tests/unit/b.spec.luau: no result for it")).toBe(true)
			t.expect(gatefix.sql(dir, "select count(*) from specs where spec = 'tests/unit/b.spec.luau'"))
				.toBe("0")
			local ok2, _ = gatefix.specs(dir, { "--", "tests/unit/b.spec.luau" })
			t.expect(ok2).toBe(true)
			t.expect(count(ran(dir), "b")).toBe(2)
		end
	)
end)
