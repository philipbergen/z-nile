--!strict
-- c0165 AC7 (what a whole-gate digest holds, through `z-nile/check.sh --affected` in fixture repositories,
-- gatefix.luau): not HEAD and not the base, every selected spec's declared refs, never an unrelated ref. Fixtures under
-- .cache/c0165-gate-refs.
local fixture = require("@tests/lib/fixture")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-refs`
local has, count, ran, write = gatefix.has, gatefix.count, gatefix.ran, gatefix.write

return t.spec("c0165 what the whole-gate digest holds", function(it)
	it(
		"AC7: an affected whole-gate digest ignores a content-free HEAD move and holds a declared ref, never an unrelated ref",
		function()
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
			-- the file bytes did not change and HEAD is not in the digest: the gate is reused
			t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(true)
			t.expect(count(ran(dir), "b")).toBe(1)
			-- a declared ref that is not the base moves while HEAD and the base stand still: no reuse, b runs again
			fixture.git(dir, { "update-ref", "refs/heads/declared", "HEAD" })
			local okDeclared, outDeclared = gatefix.gate(dir, { "--affected" })
			t.expect(okDeclared).toBe(true)
			t.expect(has(outDeclared, "reused: an affected gate passed on this content")).toBe(false)
			t.expect(count(ran(dir), "b")).toBe(2)
			-- origin/main is itself a declared ref, so moving it reruns even though the base sha is not in the digest
			fixture.git(dir, { "update-ref", "refs/remotes/origin/main", "HEAD" })
			local ok3, out3 = gatefix.gate(dir, { "--affected" })
			t.expect(ok3).toBe(true)
			t.expect(has(out3, "reused: an affected gate passed on this content")).toBe(false)
			t.expect(count(ran(dir), "b")).toBe(3)
		end
	)

	it("AC7: a ref: spec's ref alone moves: the whole gate is not reused and that spec runs again", function()
		-- c declares only a ref, no `*`: the declared refs are in the digest whatever the selection holds (R53b)
		local dir = gatefix.make(base, "refonly", {
			extra = { c = {} },
			setup = function(d: string)
				write(
					`{d}/pickman/tests/inputs.tsv`,
					"# extra inputs per spec\ntests/unit/c.spec.luau\tref:refs/heads/only-ref\n"
				)
			end,
		})
		fixture.git(dir, { "update-ref", "refs/heads/only-ref", "HEAD" })
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		local ok1, _ = gatefix.gate(dir, { "--affected" })
		t.expect(ok1).toBe(true)
		t.expect(count(ran(dir), "c")).toBe(1)
		t.expect(count(ran(dir), "a")).toBe(1)
		-- nothing moved: the whole gate is reused
		local ok2, out2 = gatefix.gate(dir, { "--affected" })
		t.expect(ok2).toBe(true)
		t.expect(has(out2, "reused: an affected gate passed on this content")).toBe(true)
		t.expect(count(ran(dir), "c")).toBe(1)
		-- only-ref moves to a commit that is not HEAD; content, base and HEAD stand still
		local tip = fixture.git(dir, { "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "only-ref moves" })
		fixture.git(dir, { "update-ref", "refs/heads/only-ref", tip })
		local ok3, out3 = gatefix.gate(dir, { "--affected" })
		t.expect(ok3).toBe(true)
		t.expect(has(out3, "reused: an affected gate passed on this content")).toBe(false)
		t.expect(count(ran(dir), "c")).toBe(2)
		-- a (no declared ref) is reused by its own fingerprint: only the ref spec reran
		t.expect(count(ran(dir), "a")).toBe(1)
	end)
end)
