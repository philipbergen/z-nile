--!strict
-- The watch map: parse and render, what counts as a source file, which specs a change selects, and how a
-- rename rewrites a list. Pure tables and strings.
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

return t.spec("the watch map", function(it)
	it("parses a sorted list and refuses a broken one", function()
		local paths, perr = watch.parse("a/b.luau\nz.luau\n")
		t.expect(perr).toBe(nil)
		t.expect(paths).toEqual({ "a/b.luau", "z.luau" })
		local empty, eerr = watch.parse("")
		t.expect(eerr).toBe(nil)
		t.expect(empty).toEqual({})
		t.expect(watch.render({ "z.luau", "a/b.luau", "a/b.luau" })).toBe("a/b.luau\nz.luau\n")
		local _, dup = watch.parse("a.luau\na.luau\n")
		t.expect(dup).toBe("line 2: a.luau is duplicated")
		local _, order = watch.parse("z.luau\na.luau\n")
		t.expect(order).toBe("line 2: a.luau is out of order")
		local _, abs = watch.parse("/etc/passwd\n")
		t.expect(string.find(abs :: string, "repository-relative", 1, true) ~= nil).toBe(true)
	end)

	it("leaves out tracker files, docs, skills, lessons and tests", function()
		t.expect(watch.sourceOf({
			"pickman/src/A.luau",
			"pickman/.tracker/issues/f0001/f0001.md",
			"z-nile/skills/zz-test/SKILL.md",
			"z-nile/skills/zz-test/lessons/x.md",
			"README.md",
			"pickman/tests/unit/a.spec.luau",
			"pickman/tests/unit/a.watch.txt",
			"z-nile/check.sh",
		})).toEqual({ "pickman/src/A.luau", "z-nile/check.sh" })
	end)

	it("selects the spec that watches a path, the spec a change edits, and no other", function()
		local bindings = {
			{
				spec = "pickman/tests/acceptance/f0001/a.spec.luau",
				watch = "pickman/tests/acceptance/f0001/watch.txt",
				paths = { "pickman/src/A.luau" },
			},
			{
				spec = "pickman/tests/unit/b.spec.luau",
				watch = "pickman/tests/unit/b.watch.txt",
				paths = { "pickman/src/B.luau" },
			},
		}
		t.expect(watch.select(bindings, { "pickman/src/A.luau" }, nil)).toEqual({
			"pickman/tests/acceptance/f0001/a.spec.luau",
		})
		t.expect(watch.select(bindings, { "z-nile/skills/zz-test/SKILL.md" }, nil)).toEqual({})
		t.expect(watch.select(bindings, { "pickman/.tracker/x.md" }, nil)).toEqual({})
		t.expect(watch.select(bindings, { "pickman/tests/unit/c.spec.luau" }, nil)).toEqual({
			"pickman/tests/unit/c.spec.luau",
		})
		t.expect(watch.fileFor("pickman/tests/acceptance/f0001/a.spec.luau"))
			.toBe("pickman/tests/acceptance/f0001/watch.txt")
		t.expect(watch.fileFor("pickman/tests/unit/b.spec.luau")).toBe("pickman/tests/unit/b.watch.txt")
	end)

	it("a source commit that names two issues shares the raft's list; a start commit does not", function()
		local shared = {
			{ message = "start\n", files = {} },
			{
				message = "both\n\nIssue: f0001 +1/-0 1.0m\nIssue: f0002 +1/-0 1.0m\n",
				files = { "pickman/src/A.luau", "README.md" },
			},
		}
		local per, isShared = watch.assign(shared, { "f0001", "f0002" })
		t.expect(isShared).toBe(true)
		t.expect(per.f0001).toEqual({ "pickman/src/A.luau" })
		t.expect(per.f0002).toEqual({ "pickman/src/A.luau" })
		local split = {
			{
				message = "tracker: start R0001\n",
				files = { "pickman/.tracker/rafts/active/R0001/R0001.md" },
			},
			{ message = "maze\n\nIssue: f0001 +1/-0 1.0m\n", files = { "pickman/src/A.luau" } },
		}
		local own, mixed = watch.assign(split, { "f0001", "f0002" })
		t.expect(mixed).toBe(false)
		t.expect(own.f0001).toEqual({ "pickman/src/A.luau" })
		t.expect(own.f0002).toEqual({})
	end)

	it("rewrites a renamed path and drops a deleted one", function()
		local nextp = watch.rewrite(
			{ "pickman/src/A.luau", "pickman/src/B.luau" },
			{ ["pickman/src/A.luau"] = "pickman/src/C.luau" },
			{ ["pickman/src/B.luau"] = true }
		)
		t.expect(nextp).toEqual({ "pickman/src/C.luau" })
		t.expect(watch.missing({ "pickman/src/C.luau", "gone.luau" }, function(p: string)
			return p == "pickman/src/C.luau"
		end)).toEqual({ "gone.luau" })
	end)

	it("reads a failing spec path out of a suite log", function()
		t.expect(watch.failingSpecs("ok\nFAIL pickman/tests/unit/a.spec.luau :: holds\n")).toEqual({
			"pickman/tests/unit/a.spec.luau",
		})
	end)
end)
