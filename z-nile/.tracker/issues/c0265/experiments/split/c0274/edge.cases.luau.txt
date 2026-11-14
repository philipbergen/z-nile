-- c0265 split: cases of edge.spec (monolithic version) that belong to c0274. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../edge.spec.orig. They never ran against an implementation.



	it("a takeover that meets a claim restamped between its verdict and its publish is refused", function()
		local old = stampOf(`{P}/c0070/c0070.md`)
		fs.writeFile(`{h.fakes}/race`, "1")
		local r = zn(wt2, { "status", "c0070", "preparing" }, { ZN_NOW = tostring(os.time() + 3 * STALE) })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, RESTAMP)).toBe(true) -- names the stamp it met
		t.expect(stampOf(`{P}/c0070/c0070.md`)).toBe(RESTAMP) -- the other terminal's claim stands
		t.expect(old ~= RESTAMP).toBe(true)
	end)
