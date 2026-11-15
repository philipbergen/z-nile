-- c0265 split: cases of edge.spec (monolithic version) that belong to c0275. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../edge.spec.orig. They never ran against an implementation.



	it("fold beats for the raft it claims", function()
		must(zn(wt, { "fold", "R0030", "c0095" }), "fold")
		local stamp = stampOf("pickman/.tracker/rafts/R0030/R0030.md")
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		t.expect(#epochs(stamp)).toBe(1)
	end)
